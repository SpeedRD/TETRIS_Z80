---
name: piece-data-and-spawn
description: Use when editing tetromino shape data, colours, or rotation pointers in piezas.asm; when adding or removing a piece record; when changing which piece spawns, the spawn column, or the random piece selection in tetromino_next.asm; or when adding the missing next-piece preview.
---

# Piece data format and the spawn path

Owns `piezas.asm:1-31` (the data table) and all of `tetromino_next.asm`. Elsewhere: following
rotation pointers `piece-rotation`; drawing `rendering-and-attributes`; the loop
`game-loop-and-collision`; **where variables live `memory-map` §6**.

Spanish: `piezas`/`pieza` = pieces/piece, `seleccionar_pieza` = select piece, `longitud_pieza` =
piece length, `Medio` = middle (the current column), `siguiente` = next, `filas`/`columnas` =
rows/columns, `girar` = rotate, `semilla` = seed.

Background: the **attribute file** at `$5800` is the board — one byte per 8x8 cell, 32 bytes per
screen row — and **`0` means empty**, so collision is literally `attribute byte != 0`
(`test_col.asm:24-26`). `IX` is the Z80 index register (`(ix+n)` = the byte `n` past it) and
globally holds the current piece record. Well interior: columns **7-24** (`tableroJuego.asm:8,19`).

## 1. The 12-byte record format

| Offset | Contents | Read by |
|---|---|---|
| `+0` | rows (`filas`) | `piezas.asm:42`, `test_col.asm:12` |
| `+1` | cols (`columnas`) | `piezas.asm:43,59`, `test_col.asm:13,34` |
| `+2 .. +7` | 6 attribute bytes, row-major, `0` = empty | `piezas.asm:45,48`, `test_col.asm:16,19` |
| `+8 .. +9` | address of rotate-**left** successor (lo, hi) | `giro.asm:17-18` |
| `+10 .. +11` | address of rotate-**right** successor (lo, hi) | `giro.asm:25-26` |

`longitud_pieza EQU T_L1 - T_0` (`tetromino_next.asm:3`) = **12**; confirmed at `main.lst:523`,
where `ld de, longitud_pieza` assembles as `11 0C 00` (`$000C`). Drawing and collision both read
exactly `rows * cols` bytes from `+2`, and only 6 bytes exist before the rotation pointers:

> **`rows * cols <= 6`.** No exceptions. Permitted boxes: 1x1..1x6, 2x1, 2x2, 2x3, 3x1, 3x2, 4x1,
> 5x1, 6x1. **4x4 is impossible**, so SRS-style piece data cannot be dropped in without changing
> the record size, `longitud_pieza` and §4 together.

Bytes past `rows * cols` are never read (`T_0` is 2x2; its last two are dead) but must still be
emitted, so every record is 12 bytes.

## 2. The record table (all 19, addresses from `main.lst`)

Labels are `T_0` (the O piece), then `T_<shape><n>`. States per shape: **1 / 4 / 4 / 4 / 2 / 2 / 2**.

| Idx | Label | Addr | Shape | rows x cols | Colour | Src |
|---|---|---|---|---|---|---|
| 0 | `T_0` | `$A08B` | O | 2x2 | `6*8` yellow | `piezas.asm:5` |
| 1 | `T_L1` | `$A097` | L | 3x2 | `4*8` green | `piezas.asm:7` |
| 2 | `T_L2` | `$A0A3` | L | 2x3 | `4*8` green | `piezas.asm:8` |
| 3 | `T_L3` | `$A0AF` | L | 2x3 | `4*8` green | `piezas.asm:9` |
| 4 | `T_L4` | `$A0BB` | L | 3x2 | `4*8` green | `piezas.asm:10` |
| 5 | `T_J1` | `$A0C7` | J | 3x2 | `2*8` red | `piezas.asm:12` |
| 6 | `T_J2` | `$A0D3` | J | 2x3 | `2*8` red | `piezas.asm:13` |
| 7 | `T_J3` | `$A0DF` | J | 2x3 | `2*8` red | `piezas.asm:14` |
| 8 | `T_J4` | `$A0EB` | J | 3x2 | `2*8` red | `piezas.asm:15` |
| 9 | `T_T1` | `$A0F7` | T | 2x3 | `5*8` cyan | `piezas.asm:17` |
| 10 | `T_T2` | `$A103` | T | 3x2 | `5*8` cyan | `piezas.asm:18` |
| 11 | `T_T3` | `$A10F` | T | 3x2 | `5*8` cyan | `piezas.asm:19` |
| 12 | `T_T4` | `$A11B` | T | 2x3 | `5*8` cyan | `piezas.asm:20` |
| 13 | `T_I1` | `$A127` | I | 4x1 | `6*8` yellow | `piezas.asm:22` |
| 14 | `T_I2` | `$A133` | I | 1x4 | `6*8` yellow | `piezas.asm:23` |
| 15 | `T_Z1` | `$A13F` | Z | 2x3 | `7*8` white | `piezas.asm:25` |
| 16 | `T_Z2` | `$A14B` | Z | 3x2 | `7*8` white | `piezas.asm:26` |
| 17 | `T_S1` | `$A157` | S | 2x3 | `7*8` white | `piezas.asm:28` |
| 18 | `T_S2` | `$A163` | S | 3x2 | `7*8` white | `piezas.asm:29` |

## 3. Colours

Colour lives **inside each pattern byte** as `colour*8` (the ZX PAPER field), so a non-zero pattern
byte says *both* "filled" *and* "this colour"; `pintar_tetromino` copies it straight to the
attribute file (`piezas.asm:53`). Bit layout: `rendering-and-attributes`.

| Value | Hex | Colour | Used by |
|---|---|---|---|
| `1*8` | `$08` | blue | **free** |
| `2*8` | `$10` | red | J |
| `3*8` | `$18` | magenta | **free** |
| `4*8` | `$20` | green | L |
| `5*8` | `$28` | cyan | T |
| `6*8` | `$30` | yellow | **O and I (collision)** |
| `7*8` | `$38` | white | **Z and S (collision)** |

**Two colour collisions, not one**: Z/S share `7*8`, O/I share `6*8`. Exactly two free values
remain — enough to fix both. Change the constant in **both** records of one shape of a pair, e.g.
`piezas.asm:28-29` `7*8` -> `3*8` makes S magenta. It **must be non-zero**; `0*8` = 0 = empty,
which deletes the piece.

## 4. The `Medio` adjacency hazard — the margin is ZERO

`Medio: DB 14` sits at `$A16F` (`piezas.asm:31`, `main.lst:609`) **immediately** after the last
record: `T_S2` is `$A163`, and `$A163 + 12 = $A16F`. The clamp allows indices 0-18 and index 18
lands on `T_S2`, so there is **no spare record between the table and `Medio`** and no assertion.

Index 19 would point `IX` at `Medio`: `pintar_tetromino` would read `rows = (ix+0)` = 14 and
`cols = (ix+1)` = the byte at `$A170` = `$F5` = **245** (the `push af` opcode that follows) — a
14 x 245 = **3430-byte** write over a 768-byte attribute file, the whole screen and far beyond.

> **Rule:** the record count, the `cp 19` / `sub 19` clamp (`tetromino_next.asm:9,11`) and the
> record size are one coupled unit. Change any of them in a single edit, then rebuild and confirm
> the last record's address and `Medio`'s address in `main.lst`.
>
> **Never add a new variable after the last record.** Variables go in `variables.asm`, `INCLUDE`d
> last, landing at `$A2C7` (`memory-map` §6).

## 5. `seleccionar_pieza` — the spawn path

Whole routine: `tetromino_next.asm:5-26`. It runs **once per lock, not once per gravity step.** Its
only caller is `iniciar` (`juego.asm:4`), reached by the fall-through at `juego.asm:34-37` — the
branch taken when `comprobar` reports a collision. The keep-falling branch is `cambiar_tetromino`
(`juego.asm:39`), despite the name, and it loops back to `ciclo_juego` without re-selecting
(`game-loop-and-collision`, `project-orientation`).

**Entropy is `ld a, r` (`:7`)** — the Z80 memory-refresh counter, whose low 7 bits increment once
per opcode fetch. Not random: the call site is reached along a fixed instruction path, so
consecutive reads differ by a near-constant amount. Short period, strongly correlated.

**Index computation (`:8-21`):** `and 31` (A = 0..31), `cp 19`, `jr c` keeps A < 19, else `sub 19`
maps 19..31 -> 0..12; then `IX = T_0 + A*12` by repeated `add ix, de` with `de = 12`. Indices
**0-12 get two of the 32 source values and 13-18 get one** — 0-12 are twice as likely.

**The deeper bug: it picks a rotation STATE, not a piece.** 19 states over 7 shapes, so pieces
spawn in a random orientation and 4-state shapes dominate. With the bias above (assuming `ld a,r`
were uniform):

| Shape | States | Indices | Weight /32 | P |
|---|---|---|---|---|
| L | 4 | 1-4 | 8 | **25.0%** |
| J | 4 | 5-8 | 8 | **25.0%** |
| T | 4 | 9-12 | 8 | **25.0%** |
| O | 1 | 0 | 2 | 6.25% |
| I | 2 | 13-14 | 2 | 6.25% |
| Z | 2 | 15-16 | 2 | 6.25% |
| S | 2 | 17-18 | 2 | 6.25% |

L, J and T are 75% of all spawns; a fair game would be 14.3% each.

### Correct replacement — verified, `Errors: 0, warnings: 0`

Select a **shape** from a 7-entry table of spawn states, then follow it.

```asm
; --- in variables.asm (memory-map §6). The seed is a VARIABLE; it must NOT go in piezas.asm ---
semilla:     DB $A5   ; "seed". MUST be non-zero -- a zero LFSR state stays zero forever.

; --- in piezas.asm after the records: read-only table data, so §4's hazard does not apply ---
spawn_table: DW T_0, T_L1, T_J1, T_T1, T_I1, T_Z1, T_S1

; --- replaces tetromino_next.asm:5-26 ---
; OUT: IX = spawn record, B = 0 (row), C = 15 (column).
; Clobbers AF, BC, DE, IX. Preserves HL and IY -- the same contract as the original.
seleccionar_pieza:
    push hl                 ; the original preserves HL; keep it that way
sp_tirar:
    ld a, (semilla)         ; 8-bit Galois LFSR, period 255, never yields 0
    srl a                   ; shift right, low bit into carry
    jr nc, sp_sin_tap
    xor $B4                 ; feedback taps
sp_sin_tap:
    ld (semilla), a
    and 7 : cp 7
    jr z, sp_tirar          ; reject 7 -> uniform 0..6 (retry is BELOW the push: no stack leak)
    add a, a                ; *2: table entries are 2 bytes
    ld hl, spawn_table
    ld d, 0 : ld e, a : add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    ld ix, de               ; sjasmplus fake instr -> LD IXH,D : LD IXL,E (bytes DD 62 DD 6B)
    pop hl
    ld b, 0 : ld c, 15      ; row, column
    ret
```

`ld ix, de` is the same fake instruction used at `giro.asm:19,27` (`assembler-conventions`). To
vary the sequence per run, write `ld a,r` into `semilla` once at the first keypress — never zero.

### Return values and the spawn column — three sources disagree

| Value | Where | `file:line` |
|---|---|---|
| `C = 15` | `seleccionar_pieza` return | `tetromino_next.asm:25` |
| `Medio = 14` | initialiser in the data table | `piezas.asm:31` |
| `Medio = 15` | written by `iniciar` right after the call | `juego.asm:7-8` |

**`juego.asm:7-8` wins at runtime** — it overwrites the `DB 14`, and `B` is overwritten with 255 at
`juego.asm:6`, so the returned `B = 0` is dead too; the loop reloads `C` from `Medio`
(`juego.asm:25-26,35,40`). **Rule: exactly one definition of the spawn column** — pick a site and
make the other two derive from it or delete them. `fin_selec_pieza: jr fin_selec_pieza` (`:28`) is
an unreachable debug trap after the `ret`; do not make it reachable (`failure-patterns` §3.8).

## 6. Adding the next-piece preview

`tetromino_next.asm` is named for a preview it does not contain. Because selection happens once per
lock (§5), a one-slot lookahead is enough:

1. Add a 2-byte `siguiente_pieza` (= next piece) holding a record address — in `variables.asm`
   (`memory-map` §6), **not** next to `Medio`.
2. Split selection from spawning: a `nueva_pieza` helper returns a record address; at boot, call it
   once into `siguiente_pieza`.
3. `seleccionar_pieza` loads `IX` from `siguiente_pieza`, then refills it with a fresh call.
4. Draw with `pintar_tetromino` using a separate `B`/`C`, and erase before redrawing.

> **Critical:** collision is "attribute byte != 0", so **anything drawn in columns 7-24 becomes
> solid geometry.** Draw the preview only in columns **0-5** or **26-31**.

## 7. Adding or editing a shape

1. Bounding box with `rows * cols <= 6`; then `DB rows, cols,` and **exactly six** pattern bytes,
   row-major, `0` for empty.
2. A non-zero colour; pick an unused one (§3) if it must be distinct.
3. `DW <left successor>, <right successor>` — wire **both** directions, close the cycle, verify
   with `piece-rotation`.
4. If the record count changed, update the clamp (§4) **in the same edit** and `spawn_table` (§5).
5. Rebuild; confirm in `main.lst` that addresses moved by exactly 12 per inserted record and that
   `Medio` moved with them (`build-and-verify`).

## Common mistakes

- **Writing 7+ pattern bytes.** Silently overwrites the record's own rotation pointers (`+8..+11`)
  and shifts every later record. No assembler error.
- **Using `0` as a colour.** The cell is empty and non-collidable — a hole in the piece.
- **Adding a record without updating the `cp 19` / `sub 19` clamp.** New records unreachable, or
  indexing reads a variable (§4).
- **Putting `semilla`, `siguiente_pieza` or any variable after the last record.** It lands in the
  index's blast radius; variables go in `variables.asm` (`memory-map` §6).
- **Assuming the index picks a piece.** It picks a rotation state (§5).
- **Assuming `seleccionar_pieza` runs every gravity step.** Once per lock (§5).
- **Wiring a rotation pointer one way only.** Rotate right then left and you land elsewhere.
- **Drawing the preview inside columns 7-24.** Creates an invisible wall.
- **Believing `main.asm:25-26` cannot be reordered.** Swapping the two `INCLUDE`s assembles at
  0 errors / 0 warnings and `ld de, longitud_pieza` still emits `11 0C 00` — the forward reference
  just becomes a backward one. What *does* change is every address: `Medio` moves `$A16F` ->
  `$A14F`, records shift with it, so re-check §2 and §4 against a fresh `main.lst`.
