---
name: scoring-and-level
description: Use when adding or changing a score, a cleared-line counter, a level, points awarded per line clear, the level-to-drop-speed mapping, or any on-screen display of those values in this ZX Spectrum Tetris. Also use when reading caida.asm's level arithmetic or NIVEL_ACTUAL, or when text output must coexist with a falling piece.
---

# Scoring, line count, and level

Spanish here: `caida` = fall, `Tiempo` = time, `TIEMPO_BASE`/`TIEMPO_MINIMO`/`REDUCCION_TIEMPO` =
base / minimum / reduction time, `NIVEL_ACTUAL` = current level, `InicializarTiempo` = initialise
time, `Mensaje...` = message, `puntos`/`lineas`/`nivel` = points/lines/level.

## 1. What exists today

- **No score variable, no line counter, no score display, anywhere in the tree** — verified.
- `NIVEL_ACTUAL` = `EQU 0x7002` (`caida.asm:11`) is **never written by any instruction**; it is read
  once (`caida.asm:22`) and destroyed on the next line. `InicializarTiempo` (`caida.asm:63-66`) is
  dead — the label appears only at its own definition.

## 2. Z80 facts this file assumes

| Fact | Consequence |
|---|---|
| `SUB A` computes `A - A` | it is the "set `A` to zero" idiom, not a useful subtraction |
| `SBC HL,BC` = `HL - BC - carry`; `OR A` leaves `A` alone but **clears carry** | a 16-bit subtraction depends on the flag left by the *previous* instruction, so put `OR A` first |
| No multiply and no divide instruction | `level * constant` needs a shift-add loop or a lookup table; prefer the table |
| `DAA` fixes up `A` after `ADD`/`ADC` so each nibble stays a decimal digit | packed BCD addition is cheap, and printing is a nibble plus `'0'` |
| `IX` is a 16-bit index register, used here as the global falling-piece pointer | any routine that touches `IX` moves the piece (`register-protocol`, §5) |

## 3. `caida.asm`'s level arithmetic is dead code

Actual source, `caida.asm:22-35`:
```asm
    LD A, (NIVEL_ACTUAL)    ; :22  A = level
    LD HL, TIEMPO_BASE      ; :23  HL = 0x11FF
    SUB A                   ; :24  A = 0  <-- destroys the level just loaded
    LD B, 0                 ; :25
    LD C, A                 ; :26  BC = 0
    LD DE, REDUCCION_TIEMPO ; :27  DE = 10, never read again
    LD A, 0                 ; :28  LD does not touch flags
    SBC HL, BC              ; :29  HL = 0x11FF - 0 - carry(0) = 0x11FF
    LD A, H                 ; :30  A = 0x11
    OR A                    ; :31
    JR NZ, SkipMinCheck     ; :32  H is always 0x11, so ALWAYS taken
    CP L                    ; :33  unreachable
    JR NC, SkipMinCheck     ; :34  unreachable
    LD HL, TIEMPO_MINIMO    ; :35  unreachable
```

| Defect | Where | Detail |
|---|---|---|
| Level value destroyed | `caida.asm:24` | `SUB A` zeroes `A` one instruction after the level was loaded into it |
| No multiplication | `caida.asm:27` | the comment on `:29` claims `base - (level * reduction)`, but `REDUCCION_TIEMPO` goes into `DE` and is never read; there is no multiply |
| Accidental carry | `:24` -> `:29` | `SBC HL,BC` needs carry clear; it is clear only because `SUB A` cleared it. Inserting **any** flag-affecting instruction between them silently changes the result |
| Clamp unreachable | `caida.asm:30-35` | the branch tests only `H`. With base `0x11FF`, `H` = `0x11` != 0 so the jump is always taken — unreachable for any base >= `$0100`. Even if reached it compares `H` against `L`, not against `TIEMPO_MINIMO` |
| Dead routine | `caida.asm:63` | `InicializarTiempo` is never called |

**Net effect: the drop interval is a hard constant; the level influences nothing.** T-state to
millisecond derivation: `interrupts-and-timing`. Why `TIEMPO_BASE` became `0x11FF`:
`failure-patterns`. **Rule: put `OR A` immediately before your own `SBC HL,rr`.**

## 4. Where the new state lives — code in one file, variables in another

- **Code** — the routines below and the read-only `EQU`/`DB`/`DW` tables they index — goes in a new
  `puntuacion.asm` ("scoring"), `INCLUDE`d from `main.asm`. Owned by this skill.
- **Variables** — `PUNTOS`, `LINEAS`, `NIVEL`, `PROX_NIVEL`, `FRAMES_POR_FILA` — go in the single
  `variables.asm`, `INCLUDE`d **last**, landing at `$A2C7`. Owned by **`memory-map` §6**.

**Never declare a second variable block in `puntuacion.asm`.** Declaring `NIVEL` and `LINEAS` in
both files is a duplicate-label error: `Errors: 2, warnings: 4` — verified. Declare each exactly once:

```asm
; in variables.asm (memory-map §6) -- the ONLY place these exist
PUNTOS:          DB 0, 0, 0 ; "points": packed BCD, 6 digits, digit pairs 1-2, 3-4, 5-6
LINEAS:          DB 0       ; "lines": total rows cleared (8-bit binary)
NIVEL:           DB 0       ; "level" (8-bit binary)
PROX_NIVEL:      DB 10      ; "next level": rows still needed to level up
FRAMES_POR_FILA: DB 48      ; gravity reload, frames per row; written by ActualizarVelocidad (§8)
```

**Packed BCD for the score, not 16-bit binary.** Each byte holds two decimal digits (`$47` = 47),
`DAA` keeps addition correct, printing is a nibble shift plus `ADD A,'0'`. Binary adds in one
instruction but the Z80 has no divide, so displaying it costs a divide-by-10 loop. Lines and level
stay 8-bit binary.

> **`main.asm` has no trailing newline.** A blind append puts your `INCLUDE` on the same line as
> `INCLUDE "giro.asm"`, and sjasmplus then **ignores it while still reporting `Errors: 0, warnings:
> 0`** — verified. Add the newline first, then each `INCLUDE` on its own line
> (`assembler-conventions`). Hex prefixes: `caida.asm` uses `0x`, most files `$`, printat `#`.

## 5. LANDMINE: printing destroys the falling piece

`PRINTAT` (`L30.3 - printat.asm:14`) falls through into `PRINTSTR` (`:20`), which walks the string
with `INC IX` (`:24`): **on return `IX` no longer points at the current piece.** `PRINTCHNUM` (`:96`)
reaches `PRINTCHAR`, which does `LD B,8` (`:113`) and `DJNZ` (`:120`), so **`B` — the piece row —
comes back as 0.** Clobbered by any print: `AF`, `B`, `DE`, `HL`, plus `IX` for `PRINTAT`/`PRINTSTR`;
`C` and `IY` survive. Skip the wrapper and the piece changes shape, teleports mid-fall, or draws
garbage. Wrap **every** print made while a piece is up:

```asm
    PUSH IX : PUSH BC           ; IX = piece pointer, B = piece row, C = piece column
    LD A, 7 : LD B, 0 : LD C, 26  ; attribute (white on black), screen row, screen column
    LD IX, MensajePuntos        ; here IX is the STRING pointer, not the piece
    CALL PRINTAT
    POP BC : POP IX
```

`register-protocol` holds the full clobber table; it is restated here because this is the most
common way to break the game while adding a display.

## 6. Printing a number — no such routine exists

The library offers `PRINTSTR` (zero-terminated string) and `PRINTCHNUM` (one character, code in `A`);
**there is no integer-to-decimal routine.** `PRINTCHNUM` advances the cursor itself, so digits can be
emitted one at a time once `PREP_PRT` has set the position. Print **fixed width with leading zeros**
(`000420`) so the field never shrinks and stale digits cannot survive.

```asm
; Print the two decimal digits of the packed-BCD byte in A. Cursor must already be set.
; Clobbers AF, B, DE, HL. Preserves C, IX, IY.
ImprimirBCD:
    PUSH AF
    RRCA : RRCA : RRCA : RRCA   ; high nibble down into bits 0-3
    AND $0F : ADD A, '0'        ; digit value -> ASCII character code
    CALL PRINTCHNUM : POP AF
    AND $0F : ADD A, '0'        ; low nibble
    JP PRINTCHNUM               ; tail call: prints, advances cursor, returns

ImprimirPuntos:                 ; 6-digit score at row 1, columns 26-31
    PUSH IX : PUSH BC
    LD A, 7 : LD B, 1 : LD C, 26          ; attribute, row, column
    CALL PREP_PRT                         ; sets PRINT_ATTR and both cursors from B,C
    LD A, (PUNTOS+2) : CALL ImprimirBCD   ; most significant pair first
    LD A, (PUNTOS+1) : CALL ImprimirBCD
    LD A, (PUNTOS)   : CALL ImprimirBCD
    POP BC : POP IX
    RET
```

Never run a field past column 31: `PRINTCHAR` advances the cursor with `INC (HL)` on the low byte
only (`:125,127`), so it wraps inside a 256-byte block instead of wrapping to the next row.

## 7. Where the display may go — a correctness constraint, not a preference

Collision means "attribute byte != 0" (`game-loop-and-collision`), so **anything printed inside the
well becomes solid, collidable geometry.** The well interior is columns 7-24 (`memory-map`), so
**print only in columns 0-5 or 26-31.** Recommended: `SCORE` label at row 0 col 26 with digits at
row 1 col 26; `LINES` rows 3-4; `LEVEL` rows 6-7. Six cells wide fits exactly.

**ASCII only in every string you add.** Non-ASCII (`¡`, `¿`, accents) assembles to multi-byte UTF-8
that indexes outside the 768-byte character set and renders garbage — `pantallas.asm:113-114` already
has this bug; `rendering-and-attributes` §7 explains it.

## 8. Scoring and level rules

Points per simultaneous clear: 1 row = 100, 2 = 300, 3 = 500, 4 = 800. `LINEAS` += rows cleared.
Level rises every 10 rows — count `PROX_NIVEL` down rather than dividing — and caps at 10. Gravity
comes from a **lookup table of frames per row**, not arithmetic: a table cannot underflow, has no
carry-flag hazard, and is shorter than a multiply loop.

```asm
; in puntuacion.asm. NIVEL and FRAMES_POR_FILA are declared in variables.asm (§4), not here.
NIVEL_MAX EQU 10
PUNTOS_POR_LINEA: DW $0100, $0300, $0500, $0800     ; packed BCD, indexed by (rows-1)*2
FRAMES_POR_NIVEL: DB 48,40,33,27,22,18,15,12,10,8,6 ; levels 0..10, at 50 frames/sec

; Add DE (4-digit packed BCD) to the 6-digit score. Clobbers AF, HL.
SumarPuntos:
    LD HL, PUNTOS
    LD A, (HL) : ADD A, E : DAA : LD (HL), A          ; DAA makes the binary sum decimal again
    INC HL : LD A, (HL) : ADC A, D : DAA : LD (HL), A ; LD leaves flags alone, so carry survives
    INC HL : LD A, (HL) : ADC A, 0 : DAA : LD (HL), A
    RET

; Copy the current level's speed into the gravity reload value.
ActualizarVelocidad:
    LD A, (NIVEL)
    CP NIVEL_MAX : JR C, NivelOK
    LD A, NIVEL_MAX             ; clamp: never index past the table
NivelOK:
    LD E, A : LD D, 0
    LD HL, FRAMES_POR_NIVEL : ADD HL, DE
    LD A, (HL) : LD (FRAMES_POR_FILA), A   ; floor 6 frames (~120 ms); table can never yield 0
    RET
```

`FRAMES_POR_FILA` is a **variable declared once in `variables.asm`** (§4); without it this snippet
fails with `error: Label not found: FRAMES_POR_FILA` — verified. The gravity loop that *reads* it
belongs to `interrupts-and-timing` / `game-loop-and-collision`.

## 9. Wiring it up

1. `line-clear` returns the number of rows cleared in `A` (0-4). If 0, do nothing.
2. Index `PUNTOS_POR_LINEA` at `(rows-1)*2`, load the entry into `DE`, `CALL SumarPuntos`.
3. Add `rows` to `LINEAS`; decrement `PROX_NIVEL` once per row; at 0, reload 10 and `INC NIVEL`.
4. `CALL ActualizarVelocidad`.
5. Redraw the display **only if a value changed** — redrawing text every frame is pure waste.

### Hook point — the `juego.asm` labels are inverted; read before wiring anything

Update **once per lock**: the **fall-through at `juego.asm:34-37`**, never `cambiar_tetromino`.

```asm
    call comprobar           ; :29  A = 0 means NO collision (test_col.asm:42)
    or a
    jr z, cambiar_tetromino  ; :32  A = 0 -> KEEP FALLING. Despite its name, not the lock path.
    dec b                    ; :34  fall-through = collision = the piece locks
    ld c, e                  ; :35
    call pintar_tetromino    ; :36  <-- lock. limpiar_lineas, then score/level, go HERE
    jr iniciar               ; :37  spawns the next piece
```

Hooked at `cambiar_tetromino` (`:39`) instead, the update fires on **every gravity step** and the
score climbs with nothing cleared. `game-loop-and-collision` owns the loop; `line-clear` uses the
same hook. **Ordering rule:** redraw **outside** the erase/draw window, never between
`borrar_tetromino` and `pintar_tetromino` — there the `IX`/`BC` save-restore must nest around code
already using those registers, and one missed `POP` silently moves the piece.

## 10. Replacing the busy-wait

Correct end state: `HALT` once per frame, decrement a counter reloaded from `FRAMES_POR_FILA` (§4).
Tuning `TIEMPO_BASE` is not a fix. `interrupts-and-timing` owns the mechanism — not implemented here.

## Common mistakes

- **Printing without saving `IX`** — corrupts the falling-piece pointer. Save `BC` too: `PRINTCHAR`'s `DJNZ` destroys `B`, the piece row.
- **Printing inside columns 7-24** — every printed cell becomes an invisible wall.
- **Non-ASCII characters in a message string** — garbage glyphs (§7).
- **`SBC HL, rr` without `OR A` first** — off by one whenever carry happens to be set.
- **A level-to-speed formula instead of the table** — formulas underflow to 0 frames and the game becomes unplayable. The table's floor is 6.
- **Redrawing the score every frame** — wasted T-states; redraw only on change.
- **Storing the score as plain binary** — no divide instruction, so displaying it costs an extra divide-by-10 loop. Use packed BCD (§4).
- **Assuming `NIVEL_ACTUAL` (`0x7002`) holds something** — nothing ever writes it. Use `NIVEL` from `variables.asm` (§4).
- **Declaring `NIVEL`/`LINEAS`/`FRAMES_POR_FILA` in `puntuacion.asm`** — they already exist in `variables.asm`; two declarations is `Errors: 2, warnings: 4` (§4).
- **Hooking the update at `cambiar_tetromino`** — that is the keep-falling branch, so it fires on every gravity step, not once per lock (§9).
- **Appending the `INCLUDE` to `main.asm` without a newline first** — silently dropped, 0 errors, 0 warnings (§4).
