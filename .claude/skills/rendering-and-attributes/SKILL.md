---
name: rendering-and-attributes
description: Use when changing how anything appears on screen in this ZX Spectrum Tetris — drawing or erasing a piece, computing an attribute address, adding or moving text, changing a colour, or diagnosing flicker, tearing, garbage glyphs, or a well border that disappears during play.
---

# Rendering and attributes

Spanish: `pintar` = paint/draw, `borrar` = erase, `pantalla` = screen, `fila` = row, `columna` =
column, `tablero` = board, `atributo` = attribute, `CalcularAtributo` = "calculate attribute",
`dibujar_tablero` = "draw board", `Medio` = "middle" (column). `tetromino` is as-is.

## 1. The Spectrum screen: two regions, and this game uses one

The screen is 32 columns x 24 rows of 8x8 pixel cells, described by **two separate, independent** regions:

| Region | Address | Size | Holds |
|---|---|---|---|
| Pixel display file | `$4000` | 6144 bytes | 1 bit per pixel, monochrome shapes. Addressing is **non-linear** — consecutive pixel rows are not consecutive addresses. |
| Attribute file | `$5800` | 768 bytes | 1 byte per 8x8 cell, linear, 32 bytes per row. Colours only. |

| attribute bit | 7 | 6 | 5-3 | 2-0 |
|---|---|---|---|---|
| meaning | FLASH | BRIGHT | PAPER (background) | INK (foreground) |

Colours 0-7: 0 black, 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white.
**This game draws pieces and board with PAPER only** — a colour is written as `colour*8`, INK 0, no
FLASH/BRIGHT (`piezas.asm:5-29`). Cells are solid blocks, so no pixel data is needed. Therefore **a
filled cell is any non-zero attribute byte, an empty cell is `0`**; collision is literally
`ld a,(hl) : or a` (`test_col.asm:24-25`, see `game-loop-and-collision`). The pixel file is only
decoration — the title picture (`titulo.asm`) and the `Tetris_3D` bevel (`L35 - Tetris_3D.asm:3-27`,
which also leaves `IY = $9FDF`, see `interrupts-and-timing`). `memory-map` owns the address map.

## 2. Two attribute-address routines — there is a choice, and it matters

Both take `B` = row, `C` = column and return `HL` = attribute address. Same formula,
`$5800 + row*32 + col`. Row stride is **32**, always.

| Routine | Where | Preserves | Destroys | Valid rows |
|---|---|---|---|---|
| `CalcularAtributo` | `pantallas.asm:67-80` | `AF`, `DE`, `IX`, `IY` | **`BC`** | any row (plain `row*32+col`) |
| `CRtoATTR` | `L30.3 - printat.asm:72-88` | **`BC`**, `DE`, `IX`, `IY` | `AF`, `(SCR_ATTR_PTR)` | **0-23 only** |

- **New code: use `CRtoATTR`** — it preserves `BC`, so a row/column loop counter survives the call
  (`line-clear` depends on this). Limit: it builds the high byte with `AND 3 : OR #58`
  (`printat.asm:78-79`), so any row >= 24 wraps modulo 32 back to the top of the screen. For a row
  outside 0-23 (a below-the-floor probe, say) use `CalcularAtributo`.
- **Do not change existing call sites** — the three `CalcularAtributo` callers already work around
  its `BC` clobber and are correct as they stand.

`CalcularAtributo` bit-splits rather than multiplying: `SRL H` ×3 gives `row>>3` (which 256-byte
third), `SLA A` ×5 then `OR c` gives `(row&7)*32 + col`, and `LD BC,$5800 : ADD HL,BC` adds the
base — **that `LD BC` is what destroys the caller's row and column** (`pantallas.asm:67-80`).
**Never revert it to the old `and $F8` + three `rlca` form** (`pantallas.lst:49`): `rlca` rotates
instead of shifting and gave garbage addresses. The current form is a deliberate, verified fix —
`failure-patterns` §3.2.

**The calling rule the whole codebase depends on.** `CalcularAtributo` returns with `BC` =
`$5800`. All three callers survive only by reloading `B` and `C` from the piece record **after**
the call (`piezas.asm:41-43`, `clear.asm:10-12`, `test_col.asm:10-13`). Reorder those lines and
the loops run with rows=`$58`, cols=`$00` and the game breaks silently. Always:

```asm
    call CalcularAtributo   ; HL = attribute address; BC now destroyed
    ld b, (ix)              ; rows — MUST come after the call
    ld c, (ix+1)            ; cols — MUST come after the call
```

## 3. Drawing and erasing a piece

Both walk the record's pattern bytes (offsets `+2..+7`, `piece-data-and-spawn`), `rows x cols` cells, at most 6.

| | `pintar_tetromino` (`piezas.asm:34-73`) | `borrar_tetromino` (`clear.asm:3-45`) |
|---|---|---|
| Per cell | pattern byte 0 -> skip, else `ld (hl),a` (`:53`) | pattern byte 0 -> skip, else `ld (hl),0` (`:25`) |
| Tests | the pattern byte | the **pattern** byte, not the screen |
| Row step | `ld a,32 : sub c : add hl,de` (`:59-64`) | `ld a,32 : sub (ix+1) : add hl,de` (`:32-36`) |
| Registers | preserves `AF/BC/DE/HL/IY`, never touches `IX` | same |

**Why `32 - cols` is right:** the inner loop does `inc hl` once per cell, so `HL` has advanced by
`cols`; a row is 32 bytes, so `+ (32 - cols)` lands on the same column one row down. Skipping zero
bytes makes both routines **composite** rather than blit — an L-piece does not blank the empty
cells of its bounding box.

### Hard rule: erase to `0`, always

`borrar_tetromino` writes `0` = black PAPER on black INK, so the well interior is pure black and the
`Tetris_3D` bevel under it is invisible. That is intended, and testing the pattern rather than the
screen was a deliberate fix (`failure-patterns` §3.1). If you "improve" this by erasing to a non-zero
background attribute, **every erased cell becomes solid geometry** — occupied means `attribute != 0`,
so the well fills with invisible walls within one frame. **No non-zero value is safe.**

**Do not tidy the shared loop label in `pintar_tetromino`.** It has no row label: the row-advance
code at `:59-64` falls into `djnz pintar_loop` (`:65`), which jumps back to the **column**-loop
entry at `:47` — correct only because `ld c, (ix+1)` at `:59` reloads the column counter first.
`borrar_tetromino` does the same job cleanly with its own `loop_filas` label (`clear.asm:17-18`);
if you restructure `piezas.asm:59-65`, copy that.

## 4. Flicker and tearing — two separate causes

**Cause 1: nothing waits for the raster.** No code synchronises with the display, so an erase or
redraw can land while the ULA is reading those bytes and a cell shows half-old, half-new. The fix
mechanism and its interrupt prerequisite belong to `interrupts-and-timing`.

**Cause 2: erase-then-check-then-draw with no buffer.** `juego.asm:20` erases the piece; it is redrawn
only at `:36`/`:42`, after `comprobar` (`:29`) and `GIRAR` (`:41`) — absent from the screen for that
whole span, every frame. `GIRAR` is worst: it blocks in `Soltar_Tecla` (`giro.asm:33-38`) until the
key is released, so holding Q or W makes the piece vanish. Shrink the invisible window:

1. Read input into a register/variable only — candidate row and column, and *which way* to
   rotate. **No screen writes, and do not follow the rotation pointer yet: `IX` must still hold
   the shape that is currently on screen.**
2. `call borrar_tetromino` — erases using the **old** `IX`, so it erases exactly the cells it drew.
3. Now apply the rotation (`IX` = `(ix+8/+9)` or `(ix+10/+11)`) and `call comprobar` on the
   candidate. Both must stay inside the window: `comprobar` reads the attribute file, so the
   piece has to be gone or it collides with itself.
4. `call pintar_tetromino` immediately — candidate `IX`/`B`/`C` if accepted, the originals if rejected.

> **Order rule: erase before `IX` changes.** `borrar_tetromino` tests the *pattern* byte, not the
> screen (`clear.asm:20-25`), so rotating first makes it blank the **new** shape's cells and leave
> the old shape's behind. Those leftovers are non-zero, so `comprobar` reads them as settled blocks
> forever — invisible debris. `piece-rotation` calls this fatal.

Delay loops (`Tiempo`), key-release waits and text printing all go outside steps 2-4. A double
buffer does not help: 48K has no page flipping, so a shadow buffer must still be `LDIR`-ed into
`$5800` and tears the same way.

## 5. Border erosion — permanent damage to the board

`dibujar_tablero` (`tableroJuego.asm:4-42`) paints the well **once**: left wall column 6, right wall
column 25, rows 0-21; floor row 22 columns 6-25; attribute `6*8+7` = 55 (yellow paper, white ink).
Nothing ever redraws it. Failure chain: a piece overlaps a border cell -> `pintar_tetromino`
overwrites it with the piece colour -> next frame `borrar_tetromino` writes `0` there -> the cell is
zero, so it is no longer a wall -> the next piece passes through the hole and erases more. **Seen as:**
black gaps grow in the yellow wall, then pieces slide out sideways or fall through the floor.

- **(a) Prevent it — the fix.** Never let a piece occupy a border cell. Correct collision testing does
  this for free, since border cells are non-zero. The real bug is that moves and rotations get drawn
  without being validated: `game-loop-and-collision`, `piece-rotation`.
- **(b) Repair it — optional insurance.** Re-run the border and floor loops once per new piece.
  Cheap: 22 + 22 + 20 = 64 byte writes. It hides the bug rather than fixing it.

## 6. Text output library (`L30.3 - printat.asm`) — third-party, treat as stable

| Entry | Line | Does |
|---|---|---|
| `PRINTAT` | `:14` | `A`=attribute, `B`=row, `C`=col, `IX`=zero-terminated string; sets cursor, falls through to `PRINTSTR` |
| `PRINTSTR` | `:20` | prints from `IX` until a `0` byte; **increments `IX`** |
| `PRINTCHNUM` | `:96` | `A` = character code -> `DE` = glyph address; falls into `PRINTCHAR` |
| `PRINTCHAR` | `:112` | copies 8 pixel bytes from `(DE)`, writes 1 attribute byte, advances both cursors |
| `CRtoSCREEN` | `:45` | `B`,`C` -> pixel address, stored in `(SCR_CUR_PTR)` |
| `CRtoATTR` | `:72` | `B`,`C` -> attribute address, stored in `(SCR_ATTR_PTR)`; keeps `BC`, rows 0-23 (§2) |
| `CLEARSCR` | `:150` | zeroes `$4000`-`$5AFF`, i.e. both regions |
| `INK2PAPER` | `:137` | **dead code** — defined once, never called anywhere in the tree |

Cursor state lives in three variables at the end of the file: `SCR_CUR_PTR` `$9CD2`,
`SCR_ATTR_PTR` `$9CD4`, `PRINT_ATTR` `$9CD6`.

**Defect — column 31 does not wrap to the next row.** `PRINTCHAR:124-127` advances both cursors with
`INC (HL)`, incrementing only each pointer's **low byte**, so past column 31 it wraps within the same
256-byte block instead of moving down a row. Keep every string inside one row.

`PRINTAT`/`PRINTSTR` use `IX` as the string pointer, so **any text output destroys the current piece
pointer** — see `register-protocol` and `scoring-and-level`.

## 7. The UTF-8 string bug

The `.asm` files are UTF-8, so Spanish punctuation assembles as **two bytes**: `MensajeReiniciar`
starts `C2 BF` for `¿` (`pantallas.asm:113`, `main.lst:192`) and `MensajeGameOver` starts `C2 A1`
for `¡` (`pantallas.asm:114`, `main.lst:199`).

`PRINTCHNUM` computes `CHARSET + (code-32)*8` as `HL = code*8 + $9BD7` (from
`LD DE, CHARSET-(8*32)`). `CHARSET` is `incbin "charset.bin"` — only 768 bytes at `$9CD7`-`$9FD6`,
covering codes 32-127. Any byte >= 128 indexes past the end into whatever assembled next:

- code `$C2` -> `$9BD7 + 194*8` = **`$A1E7`**, holding `DD E1 C9 F5 FD E5 E5 D5` — the `POP IX / RET` tail of `comprobar` plus the prologue of `borrar_tetromino`.
- code `$A1` -> `$9BD7 + 161*8` = `$A0DF`, inside the piece table (`T_J3`, `piezas.asm:14`).

Each affected message prints two garbage glyphs before its text. **Rule: ASCII only in strings** —
write `Reiniciar el juego (S/N)?` and `Juego Terminado!`; accented letters fail the same way. Only
bytes inside `db "..."` matter (comments are safe); `pantallas.asm:113-114` are the only two such
lines in the tree, and both sit on the unreachable `Pantalla_Final` path, so the garbage appears the
moment the game-over screen is wired up — which this project has to do.

## 8. Two colour collisions, not one

**Z and S** both assemble with `7*8` white (`piezas.asm:25-29`) and **O and I** both with `6*8`
yellow (`piezas.asm:5,22-23`). Each pair is indistinguishable in play. Only `1*8` blue and `3*8`
magenta are unused — exactly enough to fix both. Fix belongs to `piece-data-and-spawn`;
`failure-patterns` §3.3 records that the O/I collision was introduced by the table rewrite.

## Common mistakes

- Erasing to a non-zero "background" attribute. Turns every erased cell into a solid wall.
- Using a row stride other than 32, or hand-rolling the address instead of one of the two routines
  in §2 (new code: `CRtoATTR`, which keeps `BC`).
- Calling `CRtoATTR` with a row >= 24. `AND 3 : OR #58` wraps it to the top of the screen (§2).
- Putting `ld b,(ix)` / `ld c,(ix+1)` **before** `call CalcularAtributo`. Silent breakage.
- Following the rotation pointer before `borrar_tetromino`. Old shape stays as invisible debris (§4).
- Reformatting `piezas.asm:59-65` and breaking the shared `pintar_loop` label.
- Adding a double buffer. No page flipping on 48K; the copy tears anyway.
- Printing text into columns 7-24. It becomes collidable geometry inside the well.
- Accented characters or `¡` / `¿` in a new message string.
- Assuming the border repairs itself. It is drawn once and never again.
- Leaving a blocking key-release wait or a delay loop between the erase and the redraw.
