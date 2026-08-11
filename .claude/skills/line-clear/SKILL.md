---
name: line-clear
description: Use when adding, debugging or reviewing line clearing in this ZX Spectrum Tetris — detecting a completed row, shifting the board down after a clear, counting cleared rows, blanking the top row, or wiring a clear routine into the lock-and-spawn path.
---

# Line clear — detect full rows and shift the board down

**Shipped in `lineas.asm`.** `limpiar_lineas` is called from the lock path at `juego.asm:105`, and
`tests/test_lineas.py` covers single, double and quadruple clears, non-adjacent full rows, a
top-row clear, a completely full board, and that the well border survives all of it.

Nothing existed before the fix pass — no row scan, no shift, no counter, no call site — so there is
no older version to compare against and no dead end to avoid. This file is the design rationale for
what is there now; the reasoning matters because most of the ways to get line clearing wrong are
silent.

## Background (no Z80 or Spectrum knowledge assumed)

- The **attribute file** is a 32-column x 24-row grid of bytes at `$5800`, one byte per 8x8 screen
  cell, stored row by row. **Consecutive columns are consecutive bytes; consecutive rows are 32
  bytes apart.** This grid *is* the board — there is no board array (`memory-map`).
- **Occupied = attribute byte non-zero. Empty = `0`.**
- `LDIR` / `LDDR` are single Z80 instructions that block-copy `BC` bytes from `(HL)` to `(DE)`,
  ascending and descending respectively. Both leave `BC` = 0 and advance `HL`/`DE` past the block.
- Spanish: `tablero` = board, `fila` = row, `columna` = column, `tetromino` = piece, `limpiar` =
  to clear, `borrar_tetromino` = erase piece, `comprobar` = to check (collision), `juego` = game.

## Board geometry — verified from `tableroJuego.asm`

| Feature | Cells | Attribute | Source |
|---|---|---|---|
| Left wall | column 6, rows 0-21 | `6*8+7` = 55 = `$37` | `tableroJuego.asm:8-16` |
| Right wall | column 25, rows 0-21 | 55 | `tableroJuego.asm:19-27` |
| Floor | row 22, columns 6-25 | 55 | `tableroJuego.asm:30-37` |
| **Interior** | **columns 7-24 = 18 wide, rows 0-21** | 0 when empty | — |

```
        col 6                                     col 25
 row 0    # . . . . . . . . . . . . . . . . . . #    # = wall/floor, attribute 55
 ...      # <----- 18 interior cells ---------> #    . = interior, 0 when empty
 row 21   # . . . . . . . . . . . . . . . . . . #
 row 22   # # # # # # # # # # # # # # # # # # # #  <- floor
```

First interior cell of row R: **`$5800 + R*32 + 7`** — base, plus 32 bytes per row above, plus 7
columns across. **Never write to column 6, column 25, or row 22.** Nothing redraws the border
after `dibujar_tablero` ("draw board") runs once at startup, so one stray byte punches a permanent
hole that pieces then fall through.

## The full-row test

Full = **all 18 attribute bytes in columns 7-24 are non-zero.**

Test non-zero, never a specific colour: `comprobar` (`test_col.asm:24-26`) defines occupancy as
`byte != 0`, so reusing that test gives the board exactly one definition of "occupied" and works
for every piece colour; a colour comparison misses five of the seven pieces
(`game-loop-and-collision`). **Scan 18 columns, not 32** — the wall bytes are always 55, so a
32-wide scan reports every row as full from the first frame.

## The shift — direction is the thing to get right

When row R clears, everything **above** it moves **down** one, so the copy walks **from row R
upward**: `row R <- row R-1`, then `row R-1 <- row R-2`, ..., `row 1 <- row 0`, then blank row 0.
The other order (row 1 into row 0, row 2 into row 1) smears the top row over the whole stack,
because each copy overwrites a source that has not been read yet.

Per row: source `$5800 + (R-1)*32 + 7`, destination `$5800 + R*32 + 7`, **18 bytes — never 32.**
32 drags wall cells into the playfield and the playfield over the walls. The code below uses
`LDIR`; the two 18-byte spans sit exactly 32 bytes apart so they never overlap and the ascending
direction is safe. `LDDR` would work equally well — only the outer row order matters.

## The complete routine

This is `lineas.asm` as shipped, with the comments translated. `:` separates statements on one line,
as in `pantallas.asm:74`. **Edit the file, not this copy.**

```asm
; lineas.asm -- deteccion y borrado de lineas completas (detect and clear full lines)
COL_IZQ    EQU 7        ; leftmost interior column
ANCHO_POZO EQU 18       ; interior width: columns 7..24 inclusive
FILA_BAJA  EQU 21       ; lowest interior row (row 22 is the floor)

; limpiar_lineas -- clears every completed row and compacts the board.
;   IN: nothing.  OUT: A = number of rows cleared (0..4 in practice).
;   Preserves BC, DE, HL, IX, IY. Destroys AF only.
limpiar_lineas:
    push bc : push de : push hl : push ix  ; BC = piece row/column, IX = piece: must survive
    ld c, 0                  ; C = running count of cleared rows
    ld b, FILA_BAJA          ; B = row under test; start at the bottom, work up
ll_probar:
    call fila_llena : or a   ; A = 1 if row B is full; "or a" sets Z when A = 0
    jr z, ll_arriba          ; not full -> move up one row
    inc c
    call bajar_filas         ; shift everything above row B down into it
    jr ll_probar             ; RE-TEST THE SAME ROW B: after the shift a DIFFERENT row sits
                             ; at index B. "dec b" here is the classic bug -- a double
                             ; clear would then remove only one row.
ll_arriba:
    ld a, b : or a
    jr z, ll_fin             ; row 0 was the last to test -> done
    dec b : jr ll_probar
ll_fin:
    ld a, c                  ; return the count; scoring-and-level consumes it
    pop ix : pop hl : pop de : pop bc      ; exact mirror: pushed last, popped first
    ret

; fila_llena ("row full") -- IN: B = row 0..21.  OUT: A = 1 full, 0 not full.
;   Preserves BC, DE, HL. Destroys AF.
fila_llena:
    push bc : push de : push hl
    ld c, COL_IZQ
    call CRtoATTR            ; HL = $5800 + B*32 + 7. Unlike CalcularAtributo this
                             ; PRESERVES BC (register-protocol). B is 0..21 here,
                             ; inside CRtoATTR's valid range of rows 0-23.
    ld e, ANCHO_POZO         ; exactly 18 cells -- never 32
fl_celda:
    ld a, (hl) : or a
    jr z, fl_hueco           ; one empty cell is enough: row is not full
    inc hl : dec e
    jr nz, fl_celda          ; dec e set the flags; inc hl did not disturb them
    ld a, 1 : jr fl_fin
fl_hueco:
    ld a, 0
fl_fin:
    pop hl : pop de : pop bc
    ret

; bajar_filas ("lower rows") -- IN: B = the row just cleared (0..21).
;   Copies every row above it down one, then blanks row 0. Preserves AF, BC, DE, HL.
bajar_filas:
    push af : push bc : push de : push hl
    ld a, b : or a           ; A = number of row copies to do = B
    jr z, bf_fila0           ; row 0 cleared -> nothing above it, just blank it
    ld c, COL_IZQ
    push af                  ; MANDATORY. CRtoATTR ends in "LD A,L", so it
    call CRtoATTR            ;  DESTROYS A. HL = destination = $5800 + B*32 + 7
    pop af                   ;  Without this the copy count became the low byte
                             ;  of that address: 167 passes instead of 21 for
                             ;  row 21. See the timing table and the mistakes
                             ;  table below -- this one is invisible in the
                             ;  finished board, so only a count assertion sees it.
    ex de, hl                ; DE = destination
    ld hl, -32 : add hl, de  ; HL = source = destination - 32 = one row higher
bf_copiar:
    ld bc, ANCHO_POZO
    ldir                     ; 18 bytes (HL)->(DE); both advance by 18, BC -> 0
    ld bc, -(ANCHO_POZO + 32); undo the 18, then step one more row up
    add hl, bc               ; HL -= 50
    ex de, hl : add hl, bc : ex de, hl   ; DE -= 50 (the Z80 has no "add de,bc")
    dec a                    ; add hl,bc leaves Z alone; dec a sets it
    jr nz, bf_copiar
bf_fila0:
    ld b, 0 : ld c, COL_IZQ  ; blank row 0's 18 cells, or the top row is
    call CRtoATTR            ; duplicated downward forever. HL = $5807.
    ld b, ANCHO_POZO
bf_cero:
    ld (hl), 0 : inc hl
    djnz bf_cero
    pop hl : pop de : pop bc : pop af
    ret
```

Four simultaneous clears need no special case: the re-test finds them one at a time, `C` ends at 4.

## Where it hooks into the game loop

**After the piece locks, before the next spawns** — `juego.asm:103-106`:

```asm
    call pintar_tetromino    ; :103 this call IS the lock
    call limpiar_lineas      ; :105 A = rows cleared, 0..4
    call anotar_lineas       ; :106 scores it, levels up, refreshes the marker
    call seleccionar_pieza   ; :108 the next piece
```

The pairing is fixed: `limpiar_lineas` returns the count in `A` and `anotar_lineas` consumes it
immediately, so **nothing may sit between those two calls that touches `A`**.
`game-loop-and-collision` owns the loop; `scoring-and-level` owns what happens to the count.

Two register notes: `IX` still points at the just-locked piece here, and `B`/`C` hold the locked
position — `limpiar_lineas` preserves all of them (`register-protocol`) and must keep doing so.

## The file itself

`lineas.asm` is `INCLUDE`d at `main.asm:43`, before `variables.asm`. It **holds code only**: the
three `EQU`s are compile-time constants, not storage, and the cleared count lives in `C`/`A`, so
nothing here needs RAM. Any *variable* you later add goes in `variables.asm` — `memory-map` §6 owns
placement, and a second declaration of an existing name is a duplicate-label error.

## Timing — one call, do not split across frames

`LDIR` costs 21 T-states per byte moved plus 16 for the last, so 18 bytes = 373 T.

**Measured under ZEsarUX, stepping opcode by opcode, against the fixed build.** The earlier
hand-counted figures here counted only the row copies and left out the 22 `fila_llena` scans, which
is most of the cost of a single clear — trust the table below, not an opcode count of the copy loop.

| Case | Cost |
|---|---|
| One row copy including loop overhead | ~439 T |
| `limpiar_lineas`, nothing to clear (22 scans, all exiting early) | **6,291 T** |
| `limpiar_lineas`, one full row at row 21 | **22,235 T** |
| `limpiar_lineas`, two full rows | **30,612 T** |
| `limpiar_lineas`, four full rows — the absolute worst | **65,059 T** |

The whole locking `paso` frame is what actually has to fit, and `limpiar_lineas` is only part of it —
`anotar_lineas` reprints the scoreboard, then a piece is spawned and previewed:

| Locking frame | Cost | Share of a 69,888 T frame |
|---|---|---|
| lock, 0 rows cleared | 13,848 T | 19.8% |
| lock, 1 row cleared | 37,516 T | 53.7% |
| lock, 2 rows cleared | 44,875 T | 64.2% |
| lock, 3 rows cleared | 63,129 T | 90.3% |
| lock, 4 rows cleared | **76,864 T** | **110.0% — overruns the frame** |

So a *tetris* does not fit in one frame even with the copy loop correct: the loop misses one 50 Hz
interrupt and that frame takes two. Everything below four rows fits. This is inherent to doing the
whole shift in one frame, and doing it in one frame is still right (§ "One call, do not split") —
the alternative is a half-shifted board visible to `comprobar`. The attribute file is contended
memory, so these are floors; `interrupts-and-timing` owns contention.

## Optional: flash the cleared row — two mandatory rules

Frame sync exists now (`HALT` at `juego.asm:35`), so this is buildable. If you add it:

1. **Restore to `0` before any collision test can run.** Bright white `7*8 + 7 + $40` = `$7F` is
   **non-zero and therefore solid** to `comprobar`. `bajar_filas` overwrites the flashed cells on
   the normal path, but on any path where the row is not actually cleared you must write `0` back
   over all 18 — `rendering-and-attributes`: *no non-zero value is safe*.
2. **Do not busy-wait for the delay.** A spin loop's wall-clock length varies per emulator, and it
   would sit inside the erase/redraw window `rendering-and-attributes` §4 requires be kept empty.
   Delay with `HALT` + a frame counter, the same mechanism gravity uses (`interrupts-and-timing`
   §5) — and remember the loop's own `contador_frames` keeps counting while you hold the frame.

## Common mistakes

| Mistake | What happens |
|---|---|
| Shifting upward (row 1 into row 0, walking down the array) | The top row is smeared over the whole stack. |
| Copying 32 bytes per row instead of 18 | Wall cells drag into the playfield, walls get overwritten, the well develops permanent holes. |
| Scanning all 32 columns | Wall bytes are always 55, so every row tests as full. |
| `dec b` after a clear instead of re-testing the same index | The row that slid into position B is never checked; a double clear removes one row. |
| Forgetting to blank row 0 | Row 0 is duplicated downward forever; the board never empties. |
| Testing for a specific colour instead of non-zero | Only that colour counts; mixed rows never complete. |
| Leaving a flash attribute in place | Non-zero = occupied, so the row stays solid to `comprobar`. |
| Running the clear before the piece is locked | The piece is not in the attribute file yet, so its row never reads as full. |
| Putting anything that touches `A` between `limpiar_lineas` and `anotar_lineas` | The row count is the return value; the score silently stops matching the clears. |
| Making `limpiar_lineas` clobber `BC` or `IX` | They still hold the locked piece's position and record when it runs. |
| Holding the row-copy count in `A` across `call CRtoATTR` in `bajar_filas` | `CRtoATTR` ends in `LD A,L`, so the count becomes the low byte of the attribute address — 167 passes instead of 21 for row 21. The finished board is still correct, because `bf_cero` rewrites row 0 afterwards, so **every board-state assertion passes**. What it costs is 146 stray row copies walking down through the pixel display file, ~230 corrupted bytes of background per clear, and a 119,000 T frame instead of 38,000. `tests/test_bajar_filas.py` counts the iterations directly; keep the `push af`/`pop af`. |
| Using `CalcularAtributo` instead of `CRtoATTR` **here** | It clobbers `BC` (`pantallas.asm:79`), destroying the row counter mid-loop. This is a rule for *these* loops, not everywhere: `CRtoATTR` is only valid for rows 0-23 (`AND 3 : OR #58`), and rows 0-21 is all this file ever passes. For a row outside 0-23, `CalcularAtributo` is the correct routine — see `rendering-and-attributes` §2. |

## See also

`memory-map` (geometry, free RAM) · `register-protocol` (clobber table, `CRtoATTR` vs
`CalcularAtributo`) · `game-loop-and-collision` (hook point, `comprobar`) · `scoring-and-level`
(consumes `A`) · `assembler-conventions` (the `INCLUDE`) · `build-and-verify` · `interrupts-and-timing`.
