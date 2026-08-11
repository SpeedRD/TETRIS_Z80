---
name: assembler-conventions
description: Use when writing or editing any .asm source in this repo — adding a routine, a new file, an INCLUDE line, DB/DW data or an EQU constant — or when the build errors, an instruction assembles to unexpected bytes, or you need to know which sjasmplus directives and syntax this tree actually uses.
---

# Assembler conventions (sjasmplus, TETRIS_Z80)

Toolchain: **SjASMPlus v1.23.1**; build command and verification live in `build-and-verify`. Current
baseline: `Errors: 0, warnings: 0, compiled: 1440 lines`, 9614 bytes, `$8000-$A58D`.

## Column rule (breaks builds first)

Column 0 is for **labels only**. Every instruction and directive must be indented.
`--dirbol` is not used, so a directive at column 0 is parsed as a label:

```
DB 1,2,3            ; error: Unrecognized instruction: 1,2,3  (DB became a label)
    DB 1,2,3        ; correct
mydata: DB 1,2,3    ; correct — label + directive on one line, as in piezas.asm:5
```

Only exception: `EQU` takes its symbol at column 0 with no colon (`entrada.asm:6-7`,
`lineas.asm:9-11`, `puntuacion.asm:13`, `tetromino_next.asm:85-86`).

## Directives used in this tree

| Directive | Example | Meaning | Gotcha |
|---|---|---|---|
| `DEVICE` | `main.asm:3` `DEVICE ZXSPECTRUM48` | Selects 48K target | Appears once, before `ORG`. Do not add a second. |
| `ORG` | `main.asm:4` `ORG $8000` | Sets assembly address | **The only `ORG` in the tree.** Everything is one contiguous image. |
| `INCLUDE` | `main.asm:31-45` (15 lines) | Textual inclusion | Order is load-bearing, and `variables.asm` must stay **last** — see below. |
| `INCBIN` | `titulo.asm:32`, `L30.3 - printat.asm:162` | Embeds a binary file | Bytes land inline at that address (`TETRIS.scr` = 6912 bytes, `charset.bin` = 768). |
| `EQU` | `entrada.asm:6-7`, `lineas.asm:9-11`, `puntuacion.asm:13` | Compile-time constant | Emits **no bytes**. `COL_IZQ EQU 7` is a bare number, not reserved storage. |
| `DB` / `db` | `piezas.asm:5`, `L35 - Tetris_3D.asm:1`, `pantallas.asm:113-121`, `variables.asm:13-36` | Define bytes | Accepts strings: `db "Gracias por jugar",0`. |
| `DW` | `piezas.asm:5` `DW T_0, T_0`; `piezas.asm:35` `spawn_table`; `puntuacion.asm:15` | Define 16-bit words, little-endian | Rotation pointers, the spawn table, the BCD score table, `siguiente_pieza`. |

`DEFB`, `DEFW`, `DEFS`, `DS`, `ALIGN` appear **nowhere** — use `DB`/`DW`, matching the tree.

**There are no macros in this codebase.** No `MACRO`/`ENDM`, no `MODULE`, no `STRUCT`, no `IFDEF`
or any conditional assembly, no `REPT`/`DUP`. Do not go looking for a macro layer; there isn't one.

## Fake instructions (highest-risk item)

sjasmplus accepts register-pair loads that **are not Z80 instructions** and silently expands them
into several real ones. **No warning is printed.** This tree depends on two:

| Source | Where | Assembles to | Real meaning |
|---|---|---|---|
| `LD IX, DE` | `giro.asm:30`, `tetromino_next.asm:72` | `DD 62 DD 6B` | `LD IXH,D` : `LD IXL,E` |
| `ld iy, ix` | `piezas.asm:52`, `clear.asm:14`, `test_col.asm:15` | `DD E5 FD E1` | `PUSH IX` : `POP IY` |

What a cold reader must know:

1. **Not portable.** These are assembler-level sugar. This tree will not assemble under pasmo,
   z80asm, or most other assemblers. The *emitted bytes* do run on real Z80 hardware
   (`LD IXH,D` is an undocumented but functional opcode), so this is a source-syntax issue only.
2. **Side effects differ.** `LD IX, DE` is 2 register moves, 4 bytes, no memory touched.
   `ld iy, ix` **uses the stack**: it writes 2 bytes below `SP` and pops them back. It is not free,
   and it is not valid if `SP` is pointing anywhere you care about. There is no real Z80 instruction
   that copies IX to IY, so `push ix : pop iy` is the only way — the fake form is just shorthand.
3. Other fakes expand silently too: `LD HL, IX` → `DD E5 E1` (stack), `LD DE, HL` → `54 5D`
   (register moves). Never assume a 16-bit pair load is one instruction.

**Rule:** `LD IX, DE` / `ld iy, ix` in a diff is intentional — do not "fix" it. In *new* code prefer
the explicit form (`push ix`/`pop iy`, or `ld ixh,d`/`ld ixl,e`) so the cost is visible.

## Syntax quirks present in this tree

| Quirk | Real example | Rule |
|---|---|---|
| Mixed case, no convention | `LD  D,(IX + 9)` (`giro.asm:20`) vs `ld hl, spawn_table` (`tetromino_next.asm:42`) | Both assemble identically. Do not normalise case; it produces huge no-op diffs. |
| `:` is *both* label terminator and statement separator | `pantallas.asm:74` `SRL H : SRL H : SRL H`; `lineas.asm:17` `push bc : push de : push hl : push ix` | A second `:` on a line starts another statement, it does not define a label. The newer files use it heavily. |
| Two hex prefixes | `$5800` (`pantallas.asm:79`), `#40` (`L30.3 - printat.asm:47`) | Both valid. **Match the file you are editing:** `#` in `L30.3 - printat.asm`, `$` everywhere else. (`0x` was only in `caida.asm`, now deleted.) |
| Labels | Every code/data label ends in `:` (`giro.asm:41` `giro_bucle:`); `L30.3 - printat.asm:158` has a space before it (`SCR_CUR_PTR : db ...`). `EQU` symbols take **no** colon. | Always write `label:`. |
| Comments | `;` to end of line, everywhere. No `//`, no block comments. | Source is UTF-8 and comments are Spanish with accents; leave them alone. |

## Include order is load-bearing

`main.asm:31-45` includes the other 15 `.asm` files. Three consequences:

1. **Forward references work.** A *forward reference* is a symbol used before the line that defines
   it; sjasmplus runs multiple passes, so pass 1 records the use and a later pass fills in the
   value. `variables.asm:30` does `siguiente_pieza: DW T_0` while `T_0` is defined in `piezas.asm`,
   included seven lines earlier — that one is backward — but `juego.asm` (`main.asm:36`) calls
   `limpiar_lineas`, `anotar_lineas` and `leer_teclas`, all defined in files included after it, and
   resolves fine. **You do not need to order includes by dependency.**
2. **Reordering moves every address.** Includes are concatenated into the single `ORG $8000` image,
   so swapping two `INCLUDE` lines relocates the 19-record piece table (`$A154`), `CHARSET`
   (`$9CE0`), the `variables.asm` block (`$A581`) and every routine entry point.
3. **`variables.asm` must stay last** (`main.asm:45`). That is what puts all mutable state past the
   end of the code, and `memory-map` §6's addresses assume it.

**Rule: append new `INCLUDE` lines immediately *before* `INCLUDE "variables.asm"`. Never reorder,
never insert in the middle, never move `variables.asm` off the end.**

## Adding new code or data

1. Create `yourfile.asm` in the repo root (flat layout; there are no subdirectories for source).
2. Start it with a `;` header comment naming the routine, matching the existing files.
3. Write `RoutineName:` at column 0, everything else indented. End with `RET`.
4. Insert `    INCLUDE "yourfile.asm"` on its own line, **immediately before**
   `INCLUDE "variables.asm"` (`main.asm:45`).

   > **Two lines on one line is silent.** sjasmplus honours the first `INCLUDE` on a line and
   > **discards anything after it with no diagnostic** — 0 errors, 0 warnings, and your file is
   > simply never assembled. `main.asm` does end with a newline now, but the failure mode is
   > invisible, so confirm the build instead of assuming: `compiled: N lines` must move off 1440.

5. `DB`/`DW` tables in your file become part of the program image. The last used byte is `$A58D`,
   so new data starts at **`$A58E`** and grows upward. Fine for read-only data — `spawn_table`,
   `giro_kicks`, `PUNTOS_POR_LINEA` and `FRAMES_POR_NIVEL` all live this way, each placed after
   its file's last `ret`.
6. **Mutable variables go in `variables.asm` and nowhere else.** What is forbidden is
   *interleaving* — a `DB` inside a routine's code path, or a variable tacked onto the end of the
   piece table, which is where `Medio` used to sit. **`memory-map` §6 owns the layout and the
   addresses — cite it, declare nothing of your own.** A name declared in two files is a
   duplicate-label error.
7. Rebuild. The result must stay at `Errors: 0, warnings: 0`. A new warning is a regression.
8. Run `python3 tests/run_all.py` (`build-and-verify` §5b).

## Available but unused — none of these appear anywhere in the tree

| Directive | Purpose |
|---|---|
| `SAVESNA` | Writes a loadable `.sna` snapshot. Exists; `build-and-verify` owns whether to add one. |
| `SAVETAP` / `SAVEBIN` / `EMPTYTAP` | Tape image / raw binary output from source. |
| `MACRO`/`ENDM`, `MODULE`/`ENDMODULE` | Macros; label namespacing. |
| `DISP` / `ENT` | Assemble at one address, run at another. |

## Common mistakes

- **"Fixing" `LD IX, DE`** into `LD IX, (DE)` or a load through HL. It already works and means
  `IX = DE`; any rewrite changes rotation behaviour.
- **Assuming `ld iy, ix` is free.** It is `PUSH IX : POP IY` and touches memory below `SP`.
- **Reordering the `INCLUDE` list** to group things tidily, or moving `variables.asm` off the end.
  Every absolute address shifts.
- **Adding a variable with `DB` in the middle of a routine.** Execution falls through data bytes and
  runs them as opcodes. Data goes after a `RET`; mutable state goes in `variables.asm` (`memory-map` §6).
- **Putting a second `INCLUDE` on an existing line** — silently dropped, build still says 0/0.
- **Looking for a macro system.** There is none; write the instructions out.
- **Mixing hex prefixes** — `#`/`$` are both valid, so nothing warns you; match the file.
- **Putting a directive at column 0** — it silently becomes a label, then errors on the operands.
- **Normalising case or indentation** across a file, burying the real change in noise.

## Complete example — a new file added correctly

```asm
; borrar_linea.asm — clears one full row of the board (English: "clear line")
; Param. de Entrada: B = fila (row 0-22) — Param. de Salida: ninguno
; Preserves AF/BC/HL. See register-protocol before changing what this clobbers.
COL_IZQ     EQU 7            ; leftmost playfield column (EQU emits no bytes)
COL_DER     EQU 24           ; rightmost playfield column

borrar_linea:                ; label at column 0, with its colon
    push af                  ; everything else indented
    push bc
    push hl
    ld c, COL_IZQ
    call CRtoATTR            ; B,C -> HL = attribute address; PRESERVES BC. Rows 0-23 only.
    ld b, COL_DER - COL_IZQ + 1
limpiar_celda:
    ld (hl), 0 : inc hl      ; ':' as a statement separator, as in pantallas.asm:72
    djnz limpiar_celda
    pop hl
    pop bc
    pop af
    ret

ATRIB_VACIO: DB 0            ; read-only data, placed AFTER the ret, never inside the code path
```

Then add to `main.asm`, on its own line, immediately before `INCLUDE "variables.asm"`:

```asm
    INCLUDE "borrar_linea.asm"   ; nothing above it moves; variables.asm stays last
```
