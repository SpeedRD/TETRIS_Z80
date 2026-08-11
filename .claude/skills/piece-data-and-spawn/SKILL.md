---
name: piece-data-and-spawn
description: Use when editing tetromino shape data, colours, rotation pointers or spawn_table in piezas.asm; when adding or removing a piece record; or when changing which piece spawns, the spawn column, the LFSR piece selection, or the next-piece preview in tetromino_next.asm.
---

# Piece data format and the spawn path

Owns `piezas.asm:1-35` (the records and `spawn_table`) and all of `tetromino_next.asm`. Elsewhere: following
rotation pointers `piece-rotation`; drawing `rendering-and-attributes`; the loop
`game-loop-and-collision`; **where variables live `memory-map` §6**.

Spanish: `piezas`/`pieza` = pieces/piece, `seleccionar_pieza` = select piece, `nueva_pieza` = new
piece, `sembrar_azar` = seed the randomness, `iniciar_secuencia` = start the sequence,
`siguiente_pieza` / `pintar_siguiente` = next piece / paint the next one, `Medio` = middle (the
current column), `filas`/`columnas` = rows/columns, `girar` = rotate, `semilla` = seed.

Background: the **attribute file** at `$5800` is the board — one byte per 8x8 cell, 32 bytes per
screen row — and **`0` means empty**, so collision is literally `attribute byte != 0`
(`test_col.asm:24-26`). `IX` is the Z80 index register (`(ix+n)` = the byte `n` past it) and
globally holds the current piece record. Well interior: columns **7-24** (`tableroJuego.asm:8,19`).

## 1. The 12-byte record format

| Offset | Contents | Read by |
|---|---|---|
| `+0` | rows (`filas`) | `piezas.asm:50`, `test_col.asm:13` |
| `+1` | cols (`columnas`) | `piezas.asm:51,67`, `test_col.asm:14,35`; also `en_rango` (`entrada.asm:46`) and `GIRAR`'s recentring (`giro.asm:29,32`) |
| `+2 .. +7` | 6 attribute bytes, row-major, `0` = empty | `piezas.asm:53,56`, `test_col.asm:17,20` |
| `+8 .. +9` | address of rotate-**left** successor (lo, hi) | `giro.asm:20-21` |
| `+10 .. +11` | address of rotate-**right** successor (lo, hi) | `giro.asm:24-25` |

Record size is **12 bytes**, `$A154` to `$A237`. There is no longer a `longitud_pieza` constant —
it existed only for the old arithmetic index into the table, which `spawn_table` replaced (§5).
Drawing and collision both read exactly `rows * cols` bytes from `+2`, and only 6 bytes exist
before the rotation pointers:

> **`rows * cols <= 6`.** No exceptions. Permitted boxes: 1x1..1x6, 2x1, 2x2, 2x3, 3x1, 3x2, 4x1,
> 5x1, 6x1. **4x4 is impossible**, so SRS-style piece data cannot be dropped in without changing the
> record size and every `(ix+n)` offset that depends on it — see §4.

Bytes past `rows * cols` are never read (`T_0` is 2x2; its last two are dead) but must still be
emitted, so every record is 12 bytes.

## 2. The record table (all 19, addresses from `main.lst`)

Labels are `T_0` (the O piece), then `T_<shape><n>`. States per shape: **1 / 4 / 4 / 4 / 2 / 2 / 2**.

| Idx | Label | Addr | Shape | rows x cols | Colour | Src |
|---|---|---|---|---|---|---|
| 0 | `T_0` | `$A154` | O | 2x2 | `6*8` yellow | `piezas.asm:5` |
| 1 | `T_L1` | `$A160` | L | 3x2 | `4*8` green | `piezas.asm:7` |
| 2 | `T_L2` | `$A16C` | L | 2x3 | `4*8` green | `piezas.asm:8` |
| 3 | `T_L3` | `$A178` | L | 2x3 | `4*8` green | `piezas.asm:9` |
| 4 | `T_L4` | `$A184` | L | 3x2 | `4*8` green | `piezas.asm:10` |
| 5 | `T_J1` | `$A190` | J | 3x2 | `2*8` red | `piezas.asm:12` |
| 6 | `T_J2` | `$A19C` | J | 2x3 | `2*8` red | `piezas.asm:13` |
| 7 | `T_J3` | `$A1A8` | J | 2x3 | `2*8` red | `piezas.asm:14` |
| 8 | `T_J4` | `$A1B4` | J | 3x2 | `2*8` red | `piezas.asm:15` |
| 9 | `T_T1` | `$A1C0` | T | 2x3 | `5*8` cyan | `piezas.asm:17` |
| 10 | `T_T2` | `$A1CC` | T | 3x2 | `5*8` cyan | `piezas.asm:18` |
| 11 | `T_T3` | `$A1D8` | T | 3x2 | `5*8` cyan | `piezas.asm:19` |
| 12 | `T_T4` | `$A1E4` | T | 2x3 | `5*8` cyan | `piezas.asm:20` |
| 13 | `T_I1` | `$A1F0` | I | 4x1 | `1*8` blue | `piezas.asm:22` |
| 14 | `T_I2` | `$A1FC` | I | 1x4 | `1*8` blue | `piezas.asm:23` |
| 15 | `T_Z1` | `$A208` | Z | 2x3 | `7*8` white | `piezas.asm:25` |
| 16 | `T_Z2` | `$A214` | Z | 3x2 | `7*8` white | `piezas.asm:26` |
| 17 | `T_S1` | `$A220` | S | 2x3 | `3*8` magenta | `piezas.asm:28` |
| 18 | `T_S2` | `$A22C` | S | 3x2 | `3*8` magenta | `piezas.asm:29` |

The "Idx" column is now only a reading aid — nothing indexes the table arithmetically (§5). Every
address shifts if anything earlier in the `INCLUDE` order changes size; re-read them from `main.lst`.

## 3. Colours

Colour lives **inside each pattern byte** as `colour*8` (the ZX PAPER field), so a non-zero pattern
byte says *both* "filled" *and* "this colour"; `pintar_tetromino` copies it straight to the
attribute file (`piezas.asm:53`). Bit layout: `rendering-and-attributes`.

| Value | Hex | Colour | Used by |
|---|---|---|---|
| `1*8` | `$08` | blue | I |
| `2*8` | `$10` | red | J |
| `3*8` | `$18` | magenta | S |
| `4*8` | `$20` | green | L |
| `5*8` | `$28` | cyan | T |
| `6*8` | `$30` | yellow | O — and the border, as `6*8+7` |
| `7*8` | `$38` | white | Z |

**All seven shapes are distinct.** They were not: the submitted table had Z/S both on `7*8` and O/I
both on `6*8`. I moved to `1*8` and S to `3*8`, each with the reason in the comment above its
records (`piezas.asm:21,27`). There is **no free value left** — adding an eighth shape means either
reusing a colour deliberately or going beyond PAPER-only encoding (BRIGHT, bit 6, would give a
second set; `rendering-and-attributes` §1 has the bit layout). A colour **must be non-zero**;
`0*8` = 0 = empty, which deletes the cell.

## 4. Record size is a coupled unit

Records are indexed only by **label** now — `spawn_table` (`piezas.asm:35`) holds seven pointers and
the rotation pointers at `+8..+11` hold the rest — so a wrong record count no longer runs off the
end of the table into the next byte.

That safety came from deleting the arithmetic index, and it is worth knowing what it replaced:
`Medio: DB 14` used to sit **immediately** after the last record with zero margin, while the spawn
RNG computed `T_0 + index*12` under a `cp 19` / `sub 19` clamp. Index 19 would have pointed `IX` at
`Medio`, and `pintar_tetromino` would have read `rows` = 14 and `cols` = the following opcode byte
`$F5` = 245 — a 3430-byte write over a 768-byte attribute file.

> **Rule:** if you change the record size, you change `+8..+11`'s meaning and every `(ix+n)` offset
> in `piezas.asm`, `clear.asm`, `test_col.asm`, `entrada.asm` and `giro.asm`. Do it in one edit, and
> rebuild and re-read the addresses from `main.lst`.
>
> **Never add a variable after the last record.** Variables go in `variables.asm`, `INCLUDE`d last
> (`memory-map` §6). `spawn_table` may sit there because it is read-only.

## 5. `seleccionar_pieza` — the spawn path

`seleccionar_pieza` (`tetromino_next.asm:65-76`) runs **once per lock, not once per gravity step**:
from `iniciar` for the first piece (`juego.asm:23`) and from the lock path (`juego.asm:108`). It
puts the already-announced piece into play and draws the next one, so the player always sees one
ahead.

Four routines, in dependency order:

| Routine | Lines | Does |
|---|---|---|
| `sembrar_azar` | `:17-24` | `ld a, r` into `semilla`, forced non-zero. Once per game, **after** the player presses S — the variable number of keyboard-wait iterations is what makes it actually vary |
| `nueva_pieza` | `:28-47` | One LFSR draw → `DE` = a `spawn_table` record address |
| `iniciar_secuencia` | `:51-57` | `sembrar_azar` + one `nueva_pieza` into `siguiente_pieza`. Once per game, before the first spawn |
| `seleccionar_pieza` | `:65-76` | `IX` ← `siguiente_pieza`; refill `siguiente_pieza` with a fresh draw; return `B=0, C=15` |

**Randomness is an 8-bit Galois LFSR** (`:31-36`): `srl a`, and on carry `xor $B4`. Period 255, and
it never reaches zero — which is why `semilla` **must** start non-zero and why `sembrar_azar` has
its `or a` / `ld a,$A5` guard. `and 7` then rejecting 7 (`:37-39`) gives a uniform 0..6; the retry
jumps to `np_tirar`, **below** the `push hl`, so it cannot leak stack.

`tests/test_spawn.py` asserts the distribution is ~14.3% per shape, that the LFSR never reaches
zero, and that the previewed piece is the one that actually spawns.

### What this replaced

The old `seleccionar_pieza` picked a random **rotation state** out of all 19 records, not a shape,
using `ld a, r` as entropy and folding 19..31 back onto 0..12. Two consequences: pieces spawned in
a random orientation, and because L, J and T have four states each they were 75% of all spawns
(25% each) against 6.25% for O, I, Z and S. `ld a, r` was also poor entropy on its own — the call
site is reached along a fixed instruction path, so consecutive reads differ by a near-constant
amount. It survives only as the one-shot seed, where a single unpredictable value is all that is
needed.

### The spawn column has exactly one definition

`ld c, 15` at `tetromino_next.asm:75`. Everything else derives from it: `juego.asm:25-26` and
`:110-111` copy `C` into `(Medio)` right after each call, and the `Medio: DB 15` in
`variables.asm:36` is an inert placeholder overwritten before the first piece is drawn. There used
to be three disagreeing definitions (14, 15, 15). **Keep it at one.**

## 6. The next-piece preview

`pintar_siguiente` (`tetromino_next.asm:90-110`) draws it, into a 4x4 box at rows 10-13, columns
27-30 (`PREV_FILA`/`PREV_COL`, `:85-86`). It blanks the box row by row with `CRtoATTR` — which
preserves `BC`, unlike `CalcularAtributo` — then calls `pintar_tetromino` with `IX` from
`siguiente_pieza`. It preserves every register, so it can be called from the middle of the loop.

It is called twice: at `juego.asm:24` for the first piece and `juego.asm:109` after each lock, both
times immediately after `seleccionar_pieza` so the box always shows the piece that has just been
announced rather than the one now falling.

> **Critical:** collision is "attribute byte != 0", so **anything drawn in columns 7-24 becomes
> solid geometry.** Columns 27-30 are outside the well and outside anything `en_rango` will let a
> piece or a rotation kick reach. If you move the box, keep it in columns **0-5** or **26-31**.
>
> The box is blanked to `0`, the same as the well interior — never to a "background" attribute, for
> the reason in `rendering-and-attributes` §3.

## 7. Adding or editing a shape

1. Bounding box with `rows * cols <= 6`; then `DB rows, cols,` and **exactly six** pattern bytes,
   row-major, `0` for empty.
2. A non-zero colour. All seven values are taken (§3), so decide deliberately what to share.
3. `DW <left successor>, <right successor>` — wire **both** directions, close the cycle, verify
   with `piece-rotation` and `tests/test_giro.py`.
4. If it is a new *shape* rather than a new state, add its spawn record to `spawn_table` (§5) — and
   note the draw is `and 7` with 7 rejected, so a table of 8 entries needs the reject removed and
   anything other than 7 or 8 entries needs a different reduction.
5. Rebuild; confirm in `main.lst` that addresses moved by exactly 12 per inserted record
   (`build-and-verify`), then run `tests/run_all.py`.

## Common mistakes

- **Writing 7+ pattern bytes.** Silently overwrites the record's own rotation pointers (`+8..+11`)
  and shifts every later record. No assembler error.
- **Using `0` as a colour.** The cell is empty and non-collidable — a hole in the piece.
- **Adding a shape to `spawn_table` without fixing the `and 7` / `cp 7` reduction.** The new entry
  is never drawn, or the draw indexes past the table (§5).
- **Letting `semilla` reach zero,** or initialising it to zero. A zero LFSR stays zero and every
  piece is the same one forever.
- **Putting `semilla`, `siguiente_pieza` or any variable in `piezas.asm`.** Variables go in
  `variables.asm` (`memory-map` §6); `piezas.asm` is read-only data now.
- **Assuming `seleccionar_pieza` runs every gravity step.** Once per lock (§5).
- **Calling `seleccionar_pieza` without `pintar_siguiente` right after it.** The preview box then
  shows a piece that is already falling.
- **Wiring a rotation pointer one way only.** Rotate right then left and you land elsewhere.
- **Drawing the preview inside columns 7-24.** Creates an invisible wall.
- **Reordering the `INCLUDE`s for `tetromino_next.asm` and `piezas.asm`.** It still assembles at
  0 errors / 0 warnings — sjasmplus resolves either direction — but every address in §2 shifts, so
  re-read them from a fresh `main.lst`.
