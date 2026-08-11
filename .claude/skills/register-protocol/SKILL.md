---
name: register-protocol
description: Use when editing, adding, reordering, or calling any routine in the TETRIS_Z80 Z80 assembly source — new routines, new call sites, changing instruction order around an existing call, or adding text/score output while a piece is on screen. Load before writing any Z80 code in this repo.
---

# Register protocol — the unwritten calling convention

## The core model

This program has almost no variables. Game state lives in CPU registers and is passed between
routines by convention. Nothing enforces it, nothing validates it, and there is no error.

| State | Lives in | Written at |
|---|---|---|
| Current piece row | register `B` | `juego.asm:6, 23, 34` |
| Current piece column | register `C` | `juego.asm:35, 40` |
| Current piece shape | `IX` → 12-byte rotation record | `tetromino_next.asm:6`, `giro.asm:19, 27` |
| Column, second copy | `Medio` ("middle"), memory `$A16F` | `piezas.asm:31`, `juego.asm:8`, `movimiento.asm:22, 30` |

**Any routine that clobbers `BC` moves the piece. Any routine that clobbers `IX` changes which
piece is falling.** The game does not crash — it silently does something wrong.

## Z80 background this file assumes

- 8-bit registers `A B C D E H L` plus flags `F`; they pair as `AF BC DE HL`. `IX` and `IY` are
  separate 16-bit **index registers**, used here as data pointers.
- `push rr` copies a pair onto the **stack**, `pop rr` takes the top entry back; they are
  last-in-first-out, so pops must mirror pushes exactly.
- `call` puts the **return address** on that same stack. A routine that pushes more than it pops
  makes its own `ret` jump to garbage.
- `djnz label` means "decrement `B`, jump if non-zero". It **always** uses `B`, so any `djnz` loop
  destroys the piece row unless `BC` was pushed first.
- "Destroys"/"clobbers" below means: on return the register holds a different value.

## Clobber table

Traced from each routine body. `—` means none.

| Routine (English) | file:line | Inputs | Returns | Preserves | Destroys |
|---|---|---|---|---|---|
| `CalcularAtributo` (calculate attribute address) | `pantallas.asm:67` | `B`=row, `C`=col | `HL`=attr address | `AF DE IX IY` | **`BC`** (→`$5800`), `HL` |
| `comprobar` (to check — collision test) | `test_col.asm:3` | `B`,`C`,`IX` | `A`=1 collision, 0 free | `BC DE HL IX IY` | **`AF`** |
| `pintar_tetromino` (paint piece) | `piezas.asm:34` | `B`,`C`,`IX` | — | `AF BC DE HL IX IY` | — |
| `borrar_tetromino` (erase piece) | `clear.asm:3` | `B`,`C`,`IX` | — | `AF BC DE HL IX IY` | — |
| `GIRAR` (to rotate) | `giro.asm:1` | `IX`, keyboard | `IX`=new rotation | `BC HL IY` | `AF`, `DE`, **`IX`** |
| `MOVER` (to move) | `movimiento.asm:1` | keyboard | writes `(Medio)` | `BC DE HL IX IY` | `AF` |
| `Tiempo` (time — busy-wait) | `caida.asm:14` | — | — | `AF BC DE HL IX IY` | — (writes `$7000`) |
| `seleccionar_pieza` (select piece) | `tetromino_next.asm:5` | — | `IX`=piece, `B`=0, `C`=15 | `HL IY` | `AF`, **`BC`**, `DE`, **`IX`** |
| `dibujar_tablero` (draw board) | `tableroJuego.asm:4` | — | — | — | `AF BC DE HL` **`IX IY`** |
| `iniciar` (to start — the game loop) | `juego.asm:3` | — | — | — | everything |
| `Pantalla_Ini` (initial screen) | `pantallas.asm:3` | — | — | `IY` | `AF BC DE HL` **`IX`** |
| `EsperarTecla` (wait for key) | `pantallas.asm:83` | — | `A`=`$FF` | `DE HL IX IY` | `AF`, `BC` |
| `LeerTecla` (read key) | `pantallas.asm:89` | — | `A`=`$FF` | `DE HL IX IY` | `AF`, `BC` |
| `SoltarTecla` (release key) | `pantallas.asm:100` | `BC`=port | `A`=`$FF` | `BC DE HL IX IY` | `AF` |
| `PRINTAT` | `L30.3 - printat.asm:14` | `A`=attr, `B`=row, `C`=col, `IX`=string | — | `C`, `IY` | `AF`, **`B`**(→0), `DE`, `HL`, **`IX`** |
| `PRINTSTR` | `L30.3 - printat.asm:20` | `IX`=string | — | `C`, `IY` | `AF`, **`B`**(→0), `DE`, `HL`, **`IX`** |
| `PREP_PRT` (set attribute + cursor) | `L30.3 - printat.asm:32` | `A`=attr, `B`, `C` | `HL` | `BC DE IX IY` | `AF`, `HL` |
| `PRINTCHNUM` (print char by code) | `L30.3 - printat.asm:96` | `A`=char code | — | `C`, `IX`, `IY` | `AF`, **`B`**(→0), `DE`, `HL` |
| `PRINTCHAR` | `L30.3 - printat.asm:112` | `DE`=glyph address | — | `C`, `IX`, `IY` | `AF`, **`B`**(→0), `DE`, `HL` |
| `CRtoSCREEN` (coord → pixel address) | `L30.3 - printat.asm:45` | `B`, `C` | `HL`, `(SCR_CUR_PTR)` | `BC DE IX IY` | `AF`, `HL` |
| `CRtoATTR` (coord → attribute address) | `L30.3 - printat.asm:72` | `B`, `C` | `HL`, `(SCR_ATTR_PTR)` | `BC DE IX IY` | `AF`, `HL` |
| `CLEARSCR` (clear screen) | `L30.3 - printat.asm:150` | — | — | `A`, `IX`, `IY` | `F`, `BC DE HL` |
| `Tetris_3D` (bevel background) | `L35 - Tetris_3D.asm:3` | — | — | `E`, `HL` | `AF`, `B`, `C`, `D`, **`IX`**(→`$5800`), **`IY`**(→`$9FDF`) |
| `InicioDePantalla` (start of screen) | `titulo.asm:3` | — | blocks until **Q** | `E`, `IX`, `IY` | `AF`, `BC`, `D`, `HL` |
| `PintarPantalla` (paint screen) | `titulo.asm:8` | `HL`=6912-byte source | blocks until **Q** | `E`, `IX`, `IY` | `AF`, `BC`, `D`, `HL` |

`pintar_tetromino`, `borrar_tetromino` and `Tiempo` are the only fully register-safe routines here.
`CRtoATTR` returns the **same address** as `CalcularAtributo` **for rows 0-23** but keeps `BC` —
prefer it in new code (its only side effect is the print-cursor variable, which `PRINTAT`
recomputes anyway). Outside that range they differ: `CRtoATTR` does `AND 3 : OR #58`
(`L30.3 - printat.asm:78-79`) and so wraps rows mod 32 — `B=255, C=15` gives `$5BEF`, where
`CalcularAtributo` gives `$77EF`. See `memory-map` §1.

## Landmine 1 — `CalcularAtributo` destroys `BC`

`pantallas.asm:77` is `LD BC, $5800`: it loads the attribute-file base into `BC` to add it, and
never restores it. Its header comment (`pantallas.asm:68-69`) does not say so. All three callers
survive only because they reload `B`/`C` from the piece record *after* the call —
`piezas.asm:41-43`, identical at `test_col.asm:10-13` and `clear.asm:10-12`:

```asm
    call CalcularAtributo  ; HL = attribute address for (B,C). BC is now $5800.
    ld b, (ix)             ; B = piece height, reloaded from the record
    ld c, (ix+1)           ; C = piece width, reloaded from the record
```

**Never reorder those three lines.** The broken version assembles cleanly and fails silently:

```asm
    ld b, (ix)             ; WRONG
    ld c, (ix+1)           ; WRONG
    call CalcularAtributo  ; WRONG: address computed from height/width, not row/column —
                           ; and BC is clobbered anyway. Piece draws in the wrong place.
```

## Landmine 2 — printing text destroys the current piece

`PRINTSTR` reads the string through `IX` and walks it to the terminating zero
(`L30.3 - printat.asm:20, 24`); `PRINTCHAR` runs `djnz` over 8 scanlines (`:113, 120`), leaving
`B` = 0. **Every text call destroys both the piece pointer and the piece row.** This is the number
one way to break the game while adding a score display. `Pantalla_Ini` gets away with it only
because it runs before any piece exists (`main.asm:10` precedes `main.asm:14`).

Mandatory wrapper — copy the whole block:

```asm
    push ix                ; save the current piece pointer
    push bc                ; save piece row (B) and column (C)
    ld a, 6                ; attribute byte: yellow ink, black paper
    ld b, 1                ; text row 1 (valid 0..23)
    ld c, 26               ; text column 26 — OUTSIDE the well. Columns 6-25 are playfield.
    ld ix, MiTexto         ; IX = address of a zero-terminated string
    call PRINTAT
    pop bc                 ; mirror order: BC pushed last, so popped first
    pop ix
```

Do not print inside the well (attribute columns 6-25, rows 0-22): collision means "attribute byte
non-zero", so text there becomes solid blocks. See `rendering-and-attributes`.

## Landmine 3 — `comprobar` returns in `A` and must not be "cleaned up"

`test_col.asm:4-8` pushes `IX IY HL DE BC` and `:49-53` pops them — **`AF` is deliberately absent**.
The result is set by `ld a,0` / `ld a,1` at `:42` / `:46` and read by callers with `or a` / `jr z`.
Every other routine in the tree preserves `AF`. Adding `push af` / `pop af` here for "consistency"
restores the old `A` and throws the collision result away. Do not do it.

## `Medio` vs `C` — two copies of the column, out of sync by design

`MOVER` writes `(Medio)` in memory (`movimiento.asm:22, 30`) and never touches `C`. The loop
reconciles them with `ld c, e` (`juego.asm:35, 40`) — but only **after** `call comprobar`
(`juego.asm:29`) has already tested the old `C`, so a sideways move is validated one iteration late.

**Invariant every correct edit must maintain: `C` equals `(Medio)` at every `call comprobar`.**
Fixing the loop ordering belongs to `game-loop-and-collision`; do not do it here.

Three places define the spawn column and they disagree: `piezas.asm:31` `Medio: DB 14`,
`tetromino_next.asm:25` `ld c, 15`, `juego.asm:7-8` `ld a,15 / LD (Medio),A`. The `DB 14` never
takes effect because `iniciar` overwrites it first. See `piece-data-and-spawn`.

## `IY` is unmanaged

`piezas.asm:44`, `clear.asm:13` and `test_col.asm:14` point `IY` at piece-pattern data around
`$A0xx`; `L35 - Tetris_3D.asm:9` sets it to `Tetro_3D` = `$9FD7` and exits with `$9FDF`. Nothing
ever restores a sane value. `pintar_tetromino`, `borrar_tetromino` and `comprobar` do `push iy` /
`pop iy`, so they restore the **caller's** `IY` — which is already garbage. Treat `IY` as undefined
at all times: never pass data in it, never assume it survives a call. Why this is dangerous rather
than merely untidy: `interrupts-and-timing`.

## Rules for writing a new routine

1. Push every register pair you write; pop in exact mirror order, on **every** exit path.
2. `B` and `C` belong to the piece. If your routine loops, `push bc` first — `djnz` eats `B`.
3. `IX` belongs to the piece. Push it around anything that prints.
4. Balance `push`/`pop` per path: an early `ret` that skips a `pop` returns to a garbage address.
5. If your routine needs the piece position, take it in `B`/`C`. Do not add a new variable.
6. Need an attribute address without losing `BC`? Call `CRtoATTR` — but only for rows 0-23. Do not
   swap it into existing `CalcularAtributo` call sites; the `B=255` probe in `test_col.asm` moves.
7. Never assume a routine preserves a register because a similar one does — check the table.

Skeleton to copy (a row scanner, the shape line-clear work needs):

```asm
; contar_fila ("count row") — counts occupied cells in one board row.
;   IN : A = attribute row 0..22
;   OUT: A = count of non-zero attribute bytes in columns 7..24
;   Preserves BC, DE, HL, IX. Destroys F. IY untouched.
contar_fila:
    push bc                ; B = piece row, C = piece column — must survive
    push de
    push hl
    push ix                ; current piece pointer — must survive
    ld b, a                ; safe: the caller's B is on the stack now
    ld c, 7                ; leftmost playfield column (well is columns 7..24)
    call CRtoATTR          ; HL = $5800 + row*32 + col, and BC survives
    ld d, 0                ; D = running count
    ld e, 18               ; E = 18 columns to scan
cf_loop:
    ld a, (hl)             ; one attribute byte
    or a                   ; sets the Z flag when the byte is 0 (empty)
    jr z, cf_next
    inc d
cf_next:
    inc hl
    dec e
    jr nz, cf_loop         ; dec e set the flags; inc hl did not disturb them
    ld a, d                ; result into A
    pop ix                 ; mirror of the pushes: pushed last, popped first
    pop hl
    pop de
    pop bc
    ret
```

## Common mistakes

| Mistake | What happens |
|---|---|
| Reordering `call CalcularAtributo` against `ld b,(ix)` / `ld c,(ix+1)` | Address computed from the wrong numbers; piece renders elsewhere. Silent. |
| Adding `push af` / `pop af` to `comprobar` | Collision result destroyed; pieces pass through walls or lock instantly. |
| Printing text mid-game without `push ix` | `IX` ends on the string terminator; the "current piece" becomes whatever bytes follow it. |
| Using `B` as a scratch counter, or any `djnz`, without `push bc` | Piece row jumps. `PRINTAT` does this to you too. |
| Assuming a routine preserves registers because a neighbour does | `pintar_tetromino` preserves everything; `CalcularAtributo` two files away eats `BC`. |
| Adding a `FILA`/`COLUMNA` variable instead of using `B`/`C` | Three copies of the position (`B`/`C`, `Medio`, yours) drift apart, as `Medio` already does. |
| Unbalanced `push`/`pop` on an early-exit path | `ret` pops a saved register as the return address; execution lands in data. |

## See also

`project-orientation` (file map, Spanish glossary) · `assembler-conventions` (`ld iy, ix` and
`LD IX, DE` are sjasmplus fake instructions) · `memory-map` (`$5800`, `Medio`, ports) ·
`interrupts-and-timing` (the `IY` hazard) · `game-loop-and-collision` (fixing `C`/`Medio` order).
