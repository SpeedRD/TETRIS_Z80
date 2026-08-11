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
| `CalcularAtributo` (`pantallas.asm:67`) | **clobbers `BC`** (→ `$5800`) | any `B`, 0-255 |

Leave `CalcularAtributo` at every existing call site, and use it for out-of-range probes: with
`B=255, C=15` it gives `$77EF` but `CRtoATTR` gives `$5BEF`, so swapping `CRtoATTR` into
`test_col.asm` silently relocates the game-over probe. See `rendering-and-attributes`.

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
Tetris is 10 wide; 18 is what this code draws, and 18 stays. Spawn column is 15 (`juego.asm:7`).

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
| `$5B00-$6FFF` | 5376 | **Free. Nothing in this program touches it.** | — |
| `$7000-$7001` | 2 | `TIEMPO_CAIDA` ("fall time") | `caida.asm:10` |
| `$7002-$7003` | 2 | `NIVEL_ACTUAL` ("current level") — **never written by any code**, read once at `caida.asm:22` and discarded | `caida.asm:11` |
| `$7004-$7FFF` | 4092 | Free — except `$77EF`, an accidental scratch byte: `comprobar` called with B=255, C=15 computes and reads that address. Not intentional; see `game-loop-and-collision` | `juego.asm:6,10` |
| `$8000-$A2C6` | 8903 | Program image (code + data + `Medio`, interleaved) | `main.asm:4` |
| ` $8036-$9B35` | 6912 | `TETRIS.scr` title picture, `INCBIN`. `$9B36` is `Pantalla_Ini` | `titulo.asm:33` |
| ` $9CD2-$9CD6` | 5 | `SCR_CUR_PTR`, `SCR_ATTR_PTR`, `PRINT_ATTR` — print library cursor state | `L30.3 - printat.asm:158-160` |
| ` $9CD7-$9FD6` | 768 | `CHARSET` (`charset.bin`, 96 glyphs, ASCII 32-127) | `L30.3 - printat.asm:162` |
| ` $A08B-$A16E` | 228 | 19 piece records, 12 bytes each | `piezas.asm:5-29` |
| ` $A16F` | 1 | `Medio` ("middle") — current piece column | `piezas.asm:31` |
| `$A2C7-...` | — | Free RAM, uncontended. First byte past the image. | — |
| `$FFFF` downward | — | Stack. `LD SP, 0` means the first PUSH wraps to `$FFFE/$FFFF` | `main.asm:5` |

**Contention:** `$4000-$7FFF` is shared with the video chip; every access there is slowed
unpredictably. `$8000-$FFFF` is not. See `interrupts-and-timing`.

## 5. Total mutable state is one byte

`Medio` at `$A16F`, plus the two bytes at `$7000` written but never meaningfully read. There is
**no** board array, **no** score, **no** level, **no** line counter, **no** piece-position
variable, **no** next-piece slot. Piece row is `B`, piece column `C`, current piece pointer `IX`
— registers only. Anything that clobbers `BC`/`IX` moves or changes the piece; read
`register-protocol` first.

## 6. Where to put new variables — this section owns the answer

**This is the single place variable placement is decided.** Every other skill cites this section
and declares nothing. There is exactly **one** variables file, `variables.asm`, `INCLUDE`d
**last**, landing at `$A2C7`.

`Medio` sits at `$A16F` **inside the code image**, immediately after the last piece record `T_S2`
(`piezas.asm:29-31`). Do not copy that pattern: there is **zero margin** at that boundary — the
spawn RNG's `sub 19` clamp reaches index 18 = `T_S2`, the last record, and `Medio` is the very
next byte at `T_S2 + 12` (`tetromino_next.asm:11`). One more record and the RNG reads `Medio` as
piece data.

**Do this instead.** Create `variables.asm`; add `INCLUDE "variables.asm"` as the **last** line of
`main.asm` (after `INCLUDE "giro.asm"` — mind the missing trailing newline, see
`assembler-conventions`). It lands at `$A2C7`: uncontended, separated from code and piece data,
shipped in the binary with its initial values, referenced by label so no address is hardcoded.

```asm
; variables.asm  -- ALL new game state, one place. Included LAST in main.asm.
PUNTUACION:      DW 0     ; score, 16-bit
LINEAS:          DB 0     ; lines cleared
NIVEL:           DB 0     ; level
FRAMES_POR_FILA: DB 24    ; gravity: frames between one-row drops
contador_frames: DB 0     ; frames elapsed since the last drop
SEMILLA:         DB 0     ; RNG seed ("semilla")
TECLAS_ANT:      DB $FF   ; previous keyboard read, for edge detection (active low)
SIG_PIEZA:       DW 0     ; pointer to the next piece record
```

Use as `LD A,(NIVEL)` / `LD (NIVEL),A` / `LD HL,(PUNTUACION)`. Appending this block at the end of
the image is sanctioned; *interleaving* is not — no `DB` inside a routine's code path, no variable
tacked onto the piece table the way `Medio` is.

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
pushes it first (`giro.asm:8`, `movimiento.asm:9`, `pantallas.asm:90`). Omit the push and the
piece teleports.

**A pressed key is a `0` bit.** Test with `BIT n,A` + `JR Z`. `CP $FF` means "nothing pressed".

| Port | bit0 | bit1 | bit2 | bit3 | bit4 | Sites |
|---|---|---|---|---|---|---|
| `$FBFE` | Q | W | E | R | T | `titulo.asm:20`, `giro.asm:9` |
| `$BFFE` | ENTER | L | K | J | H | `movimiento.asm:10` |
| `$7FFE` | SPACE | SYM SHIFT | M | N | B | `pantallas.asm:90` |
| `$FDFE` | A | S | D | F | G | `pantallas.asm:94` |

Controls as implemented: **Q** rotate left (`giro.asm:12`), **W** rotate right (`giro.asm:14`),
**J** move left (`movimiento.asm:13`), **K** move right (`movimiento.asm:15`), **S** start
(`pantallas.asm:96`), **N** quit (`pantallas.asm:93`), **Q** dismiss title (`titulo.asm:22`).
**No down key is read**; a soft drop must claim a free key from the table above.

**Port `$FE` is never written.** Writing it sets the border colour (bits 0-2) and toggles the
beeper (bit 4) — so the game is silent and never sets the border.

## Common mistakes

- **`$5800 + row*24 + col`.** Wrong. The stride is **32** (columns per row); 24 is the row count.
- **Adding a variable next to `Medio` in `piezas.asm`.** It lands between the piece table and code
  and shifts every later address. Use `variables.asm` (§6).
- **Looking for the board array.** There isn't one. Read the attribute file at `$5800`.
- **Printing text inside columns 7-24.** Non-zero attributes are solid; the text becomes an
  invisible wall. Print in columns 0-5 or 26-31, or row 23.
- **Treating a keyboard bit as 1 = pressed.** It is active low: 0 = pressed.
- **Assuming `$5B00-$6FFF` is used.** Free; the only things above `$5AFF` are 4 bytes at `$7000`.
- **Reading a port without `push bc`.** The port number lands in `BC`, which is the piece position.
- **Putting a variable near `$FF00` or above.** The stack grows down from `$FFFF` and will eat it.
- **Assuming the pixel display file is linear.** It is not; use `L30.3 - printat.asm`.
