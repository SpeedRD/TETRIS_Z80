#!/usr/bin/env python3
"""Drive TETRIS_Z80 under ZEsarUX over ZRCP (the remote debug protocol).

Two things make this project testable without a human at the keyboard:

  * the attribute file at $5800 IS the board, so reading 768 bytes gives the
    whole game state -- see Z.board() for an ASCII rendering;
  * ZEsarUX's set-ui-io-ports command sets the keyboard matrix directly, which
    is exactly what the game polls.

Run as a script to replay a small command file:

    python3 tests/tetris.py tests/scripts/whatever.txt

Script lines ('#' starts a comment):
  boot             reset, load main.bin at $8000, set PC, free-run
  boot basic       let the ROM boot first, then load and jump (as USR 32768 would)
  press <NAMES>    hold keys, comma separated: 'press J,K'
  release          release every key
  tap <NAMES> [ms] press, wait, release
  wait <ms>        sleep
  board            print the attribute file as an ASCII board
  regs             print the CPU registers
  shot <name>      save a screenshot as PNG (into a temp dir, never the repo)
  poke <LBL|hex> <hexbytes>    write memory; labels come from main.lst
  peek <LBL|hex> <len>         read memory
  zero <hexaddr> <len>         zero a span
  cmd <zrcp...>    send a raw ZRCP command
"""
import os
import socket
import subprocess
import sys
import tempfile
import time

HOST, PORT = "localhost", 10000

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BIN = os.path.join(REPO, "main.bin")
LST = os.path.join(REPO, "main.lst")
# Screenshots are build artefacts: keep them out of the repo, which has no
# .gitignore (build-and-verify section 3).
SHOTS = os.path.join(tempfile.gettempdir(), "tetris-z80-shots")

# Keyboard half-rows, most significant key first: bit4, bit3, bit2, bit1, bit0.
ROWS = [
    ("V", "C", "X", "Z", "SHIFT"),
    ("G", "F", "D", "S", "A"),
    ("T", "R", "E", "W", "Q"),
    ("5", "4", "3", "2", "1"),
    ("6", "7", "8", "9", "0"),
    ("Y", "U", "I", "O", "P"),
    ("H", "J", "K", "L", "ENTER"),
    ("B", "N", "M", "SYM", "SPACE"),
]


def matrix(names):
    """Key names -> the 9 hex bytes set-ui-io-ports wants. A pressed key is 0."""
    rows = [0x1F] * 8
    for n in [x.strip().upper() for x in names if x.strip()]:
        found = False
        for r, keys in enumerate(ROWS):
            for i, k in enumerate(keys):
                if k == n:
                    rows[r] &= ~(1 << (4 - i)) & 0x1F
                    found = True
        if not found:
            raise SystemExit(f"unknown key {n!r}")
    return "".join(f"{v:02x}" for v in rows) + "00"


class Z:
    def __init__(self):
        try:
            self.s = socket.create_connection((HOST, PORT), timeout=20)
        except OSError as e:
            raise SystemExit(
                f"cannot reach ZEsarUX on {HOST}:{PORT} ({e}).\n"
                "Start it with ZRCP enabled:\n"
                "  /Applications/ZEsarUX.app/Contents/MacOS/zesarux "
                "--enable-remoteprotocol --remoteprotocol-port 10000 --machine 48k")
        self.s.settimeout(20)
        self._read()

    # ZRCP switches the prompt to "command@cpu-step> " in step mode.
    PROMPTS = (b"command> ", b"command@cpu-step> ")

    def _read(self):
        buf = b""
        while not buf.endswith(self.PROMPTS):
            try:
                c = self.s.recv(65536)
            except socket.timeout:
                break
            if not c:
                break
            buf += c
        t = buf.decode("utf8", "replace")
        for p in self.PROMPTS:
            ps = p.decode()
            if t.endswith(ps):
                return t[: -len(ps)]
        return t

    def cmd(self, c):
        self.s.sendall((c + "\n").encode())
        return self._read().strip()

    # ---- helpers ---------------------------------------------------------
    def read_mem(self, addr, length):
        """Bytes via hexdump, whose lines are 'ADDR xx xx ...  ascii'."""
        out = b""
        done = 0
        while done < length:
            n = min(256, length - done)
            txt = self.cmd(f"hexdump {addr+done:04X}H {n}")
            for line in txt.splitlines():
                parts = line.split()
                if len(parts) < 2:
                    continue
                hx = []
                for p in parts[1:]:
                    if len(p) == 2 and all(ch in "0123456789ABCDEFabcdef" for ch in p):
                        hx.append(p)
                    else:
                        break
                out += bytes(int(h, 16) for h in hx[:16])
            done += n
        return out[:length]

    def boot(self, mode="cold"):
        self.cmd("enter-cpu-step")
        self.cmd("hard-reset-cpu")
        if mode == "basic":
            self.cmd("exit-cpu-step")
            time.sleep(2.5)
            self.cmd("enter-cpu-step")
        self.cmd(f'load-binary "{BIN}" 8000H 0')
        self.cmd("set-register PC=8000H")
        self.cmd("exit-cpu-step")

    def board(self):
        """The attribute file as 24 rows of 32 cells.

        '.' empty   '#' well border (attribute 55)   otherwise the PAPER colour:
        b blue  R red  m magenta  G green  C cyan  Y yellow  W white
        """
        at = self.read_mem(0x5800, 768)
        lut = {0: ".", 0x37: "#"}
        names = {1: "b", 2: "R", 3: "m", 4: "G", 5: "C", 6: "Y", 7: "W"}
        lines = []
        for r in range(24):
            row = ""
            for c in range(32):
                v = at[r * 32 + c]
                if v in lut:
                    row += lut[v]
                else:
                    row += names.get((v >> 3) & 7, "?") if (v & 0x7F) else "."
            lines.append(f"{r:2d} |{row}|")
        return "\n".join(lines)

    def shot(self, name):
        os.makedirs(SHOTS, exist_ok=True)
        bmp = os.path.join(SHOTS, f"{name}.bmp")
        png = os.path.join(SHOTS, f"{name}.png")
        for p in (bmp, png):
            if os.path.exists(p):
                os.remove(p)
        self.cmd(f'save-screen "{bmp}"')
        time.sleep(0.4)
        if os.path.exists(bmp):
            subprocess.run([sys.executable, os.path.join(HERE, "bmp2png.py"), bmp, png],
                           capture_output=True)
            return png if os.path.exists(png) else bmp
        return None


_LABELS = {}


def resolve(tok):
    """A label from main.lst, or a bare hex address."""
    if not _LABELS:
        import re
        pat = re.compile(r"^\s*\d+\+?\s+([0-9A-F]{4})\s+(?:[0-9A-F ]*?\s\s)?"
                         r"([A-Za-z_][A-Za-z0-9_]*):")
        with open(LST, encoding="utf8", errors="replace") as fh:
            for line in fh:
                m = pat.match(line)
                if m:
                    _LABELS.setdefault(m.group(2), int(m.group(1), 16))
    if tok in _LABELS:
        return _LABELS[tok]
    return int(tok, 16)


def main():
    z = Z()
    script = open(sys.argv[1]).read().splitlines() if len(sys.argv) > 1 else []
    for raw in script:
        line = raw.split("#")[0].strip()
        if not line:
            continue
        op, *a = line.split()
        if op == "boot":
            z.boot(a[0] if a else "cold")
        elif op == "keys":
            z.cmd(f"set-ui-io-ports {a[0]}")
        elif op == "press":
            z.cmd(f"set-ui-io-ports {matrix(a[0].split(','))}")
        elif op == "release":
            z.cmd(f"set-ui-io-ports {matrix([])}")
        elif op == "tap":
            ms = int(a[1]) if len(a) > 1 else 120
            z.cmd(f"set-ui-io-ports {matrix(a[0].split(','))}")
            time.sleep(ms / 1000)
            z.cmd(f"set-ui-io-ports {matrix([])}")
        elif op == "wait":
            time.sleep(int(a[0]) / 1000)
        elif op == "board":
            print(z.board())
        elif op == "regs":
            print(z.cmd("get-registers"))
        elif op == "shot":
            print("SHOT:", z.shot(a[0]))
        elif op == "mem":
            print(z.cmd(f"hexdump {a[0]} {a[1]}"))
        elif op == "echo":
            print(" ".join(a))
        elif op == "zero":
            addr, n = int(a[0], 16), int(a[1])
            z.cmd(f"write-memory-raw {addr:04X}H {'00'*n}")
        elif op == "poke":
            z.cmd(f"write-memory-raw {resolve(a[0]):04X}H {a[1]}")
        elif op == "peek":
            print(f"{a[0]} =", z.read_mem(resolve(a[0]), int(a[1])).hex(" "))
        elif op == "cmd":
            print(z.cmd(" ".join(a)))
        else:
            print("?", line)
    z.cmd("exit")


if __name__ == "__main__":
    main()
