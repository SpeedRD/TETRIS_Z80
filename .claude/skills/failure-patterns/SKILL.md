---
name: failure-patterns
description: Use when about to change clear.asm, juego.asm, pantallas.asm or piezas.asm; when code looks obviously wrong and you need to know whether it was already deliberately fixed; when you want to check whether an idea has already been tried; or when you need an older version of a file recovered from a committed .lst listing or from the school-submission tag.
---

# What was already tried, and what it proves

**There are now three commits.** `git log` is the first place to look:

| Commit | What it is |
|---|---|
| `0a2377e` (tag `school-submission`) | The original hand-in, as pulled from Canvas. The only state the rest of this file calls "old" |
| `4d9e1fb` | The fix pass: gameplay loop, line clear, scoring, level, preview, gravity, tests, this skill library |
| `4809651` | Leftover files |

`git show 0a2377e:caida.asm` recovers either deleted file in full. Everything in §3 below describes
the state at `0a2377e` and what became of it, so **§3 is history, not a description of the tree**.

Before those commits existed there was one commit and no history at all, and the only record was
five committed `.lst` files (assembler listings). A sjasmplus listing **embeds the source text it
was built from**, so each one is a snapshot of a version older still — older than
`school-submission`. That layer is unchanged and still the only window onto it.

Spanish used below: `caida` = fall, `juego` = game, `piezas` = pieces, `pantallas` = screens,
`giro` = rotation, `movimiento`/`desplazar` = movement / to displace, `comprobar` = to check,
`Medio` = middle (the piece's column), `Pantalla_Final` = final screen, `MensajeReiniciar` =
restart message. `clear` is already English.

## 1. Recover an older version of a file (reusable procedure)

Each listing line is `<line#> <address> <bytes> <source>` with a **fixed 24-character prefix**,
so `cut -c25-` gives back the original source exactly.

1. Pick a file that has a listing: only `caida`, `clear`, `juego`, `pantallas`, `piezas`.
2. Strip listing headers, error and warning lines, then cut the prefix.
3. Diff against `git show 0a2377e:"$F.asm"` (the deleted files exist only there) or the current
   `.asm`. Use `-bB` — the old files used CRLF and different blank lines.

```bash
cd /Users/ed/Projects/TETRIS_Z80
F=juego        # or caida, clear, pantallas, piezas
grep -vE '^#|error:|warning\[' "$F.lst" | cut -c25- | tr -d '\r' > /tmp/"$F".old.asm
git show 0a2377e:"$F.asm" > /tmp/"$F".submission.asm
diff -bB /tmp/"$F".old.asm /tmp/"$F".submission.asm
```

Write only outside the repo. **Use this to answer "has this been tried?" yourself** instead of
trusting §3. For everything at or after `school-submission`, use `git log -p` — that is now the
better tool. The files with no listing have no pre-submission history at all: `main.asm`,
`titulo.asm`, `L30.3 - printat.asm`, `L35 - Tetris_3D.asm`, `tableroJuego.asm`,
`tetromino_next.asm`, `test_col.asm`, `giro.asm`, `movimiento.asm`, and everything created by the
fix pass (`entrada.asm`, `lineas.asm`, `puntuacion.asm`, `variables.asm`).

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

Each entry says what the pre-submission listing shows, what `school-submission` did with it, and —
tagged **STILL LIVE** or **RESOLVED** — whether it is something you can still hit today.

### 3.1 `clear.asm` rewritten — GENUINE FIX, do not revert — **STILL LIVE**

Old `borrar_tetromino` decided whether to erase by reading the **screen** byte
(`clear.lst:18-20`: `ld a, (hl)` / `cp 0` / `jr z, haynegro`). Current version reads the
**pattern** byte (`clear.asm:21-24`: `ld a, (iy)` / `or a` / `jr z, siguiente_columna`) and
resets the column counter per row (`clear.asm:18-19`, label `loop_filas`).
Testing the screen byte is wrong because it erases wherever the screen happens to be non-empty
instead of where this piece's cells actually are — it erases settled blocks and misses its own.

The only later change to this file is the `di`/`ei` bracket around the `IY` window (`:9`, `:44`);
the erase logic is untouched. Leave both alone.

### 3.2 `pantallas.asm` — `CalcularAtributo` rewritten — GENUINE FIX, do not revert — **STILL LIVE**

Old version built the row into `H` with `and $F8` then three `rlca` (`pantallas.lst:49`), which
rotates rather than shifts and yields a garbage address. Current version uses `SRL H` ×3 and
`SLA A` ×5 (`pantallas.asm:73-76`). Every draw, erase and collision goes through this routine.
Same diff: start-menu row 13 → 11 plus an explicit `LD c, 2` (`pantallas.asm:13-14`), and
`MensajeIniciar` lost its leading `¿` (`pantallas.lst:104`) — at the time, the UTF-8 glyph bug
worked around one string at a time. **RESOLVED for the rest:** `MensajeReiniciar` and
`MensajeGameOver` are now ASCII too (`pantallas.asm:116-121`, with the reason in the comment above
them), so the whole tree is clean. See `rendering-and-attributes` §7.

### 3.3 `piezas.asm` rewritten — mixed — **RESOLVED**

Old table: generic `Tetro1`…`Tetro19`, colours `1*8`–`5*8` (`piezas.lst:5,67`). Current table:
semantic `T_0`, `T_L1..4`, `T_J1..4`, `T_T1..4`, `T_I1..2`, `T_Z1..2`, `T_S1..2`, colours
`2*8`–`7*8` (`piezas.asm:5-29`). Same 19 records, same 12-byte format.

- Old L/J were one 8-state group all coloured `3*8`; the rewrite split them into proper L
  (`4*8`) and J (`2*8`). That part was an improvement.
- **`Medio` did not exist in the old table** — this rewrite introduced it, inside the code
  image at `piezas.asm:31`. It has since moved to `variables.asm` with the rest of the mutable
  state (`memory-map` §6); the piece file now holds only read-only data.
- It left Z and S both on `7*8` and newly put **O and I both on `6*8`** (previously `1*8` and
  `2*8`). **Both collisions are now fixed:** I is `1*8` blue (`piezas.asm:22-23`) and S is `3*8`
  magenta (`:28-29`), each with the reason in the comment above it. All seven shapes are distinct;
  do not "tidy" a colour back onto a used value. See `piece-data-and-spawn` §3.

### 3.4 Gravity constant changed — one constant, huge effect — **RESOLVED**

`TIEMPO_BASE` went from `0x88FF` = 35071 (`caida.lst:6`) to `0x11FF` = 4607 (`caida.asm:5`) —
a **7.6× speed-up**, ~260 ms per row down to ~35 ms per row, which is what made the submitted game
unplayably fast. Almost certainly a debug shortcut never changed back.

`caida.asm` no longer exists. Gravity is a frame counter — `contador_frames` against
`FRAMES_POR_FILA`, fed from the `FRAMES_POR_NIVEL` table — so there is no constant of this kind to
get wrong any more. **Do not reintroduce a busy-wait:** its wall-clock speed varies per emulator.
`interrupts-and-timing` §4 owns this.

### 3.5 Input moved to the wrong side of the collision check — WORST REGRESSION — **RESOLVED**

```
PRE-SUBMISSION (juego.lst:36-40)   SUBMITTED (juego.asm:29, :41, :44)
    call MOVER      ; input            call comprobar   ; validated first
    call GIRAR      ; rotation         ...
    call comprobar  ; validated        call GIRAR       ; rotation applied AFTER
                                       call MOVER       ; input applied AFTER
```

Neither was correct — the older one still tested against a stale `C` — but the submitted ordering
validated a position the piece would never occupy, which is what let pieces walk through walls and
eat the border. The loop was rebuilt around the opposite rule: **test the exact position you are
about to draw, with the exact `IX` you are about to draw** (`juego.asm:3-6`).

**This remains the easiest way to break the file.** Any edit that moves a candidate's commit after
its `comprobar`, or reads input after the check, undoes the whole fix. `game-loop-and-collision`
owns the structure.

### 3.6 Game-over check added without following its exit — **RESOLVED**

Pre-submission code computed the startup collision and threw it away — `CALL comprobar` / `or a`
with no branch (`juego.lst:14-15`). The submission added `jr nz, end`, but `end:` was a plain `ret`
and `main.asm` had no terminator after `CALL iniciar`, so that `ret` fell into the first byte of
`titulo.asm` — the title screen reappeared at random. The check also ran with `B = 255`, reading
RAM outside the screen entirely.

Now: both game-over tests run at the real spawn position, row 0 (`juego.asm:28-30`, `:112-114`),
`fin_partida` is `JP Pantalla_Final`, and `main.asm:27` carries a `jr` terminator. **The lesson
stands: when you add an exit path, follow it to where control actually lands.**

### 3.7 Game-over screen written, never wired up — **RESOLVED**

`Pantalla_Final` (`pantallas.asm:27-53`) does not appear anywhere in `pantallas.lst` — it was
written after that snapshot and then never called; the label occurred once, at its own definition.
A whole feature, missing the one line that would invoke it.

It is now reached by `JP` from `juego.asm:121`, and the two defects it carried are fixed: it loaded
`MensajeGameOver` twice (`:41` now loads `MensajeReiniciar`), and it restarted with
`call inicializar`, which leaked 2 bytes of stack per game — now `jp inicializar` (`:53`), with
`inicializar` re-setting `SP` itself (`main.asm:15`). Both message strings already existed in the
old snapshot (`pantallas.lst:119,126`).

### 3.8 Debug traps left in the image — **RESOLVED**

`fin_dibujar_tablero` in `tableroJuego.asm` and `fin_selec_pieza` in `tetromino_next.asm` were
`jr $` infinite loops placed **after** the routine's `ret`, so they were unreachable — breakpoints
someone used to freeze execution and inspect the screen, then abandoned rather than deleted. Both
went with the rewrites of those files. **Recognise the idiom anyway**; the remaining self-branches
(`main.asm:27`, `pantallas.asm:67`) are deliberate, and `tests/unit.py` uses one as a return trap.

### 3.9 The two input files are copy-paste clones — **RESOLVED**

`giro.asm` and `movimiento.asm` shared the same dead `POP BC` / `RET` pair after an unconditional
`JR`, and both header comments named `desplazar.asm`, a file that never existed in the tree — a
rename followed by a clone, comments never updated. `movimiento.asm` is deleted and `giro.asm` was
rewritten, so there is no clone pair left. The general lesson survives: **when two files in this
tree look alike, check whether one was copied from the other before fixing only one.**

### 3.10 A second title screen exists and is used by nothing — **STILL LIVE**

`TETRIS2.scr` is never `INCBIN`-ed; only `TETRIS.scr` is loaded (`titulo.asm:33`). Do not wire
it up expecting it to be needed somewhere.

## 4. Do not repeat these

1. Do not restore the screen-byte test in `borrar_tetromino` (§3.1).
2. Do not restore the `and $F8` / `rlca` form of `CalcularAtributo` (§3.2).
3. Do not commit a candidate position before validating it, or apply input after `comprobar` —
   this is the regression the whole loop was rebuilt to remove (§3.5).
4. Do not add an exit path without following where its `ret`/`jr` actually lands (§3.6).
5. Do not turn `JP Pantalla_Final` or `jp inicializar` back into a `CALL` (§3.7).
6. Do not reintroduce a busy-wait delay in place of the frame counter (§3.4).
7. Do not put two shapes back on the same colour (§3.3).
8. Do not treat `jr $` after a `ret` as live code — and do not delete the two that are live (§3.8).
9. Do not assemble a single `.asm` standalone to "check" it — only `main.asm` builds (§2).
10. Do not trust addresses or opcode bytes printed in the five stale listings (§2).
11. Do not put a non-ASCII character in a `db` string; the encoding bug is real (§3.2).
12. Do not remove a `di`/`ei` bracket around an `IY` window because it "looks unnecessary"
    (`interrupts-and-timing` §1).
13. Do not "fix" `T_0`'s self-referencing rotation pointer (`piezas.asm:5`, `DW T_0, T_0`) into
    pointing anywhere else. The O-piece has 4-fold symmetry, so both rotation directions
    correctly loop back to itself — `IX` not changing on a Q/W press is the right outcome for
    this one piece, not a missed rotation (`piece-rotation` §2, §"Common mistakes").

## 5. What the history does not tell you

Five features had **no** trace in any listing — they were never attempted before the fix pass, so
there was no dead end to avoid. All five were built from scratch, and the file that owns each one is
now the authority on it:

- **Line clearing and row shifting** — `lineas.asm` (`line-clear`).
- **Scoring and level progression** — `puntuacion.asm` (`scoring-and-level`). The old
  `NIVEL_ACTUAL` at `$7002` was declared and never written, in every version.
- **Rotation kicks and anchoring** — `giro.asm` was rewritten and has no listing at all
  (`piece-rotation`).
- **Non-blocking input** — `entrada.asm` (`game-loop-and-collision` §7).
- **Next-piece preview** — `tetromino_next.asm`, which had been named for it since the start
  without containing it (`piece-data-and-spawn` §6).

Because they are new, `git log -p` on commit `4d9e1fb` is the history for all of them, and the
tests in `tests/` are the record of what each was verified to do.

If §3 has no entry for the file you are editing, the pre-submission history has nothing to say —
stop looking and go to the owning skill listed in `project-orientation`.
