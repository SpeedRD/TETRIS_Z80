#!/usr/bin/env python3
"""Call one Z80 routine at a time under ZEsarUX, with controlled registers.

How a call works: put a return address on a stack we control, point PC at the
routine, and run. When the routine RETs it lands on a two-instruction trap we
poked into free RAM -- DI then JR $ -- which parks the CPU deterministically.

Three things here were learned the hard way and are load-bearing:

  * No breakpoints. When a ZEsarUX breakpoint fires it opens the debug menu,
    and an open menu makes enter-cpu-step fail, which makes `run` fail. The
    emulator then needs restarting. The trap costs the full opcode `limit` per
    call instead, so keep limits tight rather than reaching for a breakpoint.
  * The trap parks with interrupts OFF. With them on, the ROM's 50 Hz handler
    is frequently mid-flight when registers are sampled and PC reads as a ROM
    address, so "did it return?" becomes a coin flip.
  * main.asm's 5-opcode prologue is executed before every test, so routines
    run in the game's real interrupt state (IM 1, IY=$5C3A, interrupts on).
    Without it the `ei` inside comprobar/pintar_tetromino/borrar_tetromino
    enables interrupts while still in IM 0 and the CPU vectors into ROM.
"""
import re

from tetris import Z, matrix, BIN, LST

STACK = 0xFF00


def labels():
    """Every label in main.lst -> address. Never hardcode an address: they all
    move when anything earlier in the include order changes size."""
    out = {}
    pat = re.compile(r"^\s*\d+\+?\s+([0-9A-F]{4})\s+(?:[0-9A-F ]*?\s\s)?"
                     r"([A-Za-z_][A-Za-z0-9_]*):")
    with open(LST, encoding="utf8", errors="replace") as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                out.setdefault(m.group(2), int(m.group(1), 16))
    return out


class Unit:
    def __init__(self):
        self.z = Z()
        self.L = labels()
        self.TRAP = 0xFE00      # DI : JR $   -- free RAM, well above the image
        self.PARKED = 0xFE01    # PC settles on the JR
        self.z.cmd("disable-breakpoints")
        self.z.cmd("close-all-menus")
        self.z.cmd("enter-cpu-step")
        self.z.cmd("hard-reset-cpu")
        self.z.cmd(f'load-binary "{BIN}" 8000H 0')
        self.z.cmd("set-register PC=8000H")
        self.z.cmd("run 5")     # LD SP,0 / DI / LD IY,$5C3A / IM 1 / EI
        self.z.cmd(f"write-memory-raw {self.TRAP:04X}H f318fe")

    def regs(self):
        t = self.z.cmd("get-registers")
        return {k: int(v, 16)
                for k, v in re.findall(r"([A-Z]{1,3}'?)=([0-9a-f]{2,4})", t)}

    def call(self, name, regs=None, keys=None, limit=60000):
        """Run routine `name`; return its registers. Raises if it never RETs."""
        addr = self.L[name]
        if keys is not None:
            self.z.cmd(f"set-ui-io-ports {matrix(keys)}")
        self.z.cmd(f"write-memory-raw {STACK:04X}H "
                   f"{self.TRAP & 0xFF:02X}{self.TRAP >> 8:02X}")
        self.z.cmd(f"set-register SP={STACK:04X}H")
        for r, v in (regs or {}).items():
            self.z.cmd(f"set-register {r}={v:04X}H")
        self.z.cmd(f"set-register PC={addr:04X}H")
        self.z.cmd(f"run {limit}")
        r = self.regs()
        r["_returned"] = r.get("PC") in (self.TRAP, self.PARKED)
        if not r["_returned"]:
            raise AssertionError(
                f"{name} did not return within {limit} opcodes "
                f"(PC={r.get('PC'):04X}); raise the limit or it is looping")
        return r

    def poke(self, addr, data):
        self.z.cmd(f"write-memory-raw {addr:04X}H "
                   f"{''.join(f'{b:02x}' for b in data)}")

    def peek(self, addr, n):
        return self.z.read_mem(addr, n)

    def close(self):
        self.z.cmd("exit-cpu-step")
        self.z.cmd("exit")
