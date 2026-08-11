---
name: failure-patterns
description: Use when about to change caida.asm, clear.asm, juego.asm, pantallas.asm or piezas.asm; when code looks obviously wrong and you need to know whether it was already deliberately fixed; when you want to check whether an idea has already been tried; or when you need an older version of a file recovered from a committed .lst listing.
---

# What was already tried, and what it proves

Git has one commit and no history. The only real history is five committed `.lst` files
(assembler listings). A sjasmplus listing **embeds the source text it was built from**, so each
one is a snapshot of an older version of that file. Read this before changing those files.

Spanish used below: `caida` = fall, `juego` = game, `piezas` = pieces, `pantallas` = screens,
`giro` = rotation, `movimiento`/`desplazar` = movement / to displace, `comprobar` = to check,
`Medio` = middle (the piece's column), `Pantalla_Final` = final screen, `MensajeReiniciar` =
restart message. `clear` is already English.

## 1. Recover an older version of a file (reusable procedure)

Each listing line is `<line#> <address> <bytes> <source>` with a **fixed 24-character prefix**,
so `cut -c25-` gives back the original source exactly.

1. Pick a file that has history: only `caida`, `clear`, `juego`, `pantallas`, `piezas`.
2. Strip listing headers, error and warning lines, then cut the prefix.
3. Diff against the current `.asm`. Use `-bB` — the old files used CRLF and different blank lines.

```bash
cd /Users/ed/Projects/TETRIS_Z80
F=juego        # or caida, clear, pantallas, piezas
grep -vE '^#|error:|warning\[' "$F.lst" | cut -c25- | tr -d '\r' > /tmp/"$F".old.asm
diff -bB /tmp/"$F".old.asm "$F.asm"
```

Write only outside the repo. **Use this to answer "has this been tried?" yourself** instead of
trusting §3. The other nine source files have **no** listing and no recoverable history at all:
`main.asm`, `titulo.asm`, `L30.3 - printat.asm`, `L35 - Tetris_3D.asm`, `tableroJuego.asm`,
`tetromino_next.asm`, `test_col.asm`, `giro.asm`, `movimiento.asm`.

## 2. What those listings are NOT

- **Four of the five builds failed** — `clear/juego/pantallas/piezas.lst` are full of
  `error: Label not found:` because each file was assembled without the rest of the tree
  (`juego.lst:5,10,13`). Only `caida.lst` is clean, because `caida.asm` has no external
  references. The embedded **source** is still valid history; the **addresses and opcode bytes
  are meaningless** — every unresolved `CALL` assembled as `CD 00 00`.
- **Assembling one `.asm` standalone is not a way to check it.** Only `main.asm` assembles. See
  `build-and-verify`.
- **These are two separate snapshots, not one timeline**: `caida/clear/juego.lst` came from one
  machine path, `pantallas/piezas.lst` from another. Do not assume all five share a moment.
- `main.lst` / `main.sld` are the **current** build's output, not history.

## 3. Changes already made

### 3.1 `clear.asm` rewritten — GENUINE FIX, do not revert

Old `borrar_tetromino` decided whether to erase by reading the **screen** byte
(`clear.lst:18-20`: `ld a, (hl)` / `cp 0` / `jr z, haynegro`). Current version reads the
**pattern** byte (`clear.asm:20-25`: `ld a, (iy)` / `or a` / `jr z, siguiente_columna`) and
resets the column counter per row (`clear.asm:17-18`, label `loop_filas`).
Testing the screen byte is wrong because it erases wherever the screen happens to be non-empty
instead of where this piece's cells actually are — it erases settled blocks and misses its own.

### 3.2 `pantallas.asm` — `CalcularAtributo` rewritten — GENUINE FIX, do not revert

Old version built the row into `H` with `and $F8` then three `rlca` (`pantallas.lst:49`), which
rotates rather than shifts and yields a garbage address. Current version uses `SRL H` ×3 and
`SLA A` ×5 (`pantallas.asm:71-74`). Every draw, erase and collision goes through this routine.
Same diff: start-menu row 13 → 11 plus an explicit `LD c, 2` (`pantallas.asm:13-14`), and
`MensajeIniciar` lost its leading `¿` (`pantallas.lst:104` vs `pantallas.asm:111`) — the UTF-8
glyph bug worked around per-string, not fixed. See `rendering-and-attributes`.

### 3.3 `piezas.asm` rewritten — mixed

Old table: generic `Tetro1`…`Tetro19`, colours `1*8`–`5*8` (`piezas.lst:5,67`). Current table:
semantic `T_0`, `T_L1..4`, `T_J1..4`, `T_T1..4`, `T_I1..2`, `T_Z1..2`, `T_S1..2`, colours
`2*8`–`7*8` (`piezas.asm:5-29`). Same 19 records, same 12-byte format.

- Old L/J were one 8-state group all coloured `3*8`; the rewrite split them into proper L
  (`4*8`) and J (`2*8`). That part was an improvement.
- **`Medio` did not exist in the old table** — this rewrite introduced it, inside the code
  image at `piezas.asm:31`.
- It left Z and S both on `7*8` and newly put **O and I both on `6*8`** (previously `1*8` and
  `2*8`). Two colour collisions today, not one. See `piece-data-and-spawn`.

### 3.4 Gravity constant changed — one constant, huge effect

`TIEMPO_BASE` went from `0x88FF` = 35071 (`caida.lst:6`) to `0x11FF` = 4607 (`caida.asm:5`) —
a **7.6× speed-up**, ~260 ms per row down to ~35 ms per row. That is why the game is unplayably
fast. This is a one-line edit with a large gameplay effect. For the T-state derivation see
`interrupts-and-timing`; for where the value should come from (a level variable) see
`scoring-and-level`.

### 3.5 Input moved to the wrong side of the collision check — WORST REGRESSION

```
OLD (juego.lst:36-40)          CURRENT (juego.asm:29, :41, :44)
    call MOVER      ; input        call comprobar   ; validated first  (line 29)
    call GIRAR      ; rotation     ...
    call comprobar  ; validated    call GIRAR       ; rotation applied (line 41)
                                   call MOVER       ; input applied    (line 44)
```

The old ordering was **not** fully correct either — it still tested against a stale `C`. But the
current ordering validates a position the piece will never occupy: both the move and the
rotation land after the only check. **Any edit to the loop must keep input application before
validation.** `game-loop-and-collision` owns the correct structure.

### 3.6 Game-over check added without following its exit

Old code computed the startup collision and threw it away — `CALL comprobar` / `or a` with no
branch (`juego.lst:14-15`). Current code added `jr nz, end` (`juego.asm:12`). But `end:` is just
`ret` (`juego.asm:47-48`), and `main.asm:14` has no terminator after `CALL iniciar`, so that
`ret` falls into the first byte of `titulo.asm` — the title screen. When adding an exit path
here, follow it to where control actually lands. See `game-loop-and-collision`.

### 3.7 Game-over screen written, never wired up

`Pantalla_Final` (`pantallas.asm:27-53`) does not appear anywhere in `pantallas.lst` — it was
added after that snapshot, and **nothing calls it**; the label occurs once, at its own
definition. `MensajeReiniciar` (`pantallas.asm:113`) is likewise referenced nowhere. Wiring this
up is a `call`, not a new feature. Two defects to fix while wiring it:

- It loads `MensajeGameOver` twice (`pantallas.asm:34` and `:41`); line 41 should be
  `MensajeReiniciar`.
- It restarts with `call inicializar` (`pantallas.asm:53`) instead of `jp`, so every restart
  leaks 2 bytes of stack.

Both message strings already existed in the old snapshot (`pantallas.lst:119,126`); only the
routine is new.

### 3.8 Debug traps left in the image

`tableroJuego.asm:45` `fin_dibujar_tablero: jr fin_dibujar_tablero` and `tetromino_next.asm:28`
`fin_selec_pieza: jr fin_selec_pieza` are `jr $` infinite loops placed **after** the routine's
`ret`, so they are unreachable. Recognise the idiom; do not read them as live code or "fix"
them. Remove only as a deliberate cleanup.

### 3.9 The two input files are copy-paste clones

`giro.asm` and `movimiento.asm` share the same dead `POP BC` / `RET` pair after an
unconditional `JR`: `giro.asm:21-22` and `:29-30`, `movimiento.asm:24-25` and `:32-33`. Their
header comments name `desplazar.asm` (`giro.asm:3`, `movimiento.asm:3`), a file that does not
exist in the tree. These two files drift — **fix both or neither**, and do not trust the comments.

### 3.10 A second title screen exists and is used by nothing

`TETRIS2.scr` is never `INCBIN`-ed; only `TETRIS.scr` is loaded (`titulo.asm:33`). Do not wire
it up expecting it to be needed somewhere.

## 4. Do not repeat these

1. Do not restore the screen-byte test in `borrar_tetromino` (§3.1).
2. Do not restore the `and $F8` / `rlca` form of `CalcularAtributo` (§3.2).
3. Do not move `MOVER`/`GIRAR` after `comprobar` — input applies before validation (§3.5).
4. Do not add an exit path without following where its `ret`/`jr` actually lands (§3.6).
5. Do not rewrite a game-over screen — `Pantalla_Final` exists; wire it up (§3.7).
6. Do not treat `jr $` after a `ret` as live code (§3.8).
7. Do not patch only one of `giro.asm` / `movimiento.asm` (§3.9).
8. Do not assemble a single `.asm` standalone to "check" it — only `main.asm` builds (§2).
9. Do not trust addresses or opcode bytes printed in the five stale listings (§2).
10. Do not fix a garbled message by deleting characters; the encoding bug is real (§3.2).

## 5. What the history does not tell you

The features with the largest gaps were **never attempted**, so there is no dead end to avoid:

- **Line clearing and row shifting** — no code, no listing, no trace (`line-clear`).
- **Scoring and level progression** — `NIVEL_ACTUAL` is declared and never written, in both the
  old and current `caida` (`scoring-and-level`).
- **Rotation kicks and anchoring** — `giro.asm` has no listing at all (`piece-rotation`).

If §3 has no entry for the file you are editing, the history has nothing to say — stop looking
and go to the owning skill listed in `project-orientation`.
