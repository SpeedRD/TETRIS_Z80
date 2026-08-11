---
name: project-orientation
description: Use when working in the TETRIS_Z80 ZX Spectrum Z80 assembly repo and the task is not yet scoped to one file — first contact with the codebase, questions like "what does juego.asm do" or "where is the board", unfamiliar Spanish identifiers (Medio, comprobar, seleccionar_pieza, GIRAR), or deciding which specialised skill to load.
---

# TETRIS_Z80 — orientation and router

Load this first. It says what each file is, what the Spanish names mean, and which skill to load next.

## What this is

ZX Spectrum 48K Tetris in Z80 assembly, assembled with **sjasmplus 1.23.1**. One translation unit:
`main.asm` (`ORG $8000`, `main.asm:4`) `INCLUDE`s 15 other `.asm` files (`main.asm:31-45`); the output
is a raw 9614-byte image spanning `$8000-$A58D`. It is **a complete game**: pieces spawn, fall, move,
rotate with wall kicks, lock, complete rows clear and compact, score/lines/level are kept and
displayed, gravity speeds up with the level, the next piece is previewed, and game over reaches
`Pantalla_Final` and restarts.

**Architecture is unchanged and stays unchanged.** The ZX Spectrum attribute file at `$5800` *is* the
board — a cell is occupied iff its attribute byte is non-zero. The well is 18 columns wide. `B` =
piece row, `C` = piece column, `IX` = pointer to the current piece record. This is not a rewrite, and
neither is your change.

## Source file map

| File | Spanish → English | Purpose | State |
|---|---|---|---|
| `main.asm` | — | Entry point; sets `SP`, fixes the interrupt state (`DI`/`IY=$5C3A`/`IM 1`/`EI`), calls title → menu → board → `iniciar`, then INCLUDEs everything | WORKING — `fin_del_programa: jr` terminator at `:27`; `inicializar:` (`:14`) is the restart target and re-sets `SP` |
| `titulo.asm` | "title" | LDIRs `TETRIS.scr` into `$4000`, waits for **Q** | WORKING — key wait masks to `AND $1F` / `CP $1F` |
| `pantallas.asm` | "screens" | Start menu, game-over screen, `CalcularAtributo`, keyboard helpers, all message strings | WORKING — `Pantalla_Final` (`:27`) is now reached (`jp` from `juego.asm`) and restarts with `jp inicializar`; strings are ASCII-only |
| `L30.3 - printat.asm` | — | Text/print library: `PRINTAT`, `CLEARSCR`, charset | **COURSE-SUPPLIED** (header credits Daniel León, UFV 2020) — treat as stable, do not edit |
| `L35 - Tetris_3D.asm` | — | Fills the pixel file with an 8-byte bevel pattern | **COURSE-SUPPLIED** — treat as stable; leaves `IY` corrupted, so its call site brackets it |
| `tableroJuego.asm` | "game board" | Draws the well: borders at attribute columns 6 and 25, floor at row 22 (`:8,:19,:30`) | WORKING — interior is columns 7-24 = **18 wide**; brackets `Tetris_3D` with `di`/`ld iy,$5C3A`/`ei` |
| `juego.asm` | "game" | The main loop: `iniciar`, `paso` | WORKING — `HALT`-synced frame loop; every candidate position is validated before it is drawn |
| `tetromino_next.asm` | "next tetromino" | LFSR randomness, `seleccionar_pieza` (returns `B=0, C=15`), and `pintar_siguiente` — the preview | WORKING — picks a *shape* uniformly from `spawn_table`; preview box at rows 10-13, columns 27-30 |
| `piezas.asm` | "pieces" | 19 twelve-byte piece records, `spawn_table`, `pintar_tetromino` | WORKING — all seven shapes have distinct colours |
| `test_col.asm` | "collision test" | `comprobar`: returns `A=1` on collision, `A=0` clear | WORKING — and now called correctly, with the exact position about to be drawn |
| `clear.asm` | (English) | `borrar_tetromino`: erases the piece by writing attribute `0` | WORKING |
| `giro.asm` | "rotation" | `GIRAR`: takes a direction in `A`, recentres, kicks, validates and commits | WORKING — reads no keys, never blocks |
| `entrada.asm` | "input" | `leer_teclas` (non-blocking, edge-detected J/K/Q/W) and `en_rango` (column bounds) | WORKING — new file |
| `lineas.asm` | "lines" | `limpiar_lineas`, `fila_llena`, `bajar_filas` — full-row detection and downward compaction | WORKING — new file |
| `puntuacion.asm` | "score" | `anotar_lineas`, BCD score, level, speed table, marker printing | WORKING — new file; prints in columns 26-31 only |
| `variables.asm` | "variables" | Every mutable byte the new code needs, in one block at `$A581` | WORKING — new file; **must stay the last `INCLUDE`** |

Data blobs: `TETRIS.scr` (`titulo.asm:32`) and `charset.bin` (`L30.3 - printat.asm:162`), both INCBIN;
`TETRIS2.scr` is referenced by nothing.

**Deleted:** `caida.asm` (the `Tiempo` busy-wait and its dead level arithmetic — gravity is now frame
counted) and `movimiento.asm` (`MOVER` — its job is now inline in `juego.asm`, validated). Both are
recoverable at commit `0a2377e` / tag `school-submission`. Of the committed `*.bin/*.lst/*.sld` build
output only `main.lst` matches the current sources — the per-file ones are stale, see
`failure-patterns`.

## Spanish → English glossary

| Identifier | Literal | What it is |
|---|---|---|
| `iniciar` | "to start" | `juego.asm:16` — seeds the sequence, spawns the first piece, enters the loop |
| `inicializar` | "to initialise" | `main.asm:14` — restart target (reset `SP` → menu → board → `iniciar`) |
| `paso` | "step/pass" | `juego.asm:34` — top of the frame loop; opens with `HALT` |
| `sin_gravedad` / `sin_lateral` / `sin_giro` | "without gravity/sideways/rotation" | `juego.asm:45,80,91` — skip labels for the three optional actions in a pass |
| `dibujar` | "to draw" | `juego.asm:116` — the single paint of the validated `(B, C, IX)` |
| `fin_partida` | "end of the game session" | `juego.asm:120` — `JP Pantalla_Final` |
| `comprobar` | "to check" | `test_col.asm:3` — collision test; result in `A`, does **not** preserve `AF` |
| `pintar_tetromino` | "paint tetromino" | `piezas.asm:42` — draw the piece at `B`,`C` |
| `borrar_tetromino` | "erase tetromino" | `clear.asm:3` — erase the piece at `B`,`C` |
| `seleccionar_pieza` | "select piece" | `tetromino_next.asm:65` — the announced piece into `IX`, and draw a new one |
| `nueva_pieza` / `sembrar_azar` / `iniciar_secuencia` | "new piece" / "seed the randomness" / "start the sequence" | `tetromino_next.asm:28,17,51` — LFSR draw, seeding, once-per-game setup |
| `pintar_siguiente` | "paint the next one" | `tetromino_next.asm:90` — the preview box |
| `dibujar_tablero` | "draw the board" | `tableroJuego.asm:4` — draw well borders and floor |
| `GIRAR` | "to rotate" | `giro.asm:1` — rotate: recentre, kick, validate, commit. Direction in `A` |
| `leer_teclas` | "read keys" | `entrada.asm:17` — one non-blocking, edge-detected read per pass |
| `en_rango` | "in range" | `entrada.asm:42` — does the whole piece fit in columns 7-24? |
| `limpiar_lineas` / `fila_llena` / `bajar_filas` | "clear lines" / "row full" / "lower the rows" | `lineas.asm:16,40,62` — clear detection and compaction |
| `anotar_lineas` | "record the lines" | `puntuacion.asm:22` — score, lines, level and marker refresh, once per lock |
| `ActualizarVelocidad` / `reiniciar_marcador` / `ImprimirMarcador` | "update the speed" / "reset the scoreboard" / "print the scoreboard" | `puntuacion.asm:66,79,107` |
| `CalcularAtributo` | "calculate attribute" | `pantallas.asm:69` — `B`,`C` → `HL` = attribute address. **Clobbers `BC`** (`:79`) |
| `EsperarTecla` / `LeerTecla` / `SoltarTecla` | "wait for key" / "read key" / "release key" | `pantallas.asm:85,91,102` — blocking keyboard helpers, menus only |
| `Pantalla_Ini` | "screen, start" | `pantallas.asm:3` — start menu, waits for S or N |
| `Pantalla_Final` | "final screen" | `pantallas.asm:27` — game-over screen; `jp inicializar` to restart |
| `FinDelJuego` | "end of the game" | `pantallas.asm:58` — prints thanks, then `fin: JR fin` (the deliberate quit path, via **N**) |
| `InicioDePantalla` | "start of screen" | `titulo.asm:3` — title screen |
| `PintarPantalla` | "paint screen" | `titulo.asm:8` — blits 6912 bytes to `$4000`, then falls into the key wait |
| `Medio` | "middle" | `variables.asm:36` (`$A58D`) — the memory copy of `C`, kept in sync at every commit |
| `PUNTOS` / `LINEAS` / `NIVEL` / `PROX_NIVEL` | "points" / "lines" / "level" / "next level" | `variables.asm:13-16` — score (packed BCD) and progression counters |
| `FRAMES_POR_FILA` / `contador_frames` / `FRAMES_POR_NIVEL` | "frames per row" / "frame counter" / "frames per level" | `variables.asm:19-20`, `puntuacion.asm:16` — the gravity clock |
| `semilla` / `siguiente_pieza` / `teclas_ant` | "seed" / "next piece" / "previous keys" | `variables.asm:28,30,23` — LFSR state, preview slot, edge-detection state |
| `MensajeIniciar` / `MensajeReiniciar` / `MensajeGameOver` | "start message" / "restart message" / "game-over message" | `pantallas.asm:114`, `:120`, `:121` — zero-terminated, ASCII only |
| `fin` | "end" | `pantallas.asm:67` — the infinite loop after "Gracias por jugar" |

Comment vocabulary: *fila* row, *columna* column, *pantalla* screen, *tecla* key, *pulsada* pressed,
*soltar* release, *esperar* wait, *pieza* piece, *tablero* board, *borde* border, *izquierda/derecha*
left/right, *siguiente* next, *dirección* address, *guardar* save, *borrar* erase, *pintar* paint,
*aleatorio* random, *nivel* level, *caída* fall, *partida* game session, *retranqueo* wall kick,
*marcador* scoreboard, *pozo* well, *hueco* gap/hole, *ancho* width, *cuenta* count.

### The old inverted label names are gone

`juego.asm` used to name its keep-falling branch `cambiar_tetromino` ("change tetromino") and its
lock-and-spawn path was the unnamed fall-through — the names meant the opposite of what they did.
The loop was rewritten and those labels no longer exist. **If you see `ciclo_juego`,
`siguiente_juego` or `cambiar_tetromino` referenced anywhere, that text is stale.** Read the flag,
not the name, regardless: `comprobar` returns `A=0` for **no collision**.

## Which skill to load

| Task | Load |
|---|---|
| "make rotation work", "pieces rotate into the wall" | `piece-rotation`, `game-loop-and-collision` |
| "pieces go through walls", "collision is wrong" | `game-loop-and-collision`, `register-protocol` |
| "add line clearing", "full rows don't disappear" | `line-clear`, `rendering-and-attributes` |
| "add a score", "show the level" | `scoring-and-level`, `rendering-and-attributes` |
| "the game restarts by itself", "game over never happens" | `game-loop-and-collision`, `failure-patterns` |
| "gravity is too fast/slow", "it freezes" | `interrupts-and-timing` |
| "add soft drop", "add a down key" | `game-loop-and-collision` (it owns input and the loop) and `entrada.asm`'s `leer_teclas`. No down key is read today; `memory-map`'s port table shows which half-row a new one would come from |
| "add sound", "set the border colour" | `memory-map` §7 — port `$FE` is still never written |
| "it won't build", "unknown instruction", "what is `LD IX, DE`" | `assembler-conventions`, `build-and-verify` |
| "how do I run it", "how do I check my change" | `build-and-verify` |
| "where can I put a variable", "what address is free" | `memory-map` |
| "why does it flicker", "the colours are wrong", "text looks like garbage" | `rendering-and-attributes` |
| "which register can I use here", "my change moved the piece" | `register-protocol` |
| "what do the piece bytes mean", "add a next-piece preview" | `piece-data-and-spawn` |
| "I already tried X and it didn't work" | `failure-patterns` |

## Universal rules — apply to every edit

1. **`IX` is the live piece pointer, globally.** `PRINTAT` also uses `IX` as its string pointer, so
   **any text output destroys the current piece**. Save and restore it. → `register-protocol`
2. **`B` and `C` are the piece position, globally.** There is no position variable; any routine that
   clobbers `BC` moves the piece. `CalcularAtributo` clobbers `BC` (`pantallas.asm:79`). → `register-protocol`
3. **`C` is the live column and `(Medio)` must equal it at every `comprobar`.** Both are written
   together at every commit; `GIRAR` writes `Medio` itself. → `game-loop-and-collision`
4. **`IY` must be `$5C3A` outside a `di`/`ei` bracket.** Interrupts are on and the ROM's 50 Hz handler
   addresses through `IY`. → `interrupts-and-timing`
5. **Include order in `main.asm:31-45` is load-bearing**, and `variables.asm` must stay last.
   Append new files before it; do not reorder. → `assembler-conventions`
6. **The build must stay at 0 errors, 0 warnings** (currently 1440 lines, 9614 bytes). → `build-and-verify`
7. **Run `python3 tests/run_all.py`** — ~130 assertions over five suites plus the manual checklist,
   driving ZEsarUX. It cannot see tearing or flicker, so anything visual still needs a human.
   → `build-and-verify`

### Correct example: print during play without breaking the game

```asm
; PRINTAT (L30.3 - printat.asm:14) takes A=attribute, B=row, C=column,
; IX=zero-terminated string -- and IX is ALSO the live piece pointer,
; while B/C are ALSO the live piece position. Save all three.
    push ix                 ; save the current piece record pointer
    push bc                 ; save B = piece row, C = piece column
    ld a, 7                 ; attribute: white ink, black paper
    ld b, 2                 ; text row 2
    ld c, 27                ; column 27 -- OUTSIDE the well (interior is columns 7-24)
    ld ix, MiTexto          ; string pointer; this is what destroys the piece pointer
    call PRINTAT
    pop bc                  ; restore piece row/column
    pop ix                  ; restore piece pointer -- game state is now intact
; Put the string with the other strings (pantallas.asm:113-121, or
; puntuacion.asm:163-166), never in the instruction stream. ASCII only -- no
; accents; see rendering-and-attributes.
MiTexto: db "SCORE",0
```

`puntuacion.asm`'s `ImprimirEtiquetas` / `ImprimirMarcador` (`:95`, `:107`) already do exactly this;
copy from them rather than from scratch.

Column 27 matters as much as the pushes: `comprobar` treats *any* non-zero attribute byte as solid,
so text printed inside columns 7-24 becomes collidable geometry.

## Traps a first edit usually hits

- Moving `call CalcularAtributo` after the `ld b,(ix)` / `ld c,(ix+1)` pair in `piezas.asm:49-51`,
  `test_col.asm:11-14`, `clear.asm:11-13`. The order is deliberate — `CalcularAtributo` destroys `BC`.
- Making `comprobar` preserve `AF` "for consistency". It returns its result in `A` (`test_col.asm:43,47`).
- Adding a score/level display without saving `IX`, which silently swaps the falling piece.
- Wrapping `GIRAR` in a `comprobar` check. It validates, kicks and commits by itself
  (`juego.asm:90`). → `piece-rotation`
- Adding a routine that points `IY` somewhere without a `di`/`ei` bracket around that window, or
  putting the `ei` before the `pop iy`. → `interrupts-and-timing`
- Declaring a variable outside `variables.asm`, or putting `variables.asm` anywhere but last in the
  `INCLUDE` list. → `memory-map` §6
- Editing `L30.3 - printat.asm` or `L35 - Tetris_3D.asm`. They are course-supplied and known good.
