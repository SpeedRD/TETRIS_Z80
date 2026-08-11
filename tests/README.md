# tests

Automated verification for TETRIS_Z80, driving **ZEsarUX over ZRCP** — its
remote debug protocol on `localhost:10000`. No VS Code, no DeZog, no human at
the keyboard.

Two properties of this project make it testable at all:

- **The attribute file at `$5800` *is* the board.** Reading 768 bytes gives the
  entire game state, so a test can assert on positions, colours, cleared rows
  and border integrity directly. `tetris.Z.board()` renders it as ASCII.
- **`set-ui-io-ports` sets the keyboard matrix**, which is exactly what the
  game polls — so input is deterministic, including "key held" versus "key
  newly pressed".

## Running

Start ZEsarUX with ZRCP enabled (it is not on `PATH`):

```bash
/Applications/ZEsarUX.app/Contents/MacOS/zesarux \
    --enable-remoteprotocol --remoteprotocol-port 10000 --machine 48k &
nc -z localhost 10000 && echo LISTENING
```

Then, from the repo root:

```bash
python3 tests/run_all.py              # build + every suite
python3 tests/run_all.py test_giro    # just one
```

`run_all.py` rebuilds first and refuses to run if the build is not
`Errors: 0, warnings: 0` — sjasmplus exits 0 even with warnings, so the last
line is read rather than the exit code.

## What each suite covers

| Suite | Covers |
|---|---|
| `test_entrada.py` | `leer_teclas` edge detection (held keys must not repeat, neighbouring keys on the same half-rows must not leak) and `en_rango` boundaries for 1-, 2- and 4-wide pieces |
| `test_giro.py` | Every shape × every rotation state × columns 5–27 × both directions: cycles close, left/right are exact inverses, no rotation ever lands outside columns 7–24, a blocked rotation leaves `IX`/`C`/`Medio` untouched, and `GIRAR` never draws |
| `test_lineas.py` | Single/double/quadruple clears, non-adjacent full rows, top-row clear, a completely full board, and that the well border survives all of it |
| `test_puntuacion.py` | Points per clear, packed-BCD carry across digit boundaries, line counter, level-up at 10 lines, level cap, and the whole frames-per-level speed table |
| `test_spawn.py` | Shape distribution (was 25%/6.25%, must now be ~14.3% each), LFSR never reaching zero, and that the previewed piece is the one that actually spawns |
| `checklist6.py` | `build-and-verify` §6 end to end: title, menu, quit, well, gravity, J/K, Q/W, settling, and border integrity across several full games including game-over→restart |

## Harness notes

`tetris.py` is the ZRCP client plus the board renderer and a small script
interpreter. `unit.py` calls a single Z80 routine with chosen registers.

Three details in `unit.py` are load-bearing and cost real time to rediscover:

1. **No breakpoints.** A fired ZEsarUX breakpoint opens its debug menu; an open
   menu makes `enter-cpu-step` fail, which makes `run` fail, and the emulator
   then needs restarting. Routines return onto a `DI : JR $` trap instead, so
   each call costs its full opcode `limit` — keep limits tight.
2. **The trap parks with interrupts off.** With them on, the ROM's 50 Hz
   handler is often mid-flight when registers are sampled and `PC` reads as a
   ROM address, making "did it return?" unreliable.
3. **`main.asm`'s 5-opcode prologue runs before every test** (`LD SP,0 / DI /
   LD IY,$5C3A / IM 1 / EI`), so routines see the game's real interrupt state.
   Skip it and the `ei` inside `comprobar` / `pintar_tetromino` /
   `borrar_tetromino` enables interrupts while still in IM 0, and the CPU
   vectors into ROM.

Addresses are always resolved from `main.lst` by label — never hardcoded. They
all move whenever anything earlier in the include order changes size.

Screenshots go to a temp directory, never into the repo (there is no
`.gitignore`).

## Limits

These suites do not prove the game is fun, and they cannot see tearing or
flicker — anything about *when* within a frame a write lands still needs a
human watching. They do cover every routine's contract, the register protocol,
and board-level outcomes.
