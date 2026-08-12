---
name: interrupts-and-timing
description: Use when touching interrupt state or IY, adding HALT or frame synchronisation, changing gravity/drop speed or TIEMPO_BASE, budgeting T-states for a new routine, reasoning about contended memory, diagnosing flicker/tearing, or explaining why the game freezes while a key is held or behaves differently under different emulators or launch methods.
---

# Interrupts and timing

A **T-state** is one CPU clock tick; the 48K CPU runs at 3.5 MHz = 3,500,000 T-states/sec. The
**ULA** is the chip that draws the screen. Spanish: `caida` = fall, `paso` = step/pass,
`contador_frames` = frame counter, `FRAMES_POR_FILA` = frames per row, `sin_gravedad` = without
gravity, `nivel` = level.

## 1. The interrupt hazard — read this before adding any timing code

The ULA raises a maskable interrupt 50x/second. In **interrupt mode 1** (`IM 1`, the default
after reset) the CPU responds by calling the ROM routine at address **`$0038`**, which scans the
keyboard and updates the ROM's system variables. That routine **requires `IY = $5C3A`**: it
reaches system variables as `IY`-relative offsets (e.g. `$0045` executes `INC (IY+$40)`, bumping
the FRAMES counter), and the keyboard code it calls *writes* through `(IY+n)` too.

**The program now sets the interrupt state explicitly at startup** (`main.asm`, right after
`LD SP, 0`) instead of inheriting whatever the launch method left:

```asm
    DI
    LD IY, $5C3A          ; base de las variables del sistema
    IM 1
    EI                    ; el tick de 50 Hz queda disponible para HALT
```

**`IY = $5C3A` is a program-wide invariant.** Three routines still point `IY` at piece data,
and each one now brackets that window itself:

| Site | Sets `IY` to | How it is made safe |
|---|---|---|
| `piezas.asm` (`pintar_tetromino`) | `IX+2`, inside the piece table | `di` after the pushes, `ei` right after `pop iy` |
| `clear.asm` (`borrar_tetromino`) | same range | same |
| `test_col.asm` (`comprobar`) | same range | same (note: still no `push af` — `A` is the return value) |
| `L35 - Tetris_3D.asm` | `Tetro_3D` = `$9FD7`, left at `$9FDF`; **does not restore `IY`** | bracketed at its **call site** in `tableroJuego.asm`, which reloads `LD IY,$5C3A` before `EI` |

Why it matters: with interrupts on and `IY` pointing at `$A0xx`, the ROM's `$0038` handler
writes `$A0xx`-relative every 20 ms — straight into the piece tables and the code image.

### Where the brackets go — inside the routine, not at the call site

A routine that clobbers `IY` owns its own `DI`/`EI`. The pattern, from
`piezas.asm`/`clear.asm`/`test_col.asm`:

```asm
pintar_tetromino:
    push af
    push iy                ; caller's IY ($5C3A) saved
    push hl
    push de
    push bc
    di                     ; IY is about to stop being $5C3A
    ...                    ; ld iy, ix : inc iy : inc iy, then the draw loop
    pop bc
    pop de
    pop hl
    pop iy                 ; IY is $5C3A again...
    ei                     ; ...so it is safe to resume here, not before
    pop af
    ret
```

**`ei` goes immediately after `pop iy`, never before it.** `EI` takes effect after the
following instruction, so an `ei` placed earlier in the pop sequence leaves a window where an
interrupt can fire while `IY` still points at piece data — the exact corruption being
prevented.

Bracketing *inside* rather than at each call site was a deliberate choice: these routines are
called from several places (the loop, `GIRAR`'s kick search, `pintar_siguiente`), and a call
site that forgets the bracket fails silently and rarely. Doing it once in the routine cannot be
forgotten. The cost is ~1,000 T-states of interrupt latency per call, ~1.5% of a frame.

**The exception is `Tetris_3D`** (`L35 - Tetris_3D.asm`), which is course-supplied and must not
be edited. It does not restore `IY`, so its *caller* brackets it and reloads the invariant:

```asm
    di                       ; Tetris_3D deja IY en $9FDF y no lo restaura
    call Tetris_3D
    ld iy, $5C3A             ; devolvemos IY a la base de variables del sistema
    ei
```

Do not nest these brackets — nothing calls one `di`/`ei` routine from inside another today, and
the inner `ei` would re-enable interrupts early if you did.

**Why not simply `DI` forever?** That is the cheaper option and it is safe, but it forbids
`HALT`, and the gravity model in §5 is built on `HALT` plus a frame counter. Losing that means
going back to a busy-wait whose wall-clock speed differs on every emulator.

**Diagnostic:** the program no longer inherits its interrupt state, so launch method should no
longer change behaviour. If it does, something has disturbed the §1 startup block.
See `build-and-verify` for launch methods.

## 2. Frame budget

The loop is frame-synced (§5), so these numbers are live: everything one pass of `paso` does
must fit inside a frame, and the erase/redraw pair must fit inside the border window.

Current worst case, measured by opcode count: erase (~1,010) + `leer_teclas` (~120) + a
5-candidate `GIRAR` kick search (~5,500) + gravity `comprobar` (~1,040) + draw (~970) ≈ **8,600
T-states**, comfortably inside the ~14,000 T border window. A line clear adds up to ~9,700 T on
the locking frame only, which pushes that one frame past the border window — the reason a clear
can tear slightly while normal play does not.

| Quantity | Value |
|---|---|
| CPU clock | 3.5 MHz = 3,500,000 T-states/sec |
| Frame (48K) | **69,888 T-states**, ~50.08 frames/sec |
| Border window after `HALT` returns | ~14,000 T-states before the ULA starts reading the visible display |

The border/vertical-blank period is the only window in which writing the attribute file is
invisible. **Practical rule: the erase+redraw pair must be the first thing after `HALT`, and
must be short.** Anything you do after ~14,000 T-states lands on-screen mid-draw and tears.

**Since the music driver landed, the frame is no longer mostly empty — it is ~80% full.** The pass
now costs the game's ~8,400 T *plus up to 48,400 T of beeper tone*, so "there is loads of room" is
no longer a safe assumption for anything you add. §8 owns the music side of the budget; the numbers
that bind are:

| | T-states | % of frame |
|---|---:|---:|
| Worst game pass, ROM ISR included | 8,366 | 12% |
| Worst `musica_frame` call | 48,378 | 69% |
| **Total** | **56,744** | **81%** |
| Spare before the next interrupt | **13,144** | 19% |

Anything new competes for those 13,144 T, not for a whole frame. If you need more, the honest lever
is the music budget in `MUSIC_DESIGN.md` §5 — dropping it from 48,000 to 36,000 buys 12,000 T at an
audible cost — not shaving the game side.

### Measured costs

Hand-counted from the generated listing (opcode by opcode), **not** measured on an emulator.
Figures are for a typical 3x2 or 2x3 piece record (6 cells) and exclude memory contention (§3).

| Routine | T-states | Notes |
|---|---|---|
| `CalcularAtributo` (`pantallas.asm:67`) | 132 + 17 for the `CALL` | called by all three below |
| `pintar_tetromino` (`piezas.asm:34`) | ~970 | |
| `borrar_tetromino` (`clear.asm:3`) | ~1,010 | |
| `comprobar` (`test_col.asm:3`) | ~1,040 | |
| erase + check + draw per frame | **~3,000** | ~4% of a frame; fits the border window easily |

Budget a new routine by summing opcode costs the same way. Watch two traps in this codebase:
`ld iy,ix` is a sjasmplus fake instruction that assembles to `PUSH IX`/`POP IY` = **29 T**, not
8; and `ld a,(iy)` assembles to `LD A,(IY+0)` = **19 T**.

**Row copy for `line-clear`:** `LDIR`/`LDDR` cost **21 T per byte moved, 16 for the last**.
One 18-byte playfield row = 17x21 + 16 = **373 T**, ~439 T with loop overhead. `line-clear`
owns the full derivation and its figures are authoritative: **~9,700 T** for the worst single
clear, **~57,000 T** (82% of a frame) for four clears plus full-length row scans.
**Conclusion: do the whole shift in one frame. Do not split it across frames.**

## 3. Contended memory

On a 48K Spectrum the ULA and CPU share the RAM at **`$4000-$7FFF`**. While the ULA is fetching
display data, it stalls the CPU, so instructions touching that range run slower and with jitter
during the visible part of the frame.

- All game rendering targets the attribute file at **`$5800` — contended.**
- The program is `ORG $8000` (`main.asm:4`) and all code/data sits above it — **not contended.**
- All game state now lives in `variables.asm` at the top of the image — **not contended.**
  Nothing addresses `$7000-$7FFF` any more.

Rules: (1) T-state counts for attribute writes are a **floor**, not a truth, during the active
display — inflate by up to ~50% if the write happens outside the border window; (2) hot loops
that do not touch the screen belong above `$8000`. They already are.

## 4. Gravity is frame-counted — `caida.asm` is gone

**`caida.asm` no longer exists.** Its `Tiempo` busy-wait, its dead level arithmetic and its
dead `InicializarTiempo` were all removed once gravity moved onto the frame counter (§5); every
symbol in the file had become self-referential. Recover it from commit `0a2377e` if you ever
need the history. The gravity constants live in `puntuacion.asm` (`FRAMES_POR_NIVEL`) and
`variables.asm` (`FRAMES_POR_FILA`, `contador_frames`).

Why it went, in one line: `TIEMPO_BASE` = `$11FF` spun ~123,600 T-states ≈ **35 ms per row**,
about 28 rows/second, and no level ever changed it. Playable Tetris starts near 800 ms.

**Do not reintroduce a busy-wait.** Its wall-clock speed depends on the emulator's contention
model and clock accuracy, so the game plays at a different speed on every target. Frame
counting is exact everywhere: `FRAMES_POR_FILA` = 48 is 48/50 s ≈ 0.96 s per row, measured.

## 5. The timing model, as built

**Prerequisite: the interrupt setup in §1 must be in place.** `HALT` does nothing useful unless
interrupts are enabled, and enabling them without holding `IY = $5C3A` corrupts memory.

1. There is no busy-wait. `juego.asm`'s `paso` loop opens with `HALT`.
2. `FRAMES_POR_FILA` and `contador_frames` are declared in `variables.asm` — **`memory-map` §6
   owns variable placement.** Do not declare them inline: bytes sitting above a label get
   executed as opcodes by any fall-through.
3. `HALT` once per frame at the top of the loop.
4. Erase + redraw **immediately** after `HALT`, inside the border window.
5. Poll input every frame instead of once per drop (non-blocking read: `game-loop-and-collision`).
6. One frame of music **last**, after the redraw, filling most of what is left of the frame (§8).

**The frame gate is inlined at the top of `juego.asm`'s `paso` loop**, not a separate wrapper
routine calling a `paso` subroutine. One loop, one place, nothing to keep in sync — and no
call/return per frame. The gravity decision is carried in **`H`** (1 = drop a row this pass,
0 = input and redraw only); `H` survives because every routine the loop calls preserves `HL`.
`game-loop-and-collision` §6 owns the body below `sin_gravedad`.

```asm
paso:
    HALT                    ; duerme hasta el tick de 50 Hz; vuelve en el borde superior
    LD H, 0                 ; por defecto esta pasada no baja
    LD A,(contador_frames)
    DEC A
    LD (contador_frames), A
    JR NZ, sin_gravedad
    LD A,(FRAMES_POR_FILA)  ; se agoto la cuenta: recargamos y pedimos bajada
    LD (contador_frames), A
    LD H, 1
sin_gravedad:
    CALL borrar_tetromino   ; erase + redraw sit immediately after HALT, in the border window
    ...                     ; game-loop-and-collision §6
    CALL pintar_tetromino   ; ...redraw is the LAST thing in the window...
    CALL musica_frame       ; ...and the music fills the rest of the frame behind it (§8)
    JP paso
```

**Why there is no `DI`/`EI` around the render here:** the piece routines bracket their own `IY`
window internally (§1), so `IY` is `$5C3A` everywhere in this loop. Bracketing at *this* level
instead would leave interrupts off across the whole render for no benefit. And a global `DI`
would make `HALT` never return — this loop would hang on its first instruction.

## 6. Input no longer blocks the clock

It used to. `Soltar_Tecla` and `SoltarTeclaMv` each spun on `IN A,(C)` / `CP $FF` until the key
came up, so **holding a key froze gravity and rendering completely**. Both are gone: `GIRAR`
takes its direction in `A` and reads no keys, `movimiento.asm` was deleted, and `leer_teclas`
(`entrada.asm`) is called once per pass and reports only up→down transitions.

**The `CP $FF` idiom was actively broken, not merely unportable.** Only bits 0-4 of the port are
keyboard data; bit 6 is the EAR line. Under ZEsarUX a keyboard half-row with nothing pressed
reads **`$BF`**, not `$FF`, so every one of those waits looped forever and the game hung on the
title screen. The surviving waits (`titulo.asm`, `pantallas.asm`) now do `AND $1F` / `CP $1F`.
**Never compare a raw keyboard port byte against `$FF`.**

## 7. After the game loop ends — what still applies, and what does not

`fin_partida` calls `relleno_pozo` (`relleno.asm`), the fill-up animation, before jumping to the
game-over screen. It is the only code in the tree that runs *after* the loop has stopped, so it is
worth being precise about which of the rules above still bind it. **Check this rather than
assuming it either way** — post-game code is neither "under the same real-time pressure as the
loop" nor "free of timing rules".

**What no longer applies: the §2 frame budget.** The loop has ended. There is no input to read, no
gravity to count, no piece to erase and repaint, and nothing after this that a slow frame could
delay. Nothing competes for the frame, so the ~8,600 T-state worst case in §2 is simply not a
constraint here.

**What still applies, unchanged:**

1. **The border window.** `$5800` is contended (§3) and the ULA draws whether the game is running
   or not, so writing the attribute file during the visible display still tears. Each of the 22
   rows is therefore painted immediately after a `HALT`: 18 attribute writes, ~400 T-states, far
   inside the ~14,000 T window. Same discipline as the erase/redraw pair in §5, same reason.
2. **The interrupt state.** `HALT` only returns if interrupts are enabled. They are, and this is
   the part actually worth verifying rather than assuming: `main.asm:7-10` enables them once at
   startup, and **every** `di`/`ei` bracket in the tree (`piezas.asm`, `clear.asm`, `test_col.asm`,
   `tableroJuego.asm`) re-enables before returning — §1 is what guarantees that. Nothing in the
   game-over path leaves them off. `relleno_pozo` does not touch `IY`, so it needs no bracket of
   its own.
3. **No busy-waits** (§4). The pacing is `HALT` and a counter, exactly like gravity. A delay loop
   would make the animation a different length on every emulator.

**Pacing, and why frame-by-frame rather than one fast pass.** 22 rows × `RELL_FRAMES_FILA` (3)
frames, then a `RELL_PAUSA` (25) frame hold so the full well is actually visible before the screen
cuts: **91 frames, ~1.8 s**, measured. A single blind fill pass would be *faster*, not *safer* —
it saves nothing, since there is no budget to protect, and it gives up the raster sync that keeps
the fill from tearing. Frame counting was the right tool for gravity and it is the right tool
here.

`tests/test_relleno.py` asserts the animation completes, that it takes 91 frames ± 6, and that it
stays under a 150-frame (3 s) ceiling — the ceiling being the constraint that actually matters
post-game: a duration the player sits through on every single loss.

### Testing HALT-paced code — `run N` cannot host it

ZEsarUX's `run N` executes N opcodes with **no 50 Hz tick**, so a `HALT` never returns under it.
Two consequences, both learned the hard way:

- A `HALT`-paced routine looks like an infinite loop to `Unit.call`, and an opcode limit large
  enough to "wait it out" **wedges the emulator** — it detects the halted-with-interrupts-off CPU,
  opens a menu, and needs restarting (the same failure mode `tests/unit.py`'s header describes
  for breakpoints). Use `Unit.call_free`, which releases the CPU at real speed and watches for it
  to park on the trap.
- `Unit.__init__`'s `run 5` stops **one opcode short** of `main.asm`'s `EI`, so unit-tested
  routines actually run with interrupts *disabled*. No other suite notices — nothing else
  `HALT`s, and the `ei` inside `comprobar` / `pintar_tetromino` / `borrar_tetromino` re-enables
  them in passing. `call_free` re-runs the prologue through the `EI` before releasing.

## 8. The music driver's place in the frame — and why it needs no bracket

`musica_frame` (`musica.asm`) is called once per pass, as the **last** thing in the loop body. It is
by far the most expensive thing in the frame, and it is the first code in this tree that both spends
a fixed 69% of the frame and touches a hardware port. Design and budget live in `MUSIC_DESIGN.md`;
this section owns where it sits in the frame and how it interacts with the interrupt rules above.

### Position: after the render, never before

```
HALT ─┬─ ROM ISR, 889 T ─┬─ erase ── input ── move/rotate/gravity ── redraw ─┬─ musica_frame ─┬─ HALT
      │                  │←────── ~8,400 T, inside the ~14,000 T window ────→│  ≤48,378 T     │
      └── frame starts ──┘                                                                     └ 56,744 T of 69,888
```

The erase/redraw pair must stay inside the border window (§2). Putting ~48,000 T of tone in front of
the redraw pushes it deep into the visible display and the piece tears on every single frame. Behind
it, the same 48,000 T is invisible — the driver writes no screen memory at all, only port `$FE`.

### The three interrupt rules, all checked rather than assumed

1. **No new `DI`/`EI` bracket is needed, and none was added.** The existing brackets live *inside*
   `pintar_tetromino`, `borrar_tetromino` and `comprobar` (§1), each protecting a window where `IY`
   is not `$5C3A`. All of them restore `IY` and re-enable before returning, and `musica_frame` runs
   after every one of them has returned — so it never nests inside a bracket and never sees a bad
   `IY`. **`musica.asm` contains no `ld iy,...` at all**, so it needs no bracket of its own.
   `tests/test_musica.py` asserts both facts against the source rather than trusting this paragraph.

2. **The driver must never `DI`.** This is the tempting mistake, because the ROM's 889 T handler
   lands as a faint click. Masking it does not defer it — the ULA interrupt is a short pulse, so it
   is **missed**, and the following `HALT` then waits an entire extra frame. The game would run at
   25 fps and the music an octave-ish flat in tempo. The click is accepted instead: it recurs at
   exactly 50 Hz, so it merges into the duty-cycle buzz that a 69% duty cycle already has.

   In practice it does not even land mid-note. `HALT` returns *after* the handler completes, so the
   ISR runs at the top of the frame, before the loop body — the fill only ever meets an interrupt if
   the frame has already overrun, which is what rule 3 prevents.

3. **The fill must finish before the next interrupt, on every call — not on average.** Frame sync
   depends on reaching `HALT` before interrupt N+1. 8,366 + 48,378 = 56,744 T against 69,888 leaves
   13,144 T. This is why the budget is a fixed per-note allowance rather than "fill whatever time is
   left": the loop cannot cheaply ask how much of the frame remains. The note table stores a
   per-pitch half-period count so the *time* stays constant while the pitch varies —
   `tests/test_musica.py` measures all 28 notes and asserts the worst one fits.

### Frames that make no sound

Four kinds, all cheap, all costing under 250 T instead of ~48,000:

| Frame | Cost | Why |
|---|---:|---|
| A pass that cleared rows (`musica_silencio` set) | 202 T | Not even a one-row clear fits beside the fill — `limpiar_lineas` alone is 22,235 T for one row. `game-loop-and-collision` §8 owns the flag. |
| A `NOTA_SIL` rest in the melody | 229 T | The melody asked for silence. |
| The last frame of every note | 187 T | Deliberate 20 ms articulation gap, so two consecutive notes of the same pitch do not merge. |
| A pass that ends the game | — | `fin_partida` skips `dibujar`, so `relleno_pozo` and the game-over screen are silent (§7). |

A four-row clear still overruns its frame and takes two, exactly as it did before music existed
(`line-clear`, `MUSIC_DESIGN.md` §2). Music does not make that worse: those frames are muted.

### Port `$FE` is contended too

§3 covers *memory* contention, and the driver is clean there — it reads only its own tables above
`$8000`. But `out ($FE),a` is an I/O access to the ULA and **is** delayed during the visible display.
Measured inflation is up to ~50 T across all the OUTs of one note: irrelevant against 13,144 T of
slack, but it means the emitted half-period jitters by a few T-states, a fraction of a cent. This is
also why measurements of `musica_frame` vary by a few tens of T-states between runs, and why
`tests/test_musica.py` takes the **minimum** of repeated samples — the CPU is stopped between ZRCP
commands, so nothing can make a call measure short, only long.

### Measuring it: `cpu-step-over`, not `run N`

`run N` executes N opcodes regardless of what the code does, so a routine that returns early leaves
the CPU spinning on `unit.py`'s `DI : JR $` trap for the remaining opcodes — and every one of those
is counted. A 202 T muted frame measures **479,138 T** that way: the opcode limit, not the code.
`cpu-step-over` on a poked `call musica_frame` runs until that call returns and stops there. Same
trap-versus-breakpoint reasoning as §7 — this is a third way `run N` misleads, alongside `HALT`
never returning under it.

## Common mistakes

- **Adding `HALT` while `IY` is garbage and interrupts are on.** The ROM handler then writes
  into the piece tables every 20 ms. The §1 startup block must be in place.
- **Putting `ei` before `pop iy` when bracketing a new `IY`-clobbering routine.** `EI` takes
  effect one instruction later, leaving a window where an interrupt fires with `IY` still
  pointing at piece data (§1).
- **Reintroducing a busy-wait delay.** Its wall-clock speed depends on the emulator's
  contention model and clock accuracy, so the game plays at a different speed on every target.
  Frame counting is exact everywhere. Change `FRAMES_POR_NIVEL` (`puntuacion.asm`), not a spin.
- **Comparing a keyboard port byte against `$FF`** (§6). Bit 6 is EAR; mask to `$1F` first.
- **Trusting T-state counts for attribute writes during the active display.** `$5800` is
  contended (§3); the counts are a floor. Only counts taken inside the border window are firm.
- **Assuming the ROM 50 Hz tick exists.** It exists only if the launch method left interrupts
  enabled and nobody executed `DI`. Set the state explicitly at startup; never inherit it.
- **Splitting the line-clear row shift across frames because it "looks expensive".** The worst
  single clear is ~9,700 T-states, ~14% of a frame. Do it in one frame (§2).
- **Assuming `ld iy,ix` is cheap.** It is `PUSH IX`/`POP IY`, 29 T-states. See
  `assembler-conventions` for sjasmplus fake instructions.
- **Assuming post-game code is unconstrained, or assuming it is as constrained as the loop.**
  Neither. The frame budget is gone; the border window and the interrupt state are not (§7).
- **Testing a `HALT`-paced routine with `Unit.call` / a big `run N` limit.** It cannot return, and
  a large enough limit wedges the emulator. `Unit.call_free` exists for this (§7).
- **Budgeting a new routine against a mostly-empty frame.** The frame is 81% full since the music
  driver landed; there are 13,144 T going spare, not 61,000 (§2, §8).
- **Adding a `DI`/`EI` bracket around `musica_frame`** to stop the ROM handler clicking mid-note.
  The masked ULA pulse is lost, not deferred, and the next `HALT` waits a whole extra frame (§8).
- **Calling `musica_frame` before the redraw**, or anywhere but last in the loop body. ~48,000 T in
  front of the redraw pushes it out of the border window and the piece tears every frame (§8).
- **Measuring a long routine with `run N` and reading `get-tstates-partial`.** The trap spins for the
  remaining opcodes and they all count; a 202 T call reads as 479,138 T. Use `cpu-step-over` (§8).
- **Assuming port I/O is uncontended because the driver's memory is.** `out ($FE),a` is a ULA access
  and is delayed during the visible display (§8).
