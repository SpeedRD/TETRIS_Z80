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
| `CalcularAtributo` | `pantallas.asm:69-82` | `AF`, `DE`, `IX`, `IY` | **`BC`** | any row (plain `row*32+col`) |
| `CRtoATTR` | `L30.3 - printat.asm:72-88` | **`BC`**, `DE`, `IX`, `IY` | `AF`, `(SCR_ATTR_PTR)` | **0-23 only** |

- **New code: use `CRtoATTR`** — it preserves `BC`, so a row/column loop counter survives the call.
  `lineas.asm` (`fila_llena`, `bajar_filas`) and `pintar_siguiente` all depend on this. Limit: it
  builds the high byte with `AND 3 : OR #58` (`printat.asm:78-79`), so any row >= 24 wraps modulo 32
  back to the top of the screen. For a row outside 0-23 use `CalcularAtributo`; nothing in the
  program passes one today.
- **Do not change existing call sites** — the three `CalcularAtributo` callers already work around
  its `BC` clobber and are correct as they stand.

`CalcularAtributo` bit-splits rather than multiplying: `SRL H` ×3 gives `row>>3` (which 256-byte
third), `SLA A` ×5 then `OR c` gives `(row&7)*32 + col`, and `LD BC,$5800 : ADD HL,BC` adds the
base — **that `LD BC` is what destroys the caller's row and column** (`pantallas.asm:79`).
**Never revert it to the old `and $F8` + three `rlca` form** (`pantallas.lst:49`): `rlca` rotates
instead of shifting and gave garbage addresses. The current form is a deliberate, verified fix —
`failure-patterns` §3.2.

**The calling rule the whole codebase depends on.** `CalcularAtributo` returns with `BC` =
`$5800`. All three callers survive only by reloading `B` and `C` from the piece record **after**
the call (`piezas.asm:49-51`, `clear.asm:11-13`, `test_col.asm:11-14`). Reorder those lines and
the loops run with rows=`$58`, cols=`$00` and the game breaks silently. Always:

```asm
    call CalcularAtributo   ; HL = attribute address; BC now destroyed
    ld b, (ix)              ; rows — MUST come after the call
    ld c, (ix+1)            ; cols — MUST come after the call
```

## 3. Drawing and erasing a piece

Both walk the record's pattern bytes (offsets `+2..+7`, `piece-data-and-spawn`), `rows x cols` cells, at most 6.

| | `pintar_tetromino` (`piezas.asm:42-82`) | `borrar_tetromino` (`clear.asm:3-47`) |
|---|---|---|
| Per cell | pattern byte 0 -> skip, else `ld (hl),a` (`:61`) | pattern byte 0 -> skip, else `ld (hl),0` (`:26`) |
| Tests | the pattern byte | the **pattern** byte, not the screen |
| Row step | `ld a,32 : sub c : add hl,de` (`:67-72`) | `ld a,32 : sub (ix+1) : add hl,de` (`:33-37`) |
| Registers | preserves `AF/BC/DE/HL/IY`, never touches `IX` | same |
| `IY` window | `di` at `:48`, `ei` right after `pop iy` at `:80` | `di` at `:9`, `ei` at `:44` |

Those `di`/`ei` brackets are load-bearing: both routines point `IY` at the piece pattern, and the
ROM's 50 Hz handler addresses through `IY`. `interrupts-and-timing` §1 owns the rule; the short
version is that `ei` goes **after** `pop iy`, never before.

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
code at `:67-72` falls into `djnz pintar_loop` (`:73`), which jumps back to the **column**-loop
entry at `:56` — correct only because `ld c, (ix+1)` at `:67` reloads the column counter first.
`borrar_tetromino` does the same job cleanly with its own `loop_filas` label (`clear.asm:18-19`);
if you restructure `piezas.asm:67-73`, copy that.

## 4. Flicker and tearing — one cause left, and it is bounded

**Cause 1: no raster sync — FIXED.** The loop opens with `HALT` (`juego.asm:35`), so it wakes in
the top border, and the erase/redraw pair is the first thing after it. `interrupts-and-timing` §2
owns the frame budget: the pair plus input, rotation and collision comes to ~8,600 T-states against
a ~14,000 T border window. A line clear adds enough to push that one frame past the window, which is
why a clear can tear slightly while normal play does not.

**Cause 2: erase-then-check-then-draw with no buffer — bounded, not eliminated.** The piece is
still absent from the screen between `borrar_tetromino` (`juego.asm:46`) and the single
`pintar_tetromino` at `:117`. What changed is that the gap is now short and constant: no busy-wait,
no key-release spin (`GIRAR` reads no keys), and one draw per pass rather than a draw per branch.
Keep it that way — the ordering below is what any new work in the loop must preserve:

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

Delay loops, key-release waits and text printing all go outside steps 2-4 — which is why
`ImprimirMarcador` is called from the lock path (via `anotar_lineas`) and only when a value actually
changed, never per frame. A double buffer does not help: 48K has no page flipping, so a shadow
buffer must still be `LDIR`-ed into `$5800` and tears the same way.

## 5. Border erosion — permanent damage to the board

`dibujar_tablero` (`tableroJuego.asm:4-42`) paints the well **once**: left wall column 6, right wall
column 25, rows 0-21; floor row 22 columns 6-25; attribute `6*8+7` = 55 (yellow paper, white ink).
Nothing ever redraws it. Failure chain: a piece overlaps a border cell -> `pintar_tetromino`
overwrites it with the piece colour -> next frame `borrar_tetromino` writes `0` there -> the cell is
zero, so it is no longer a wall -> the next piece passes through the hole and erases more. **Seen as:**
black gaps grow in the yellow wall, then pieces slide out sideways or fall through the floor.

- **(a) Prevent it — the fix, and what shipped.** Never let a piece occupy a border cell. Every
  candidate position now passes `en_rango` and `comprobar` before anything is drawn, and rotation
  kicks are bounded the same way, so no draw can reach column 6 or 25. `line-clear`'s row shift
  moves exactly 18 bytes per row for the same reason. `game-loop-and-collision`, `piece-rotation`.
- **(b) Repair it — optional insurance, not implemented.** Re-running the border and floor loops
  once per new piece would cost 22 + 22 + 20 = 64 byte writes. It hides a bug rather than fixing
  one, which is why it was not added; `tests/test_lineas.py` and `checklist6.py` assert border
  integrity instead.

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

Cursor state lives in three variables at the end of the file: `SCR_CUR_PTR` `$9CDB`,
`SCR_ATTR_PTR` `$9CDD`, `PRINT_ATTR` `$9CDF`.

`puntuacion.asm` uses `PREP_PRT` + `PRINTCHNUM` directly (`ImprimirMarcador`, `ImprimirBCD`,
`ImprimirDec3`) rather than `PRINTAT`, because it prints digits it computes rather than a stored
string — and because `PRINTAT` would take `IX`, the live piece pointer.

**Defect — column 31 does not wrap to the next row.** `PRINTCHAR:124-127` advances both cursors with
`INC (HL)`, incrementing only each pointer's **low byte**, so past column 31 it wraps within the same
256-byte block instead of moving down a row. Keep every string inside one row.

`PRINTAT`/`PRINTSTR` use `IX` as the string pointer, so **any text output destroys the current piece
pointer** — see `register-protocol` and `scoring-and-level`.

## 7. The UTF-8 string bug — fixed, and easy to reintroduce

**Every string in the tree is ASCII today.** The rule that keeps it that way:

> **ASCII only inside `db "..."`.** No `¡`, no `¿`, no accented letters. Comments are safe — only
> bytes that get assembled matter.

The `.asm` files are UTF-8, so Spanish punctuation assembles as **two bytes**: `MensajeReiniciar`
used to start `C2 BF` for `¿` and `MensajeGameOver` `C2 A1` for `¡`.

`PRINTCHNUM` computes `CHARSET + (code-32)*8` (from `LD DE, CHARSET-(8*32)`). `CHARSET` is
`incbin "charset.bin"` — only 768 bytes, covering codes 32-127. Any byte >= 128 indexes past the end
into whatever assembled next: code `$C2` landed inside the machine code of `comprobar` /
`borrar_tetromino`, and `$A1` inside the piece table. Each affected message printed two garbage
glyphs before its text.

It was invisible for a long time because both strings sat on the then-unreachable `Pantalla_Final`
path. That path is now reached on every game over, so a regression here shows up immediately —
which is the good outcome. `pantallas.asm:116-118` carries the explanation in the source.

## 8. Colour collisions — fixed, and there is no slack left

Every one of the seven shapes now has a distinct PAPER value. Two pairs used to collide: Z and S
both on `7*8` white, O and I both on `6*8` yellow. I moved to `1*8` blue and S to `3*8` magenta
(`piezas.asm:21-29`).

**All seven values 1-7 are now in use**, so a new shape has no free colour: you would be sharing
one deliberately, or extending past PAPER-only encoding into BRIGHT (bit 6). `piece-data-and-spawn`
§3 owns the table; `failure-patterns` §3.3 records how the collisions arose.

## Common mistakes

- Erasing to a non-zero "background" attribute. Turns every erased cell into a solid wall.
- Using a row stride other than 32, or hand-rolling the address instead of one of the two routines
  in §2 (new code: `CRtoATTR`, which keeps `BC`).
- Calling `CRtoATTR` with a row >= 24. `AND 3 : OR #58` wraps it to the top of the screen (§2).
- Putting `ld b,(ix)` / `ld c,(ix+1)` **before** `call CalcularAtributo`. Silent breakage.
- Following the rotation pointer before `borrar_tetromino`. Old shape stays as invisible debris (§4).
- Reformatting `piezas.asm:67-73` and breaking the shared `pintar_loop` label.
- Adding a double buffer. No page flipping on 48K; the copy tears anyway.
- Printing text into columns 7-24. It becomes collidable geometry inside the well.
- Accented characters or `¡` / `¿` in a new message string (§7).
- Assuming the border repairs itself. It is drawn once and never again.
- Leaving a blocking key-release wait or a delay loop between the erase and the redraw.
- Redrawing the scoreboard every frame. It costs T-states in the border window for nothing; refresh
  only when a value changed (`scoring-and-level`).
- Removing the `di`/`ei` bracket around an `IY` window in `pintar_tetromino` / `borrar_tetromino`,
  or moving the `ei` before the `pop iy` (§3, `interrupts-and-timing` §1).
