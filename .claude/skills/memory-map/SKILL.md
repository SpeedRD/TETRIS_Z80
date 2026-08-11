---
name: memory-map
description: Use when adding a variable, choosing an address, reading or writing screen memory, computing an attribute address, reasoning about where the board lives, reading the keyboard, or touching any port or absolute address in this ZX Spectrum Tetris.
---

# Memory map and hardware interface

Every address below is verified against `main.lst`, the committed listing of the current sources.

## 1. The Spectrum screen: two separate regions

256x192 pixels = 32 columns x 24 rows of 8x8 cells, described by two independent memory regions:

**Pixel display file, `$4000-$57FF` (6144 bytes)** — 1 bit per pixel, monochrome shapes only. Its
addressing is *non-linear*: consecutive pixel rows are not consecutive addresses; `CRtoSCREEN`
(`L30.3 - printat.asm:45`) converts. Used only for the title picture and a decorative bevel.

**Attribute file, `$5800-$5AFF` (768 bytes)** — one byte per character cell, 32 columns x 24
rows, laid out linearly row by row. It sets the colours of the 8x8 cell:

| bit | 7 | 6 | 5-3 | 2-0 |
|---|---|---|---|---|
| meaning | FLASH | BRIGHT | PAPER (background colour 0-7) | INK (foreground colour 0-7) |

Colours: 0 black, 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white. This game
encodes a piece's colour as **PAPER only**, i.e. `colour*8`, INK 0, no FLASH/BRIGHT
(`piezas.asm:5-29`). A solid cell is a non-zero byte; an empty cell is `0`.

**Attribute address formula:**

```
attribute address = $5800 + row*32 + col      ; row 0-23, col 0-31
```

Do not hand-roll it. Two routines do it; both take `B`=row, `C`=col and return `HL`:

| Routine | Register cost | Valid rows |
|---|---|---|
| `CRtoATTR` (`L30.3 - printat.asm:72`) | **preserves `BC`** — the default for new code | **0-23 only.** It does `AND 3 : OR #58` (`:78-79`), so any row above 23 wraps mod 32 |
| `CalcularAtributo` (`pantallas.asm:69`) | **clobbers `BC`** (→ `$5800`) | any `B`, 0-255 |

Leave `CalcularAtributo` at its three existing call sites (`piezas.asm`, `clear.asm`, `test_col.asm`)
— they are written around its `BC` clobber and are correct as they stand. New loops that need the
row/column counter to survive use `CRtoATTR`; `lineas.asm` and `pintar_siguiente` both do. The two
still differ outside rows 0-23 (`B=255, C=15` gives `$77EF` vs `$5BEF`), but nothing passes a row
that high any more — the `B=255` game-over probe is gone. See `rendering-and-attributes`.

## 2. The attribute file IS the board

**There is no board array in RAM.** Nothing stores the settled stack. All collision
(`test_col.asm:24-26`), drawing (`piezas.asm:53`) and erasing (`clear.asm`) read and write
attribute bytes directly. The invariant the whole game rests on:

> **occupied = attribute byte != 0**

1. The yellow border cells are non-zero, so they act as walls for free. No wall-check code exists.
2. **Anything drawn into the well becomes solid, collidable geometry** — including printed
   text. Printing a score inside columns 7-24 creates invisible walls. Print outside the well.

## 3. Board geometry (`tableroJuego.asm`)

| Feature | Attribute cells | Source |
|---|---|---|
| Left wall | column 6, rows 0-21 | `tableroJuego.asm:8-16` |
| Right wall | column 25, rows 0-21 | `tableroJuego.asm:19-27` |
| Floor | row 22, columns 6-25 | `tableroJuego.asm:30-37` |
| Wall/floor attribute | `6*8+7` = 55 = `$37` = yellow paper, white ink | `tableroJuego.asm:10` |

**Playfield interior = columns 7-24 inclusive = 18 columns wide**, rows 0-21 (22 rows). Standard
Tetris is 10 wide; 18 is what this code draws, and 18 stays. Spawn column is 15, defined in exactly
one place — `ld c, 15` in `seleccionar_pieza` (`tetromino_next.asm:75`); `(Medio)` is derived from
`C` by the caller. The interior bounds are also `COL_IZQ_POZO`/`COL_DER_POZO` in `entrada.asm:6-7`
and `COL_IZQ`/`ANCHO_POZO`/`FILA_BAJA` in `lineas.asm:9-11`.

```
       c0        c6                              c25       c31
  r0   . . . . . |#|  . . . . . . . . . . . . .  |#| . . . . .
  r1   . . . . . |#|   interior: columns 7-24    |#| . . . . .
  ...            |#|   (18 wide, rows 0-21)      |#|
  r21  . . . . . |#|  . . . . . . . . . . . . .  |#| . . . . .
  r22  . . . . . |##############################| . . . . .    <- floor
  r23  . . . . . . . . . . . . . . . . . . . . . . . . . . .   <- free
```

`.` = free screen, safe for score/level text. `#` = attribute 55.

## 4. Address map

| Range | Size | Contents | Source |
|---|---|---|---|
| `$0000-$3FFF` | 16K | Spectrum ROM, never paged out | — |
| `$4000-$57FF` | 6144 | Pixel display file | `L35 - Tetris_3D.asm:5` |
| `$5800-$5AFF` | 768 | **Attribute file = the board** | `tableroJuego.asm:8` |
| `$5B00-$7FFF` | 9472 | **Free. Nothing in this program touches it.** The old `TIEMPO_CAIDA`/`NIVEL_ACTUAL` at `$7000-$7003` and the accidental `$77EF` scratch byte all went with `caida.asm` and the `B=255` probe | — |
| `$8000-$A5B9` | 9658 | Program image (code + read-only data + the `variables.asm` block at the very end) | `main.asm:4` |
| ` $8041-$9B40` | 6912 | `TETRIS.scr` title picture, `INCBIN`. `$9B41` is `Pantalla_Ini` | `titulo.asm:32` |
| ` $9CDB-$9CDF` | 5 | `SCR_CUR_PTR`, `SCR_ATTR_PTR`, `PRINT_ATTR` — print library cursor state | `L30.3 - printat.asm:158-160` |
| ` $9CE0-$9FDF` | 768 | `CHARSET` (`charset.bin`, 96 glyphs, ASCII 32-127) | `L30.3 - printat.asm:162` |
| ` $A16A-$A24D` | 228 | 19 piece records, 12 bytes each | `piezas.asm:5-29` |
| ` $A24E-$A25B` | 14 | `spawn_table` — 7 read-only pointers, one per shape | `piezas.asm:35` |
| ` $A362-$A367` | 6 | `giro_kicks` — read-only kick offsets, after `GIRAR`'s `ret` | `giro.asm:67` |
| ` $A428-$A43A` | 19 | `PUNTOS_POR_LINEA`, `FRAMES_POR_NIVEL` — read-only score/speed tables | `puntuacion.asm:15-16` |
| ` $A5AC-$A5B9` | 14 | **`variables.asm` — every mutable byte in the program.** `PUNTOS` `$A5AC`, `LINEAS` `$A5AF`, `NIVEL` `$A5B0`, `PROX_NIVEL` `$A5B1`, `FRAMES_POR_FILA` `$A5B2`, `contador_frames` `$A5B3`, `contador_rapido` `$A5B4`, `teclas_ant` `$A5B5`, `semilla` `$A5B6`, `siguiente_pieza` `$A5B7`, `Medio` `$A5B9` | `variables.asm:13-41` |
| `$A5BA-...` | — | Free RAM, uncontended. First byte past the image. | — |
| `$FFFF` downward | — | Stack. `LD SP, 0` means the first PUSH wraps to `$FFFE/$FFFF` | `main.asm:5, 15` |

Every address above moves if anything earlier in the `INCLUDE` order changes size. Re-derive them
from `main.lst` rather than trusting this table after a structural edit.

**Contention:** `$4000-$7FFF` is shared with the video chip; every access there is slowed
unpredictably. `$8000-$FFFF` is not. See `interrupts-and-timing`.

## 5. All mutable state is 14 bytes, in one block

`variables.asm` at `$A5AC-$A5B9` holds every byte the program writes: score, lines, level, the
level countdown, the normal gravity reload/counter pair (`FRAMES_POR_FILA`/`contador_frames`), an
independent soft-drop counter (`contador_rapido` — its own reload value, `FRAMES_CAIDA_RAPIDA`, is a
code-side `EQU` in `juego.asm`, not a variable), the keyboard mask byte (edge state for K/J/Q/W,
level state for SPACE — `entrada.asm`, `game-loop-and-collision`), the LFSR seed, the preview slot,
and `Medio`.

There is still **no board array** — the attribute file is the board (§2) — and no piece-position
variable. Piece row is `B`, piece column `C`, current piece pointer `IX`; `Medio` is a *copy* of
`C` kept in sync at every commit, not an independent source of truth. Anything that clobbers
`BC`/`IX` moves or changes the piece; read `register-protocol` first.

## 6. Where to put new variables — this section owns the answer

**This is the single place variable placement is decided.** Every other skill cites this section
and declares nothing. There is exactly **one** variables file, `variables.asm`, `INCLUDE`d
**last** (`main.asm:45`), landing at `$A5AC`.

Add your byte to that file, in the section it belongs to, and nowhere else. **A second declaration
of an existing name is a duplicate-label error** (`Errors: 2, warnings: 4` — verified), so grep the
file before adding.

```asm
; the current contents, variables.asm:13-41 -- the ONLY place any of these exist
PUNTOS:          DB 0, 0, 0 ; packed BCD, 6 digits: pairs 1-2, 3-4, 5-6
LINEAS:          DB 0       ; total rows cleared (8-bit binary)
NIVEL:           DB 0       ; current level (8-bit binary)
PROX_NIVEL:      DB 10      ; rows still needed to level up
FRAMES_POR_FILA: DB 48      ; frames between one-row drops (level 0)
contador_frames: DB 48      ; frames left until the next drop
contador_rapido: DB 4       ; frames left until the next SOFT-DROP row. Independent
                            ;  of the pair above: only decrements while SPACE is
                            ;  held (game-loop-and-collision), and is never reset
                            ;  on release, so a new hold resumes where the last
                            ;  one left off
teclas_ant:      DB 0       ; previous leer_teclas mask; 1 = PRESSED (already
                            ;  inverted), now including SPACE's bit
semilla:         DB $A5     ; LFSR state. MUST be non-zero -- a zero LFSR stays zero
siguiente_pieza: DW T_0     ; preview slot. Starts at a VALID record, never 0
Medio:           DB 15      ; memory copy of the current column (C)
```

Use as `LD A,(NIVEL)` / `LD (NIVEL),A` / `LD HL,(siguiente_pieza)`. Appending to this block is
sanctioned; *interleaving* is not — no `DB` inside a routine's code path, and never a variable
tacked onto the end of the piece table.

**Why not next to the piece table?** `Medio` used to live at `piezas.asm:31`, immediately after the
last record `T_S2`, with **zero margin**: the old spawn RNG indexed the table arithmetically and one
extra record would have made it read `Medio` as piece data. Selection is now a lookup in the
read-only `spawn_table`, so nothing indexes the records by arithmetic any more — but the placement
rule stands regardless, because `variables.asm` keeps every mutable byte together, uncontended, past
the end of the code, and referenced only by label.

**Never place variables high in memory.** `LD SP, 0` (`main.asm:5`) puts the stack at `$FFFF`
growing downward through RAM. (The 48K system variables are far below, at `$5C00-$5CB5`; the
only thing up here is the UDG area, roughly `$FF58-$FFFF`.) Anything above about `$FF00` is
overwritten by pushes and interrupts.

## 7. Port I/O — there is no memory-mapped I/O

No memory-mapped hardware registers exist; all I/O uses `IN`/`OUT`. The keyboard is a matrix of
8 half-rows of 5 keys. To read one half-row:

```asm
    push bc             ; MANDATORY: B is the piece row and C the piece column, globally (§5)
    LD BC, $FBFE        ; B = half-row select, C = $FE (the ULA port)
    IN A,(C)            ; bits 0-4 = the five keys; bits 5-7 are NOT keyboard data
    pop bc              ; piece position restored before anything can use it
    BIT 0,A
    JR Z, key_pressed   ; ACTIVE LOW: a pressed key reads as 0
```

The port number needs `BC`, which is exactly where the piece position lives, so every real caller
pushes it first (`entrada.asm:25`, `pantallas.asm:92`). Omit the push and the piece teleports.

**A pressed key is a `0` bit.** Test with `BIT n,A` + `JR Z`. To test "nothing pressed", **mask to
bits 0-4 first and compare against `$1F`** — bits 5-7 are not keyboard data and bit 6 is the EAR
line, which reads 0 under ZEsarUX. `CP $FF` on a raw port byte is wrong and used to hang the title
screen; see `interrupts-and-timing` §6.

| Port | bit0 | bit1 | bit2 | bit3 | bit4 | Sites |
|---|---|---|---|---|---|---|
| `$FBFE` | Q | W | E | R | T | `titulo.asm:20`, `entrada.asm:31` |
| `$BFFE` | ENTER | L | K | J | H | `entrada.asm:26` |
| `$7FFE` | SPACE | SYM SHIFT | M | N | B | `entrada.asm:36`, `pantallas.asm:92` |
| `$FDFE` | A | S | D | F | G | `pantallas.asm:96` |

Controls as implemented: **Q** rotate left, **W** rotate right, **J** move left, **K** move right,
**SPACE** soft drop (all five read once per frame by `leer_teclas`, `entrada.asm:24-54`), **S** start
(`pantallas.asm:98`), **N** quit (`pantallas.asm:95`), **Q** dismiss title (`titulo.asm:22`).

**SPACE is read differently from the other four.** K/J/Q/W are edge-detected — `leer_teclas` reports
only the not-pressed → pressed transition, so a held key reads `0` again next frame. SPACE (soft
drop) is deliberately **level-triggered** instead: its bit reads `1` on *every* frame the key is
down, not just the first, and `0` the instant it releases, because `juego.asm`'s fast-gravity gate
needs "is it down right now", not "did it just go down" — an edge-triggered SPACE would drop one
extra row per press and do nothing while held, a one-shot action rather than a soft drop. Both
conventions are folded into the one byte `leer_teclas` returns and the one byte `teclas_ant`
remembers between frames; see `game-loop-and-collision` §2 and §7 for the bit layout and the full
contract. **Port `$7FFE` is now read from two places for two different reasons**: `entrada.asm`
polls SPACE once per frame for gameplay, and `pantallas.asm:92` still separately blocks on N to quit
from the menu — they don't share state and don't need to.

**Port `$FE` is never written.** Writing it sets the border colour (bits 0-2) and toggles the
beeper (bit 4) — so the game is silent and never sets the border.

## Common mistakes

- **`$5800 + row*24 + col`.** Wrong. The stride is **32** (columns per row); 24 is the row count.
- **Declaring a variable in the file that uses it** instead of `variables.asm` (§6). A name declared
  twice is a duplicate-label error; a name declared in the wrong place drifts.
- **Moving `variables.asm` out of last position** in the `INCLUDE` list. Every address shifts.
- **Looking for the board array.** There isn't one. Read the attribute file at `$5800`.
- **Printing text inside columns 7-24.** Non-zero attributes are solid; the text becomes an
  invisible wall. Print in columns 0-5 or 26-31, or row 23.
- **Treating a keyboard bit as 1 = pressed.** It is active low: 0 = pressed.
- **Treating SPACE's `leer_teclas` bit as edge-triggered like K/J/Q/W's.** It is level-triggered on
  purpose, for soft drop (§7, `game-loop-and-collision`).
- **Comparing a raw keyboard port byte against `$FF`.** Mask to `$1F` first (§7).
- **Assuming `$5B00-$7FFF` is used.** It is entirely free; nothing lives below `$8000` any more.
- **Reading a port without `push bc`.** The port number lands in `BC`, which is the piece position.
- **Putting a variable near `$FF00` or above.** The stack grows down from `$FFFF` and will eat it.
- **Assuming the pixel display file is linear.** It is not; use `L30.3 - printat.asm`.
