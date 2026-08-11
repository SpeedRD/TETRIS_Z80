---
name: build-and-verify
description: Use when building this project, running it in an emulator, checking that a change assembles, deciding whether a change broke the game, interpreting sjasmplus output, dealing with main.lst/main.sld/main.bin churn, or setting up DeZog and ZEsarUX.
---

# Build and verify

There **is** an automated suite now — `tests/`, §10 — driving ZEsarUX over its remote debug
protocol. It covers every routine's contract and board-level outcomes, and it is the first
thing to run after any change.

It still cannot see *when within a frame* a write lands, so tearing, flicker and "does this
feel right" remain human-only. **§6 is still the deliverable for anything visual.**

## 1. Build

Run from the repo root (`/Users/ed/Projects/TETRIS_Z80`):

```bash
cd /Users/ed/Projects/TETRIS_Z80 && sjasmplus --fullpath --raw=main.bin --lst=main.lst --sld=main.sld main.asm
```

Only `main.asm` is assembled; it `INCLUDE`s the other 13 `.asm` files (`main.asm:19-31`).
Success looks like:

```
Pass 1 complete (0 errors)
Pass 2 complete (0 errors)
include data: name=TETRIS.scr (6912 bytes) Offset=0  Len=6912
include data: name=charset.bin (768 bytes) Offset=0  Len=768
Pass 3 complete
Errors: 0, warnings: 0, compiled: 852 lines, work time: 0.007 seconds
```

Success criteria: **0 errors and 0 warnings.** The two `include data:` lines are normal —
they are `TETRIS.scr` (title screen) and `charset.bin` (font) being embedded.

**sjasmplus exits 0 even with warnings.** Read the last line; do not trust the exit code.
Baseline binary is **8903 bytes**. For what the directives mean, see `assembler-conventions`.

### The VS Code build task — fixed, was silently emitting no binary

`.vscode/tasks.json:8` now includes `--raw=main.bin`, so Cmd+Shift+B and F5 build the current
source. Keep it that way.

Why it matters: `main.asm:3` sets `DEVICE ZXSPECTRUM48` and the source has no
`SAVEBIN`/`SAVESNA`, so without `--raw` sjasmplus emits **no binary at all** — it refreshes
`main.lst` and `main.sld`, reports `Errors: 0, warnings: 0`, and leaves `main.bin` untouched.
The build looks perfect and you debug the previous binary. Verified by deleting `main.bin` and
running the old argument list: no file is produced.

## 2. Byte-identical regression check

The cheapest real test here. Snapshot a known-good binary before touching anything:

```bash
mkdir -p /tmp/tetris-z80
cd /Users/ed/Projects/TETRIS_Z80 && sjasmplus --fullpath --raw=/tmp/tetris-z80/baseline.bin --lst=/tmp/tetris-z80/baseline.lst --sld=/tmp/tetris-z80/baseline.sld main.asm
# ...make your change, then rebuild and compare:
cd /Users/ed/Projects/TETRIS_Z80 && sjasmplus --fullpath --raw=main.bin --lst=main.lst --sld=main.sld main.asm
cmp main.bin /tmp/tetris-z80/baseline.bin && echo IDENTICAL || echo DIFFERENT
```

| Result | Meaning |
|---|---|
| IDENTICAL after an intended refactor | Good — you changed no behaviour. |
| DIFFERENT after an intended refactor | You changed behaviour. Investigate before proceeding. |
| IDENTICAL after an intended feature change | Your edit did not take effect. Wrong file, or unreachable code. |
| DIFFERENT after an intended feature change | Expected. Proves nothing about correctness — go to §6. |

This proves you did not accidentally change unrelated code. It proves **nothing** about
gameplay. Redirect scratch builds with all three of `--raw`, `--lst`, `--sld`, or they land in
the repo. `cmp -l` instead of `cmp` lists every differing offset.

## 3. Every build dirties the working tree

`main.bin`, `main.lst` and `main.sld` are committed build products and there is **no
`.gitignore`**, so they show as modified after every build. Expected — do not "clean it up".
To see whether *source* changed:

```bash
cd /Users/ed/Projects/TETRIS_Z80 && git status --porcelain -- '*.asm'
```

Empty output means you changed no source. Keep `main.lst` current — it is the address/opcode
listing that `memory-map`, `failure-patterns` and other skills cite.

## 4. Run under DeZog + ZEsarUX

1. Launch ZEsarUX: `open /Applications/ZEsarUX.app` (it is not on `PATH`).
2. Enable ZRCP. ZEsarUX menu (**F5** opens it): **Settings → Debug → ZRCP Remote protocol →
   Enabled**, **ZRCP port = 10000**. All that matters is that it listens on `localhost:10000`.
   Or: `/Applications/ZEsarUX.app/Contents/MacOS/zesarux --enable-remoteprotocol --remoteprotocol-port 10000`
3. Verify it is listening: `nc -z localhost 10000 && echo LISTENING`
4. Build with the §1 command first (the launch config's `preLaunchTask` produces no binary).
5. In VS Code, Run and Debug → **Tetris (ZEsarUX)** → F5 (`.vscode/launch.json:7`); it loads
   `main.bin` at `0x8000` (`:15`) and starts at `0x8000` (`:17`), `startAutomatically: true`.
6. It worked if ZEsarUX shows the TETRIS title screen and the debug toolbar is active.

DeZog reads symbols from `main.sld` (`launch.json:12`), so labels and source-level stepping
work — **only if `main.sld` matches the current source.** Rebuild before every run.

## 5. Optional: a self-contained snapshot

The source has no `SAVESNA`, so the binary can only be loaded by a debugger. To make a file
any emulator can open directly, append one line to the end of `main.asm`:

```asm
    SAVESNA "main.sna", $8000
```

**`main.asm` ends with no trailing newline.** A blind append lands this on the same line as
`INCLUDE "giro.asm"`; sjasmplus honours the `INCLUDE` and **silently ignores the rest** — 0
errors, 0 warnings, no `.sna` written. Add the newline first, then the line. Same hazard for
any `INCLUDE` you append; see `assembler-conventions`.

Verified: 49179-byte 48K snapshot, 0 errors, 0 warnings. A snapshot captures the interrupt enable
state and `IM` mode, which matters here (`interrupts-and-timing`). Optional — §4 is supported.

## 5b. Automated suites — `tests/`, run these first

`tests/` is the home for automated verification. There is no other convention in this repo —
source is flat `.asm` in the root, so a `tests/` directory was chosen and this section is the
record of that decision.

```bash
python3 tests/run_all.py              # rebuild + every suite
python3 tests/run_all.py test_giro    # one suite
```

`run_all.py` rebuilds with the §1 command and **refuses to run if the build is not
`Errors: 0, warnings: 0`** — it reads the last line, not the exit code (§1).

| Suite | Covers |
|---|---|
| `test_entrada.py` | `leer_teclas` edge detection, `en_rango` boundaries |
| `test_giro.py` | every shape × state × column × direction: cycles close, no rotation escapes columns 7-24, blocked rotation is atomic, `GIRAR` never draws |
| `test_lineas.py` | 1/2/4-row and full-board clears, non-adjacent rows, border survival |
| `test_puntuacion.py` | points, BCD carry, line count, level-up, level cap, speed table |
| `test_spawn.py` | shape distribution, LFSR health, preview handoff |
| `checklist6.py` | §6 end to end, across several games including game-over→restart |

Two properties make this possible and are worth knowing before writing another test: the
attribute file at `$5800` **is** the board, so 768 bytes is the whole game state; and
`set-ui-io-ports` sets the keyboard matrix directly, which is exactly what the game polls.
`tests/README.md` documents the harness pitfalls — chiefly that a fired ZEsarUX breakpoint
opens its debug menu, which then blocks `enter-cpu-step` and requires restarting the emulator.

**These suites do not replace §6.** They cannot observe tearing or flicker.

## 6. Manual verification checklist

Run through this in order after **every** change. Key bindings verified against source.

1. Title screen: the TETRIS picture fills the screen. (`titulo.asm:4-14`)
2. Press **Q** — the title screen is dismissed. (`titulo.asm:20-23`, port `$FBFE` bit 0)
3. Start menu: yellow `Tipo de Juego: Tipo-A`, green `Empezamos una partida (S/N)?`, flashing
   green cursor. (`pantallas.asm:3-22`)
4. Press **N** — screen clears to cyan `Gracias por jugar` ("thanks for playing"), program stops
   there. (`pantallas.asm:56-65`)
5. Restart and press **S** — the well is drawn: yellow columns down both sides (screen columns
   6 and 25, rows 0-21) and a yellow floor along row 22, over a 3D background pattern.
   (`tableroJuego.asm:8-39`; attribute `6*8+7` = yellow paper)
6. A coloured piece appears near the top of the well and descends on its own.
7. **J** moves it left, **K** moves it right. (`movimiento.asm:10-15`, port `$BFFE`)
8. **Q** rotates it one way, **W** the other. (`giro.asm:9-14`, port `$FBFE`)
9. The piece stops on the floor or on a settled piece, and a new piece appears at the top.
10. Repeat until several pieces have settled: the well's yellow borders and floor are still
    intact and unbroken.

**All ten items pass today**, and `tests/checklist6.py` asserts them automatically. If one
starts failing, it is a regression you introduced — §7 maps symptoms to owning skills.

Historical note, because it explains the shape of several fixes: on the original
`school-submission` tree items 1-5 passed and 6-10 did not. The tree also **hung on the title
screen under ZEsarUX** — all four key-release waits compared the raw port byte to `$FF`, and
bit 6 is the EAR line, which reads 0. They now mask to bits 0-4 (`AND $1F` / `CP $1F`). That is
the check to reach for first if input ever appears dead on real hardware or a different
emulator.

## 7. Regression signals

| Symptom | Owning skill |
|---|---|
| Border cells vanish; the well develops holes | `rendering-and-attributes`, `piece-rotation` |
| Piece drawn outside the well; garbage elsewhere on screen | `game-loop-and-collision` |
| Title screen reappears on its own | `game-loop-and-collision` (game-over path falls through) |
| Flicker or tearing | `interrupts-and-timing` |
| Piece visibly jumps position when rotated | `piece-rotation` |
| Everything freezes while a key is held | `interrupts-and-timing` |
| Rows fill but never clear | `line-clear` |

## 8. Debugging techniques that work here

- **Source-level breakpoints.** DeZog resolves them from `main.sld`, so you can breakpoint on
  a label such as `comprobar` or `pintar_tetromino` and step through the `.asm`.
- **Watch the attribute file.** Open a DeZog memory view at `$5800` (768 bytes) — pieces, well
  and collisions are all attribute bytes there. See `memory-map`.
- **Freeze-frame trap.** The codebase idiom is a self-branch, e.g. `parar: jr parar`. Insert one
  temporarily to stop execution and inspect memory. Two already exist but sit after a `ret` and
  are unreachable: `tableroJuego.asm:45`, `tetromino_next.asm:28` — see `failure-patterns`.

## 9. The discipline rule

Every change must:

1. Assemble with **0 errors and 0 warnings** (§1),
2. Pass `python3 tests/run_all.py` (§5b), and
3. Be **run and eyeballed against §6** if it touches anything visual.

Steps 1 and 2 are cheap and catch contract and logic breakage. Step 3 is the only thing that
catches timing and rendering.

### If you cannot drive the emulator

§6 needs ZEsarUX, VS Code and a human at the keyboard. A reader who has none of that still
gathers real evidence — do all four, then say what is missing. Do not skip the rule silently.

1. **Clean build** (§1): the last line must read `Errors: 0, warnings: 0`.
2. **Line count moved**: `compiled: N lines` must be above the 852 baseline by roughly the size of
   your addition. This is what catches a file that was never assembled (§5's newline hazard).
3. **Code landed where expected**: `grep -n "MiEtiqueta" main.lst` — the listing shows the address
   and the opcode bytes. Confirm both against what you intended to emit.
4. **Only the intended bytes changed**: `cmp -l main.bin /tmp/tetris-z80/baseline.bin` (§2) lists
   every differing offset. They must all fall inside the range you meant to touch.

**Necessary, not sufficient — none of this executes a single instruction.** Collision, timing,
rendering and anything visual still need a human running §6. Report what you checked and state
explicitly that §6 was not run.

## Common mistakes

- **Treating a clean build as proof the change works.** It proves the syntax parsed. Run §6.
- **Pressing Cmd+Shift+B and assuming `main.bin` is fresh.** It is not (§1); you will debug the
  June-2024 binary and conclude your edit did nothing.
- **Trusting stale `main.sld`.** DeZog then shows the wrong lines and labels. Rebuild every time.
- **Committing or reverting `main.lst`/`main.bin`/`main.sld` churn as if it were a source
  edit.** It is build output (§3). Check `git status --porcelain -- '*.asm'` instead.
- **Running the launch config with ZEsarUX not started or ZRCP off.** DeZog cannot reach
  `localhost:10000`. Do §4 steps 1-3 first.
- **Assembling one `.asm` standalone to "check it".** Only `main.asm` produces the real image.
  Most other files reference labels defined elsewhere and fail — `sjasmplus juego.asm` yields
  `juego.asm(4): error: Label not found: seleccionar_pieza`. **`caida.asm` is the exception:** no
  external references, assembles cleanly, which is why `caida.lst` is error-free — and it still
  tells you nothing. The committed `caida.bin`, `clear.bin`, `juego.bin`, `pantallas.bin`,
  `piezas.bin` and their `.lst`/`.sld` are stale relics of this mistake — see `failure-patterns`.
