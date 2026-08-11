---
name: project-orientation
description: Use when working in the TETRIS_Z80 ZX Spectrum Z80 assembly repo and the task is not yet scoped to one file — first contact with the codebase, questions like "what does juego.asm do" or "where is the board", unfamiliar Spanish identifiers (Medio, comprobar, seleccionar_pieza, GIRAR), or deciding which specialised skill to load.
---

# TETRIS_Z80 — orientation and router

Load this first. It says what each file is, what the Spanish names mean, and which skill to load next.

## What this is

ZX Spectrum 48K Tetris in Z80 assembly, assembled with **sjasmplus 1.23.1**. One translation unit:
`main.asm` (`ORG $8000`, `main.asm:4`) `INCLUDE`s 13 other `.asm` files (`main.asm:19-31`); the output
is a raw 8903-byte image spanning `$8000-$A2C6`. Today it is a **piece-dropper, not Tetris**: pieces
spawn, fall, move and rotate, but nothing clears lines, nothing scores, and game over never fires.

**Goal: complete the game in place, keeping the existing architecture.** The ZX Spectrum attribute
file at `$5800` *is* the board — a cell is occupied iff its attribute byte is non-zero. The well is
18 columns wide. `B` = piece row, `C` = piece column, `IX` = pointer to the current piece record.
This is not a rewrite.

## Source file map

| File | Spanish → English | Purpose | State |
|---|---|---|---|
| `main.asm` | — | Entry point; sets `SP`, calls title → menu → board → `iniciar`, then INCLUDEs everything | **BROKEN** — no jump after `CALL iniciar` (`main.asm:14`); on return it falls into `InicioDePantalla` at `$800F` |
| `titulo.asm` | "title" | LDIRs `TETRIS.scr` into `$4000`, waits for **Q** | PARTIAL — works; comment at `:22` contradicts the code, dead `ld d,1` at `:24` |
| `pantallas.asm` | "screens" | Start menu, `CalcularAtributo`, keyboard helpers, all message strings | MIXED — menu and `CalcularAtributo` work; `Pantalla_Final` (`:27`) and `MensajeReiniciar` (`:113`) are **DEAD** (defined, never referenced) |
| `L30.3 - printat.asm` | — | Text/print library: `PRINTAT`, `CLEARSCR`, charset | **COURSE-SUPPLIED** (header credits Daniel León, UFV 2020) — treat as stable, do not edit |
| `L35 - Tetris_3D.asm` | — | Fills the pixel file with an 8-byte bevel pattern | **COURSE-SUPPLIED** — treat as stable; leaves `IY` corrupted on exit |
| `tableroJuego.asm` | "game board" | Draws the well: borders at attribute columns 6 and 25, floor at row 22 (`:8,:19,:30`) | WORKING — interior is columns 7-24 = **18 wide**; dead trap at `:45` |
| `juego.asm` | "game" | The main loop: `iniciar`, `ciclo_juego` | **BROKEN** — checks collision against the stale column, labels are inverted, game over unreachable |
| `tetromino_next.asm` | "next tetromino" | `seleccionar_pieza`: picks a random rotation record, returns `B=0, C=15` | PARTIAL, MISNAMED — **there is no next-piece preview**; RNG is biased |
| `piezas.asm` | "pieces" | 19 twelve-byte piece records, the `Medio` variable, `pintar_tetromino` | WORKING — but **two** colour collisions: Z and S both `7*8`, O and I both `6*8` |
| `test_col.asm` | "collision test" | `comprobar`: returns `A=1` on collision, `A=0` clear | WORKING as written, **MISUSED by its only caller** (`juego.asm`) |
| `clear.asm` | (English) | `borrar_tetromino`: erases the piece by writing attribute `0` | WORKING |
| `caida.asm` | "fall" | `Tiempo` busy-wait between drops, level/time constants | **BROKEN** — level scaling is dead arithmetic; `InicializarTiempo` (`:63`) is DEAD |
| `movimiento.asm` | "movement" | `MOVER`: reads J/K, adjusts `Medio` by ±1 | PARTIAL — no bounds check, no collision check, blocks until key release |
| `giro.asm` | "rotation" | `GIRAR`: reads Q/W, follows the piece record's rotation pointer | PARTIAL — no validation, no wall kick, blocks until key release |

Data blobs: `TETRIS.scr` (`titulo.asm:33`) and `charset.bin` (`L30.3 - printat.asm:162`), both INCBIN;
`TETRIS2.scr` is referenced by nothing. Of the committed `*.bin/*.lst/*.sld` build output only
`main.lst` matches the current sources — the per-file ones are stale, see `failure-patterns`.

## Spanish → English glossary

| Identifier | Literal | What it is |
|---|---|---|
| `iniciar` | "to start" | `juego.asm:3` — spawns a piece and enters the loop. Also the fall/land re-entry point |
| `inicializar` | "to initialise" | `main.asm:9` — restart target (menu → board → `iniciar`) |
| `ciclo_juego` | "game cycle" | `juego.asm:14` — top of the drop loop |
| `siguiente_juego` | "next game" | `juego.asm:22` — advance one row and re-test |
| `cambiar_tetromino` | "change tetromino" | `juego.asm:39` — **misleading, see below** |
| `comprobar` | "to check" | `test_col.asm:3` — collision test; result in `A`, does **not** preserve `AF` |
| `pintar_tetromino` | "paint tetromino" | `piezas.asm:34` — draw the piece at `B`,`C` |
| `borrar_tetromino` | "erase tetromino" | `clear.asm:3` — erase the piece at `B`,`C` |
| `seleccionar_pieza` | "select piece" | `tetromino_next.asm:5` — random piece into `IX` |
| `dibujar_tablero` | "draw the board" | `tableroJuego.asm:4` — draw well borders and floor |
| `GIRAR` | "to rotate" | `giro.asm:1` — rotation input handler |
| `MOVER` | "to move" | `movimiento.asm:1` — horizontal input handler |
| `Tiempo` | "time" | `caida.asm:14` — busy-wait delay (the gravity tick) |
| `CalcularAtributo` | "calculate attribute" | `pantallas.asm:67` — `B`,`C` → `HL` = attribute address. **Clobbers `BC`** (`:77`) |
| `EsperarTecla` / `LeerTecla` / `SoltarTecla` | "wait for key" / "read key" / "release key" | `pantallas.asm:83,89,100` — blocking keyboard helpers |
| `Pantalla_Ini` | "screen, start" | `pantallas.asm:3` — start menu, waits for S or N |
| `Pantalla_Final` | "final screen" | `pantallas.asm:27` — game-over screen, **DEAD** |
| `FinDelJuego` | "end of the game" | `pantallas.asm:56` — prints thanks, then `fin: JR fin` (hard hang, the only real exit) |
| `InicioDePantalla` | "start of screen" | `titulo.asm:3` — title screen |
| `PintarPantalla` | "paint screen" | `titulo.asm:8` — blits 6912 bytes to `$4000`, then falls into the key wait |
| `Medio` | "middle" | `piezas.asm:31` (`$A16F`, `DB 14`) — the *shadow* column written by `MOVER` |
| `NIVEL_ACTUAL` | "current level" | `caida.asm:11` — `$7002`, declared and never written |
| `TIEMPO_CAIDA` / `TIEMPO_BASE` / `TIEMPO_MINIMO` / `REDUCCION_TIEMPO` | "fall time" / "base time" / "minimum time" / "time reduction" | `caida.asm:5-11` — delay constants |
| `longitud_pieza` | "piece length" | `tetromino_next.asm:3` — `T_L1 - T_0` = **12** bytes per record |
| `MensajeIniciar` / `MensajeReiniciar` / `MensajeGameOver` | "start message" / "restart message" / "game-over message" | `pantallas.asm:111` / `:113` (DEAD) / `:114` — zero-terminated strings |
| `fin`, `end` | "end", "end" | `pantallas.asm:65` (infinite loop) and `juego.asm:47` (a plain `ret`) |

Comment vocabulary: *fila* row, *columna* column, *pantalla* screen, *tecla* key, *pulsada* pressed,
*soltar* release, *esperar* wait, *pieza* piece, *tablero* board, *borde* border, *izquierda/derecha*
left/right, *siguiente* next, *dirección* address, *guardar* save, *borrar* erase, *pintar* paint,
*aleatorio* random, *nivel* level, *caída* fall, *partida* game session.

### Two label names in `juego.asm` mean the opposite of what they do

`comprobar` returns `A=0` for **no collision**. So at `juego.asm:32` (`jr z, cambiar_tetromino`):

- `cambiar_tetromino` ("change tetromino", `:39`) is the **keep falling** path — rotate, draw, delay, move.
- The fall-through at `:34-37` (`dec b … jr iniciar`) is the **land and spawn a new piece** path.

Read the flag, not the name. Details in `game-loop-and-collision`.

## Which skill to load

| Task | Load |
|---|---|
| "make rotation work", "pieces rotate into the wall" | `piece-rotation`, `game-loop-and-collision` |
| "pieces go through walls", "collision is wrong" | `game-loop-and-collision`, `register-protocol` |
| "add line clearing", "full rows don't disappear" | `line-clear`, `rendering-and-attributes` |
| "add a score", "show the level" | `scoring-and-level`, `rendering-and-attributes` |
| "the game restarts by itself", "game over never happens" | `game-loop-and-collision`, `failure-patterns` |
| "gravity is too fast/slow", "it freezes" | `interrupts-and-timing` |
| "add soft drop", "add a down key" | `game-loop-and-collision` (it owns input and the loop). No down key is read today; `memory-map`'s port table shows which half-row a new one would come from |
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
   clobbers `BC` moves the piece. `CalcularAtributo` clobbers `BC` (`pantallas.asm:77`). → `register-protocol`
3. **`Medio` is not the live column — `C` is.** `MOVER` writes only `Medio`; the loop copies it into
   `C` one step later. → `game-loop-and-collision`
4. **Include order in `main.asm:19-31` is load-bearing** (forward-referenced `EQU`, address adjacency).
   Append new files at the end; do not reorder. → `assembler-conventions`
5. **The build must stay at 0 errors, 0 warnings** (currently 852 lines, clean). → `build-and-verify`
6. **There is no test suite.** Every change is verified by a human watching the emulator screen.
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
; Put the string with the other strings (pantallas.asm:110-114), never in the
; instruction stream. ASCII only -- no accents; see rendering-and-attributes.
MiTexto: db "SCORE",0
```

Column 27 matters as much as the pushes: `comprobar` treats *any* non-zero attribute byte as solid,
so text printed inside columns 7-24 becomes collidable geometry.

## Traps a first edit usually hits

- Moving `call CalcularAtributo` after the `ld b,(ix)` / `ld c,(ix+1)` pair in `piezas.asm:41-43`,
  `test_col.asm:10-13`, `clear.asm:10-12`. The order is deliberate — `CalcularAtributo` destroys `BC`.
- Making `comprobar` preserve `AF` "for consistency". It returns its result in `A` (`test_col.asm:42,46`).
- Trusting the `juego.asm` label names instead of the flag (see above).
- Adding a score/level display without saving `IX`, which silently swaps the falling piece.
- Assuming an interrupt or frame sync exists. Nothing sets **any** interrupt state anywhere in the
  tree — no `DI`, no `EI`, no `IM 0/1/2`, no `HALT`, no `RETI`/`RETN`. → `interrupts-and-timing`
- Editing `L30.3 - printat.asm` or `L35 - Tetris_3D.asm`. They are course-supplied and known good.
