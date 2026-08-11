# In-game music: feasibility, cost and design decision

Decision document. Nothing here is built yet — this records what the timing actually is, what a
beeper driver actually costs, and what was decided before code gets written.

Every number below was **measured**, not estimated: the game was driven under ZEsarUX over ZRCP and
stepped one opcode at a time, with each step's T-states read from the emulator's counter and
attributed to either game code or the ROM's interrupt handler. Where a figure is a floor rather
than a truth, it says so.

---

## 1. Verdict

**Full in-game music is achievable.** Not a shortened riff, not a degraded fallback — the complete
Korobeiniki melody, at exact pitch, for the whole of normal play.

The reason is that the game is cheap. Worst-case normal play costs **8,366 T-states of a 69,888 T
frame — 12%**. The remaining **61,522 T** is idle. That is not a tight budget to squeeze music
into; it is a frame that is mostly empty.

Two qualifications, both real and neither fatal:

1. **Sound is suppressed on any frame that clears lines.** That frame is the only one in the game
   that is genuinely expensive, and a four-row clear does not fit in a single frame even now.
2. **The pitch is exact but the timbre is a 1-bit square wave with a 50 Hz amplitude gap.** It will
   sound like a ZX Spectrum, because it is one.

---

## 2. The real frame budget

One 48K frame is **69,888 T-states** at 3.5 MHz, ~50.08 frames/sec. The ROM's `$0038` handler costs
a measured **889 T** and fires once per frame, every frame; it is included in the worst-case line
below and must be in any budget.

### Normal play

| Frame type | T-states | % of frame |
|---|---:|---:|
| Idle — no gravity, no input | 2,505 | 3.6% |
| Lateral move, blocked | 2,996 | 4.3% |
| Rotation, succeeds first try | 3,389 | 4.8% |
| Soft drop + normal gravity | 3,456 | 4.9% |
| Gravity drop, one row | 3,588 | 5.1% |
| Lateral move, accepted | 3,684 | 5.3% |
| Rotation, all 5 wall-kick candidates fail | 5,806 | 8.3% |
| **Everything at once + ROM ISR** | **8,366** | **12.0%** |

The last row is the one that binds: lateral move *and* a failed five-candidate rotation *and*
normal gravity *and* soft drop in a single pass, plus the interrupt handler. It is the honest
worst case for a frame with no piece locking.

> **Headroom available to music in normal play: 61,522 T-states per frame (88% of the frame).**

This is close to the ~8,600 T figure the `interrupts-and-timing` skill carried from hand-counting,
which is reassuring — that estimate was sound.

### Locking frames

A frame where the piece locks also runs `limpiar_lineas`, `anotar_lineas` (which reprints the
scoreboard), `seleccionar_pieza` and `pintar_siguiente`. These are the expensive frames.

| Locking frame | T-states | % of frame | Headroom |
|---|---:|---:|---:|
| Lock, 0 rows cleared | 13,848 | 19.8% | 56,040 |
| Lock, 1 row cleared | 37,516 | 53.7% | 32,372 |
| Lock, 2 rows cleared | 44,875 | 64.2% | 25,013 |
| Lock, 3 rows cleared | 63,129 | 90.3% | 6,759 |
| Lock, 4 rows cleared | **76,864** | **110.0%** | **−6,976** |

`limpiar_lineas` on its own: 6,291 T with nothing to clear, 22,235 T for one row, 30,612 T for two,
65,059 T for four.

**A four-row clear does not fit in one frame and never will.** The loop misses one 50 Hz interrupt
and that clear takes two frames. This is inherent to doing the whole row shift in a single pass,
and doing it in a single pass remains correct — the alternative is a half-shifted board visible to
`comprobar`. It is a pre-existing property of the game, not something music introduces.

### These numbers are floors

ZEsarUX's step timings are uncontended. All game rendering targets the attribute file at `$5800`,
which is contended memory, so real costs during the visible display are higher — `interrupts-and-timing`
§3 owns that and puts the inflation at up to ~50%. The music driver itself touches no contended
memory (it writes port `$FE` and reads its own tables above `$8000`), so its cost is firm; the
*game* side of the budget is the part that can run over. The margins chosen in §5 absorb this.

---

## 3. What changed while measuring: the `bajar_filas` fix

The first measurement pass produced line-clear frames of 119,369 T (one row) to 403,684 T (four
rows) — 1.7 to 5.8 whole frames. That was a real bug, now fixed, and the numbers in §2 are the
post-fix ones.

`bajar_filas` loaded its row-copy count into `A` and then called `CRtoATTR`, which ends in
`LD A,L` and therefore **destroys `A`**. The count became the low byte of the destination attribute
address: for row 21, `$5AA7` → **167 copies instead of 21**.

The 146 surplus passes walked `HL`/`DE` 50 bytes lower each time, straight down out of the
attribute file and through the pixel display file, corrupting ~230 bytes of the 3D background per
line cleared.

**Why nothing caught it:** the finished board was still correct, because `bf_cero` rewrites row 0
afterwards. Every board-state assertion in `test_lineas.py` passed against the broken code, and
still does. Only the iteration count itself distinguishes 21 from 167.

The fix brackets the call:

```asm
    push af                  ; CRtoATTR ends in "LD A,L": it DESTROYS A
    call CRtoATTR
    pop af
```

`push af`/`pop af` was chosen over reloading `ld a,b` after the call because it is self-contained —
it does not depend on `CRtoATTR` happening to preserve `B`, so it survives someone later swapping in
`CalcularAtributo`, which clobbers `BC`. It is also the pattern the codebase already uses in
`anotar_lineas`, `ImprimirBCD` and `ImprimirDec3`.

**Audit:** every other site that holds a value across an AF-destroying call was checked —
all `CRtoATTR` / `CalcularAtributo` / `PRINTAT` call sites, every `dec a` counter loop and every
`djnz` loop. `bajar_filas` was the only one. Everywhere else either reloads `A` after the call or
already brackets it.

**Regression test:** `tests/test_bajar_filas.py` asserts the loop runs exactly `B` times for all 22
rows, and that a real clear leaves the pixel display file byte-identical. It was verified to *fail*
against the pre-fix build (167 copies, 2,610 corrupted bytes) — a regression test that has never
failed proves nothing.

Effect on this document: it is the difference between "music is impossible on any clearing frame
and the game visibly stutters for 6 frames" and "music pauses for one frame on a clear".

---

## 4. What a beeper driver costs

### 4.1 Pitch accuracy is free — the brief's framing was wrong

The original question posed tone-accuracy and cheapness as opposite ends of one axis. Measurement
says they are not related. Both drivers below hit every note of the melody to within **4.2 cents**,
which is inaudible (a semitone is 100 cents; trained ears resolve ~5–10 cents at best).

Two measured cost models, both fitted from stepped emulator runs of an isolated benchmark:

```
DJNZ driver     half_period_T = 51.81 + 13.00 × C      C = 1..255
                                                        → 65..3,366 T  (520 Hz .. 27 kHz)

16-bit driver   half_period_T = 75.55 + 26.01 × HL     for pitches below 520 Hz
```

These two formulas are the basis for the note table built next stage (§8). The DJNZ loop covers
C5 upward; the 16-bit loop covers A3 to B4. Worked constants across Korobeiniki's range:

| Note | Target Hz | Driver | Const | Actual Hz | Error | Toggles/frame |
|---|---:|---|---:|---:|---:|---:|
| A3 | 220.00 | 16-bit | 303 | 219.95 | −0.4c | 9 |
| B3 | 246.94 | 16-bit | 270 | 246.55 | −2.7c | 10 |
| C4 | 261.63 | 16-bit | 254 | 261.90 | +1.8c | 10 |
| D4 | 293.66 | 16-bit | 226 | 293.94 | +1.7c | 12 |
| E4 | 329.63 | 16-bit | 201 | 329.98 | +1.8c | 13 |
| F4 | 349.23 | 16-bit | 190 | 348.80 | −2.2c | 14 |
| G4 | 392.00 | 16-bit | 169 | 391.41 | −2.6c | 16 |
| G#4 | 415.30 | 16-bit | 159 | 415.58 | +1.2c | 17 |
| A4 | 440.00 | 16-bit | 150 | 440.04 | +0.2c | 18 |
| B4 | 493.88 | 16-bit | 133 | 495.08 | +4.2c | 20 |
| C5 | 523.25 | DJNZ | 253 | 523.95 | +2.3c | 21 |
| D5 | 587.33 | DJNZ | 225 | 588.02 | +2.0c | 23 |
| E5 | 659.25 | DJNZ | 200 | 660.08 | +2.2c | 26 |
| F5 | 698.46 | DJNZ | 189 | 697.71 | −1.9c | 28 |
| A5 | 880.00 | DJNZ | 149 | 880.13 | +0.3c | 35 |
| B5 | 987.77 | DJNZ | 132 | 990.16 | +4.2c | 40 |

Worst error across the whole melody: **4.2 cents**. Pitch is a solved problem at any budget.

### 4.2 Approach 1 — tone-accurate square-wave toggle loop

Toggle bit 4 of port `$FE`, wait a computed number of T-states, repeat. This is the classic
Spectrum beeper and it is what §4.1 measures.

The important property: **its cost is not fixed, it is whatever you give it.** The loop consumes
exactly the time budgeted; the budget determines how much of each frame carries sound, which
determines loudness and cleanliness. It cannot be "made cheaper" without becoming quieter.

- **Sound:** a clean square wave at exact pitch. Buzzy in the way all 1-bit beeper music is —
  strong odd harmonics, no envelope, no dynamics.
- **Blocking:** it is a spin loop. Whatever time it takes is time the game does not have. This is
  the entire design constraint.

### 4.3 Approach 2 — divided / ticked from the interrupt: **not viable**

The proposal was to have the interrupt do a small fixed amount of work per frame — advance a
counter, conditionally toggle the speaker bit — trading pitch accuracy for a small predictable cost.

This cannot produce music on a 48K Spectrum, and the arithmetic is not close:

- The only interrupt source is the ULA at **50 Hz**. There is no timer chip.
- One toggle per frame produces a square wave of **25 Hz** — below the ~20 Hz floor of pitch
  perception, four octaves under the melody's lowest note.
- A4 (440 Hz) needs **17.6 toggles per frame**. The lowest note in the melody, A3, needs **8.8**.

A once-per-frame tick is off by a factor of ~18 at concert A. It yields a 50 Hz click track, not a
melody. **Rejected — it does not trade quality for cost, it fails to make pitch at all.**

The genuinely cheap option is not a different technique; it is approach 1 with a smaller budget.

### 4.4 The real axis: duty cycle

Since pitch is free and the toggle loop consumes exactly what it is given, the only decision is
**how many T-states per frame to spend**. That sets what fraction of each frame carries sound.
Gaps between bursts recur at 50 Hz, so a low duty cycle is heard as a buzzy rasp with the pitch
faintly inside it; a high duty cycle is heard as a clear note.

| Budget | Duty | Worst normal frame | Margin | Lock frame (0 rows) | Margin |
|---:|---:|---:|---:|---:|---:|
| 24,000 T | 34% | 32,236 T (46%) | 37,652 | 37,718 T (54%) | 32,170 |
| 36,000 T | 52% | 44,165 T (63%) | 25,723 | 49,647 T (71%) | 20,241 |
| **48,000 T** | **69%** | **56,105 T (80%)** | **13,783** | **61,587 T (88%)** | **8,301** |
| 56,000 T | 80% | 64,062 T (92%) | 5,826 | 69,544 T (99.5%) | **344** |

56,000 T is not a real option: 344 T of margin on the lock frame means any future addition to the
lock path drops the game to 25 fps.

---

## 5. Decision

> **Budget: 48,000 T-states per frame (~69% duty cycle). Music suppressed entirely on any frame
> that clears one or more lines.**

Rationale:

- Leaves **13,783 T** spare on the worst normal frame and **8,301 T** on a lock frame — real
  cushion, enough to absorb attribute-file contention on the game side (§2) and future additions.
- 69% duty is comfortably into "clearly a tune" territory. The remaining 31% gap is heard as a mild
  50 Hz buzz under the note, which is characteristic of the platform rather than a defect.
- Dropping to 36,000 T would buy margin the measurements say is not needed, at an audible cost.

The tone loop's actual spend is slightly under budget because a whole number of half-periods is
emitted: worst case across the melody is **47,739 T**. The note table stores a per-note count
(`budget ÷ half_period`), so the count varies by pitch and the *time* stays constant. A fixed
toggle count would be wrong — at 8 half-periods, A3 costs 63,632 T and B5 costs 14,176 T.

---

## 6. Frames where sound is dropped

Suppression rule: **if `limpiar_lineas` returned non-zero, skip the music fill for that frame.**

| Frame | Cost + 47,739 T of music | Fits? |
|---|---:|---|
| Worst normal play | 56,105 T | yes |
| Lock, 0 rows | 61,587 T | yes |
| Lock, 1 row | 85,255 T | **no** |
| Lock, 4 rows | 124,603 T | **no** |

Even a single-row clear cannot carry music at this budget, so the rule is a flat "any clear ⇒
silent" rather than a graded one. Simpler, and it has no failure mode.

**Cost in audible terms:** one frame of silence per clear — **20 ms** — or 40 ms for a four-row
clear, which already spans two frames. That is a gap roughly one tenth the length of a semiquaver
at the melody's tempo. It lands exactly on the visual clear event, where a percussive break reads
as intentional rather than broken.

**On the trade the brief asked about:** an occasionally dropped note is unambiguously the right
sacrifice. A dropped input loses the player a piece placement; a corrupted board is unrecoverable.
Sound is the only one of the three that degrades gracefully. The suppression is also *predictable*
rather than probabilistic — it happens on exactly the frames the game can name in advance, so there
is no timing race to get wrong.

---

## 7. Interaction with the existing `DI`/`EI` brackets

**No interaction, and no new bracket is needed.** This was checked rather than assumed.

The existing brackets live *inside* `pintar_tetromino`, `borrar_tetromino` and `comprobar`
(and around the `Tetris_3D` call site), each protecting a window where `IY` stops being `$5C3A`.
All of them complete and restore `IY` before returning. The music fill runs in the main loop body
after every one of those calls has returned, so it never nests inside a bracket and never sees a
non-`$5C3A` `IY`.

Three rules the driver must follow:

1. **The music fill goes at the *end* of the loop body, after the render.** The erase/redraw pair
   must stay immediately after `HALT`, inside the ~14,000 T border window, or the piece tears.
   Music placed before the render would push it out of that window. Placed after, it is harmless.

2. **The driver must not `DI`.** Tempting, because the ROM handler's 889 T lands mid-note as a small
   click. But the ULA interrupt is a short pulse: hold interrupts off across it and it is *missed*,
   not deferred, and the following `HALT` then waits an entire extra frame — 25 fps. The 889 T gap
   is accepted. It recurs at exactly 50 Hz, so it merges into the duty-cycle buzz already there
   rather than adding a new artifact.

3. **The fill must finish before the next interrupt.** Frame sync depends on reaching `HALT` before
   interrupt N+1 arrives. 8,366 + 47,739 = 56,105 T against 69,888 T leaves 13,783 T of slack, so
   this holds with room. It is also why the budget is a fixed allowance rather than "fill whatever
   is left" — the loop cannot cheaply measure how much time remains.

---

## 8. What gets built next

1. **`variables.asm`** — music state: current note index, frames remaining on the note, a
   suppress-this-frame flag. Placement per `memory-map` §6; `variables.asm` stays the last INCLUDE.
2. **Note table** — one entry per pitch: driver selector, delay constant, half-period count for the
   48,000 T budget. Derived from the two formulas in §4.1. Read-only data.
3. **Melody table** — Korobeiniki as (note, duration) pairs. ~100 notes at 2 bytes each is ~200
   bytes; the image currently ends at `$A6BD` with free RAM above, so **the full melody costs
   nothing worth counting. There is no reason to fall back to a short riff.**
4. **`musica.asm`** — the toggle loop (both driver variants) plus a per-frame entry point that
   advances the melody and emits one frame's worth of the current note.
5. **`juego.asm` hook** — one call at the end of the loop body, plus setting the suppress flag from
   `limpiar_lineas`'s return value. This is the only change to existing game code.
6. **Tests** — the harness can assert note timing and that the suppression flag is set on clearing
   frames. It cannot assert what it sounds like; that needs a human.

### Side effect to decide at build time

Writing port `$FE` sets the **border colour** in bits 0–2 as well as toggling the speaker on bit 4.
The game currently never writes `$FE` at all (`memory-map` §7), so the border is whatever the ROM
left. The driver must pick a value; **black (bits 0–2 = 0)** is the recommendation, matching the
black paper the panels and well already use. It is a visible change either way — the border cannot
be read back, so it must be chosen rather than preserved.

---

## 9. Open questions

**Striped-panel display anomaly — unresolved, watch for it.**

A striped-rainbow corruption of the pre-game screen panels was reported from earlier manual
testing. It was checked explicitly during this work and **could not be reproduced across four
systematic walkthroughs**: first cold boot, after a completed game, after a game containing a line
clear, and after a game ending in the game-over fill animation. An attribute census of the
pre-game screen returned only four values — `0`, `55`, `6`, `7` — with no piece colours present at
all, so there was nothing on screen for stripes to be made from.

**No plausible mechanism connects it to the `bajar_filas` bug.** That loop wrote 18-byte runs at
`$5AA7 − 50k`: well rows for k = 0..21, then straight down into the pixel display file. It never
touched attribute cells outside the well, so it could not have painted menu panels. `CLEARSCR` also
zeroes `$4000–$5AFF` before any panel screen is drawn, which would wipe pixel damage regardless.
**The fix in §3 should not be assumed to have addressed this.**

One candidate explanation is that it was an artifact of concurrent ZEsarUX access during testing —
screen reads and memory pokes over ZRCP while the emulator was running — rather than a defect in
the game. That is a hypothesis, not a finding; it has not been demonstrated either.

There is a genuine striped rainbow in the game, and it is deliberate: `relleno_pozo`, the game-over
fill, packs the well with cycling colours 1–7 as horizontal bands before cutting to the game-over
screen. It was observed transitioning cleanly with no residue. Worth ruling out as the source of
the original sighting before hunting further.

**Status: not resolved, not reproduced, not explained.** If it reappears, capture the attribute
file at `$5800` at the moment it is visible — that will immediately separate a real corruption from
a rendering or capture artifact.

---

## Appendix: how the numbers were obtained

Measurement drove the already-running ZEsarUX over ZRCP, the same transport `tests/` uses. For each
frame type the CPU was parked on the `HALT` at `paso`, the exact board state that produces that
frame type was rigged, and the loop was stepped one opcode at a time with
`reset-tstates-partial` / `run 1` / `get-tstates-partial` around every step. Steps landing below
`$4000` were attributed to the ROM handler and counted separately.

Per-instruction timings were verified textbook (LDIR 21/16, `add hl,bc` 11, `ex de,hl` 4,
`dec a` 4, `jr` 12/7), confirming ZEsarUX applies no contention in step mode — hence "these numbers
are floors" in §2.

The beeper figures come from an isolated benchmark assembled separately and loaded at `$C000`,
never part of the game image and not left in the tree. Both driver loops were stepped for a known
number of half-periods and the cost fitted against the delay constant.

Benchmark scripts were kept outside the repository. The only changes to the tree from this work are
the `bajar_filas` fix, its regression test, the runner entry, and the two skill documents corrected
to match.
