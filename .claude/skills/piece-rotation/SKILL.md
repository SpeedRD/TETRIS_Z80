---
name: piece-rotation
description: Use when rotation is wrong in TETRIS_Z80 — the piece jumps when turned, overlaps or eats the well border, rotates into settled blocks, corrupts the board after rotating, or a rotation key does nothing; when adding wall kicks or a rotation anchor; or when editing giro.asm or the +8/+9 and +10/+11 rotation pointers.
---

# Piece rotation — `giro.asm`

Owns all of `giro.asm` and everything about making a rotation correct. Not owned here: record
format and shape data (`piece-data-and-spawn`), loop ordering (`game-loop-and-collision`), drawing
(`rendering-and-attributes`).

Spanish: `giro` = turn/rotation · `GIRAR` = to rotate · `comprobar` = to check, the collision
routine at `test_col.asm:3` · `pintar_tetromino` / `borrar_tetromino` = paint / erase piece ·
`Soltar_Tecla` = release key · `Medio` = middle, used as "current column" · `filas`/`columnas` = rows/cols.

## Background you need

- **`IX`** is a Z80 16-bit index register, used here purely as a pointer: `(ix+9)` reads the byte
  9 bytes past the address in `IX`. It always points at the current piece's rotation record.
- The **attribute file** at `$5800` is the board: one byte = the colour of one 8x8 screen cell,
  32 per screen row. Collision is literally **"attribute byte != 0"** (`test_col.asm:24-26`), so
  anything drawn inside the well *becomes solid geometry*.
- Well interior = columns **7-24**; borders at columns 6 and 25, floor at row 22
  (`tableroJuego.asm:8,19,30`). Position is `B` = row, `C` = column, second copy of the column in
  memory at `Medio` (`register-protocol`).
- **Wall kick** (Tetris term): retrying a rotation that will not fit at a small horizontal offset,
  instead of rejecting it outright.

## 1. The model is sound — keep it

Each of the 19 records stores the address of its rotate-left and rotate-right successor. Rotation
is two loads and a pointer assignment: no maths, no shape tables, no per-frame cost. Offsets are
`+0` rows, `+1` cols, `+2..+7` six pattern bytes, `+8..+9` left successor, `+10..+11` right
successor, each address low byte first; full format in `piece-data-and-spawn`.

```asm
turn_left:                  ; giro.asm:16-19
    LD D, (IX + 9)          ; high byte of the rotate-left successor's address
    LD E, (IX + 8)          ; low byte
    LD IX, DE               ; IX = DE — sjasmplus FAKE instruction, DD 62 DD 6B (main.lst:901)
```
`turn_right` (`giro.asm:24-27`) is identical with `+11`/`+10`; `LD IX, DE` is explained in
`assembler-conventions`. **Do not replace this model with computed SRS rotation:** the record
format caps a piece at `rows*cols <= 6`, so a 4x4 SRS box cannot be stored. Fix in place.

## 2. Verified rotation cycles

Traced through the `DW` words in `main.lst:547-607` (e.g. `main.lst:551` assembles `DW T_L2,
T_L3` as `A3 A0 AF A0` = `$A0A3`, `$A0AF`). **Every cycle is closed and left/right are exact
inverses, in all seven shapes**; each left step is also a true 90° counter-clockwise rotation of
the bit pattern, checked cell by cell against `piezas.asm:5-29`. This table is the reference for
adding or repairing a shape.

| Shape | States | Left cycle (`+8/+9`) | Right cycle (`+10/+11`) | Closed | Inverse |
|---|---|---|---|---|---|
| O | 1 | `T_0` → `T_0` | `T_0` → `T_0` | yes | yes |
| L | 4 | `L1`→`L2`→`L4`→`L3`→`L1` | `L1`→`L3`→`L4`→`L2`→`L1` | yes | yes |
| J | 4 | `J1`→`J2`→`J4`→`J3`→`J1` | `J1`→`J3`→`J4`→`J2`→`J1` | yes | yes |
| T | 4 | `T1`→`T2`→`T4`→`T3`→`T1` | `T1`→`T3`→`T4`→`T2`→`T1` | yes | yes |
| I | 2 | `I1`↔`I2` | `I1`↔`I2` | yes | yes |
| Z | 2 | `Z1`↔`Z2` | `Z1`↔`Z2` | yes | yes |
| S | 2 | `S1`↔`S2` | `S1`↔`S2` | yes | yes |

I, Z and S use one successor for both directions, which is correct — for them a 180° turn is the
identity, so each direction is its own inverse. **The data is not the bug.**

## 3. What is broken — four defects

| # | Defect | Where | Consequence |
|---|---|---|---|
| 1 | **No collision test on rotation at all.** `GIRAR` writes `IX` unconditionally. The one caller tests *first* and rotates *second*, so `comprobar` ran on the **pre**-rotation shape and the rotated shape is never validated. | `giro.asm:19,27`; `comprobar` `juego.asm:29`, `GIRAR` `juego.asm:41` | `pintar_tetromino` paints the rotated piece over settled blocks and over the border. Collision means "attribute byte != 0", so **those overpainted cells become permanently solid — the board is corrupted, not merely misdrawn.** |
| 2 | **No wall kick.** No code path retries an offset position after a failed rotation, because there is no failure path at all. | `giro.asm:1-42` | A rotation that cannot fit happens anyway, with the consequence above. |
| 3 | **No rotation anchor.** Rotating swaps `rows`/`cols` (2x3 ↔ 3x2, 4x1 ↔ 1x4) but the piece is always drawn from the same top-left `(B,C)`. | worst case I, `piezas.asm:22-23` | `T_I1` fills rows `B..B+3` of column `C`; `T_I2` then fills row `B`, columns `C..C+3`. The bar's lower three cells vanish and three appear to the right of the top one — a bar resting on the stack teleports three rows into the air. |
| 4 | **Widening rotation near the right wall** (3x2 → 2x3) extends the piece one cell right, unchecked. | erase `juego.asm:20`; border `tableroJuego.asm:19` | The *next* frame's erase uses the **new** `(ix+1)` width and blanks that extra cell — the border at column 25. Nothing redraws the border, so the well develops holes and pieces leak out. See `rendering-and-attributes`. |

Minor: dead `POP BC / RET` at `giro.asm:21-22` and `:29-30`, unreachable after the `JR` at `:20`
and `:28` (`main.lst:903-904`, `:911-912`) — copy-paste residue from `movimiento.asm`, see
`failure-patterns`. And `Soltar_Tecla` (`giro.asm:33-38`) blocks until the key is released; that
timing consequence belongs to `interrupts-and-timing`.

## 4. Ordering rule: erase with the OLD `IX`

The piece on screen was drawn with the **old** shape. If `IX` changes before the erase runs,
`borrar_tetromino` walks the **new** shape's `rows`/`cols`/pattern and blanks the wrong cells;
every old cell it misses stays on the board as debris, and debris reads as solid geometry.
**Required order, every frame:**

1. `call borrar_tetromino` — erase, still using the old `IX`.
2. `call GIRAR` — it validates the new shape **inside itself** (§5) and changes `IX` and the
   column only if that succeeded. **The caller must not test it again.**
3. gravity (`inc b` + `call comprobar`) — the loop's own candidate, `game-loop-and-collision` §6.
4. `call pintar_tetromino` — draw only what was validated.

The current loop gets 1 and 2 right (erase `juego.asm:20`, `GIRAR` `:41`) but validates in the
wrong place — `comprobar` runs at `:29`, *before* the rotation. **Hoisting input above the collision test is the
fix, not a hazard.** The older source, recovered from the listing (`juego.lst:36-40`), ran
`borrar_tetromino` → `inc b` → `MOVER` → `GIRAR` → `comprobar`: `GIRAR` was already **below** the
erase, which is exactly the order prescribed above. Its only defect was the stale `C`
(`game-loop-and-collision` §2), not the ordering. See `failure-patterns` rule 3. Restore that
order and move the validation inside `GIRAR`.

## 5. The playbook — a safe rotation

Replaces `giro.asm:1-42` entirely; nothing outside `giro.asm` references `turn_left`,
`turn_right`, `Soltar_Tecla` or `no_teclaturn` (grep-verified). Assembles clean on sjasmplus
1.23.1, 0 errors / 0 warnings. **It reads no keys and waits for nothing:** the caller polls the
keyboard once per frame, edge-detects, and passes the direction in `A`
(`game-loop-and-collision` §7). A key read here would spin between the erase and the redraw and
make the piece invisible while Q or W is held (`rendering-and-attributes` §4).

```asm
; GIRAR — rotate the current piece: validated, kicked and COMMITTED here.
; IN : IX = current record, B = row, C = column, (Medio) = column,
;      A = 0 rotate left (Q), A != 0 rotate right (W).
; OUT: success -> IX = new record, C and (Medio) = new column.
;      failure -> IX, C and (Medio) unchanged. Never draws, never waits for a key.
; Destroys AF, DE. Preserves B and HL. C is an OUTPUT on success, restored on failure.
GIRAR:
    push hl
    or  a
    jr  nz, giro_der
    ld  d,(ix+9)            ; +8/+9 = rotate-left successor, low byte first
    ld  e,(ix+8)
    jr  giro_probar
giro_der:
    ld  d,(ix+11)           ; +10/+11 = rotate-right successor
    ld  e,(ix+10)
giro_probar:
    push ix                 ; the state to roll back to
    ld  a,(ix+1)            ; A = width of the OLD shape — read it BEFORE IX moves
    ld  ix, de              ; IX = candidate state (fake instr, assembler-conventions)
    sub (ix+1)              ; A = old_cols - new_cols   (signed, -3..+3)
    jp  p, giro_media
    inc a                   ; negatives round toward zero, not toward -infinity, so
giro_media:                 ;   rotate-and-rotate-back returns to the same column
    sra a                   ; A = (old_cols - new_cols)/2 — the recentre offset
    add a, c                ; anchor about the centre instead of the top-left corner
    ld  e, a                ; E = recentred base column — a CANDIDATE, still untested
    ld  hl, giro_kicks
giro_bucle:
    ld  a,(hl)
    inc hl
    cp  $80                 ; sentinel: every candidate was rejected
    jr  z, giro_deshacer
    add a, e                ; candidate column = recentred base + kick offset
    ld  c, a                ; both tests read the row from B and the column from C
    call en_rango           ; TEST 1 geometry: whole piece inside columns 7-24?
    or  a                   ;   (game-loop-and-collision §5 — comprobar cannot see this)
    jr  nz, giro_bucle      ; kicked out of the well — next offset
    call comprobar          ; TEST 2 overlap: A=0 fits, A=1 hits a block or the border.
    or  a                   ;   Preserves BC/DE/HL/IX/IY.
    jr  nz, giro_bucle
    ld  a, c
    ld  (Medio), a          ; COMMIT the column to memory too: the loop reloads C
    pop de                  ;   from Medio and would otherwise undo the kick.
    jr  giro_fin            ; drop the saved old IX — the new one stands
giro_deshacer:
    pop ix                  ; nothing fitted: restore the old shape...
    ld  a,(Medio)
    ld  c, a                ; ...and the old column. (Medio) IS the rollback copy of C.
giro_fin:
    pop hl
    ret
giro_kicks: DB 0, -1, 1, -2, 2, $80   ; in place, then 1 then 2 cells each way.
                                      ; Read-only data, after the RET: never executed.
```

No scratch variable is needed — `BC` is never loaded with a port number here, so `B` and `C`
survive, and `(Medio)` is the rollback copy. If you ever do need one, it goes in `variables.asm`,
never in `giro.asm` (`memory-map` §6).

**Why that kick set.** In an 18-column well the widest piece is 4 cells, so a rotation blocked by a
side wall is out by at most two columns (the I-piece's overhang after recentring): ±1 then ±2
covers both walls and that overhang, and trying `0` first means a rotation that already fits never
moves. **Both tests are mandatory, in that order.** `comprobar` knows no geometry: it rejects the
border only because the border byte is non-zero, so a ±2 kick from column 24 with a 1-wide record
tests column 26 — empty screen outside the well — and *accepts*. `en_rango`
(`game-loop-and-collision` §5) rejects any candidate with `C < 7` or `C + cols - 1 > 24` before
`comprobar` ever runs.

## 6. Anchoring — keep the record format

- **(a) Add per-state offset bytes to the record.** Cost: it changes the record size, and with it
  `longitud_pieza`, the `cp 19` / `sub 19` spawn clamp and every record address — one coupled unit,
  see `piece-data-and-spawn` §4.
- **(b) Recentre at rotation time** by adjusting `C` by `(old_cols - new_cols)/2`, using the
  `rows`/`cols` bytes already in both records. No format change, six instructions.

**Use (b)** for completion-in-place — it is `giro_probar`..`giro_media` above. The ±0.5 cases (2↔3
wide) round to zero and leave the left edge pinned; only I's ±1.5 shifts, symmetrically in both
directions, so nothing drifts. **The recentred column is tested, not trusted:** it enters the kick
loop as offset `0` and is rejected like any other candidate.

## 7. Verifying a rotation change

Build and emulator setup: `build-and-verify`. Then for **each of the seven shapes**, rotate both
directions: flush against the left border (column 7); against the right border (column 24);
touching a settled stack and the floor; and four times in one direction to confirm the piece
returns to its start. Confirm each time that the piece does not jump position, that no cell of it
lands on the border or on a settled block, and that a rotation which cannot fit anywhere leaves
the piece **completely unchanged** rather than nudging it. After a dozen rotations against a wall
the border must still be an unbroken line; a gap means defect 4 is still live.

## Common mistakes

| Mistake | What happens |
|---|---|
| Rotating before erasing | The erase uses the new shape's dimensions, old cells survive, and the debris becomes permanently solid. |
| Testing collision before applying the rotation | You validate a shape the piece will never have. This is the current bug (`juego.asm:29` vs `:41`). |
| Writing `IX` before the test passes | No way back. `push ix` first; discard the copy only after `comprobar` returns 0. |
| Kicking `C` but not writing `Medio` | The loop reloads `C` from `Medio` (`juego.asm:25-26,40`) and silently undoes the kick. |
| Re-testing `GIRAR`'s result in the loop | It already validated, kicked and committed. An outer `comprobar` re-tests an accepted position and its rollback is dead code (`game-loop-and-collision` §6). |
| Reading the keyboard, or waiting for a release, inside `GIRAR` | It runs between the erase and the redraw, so the piece is invisible for as long as the key is held (`rendering-and-attributes` §4). The caller edge-detects. |
| Relying on `comprobar` alone for the kick | It cannot see a column that left the well: empty cells outside the border read as free. Call `en_rango` first. |
| Adding an offset table without updating the spawn clamp | Record size changes; the clamp then indexes past the last record into `Medio`. |
| Treating a failed rotation as "then move down" | Rotation must be positionally neutral. Gravity is the loop's job. |
| Assuming the border is decoration | It is board data. Overwrite it and pieces escape the well; erase it and the hole is never repaired. |
| Special-casing the O piece | `T_0` already points at itself both ways (`piezas.asm:5`). It needs no special handling. |

## See also

`piece-data-and-spawn` (record format, the 19 records, spawn clamp) · `register-protocol` (`B`/`C`/
`IX` contract, `Medio` duplication, clobber table) · `game-loop-and-collision` (`comprobar`'s
contract, loop ordering, `en_rango`, the non-blocking key read that feeds `A` to `GIRAR`) ·
`assembler-conventions` (`LD IX, DE`) · `rendering-and-attributes` (border erosion, the invisible
window) · `interrupts-and-timing` (frame sync) · `build-and-verify` · `failure-patterns`.
