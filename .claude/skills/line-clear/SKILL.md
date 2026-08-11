---
name: line-clear
description: Use when adding, debugging or reviewing line clearing in this ZX Spectrum Tetris — detecting a completed row, shifting the board down after a clear, counting cleared rows, blanking the top row, or wiring a clear routine into the lock-and-spawn path.
---

# Line clear — detect full rows and shift the board down

**Nothing exists.** No row scan, no shift, no line counter, no call site. This is new code, not a
repair, and it is the reason the game has no progression and no way to reduce the stack.

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

Verified: SjASMPlus 1.23.1, `Errors: 0, warnings: 0`, loads at `$A2C7`, the first free byte past
the program image. `:` separates statements on one line, as in `pantallas.asm:72`.

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
    call CRtoATTR            ; HL = destination = $5800 + B*32 + 7
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

**After the piece locks, before the next spawns.** In `juego.asm` the lock-and-spawn path is the
fall-through at `:34-37` (`dec b` / `ld c,e` / `call pintar_tetromino` / `jr iniciar`) — the labels
there are inverted, `cambiar_tetromino` is the keep-falling path. Insert one line:

```asm
    call pintar_tetromino    ; juego.asm:36 -- this call IS the lock
    call limpiar_lineas      ; NEW: A = rows cleared
    jr iniciar               ; juego.asm:37 -- spawns the next piece
```

`game-loop-and-collision` owns the loop skeleton and this hook point. Two register notes: `IX`
still points at the just-locked piece here (`iniciar` -> `seleccionar_pieza` overwrites it anyway,
but the routine preserves it), and `B`/`C` hold the locked position, which `iniciar` reloads at
`juego.asm:6-8` — preserve both regardless (`register-protocol`).

## Wiring the new file in

1. Create `lineas.asm` in the repo root with the code above.
2. **Add a newline to the end of `main.asm` first.** Its last byte is the closing quote of
   `INCLUDE "giro.asm"` (`main.asm:31`); there is no trailing newline. A blind append lands on that
   same line, sjasmplus honours the first `INCLUDE` and **silently drops the second at 0 errors, 0
   warnings**, and your file is never assembled — a perfect build with no routine in it.
3. Append `    INCLUDE "lineas.asm"` on its own line and rebuild (`assembler-conventions`,
   `build-and-verify`). Confirm `limpiar_lineas` appears in `main.lst` at `$A2C7`.
4. **`lineas.asm` holds code only.** The three `EQU`s are constants, not variables, and the cleared
   count lives in `C`/`A`, so nothing here needs RAM. Any *variable* you later add goes in
   `variables.asm` — `memory-map` §6 owns variable placement. Never put one next to `Medio`.

## Timing — one call, do not split across frames

`LDIR` costs 21 T-states per byte moved plus 16 for the last, so 18 bytes = 373 T.

| Case | Cost |
|---|---|
| One row copy including loop overhead | ~439 T |
| Worst single clear: row 21, 21 copies = 378 bytes, plus blanking row 0 | **~9,700 T** |
| Absolute worst: 4 clears at the bottom, every row scan running full length | **~57,000 T** |

One 50 Hz frame is 69,888 T, so even the pathological case fits in a single frame and a normal
clear costs ~14% of one. For scale, `Tiempo` (`caida.asm:14`) already busy-waits ~123,600 T per
gravity tick. The attribute file is contended memory so real cost is higher than these figures —
`interrupts-and-timing` owns contention; do not re-derive it here.

## Optional: flash the cleared row — two mandatory rules

Best left until frame sync exists. If you add it anyway:

1. **Restore to `0` before any collision test can run.** Bright white `7*8 + 7 + $40` = `$7F` is
   **non-zero and therefore solid** to `comprobar`. `bajar_filas` overwrites the flashed cells on
   the normal path, but on any path where the row is not actually cleared you must write `0` back
   over all 18 — `rendering-and-attributes`: *no non-zero value is safe*.
2. **Do not `call Tiempo` for the delay.** It is a ~123,600 T busy-wait `interrupts-and-timing` says
   to delete, and it would sit inside the erase/redraw window `rendering-and-attributes` §4 requires
   be kept empty. Delay with `HALT` + a frame counter (`interrupts-and-timing` owns that).

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
| Appending the `INCLUDE` onto `main.asm`'s existing last line | Silently dropped: 0 errors, 0 warnings, routine never assembled. |
| Using `CalcularAtributo` instead of `CRtoATTR` **here** | It clobbers `BC` (`pantallas.asm:77`), destroying the row counter mid-loop. This is a rule for *these* loops, not everywhere: `CRtoATTR` is only valid for rows 0-23 (`AND 3 : OR #58`), and rows 0-21 is all this file ever passes. For a row outside 0-23, `CalcularAtributo` is the correct routine — see `rendering-and-attributes` §2. |

## See also

`memory-map` (geometry, free RAM) · `register-protocol` (clobber table, `CRtoATTR` vs
`CalcularAtributo`) · `game-loop-and-collision` (hook point, `comprobar`) · `scoring-and-level`
(consumes `A`) · `assembler-conventions` (the `INCLUDE`) · `build-and-verify` · `interrupts-and-timing`.
