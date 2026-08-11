---
name: scoring-and-level
description: Use when adding or changing a score, a cleared-line counter, a level, points awarded per line clear, the level-to-drop-speed mapping, or any on-screen display of those values in this ZX Spectrum Tetris. Also use when text output must coexist with a falling piece.
---

# Scoring, line count, and level

Spanish here: `puntuacion` = scoring, `anotar_lineas` = record the lines, `PUNTOS`/`LINEAS`/`NIVEL`
= points/lines/level, `PROX_NIVEL` = next level, `FRAMES_POR_FILA`/`FRAMES_POR_NIVEL` = frames per
row / per level, `ActualizarVelocidad` = update the speed, `reiniciar_marcador` = reset the
scoreboard, `ImprimirMarcador`/`ImprimirEtiquetas` = print the scoreboard / the labels,
`Mensaje...` = message.

## 1. What exists today

All of it is in **`puntuacion.asm`** (code and read-only tables) plus **`variables.asm`** (state):

| Thing | Where | Notes |
|---|---|---|
| Score, 6 digits packed BCD | `PUNTOS` `variables.asm:13` | 100/300/500/800 per 1/2/3/4 rows |
| Lines cleared | `LINEAS` `variables.asm:14` | 8-bit binary |
| Level and its countdown | `NIVEL`, `PROX_NIVEL` `variables.asm:15-16` | +1 every 10 rows, capped at 10 |
| Gravity speed | `FRAMES_POR_FILA` `variables.asm:19`, table `puntuacion.asm:16` | 48 frames at level 0 down to 6 at level 10 |
| The scoreboard | `puntuacion.asm:95-160` | Columns 26-31, refreshed only on change |

`anotar_lineas` (`puntuacion.asm:22`) is the single entry point, called from the lock path at
`juego.asm:106` with the cleared-row count in `A`. `tests/test_puntuacion.py` covers points per
clear, BCD carry across digit boundaries, the line counter, level-up at 10 lines, the level cap, and
the whole frames-per-level table.

The old `NIVEL_ACTUAL` at `$7002` and everything around it went with `caida.asm`. §3 explains why
it is worth remembering.

## 2. Z80 facts this file assumes

| Fact | Consequence |
|---|---|
| `SUB A` computes `A - A` | it is the "set `A` to zero" idiom, not a useful subtraction |
| `SBC HL,BC` = `HL - BC - carry`; `OR A` leaves `A` alone but **clears carry** | a 16-bit subtraction depends on the flag left by the *previous* instruction, so put `OR A` first |
| No multiply and no divide instruction | `level * constant` needs a shift-add loop or a lookup table; prefer the table |
| `DAA` fixes up `A` after `ADD`/`ADC` so each nibble stays a decimal digit | packed BCD addition is cheap, and printing is a nibble plus `'0'` |
| `IX` is a 16-bit index register, used here as the global falling-piece pointer | any routine that touches `IX` moves the piece (`register-protocol`, §5) |

## 3. The dead level arithmetic this replaced — five defects in fourteen instructions

`caida.asm` is deleted; recover it with `git show 0a2377e:caida.asm`. It is reproduced here because
every one of these five mistakes is easy to make again in new code, and because the routine *looked*
like working level scaling — comments and all — while doing nothing at all.

Old source, `caida.asm:22-35`:
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

**Net effect: the drop interval was a hard constant and the level influenced nothing.** Gravity is
now a frame counter with a lookup table, which has none of these failure modes
(`interrupts-and-timing` §4). **Rule that outlives the file: put `OR A` immediately before your own
`SBC HL,rr`.**

## 4. Where the state lives — code in one file, variables in another

- **Code** — the routines below and the read-only `DB`/`DW`/`EQU` tables they index — is in
  `puntuacion.asm` ("scoring"), `INCLUDE`d at `main.asm:44`. Owned by this skill.
- **Variables** — `PUNTOS`, `LINEAS`, `NIVEL`, `PROX_NIVEL`, `FRAMES_POR_FILA`, `contador_frames` —
  are in `variables.asm`, `INCLUDE`d **last**, landing at `$A581`. Owned by **`memory-map` §6**.

**Never declare a second variable block in `puntuacion.asm`.** Declaring `NIVEL` and `LINEAS` in
both files is a duplicate-label error: `Errors: 2, warnings: 4` — verified. Each exists once:

```asm
; in variables.asm (memory-map §6) -- the ONLY place these exist
PUNTOS:          DB 0, 0, 0 ; "points": packed BCD, 6 digits, digit pairs 1-2, 3-4, 5-6
LINEAS:          DB 0       ; "lines": total rows cleared (8-bit binary)
NIVEL:           DB 0       ; "level" (8-bit binary)
PROX_NIVEL:      DB 10      ; "next level": rows still needed to level up
FRAMES_POR_FILA: DB 48      ; gravity reload, frames per row; written by ActualizarVelocidad (§8)
contador_frames: DB 48      ; frames left until the next drop; the loop decrements it
```

**Packed BCD for the score, not 16-bit binary.** Each byte holds two decimal digits (`$47` = 47),
`DAA` keeps addition correct, printing is a nibble shift plus `ADD A,'0'`. Binary adds in one
instruction but the Z80 has no divide, so displaying it costs a divide-by-10 loop — which is
exactly what `ImprimirDec3` has to do for `LINEAS` and `NIVEL` (§6). Lines and level stay 8-bit
binary because three digits of repeated subtraction is cheap; six would not be.

> A new `INCLUDE` goes on its **own line**, immediately before `INCLUDE "variables.asm"`. sjasmplus
> honours the first directive on a line and silently ignores the rest, at `Errors: 0, warnings: 0`
> (`assembler-conventions`). Hex prefixes: `#` in `L30.3 - printat.asm`, `$` everywhere else.

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
common way to break the game while adding a display. `ImprimirEtiquetas` (`puntuacion.asm:95`) and
`ImprimirMarcador` (`:107`) both open with `push ix : push bc` and close with the mirror — copy from
them. `reiniciar_marcador` (`:79`) pushes everything, because it is called from `iniciar` where the
caller's registers still matter.

## 6. Printing a number — no such routine exists

The library offers `PRINTSTR` (zero-terminated string) and `PRINTCHNUM` (one character, code in `A`);
**it has no integer-to-decimal routine**, so `puntuacion.asm` supplies two: `ImprimirBCD` (`:125`)
for the packed-BCD score and `ImprimirDec3` (`:136`) for `LINEAS` and `NIVEL`, which are binary and
need repeated subtraction because the Z80 has no divide. `PRINTCHNUM` advances the cursor itself, so
digits go out one at a time once `PREP_PRT` has set the position. Both print **fixed width with
leading zeros** (`000420`, `007`) so the field never shrinks and stale digits cannot survive.

`PRINTCHNUM` destroys `B`, which is why `ImprimirDec3` reloads `ld b, 0` before each digit's
subtraction loop rather than keeping a counter across calls.

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
**print only in columns 0-5 or 26-31.**

The shipped layout, all at column 26: `SCORE` label row 0, digits row 1; `LINES` rows 3-4; `LEVEL`
rows 6-7; `NEXT` row 9, with the preview box at rows 10-13, columns 27-30
(`puntuacion.asm:97-100`, `tetromino_next.asm:85-86`). Six cells wide fits columns 26-31 exactly —
do not run a field past column 31, for the reason at the end of §6.

**ASCII only in every string you add.** Non-ASCII (`¡`, `¿`, accents) assembles to multi-byte UTF-8
that indexes outside the 768-byte character set and renders garbage. Every string in the tree is
ASCII today — `puntuacion.asm:162` says so above its four labels — and it must stay that way;
`rendering-and-attributes` §7 explains the mechanism.

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

`FRAMES_POR_FILA` is a **variable declared once in `variables.asm`** (§4); declaring it here too is
`Errors: 2, warnings: 4`. The gravity loop that *reads* it belongs to `interrupts-and-timing` §5.

Note `ActualizarVelocidad` changes `FRAMES_POR_FILA` but not `contador_frames`, so a level-up takes
effect from the *next* drop rather than shortening the one in flight. `reiniciar_marcador` (`:87-88`)
does reload `contador_frames`, because a new game must start the clock clean.

## 9. How it is wired

`anotar_lineas` does steps 1-5 in one call:

1. `A` = rows cleared from `limpiar_lineas` (0-4). If 0, `ret z` immediately (`:23-24`).
2. Index `PUNTOS_POR_LINEA` at `(rows-1)*2`, load into `DE`, `call SumarPuntos` (`:28-34`).
3. One loop pass per row: `LINEAS` +1, `PROX_NIVEL` −1; at 0, reload 10 and `INC NIVEL` up to the
   cap (`:36-48`). Per-row rather than in bulk so a 4-row clear that crosses a level boundary
   levels up exactly once.
4. `call ActualizarVelocidad` (`:50`).
5. `call ImprimirMarcador` (`:51`) — **only here**, i.e. only when something changed.

### Hook point

Once per lock, at `juego.asm:105-106`, immediately after the `pintar_tetromino` that locks the piece
and immediately after `limpiar_lineas`:

```asm
    call pintar_tetromino    ; :103  this call IS the lock
    call limpiar_lineas      ; :105  A = rows cleared
    call anotar_lineas       ; :106  consumes A -- nothing may touch A between these two
```

Hooked anywhere else in the pass, the update fires on every gravity step and the score climbs with
nothing cleared. `game-loop-and-collision` owns the loop; `line-clear` owns the call above it.
**Ordering rule:** the scoreboard redraw stays **outside** the erase/draw window, never between
`borrar_tetromino` and `pintar_tetromino` — there the `IX`/`BC` save-restore must nest around code
already using those registers, and one missed `POP` silently moves the piece.

`reiniciar_marcador` is called once per game from `iniciar` (`juego.asm:19`), before any piece
exists — the only point where printing costs nothing and needs no wrapper.

## 10. Gravity is frame-counted

`HALT` once per frame, decrement `contador_frames`, reload from `FRAMES_POR_FILA` when it hits zero.
That is the whole mechanism and `interrupts-and-timing` §5 owns it. The busy-wait it replaced is
gone with `caida.asm`; **do not reintroduce one** — a spin loop's wall-clock speed depends on the
emulator's contention model, so the game plays at a different speed on every target. To change how
fast the game gets, edit `FRAMES_POR_NIVEL` (§8).

## Common mistakes

- **Printing without saving `IX`** — corrupts the falling-piece pointer. Save `BC` too: `PRINTCHAR`'s `DJNZ` destroys `B`, the piece row.
- **Printing inside columns 7-24** — every printed cell becomes an invisible wall.
- **Non-ASCII characters in a message string** — garbage glyphs (§7).
- **`SBC HL, rr` without `OR A` first** — off by one whenever carry happens to be set.
- **A level-to-speed formula instead of the table** — formulas underflow to 0 frames and the game becomes unplayable. The table's floor is 6.
- **Redrawing the score every frame** — wasted T-states inside the border window; redraw only on change (§9).
- **Storing the score as plain binary** — no divide instruction, so displaying it costs an extra divide-by-10 loop. Use packed BCD (§4).
- **Putting anything that touches `A` between `limpiar_lineas` and `anotar_lineas`** — the row count is the return value (§9).
- **Adding `rows` to `PROX_NIVEL` in bulk instead of looping per row** — a 4-row clear that spans a boundary then skips or double-counts a level (§9).
- **Declaring `NIVEL`/`LINEAS`/`FRAMES_POR_FILA` in `puntuacion.asm`** — they already exist in `variables.asm`; two declarations is `Errors: 2, warnings: 4` (§4).
- **Hooking the update anywhere but the lock path** — it then fires on every gravity step, not once per lock (§9).
- **Reintroducing a busy-wait to control drop speed** — edit `FRAMES_POR_NIVEL` instead (§10).
- **Putting a new `INCLUDE` on an existing line in `main.asm`** — silently dropped, 0 errors, 0 warnings (§4).
