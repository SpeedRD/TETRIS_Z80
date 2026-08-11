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
| Current piece row | register `B` | `juego.asm:97, 102`; `seleccionar_pieza` returns `B=0` |
| Current piece column | register `C` | `juego.asm:65, 75`; `giro.asm:47`; `seleccionar_pieza` returns `C=15` |
| Current piece shape | `IX` → 12-byte rotation record | `tetromino_next.asm:72`, `giro.asm:30, 60` |
| Column, memory copy | `Medio` ("middle"), `$A58D` | `variables.asm:36`, `juego.asm:26, 79, 111`, `giro.asm:55, 61` |
| Sideways delta / key mask / gravity flag, within one pass | `D` / `E` / `H` | `juego.asm:8-14` |

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
| `CalcularAtributo` (calculate attribute address) | `pantallas.asm:69` | `B`=row, `C`=col | `HL`=attr address | `AF DE IX IY` | **`BC`** (→`$5800`), `HL` |
| `comprobar` (to check — collision test) | `test_col.asm:3` | `B`,`C`,`IX` | `A`=1 collision, 0 free | `BC DE HL IX IY` | **`AF`** |
| `pintar_tetromino` (paint piece) | `piezas.asm:42` | `B`,`C`,`IX` | — | `AF BC DE HL IX IY` | — |
| `borrar_tetromino` (erase piece) | `clear.asm:3` | `B`,`C`,`IX` | — | `AF BC DE HL IX IY` | — |
| `GIRAR` (to rotate) | `giro.asm:1` | `IX`, `B`, `C`, `(Medio)`, `A`=direction | on success `IX`, `C`, `(Medio)` = new | `B HL IY` | `AF`, `DE`; **`IX`/`C` are outputs** |
| `leer_teclas` (read keys) | `entrada.asm:17` | — | `A`=new-press mask | `BC DE HL IX IY` | `AF` |
| `en_rango` (in range) | `entrada.asm:42` | `C`, `IX` | `A`=0 fits, 1 outside | `BC DE HL IX IY` | `AF` |
| `limpiar_lineas` (clear lines) | `lineas.asm:16` | — | `A`=rows cleared | `BC DE HL IX IY` | `AF` |
| `fila_llena` (row full) | `lineas.asm:40` | `B`=row | `A`=1 full, 0 not | `BC DE HL` | `AF` |
| `bajar_filas` (lower rows) | `lineas.asm:62` | `B`=cleared row | — | `AF BC DE HL` | — |
| `anotar_lineas` (record lines) | `puntuacion.asm:22` | `A`=rows cleared | — | `BC DE HL IX IY` | `AF` |
| `reiniciar_marcador` (reset scoreboard) | `puntuacion.asm:79` | — | — | `AF BC DE HL IX IY` | — |
| `ImprimirMarcador` (print scoreboard) | `puntuacion.asm:107` | — | — | `BC IX IY` | `AF`, `DE`, `HL` |
| `ActualizarVelocidad` (update speed) | `puntuacion.asm:66` | — | writes `FRAMES_POR_FILA` | `BC IX IY` | `AF`, `DE`, `HL` |
| `seleccionar_pieza` (select piece) | `tetromino_next.asm:65` | — | `IX`=piece, `B`=0, `C`=15 | `HL IY` | `AF`, **`BC`**, `DE`, **`IX`** |
| `nueva_pieza` (new piece) | `tetromino_next.asm:28` | — | `DE`=record address | `BC HL IX IY` | `AF`, `DE` |
| `pintar_siguiente` (paint the next one) | `tetromino_next.asm:90` | — | — | `AF BC DE HL IX IY` | — |
| `dibujar_tablero` (draw board) | `tableroJuego.asm:4` | — | — | `IY` (reloaded to `$5C3A`) | `AF BC DE HL` **`IX`** |
| `iniciar` (to start — the game loop) | `juego.asm:16` | — | **never returns** | — | everything |
| `Pantalla_Ini` (initial screen) | `pantallas.asm:3` | — | — | `IY` | `AF BC DE HL` **`IX`** |
| `EsperarTecla` (wait for key) | `pantallas.asm:85` | — | `A`=`$1F` | `DE HL IX IY` | `AF`, `BC` |
| `LeerTecla` (read key) | `pantallas.asm:91` | — | `A`=`$1F` | `DE HL IX IY` | `AF`, `BC` |
| `SoltarTecla` (release key) | `pantallas.asm:102` | `BC`=port | `A`=`$1F` | `BC DE HL IX IY` | `AF` |
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

`pintar_tetromino`, `borrar_tetromino`, `pintar_siguiente`, `bajar_filas` and `reiniciar_marcador`
are fully register-safe. `CRtoATTR` returns the **same address** as `CalcularAtributo` **for rows
0-23** but keeps `BC` — prefer it in new code (its only side effect is the print-cursor variable,
which `PRINTAT` recomputes anyway); `lineas.asm` and `pintar_siguiente` both depend on that. Outside
rows 0-23 they differ: `CRtoATTR` does `AND 3 : OR #58` (`L30.3 - printat.asm:78-79`) and so wraps
rows mod 32. Nothing in the program passes such a row any more. See `memory-map` §1.

**New routines follow the same contract:** push everything you write, pop in mirror order, and
return the one result in `A`. Every routine added by the fix work does — which is what lets the loop
carry `D`, `E` and `H` across half a dozen calls (`game-loop-and-collision` §2).

## Landmine 1 — `CalcularAtributo` destroys `BC`

`pantallas.asm:79` is `LD BC, $5800`: it loads the attribute-file base into `BC` to add it, and
never restores it. Its header comment (`pantallas.asm:70-71`) does not say so. All three callers
survive only because they reload `B`/`C` from the piece record *after* the call —
`piezas.asm:49-51`, identical at `test_col.asm:11-14` and `clear.asm:11-13`:

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
one way to break the game while adding a display. `Pantalla_Ini` and `reiniciar_marcador` get away
with it only because they run before any piece exists; `ImprimirMarcador`, which runs mid-game,
wraps every print in `push ix : push bc` (`puntuacion.asm:108, 120`).

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

`test_col.asm:4-8` pushes `IX IY HL DE BC` and `:50-55` pops them — **`AF` is deliberately absent**.
The result is set by `ld a,0` / `ld a,1` at `:43` / `:47` and read by callers with `or a` / `jr z`.
Every other routine in the tree preserves `AF`. Adding `push af` / `pop af` here for "consistency"
restores the old `A` and throws the collision result away. Do not do it. The comment at `:55` says
so in the source; keep it there.

## `Medio` mirrors `C` — and must, at every `comprobar`

`(Medio)` is the memory copy of the current column. It is **not** an independent value and no longer
drifts: every site that commits a new column writes both. `juego.asm:78-79` after a sideways move,
`juego.asm:26` and `:110-111` at spawn, and `giro.asm:54-55` inside a successful rotation — which
matters because `GIRAR` may kick the column sideways and the rollback path (`giro.asm:61-62`) reads
`(Medio)` back into `C`.

**Invariant every correct edit must maintain: `C` equals `(Medio)` at every `call comprobar`.**

The spawn column now has exactly one definition — `ld c, 15` in `seleccionar_pieza`
(`tetromino_next.asm:75`). The `Medio: DB 15` initialiser in `variables.asm:36` is a placeholder
that `juego.asm` overwrites from `C` before the first piece is drawn; there is no third definition
any more. See `piece-data-and-spawn`.

## `IY` is a managed invariant: `$5C3A`, always, outside a bracket

`main.asm:8-11` sets `DI` / `LD IY,$5C3A` / `IM 1` / `EI` at startup, and interrupts stay on. The
ROM's 50 Hz handler at `$0038` addresses the system variables through `IY`, so **`IY = $5C3A` is a
program-wide invariant**, not a don't-care.

`piezas.asm:52`, `clear.asm:14` and `test_col.asm:15` still point `IY` at piece-pattern data, and
each one now brackets that window with `di` after its pushes and `ei` immediately after `pop iy`.
`L35 - Tetris_3D.asm` does not restore `IY`, so its caller brackets it and reloads `$5C3A`
(`tableroJuego.asm:39-41`).

Rules for a new routine that needs `IY`: bracket it yourself, `ei` **after** `pop iy` and never
before, and do not nest brackets. Still never pass data in `IY` across a call. Full reasoning:
`interrupts-and-timing` §1.

## Rules for writing a new routine

1. Push every register pair you write; pop in exact mirror order, on **every** exit path.
2. `B` and `C` belong to the piece. If your routine loops, `push bc` first — `djnz` eats `B`.
3. `IX` belongs to the piece. Push it around anything that prints.
4. Balance `push`/`pop` per path: an early `ret` that skips a `pop` returns to a garbage address.
5. If your routine needs the piece position, take it in `B`/`C`. Do not add a new variable.
6. Need an attribute address without losing `BC`? Call `CRtoATTR` — but only for rows 0-23. Do not
   swap it into the three existing `CalcularAtributo` call sites; they are written around its
   clobber and work as they stand.
7. If you point `IY` anywhere, bracket the window with `di` / `ei`, `ei` after `pop iy`.
8. Never assume a routine preserves a register because a similar one does — check the table.

Skeleton to copy (`lineas.asm:40-57`'s `fila_llena` is the shipped version of this shape):

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
| Adding a `FILA`/`COLUMNA` variable instead of using `B`/`C` | A third copy of the position drifts from `B`/`C` and `Medio`. Two is already the maximum the loop can keep in sync. |
| Writing `C` without writing `(Medio)` | The next `comprobar` or `GIRAR` rollback uses the other column; the piece ghosts or teleports. |
| Pointing `IY` somewhere with no `di`/`ei`, or `ei` before `pop iy` | The ROM's 50 Hz handler writes through the wrong `IY` into the code image. |
| Unbalanced `push`/`pop` on an early-exit path | `ret` pops a saved register as the return address; execution lands in data. |

## See also

`project-orientation` (file map, Spanish glossary) · `assembler-conventions` (`ld iy, ix` and
`LD IX, DE` are sjasmplus fake instructions) · `memory-map` (`$5800`, `Medio`, ports) ·
`interrupts-and-timing` (the `IY` hazard) · `game-loop-and-collision` (fixing `C`/`Medio` order).
