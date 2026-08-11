---
name: game-loop-and-collision
description: Use when editing the fall loop in juego.asm, calling or debugging comprobar in test_col.asm, fixing pieces that pass through walls or into settled blocks, ordering input and rotation against the collision check, wiring up game over, or bounding horizontal movement.
---

# Game loop and collision ordering

`juego.asm` (144 lines) is the entire game loop. `test_col.asm` is correct and must not be "fixed".
**Every collision bug is a call-ordering bug.** This file also owns the two routines the loop leans
on, now shipped in `entrada.asm`: the column-bounds test `en_rango` and the non-blocking key read
`leer_teclas` (both in §7) — mostly edge-detected, except for one level-triggered bit that drives
soft drop (§2, §6).

The loop was rebuilt around one rule, stated at the top of `juego.asm:3-6`:

> **Test the exact position you are about to draw, with the exact `IX` you are about to draw.**

Everything below either states that rule or records what breaking it did.

## Vocabulary

`B`/`C` are 8-bit registers holding the piece's row (0 = top) and column (0 = left); `IX` points at
the current piece's 12-byte record (`piece-data-and-spawn`). An attribute byte describes one 8x8
screen cell at `$5800 + row*32 + col`; non-zero = solid. `or a` sets the zero flag when `A` is 0 and
does not change `A`; `jr z, L` jumps when that flag is set, `jr nz, L` when it is clear; `0 - 1`
wraps to `255`. Spanish: `iniciar` = start, `paso` = step/pass (the frame loop), `sin_gravedad` /
`sin_lateral` / `sin_giro` = without gravity / sideways / rotation, `dibujar` = draw,
`fin_partida` = end of the game session, `comprobar` = check (the collision routine), `GIRAR` =
rotate, `Medio` = middle (the memory copy of the column, `variables.asm:36`), `en_rango` = in range,
`leer_teclas` = read keys, `caida rapida` = fast fall (soft drop, SPACE). The attribute file **is**
the board: interior = columns 7-24, rows 0-21, border at columns 6 and 25, floor at row 22
(`tableroJuego.asm:8,19,30`). See `memory-map`.

## 1. `comprobar` — the contract (verified `test_col.asm:3-57`)

**In:** `B` = row, `C` = column, `IX` = piece record. **Out:** `A = 1` if any non-empty piece cell
overlaps a **non-zero** attribute byte, else `A = 0`. **Preserves** `BC`, `DE`, `HL`, `IX`, `IY`
(pushed `:4-8`, popped `:50-55`); **destroys `AF` only**, deliberately — `A` is the return channel,
so `AF` is not pushed and you must never add `push af` to "balance" it (`register-protocol`).

It points `IY` at the piece pattern, so it brackets that window with `di` (`:9`) / `ei` (`:54`),
the `ei` landing immediately after `pop iy`. Leave that bracket alone — `interrupts-and-timing` §1.

**Invariant: "occupied" means "attribute byte != 0".** The border and floor are walls for free, and
*any* non-zero attribute is solid geometry, including printed text — never print into rows 0-22 /
columns 6-25. `comprobar` tests exactly the `(B, C, IX)` you hand it, correctly; if a piece goes
*through* a wall, you called it with the wrong `B`, `C` or `IX`.

**It is not a bounds test.** It sees the border only because that byte is non-zero, so a candidate
that *jumped over* the border reads empty cells outside the well and is **accepted** — a ±2 rotation
kick from column 24 with a 1-wide record tests column 26 and passes. `en_rango` (§7) catches that.
Use both, never one instead of the other.

## 2. One pass of the loop (`juego.asm:42-141`)

`paso` runs **once per 50 Hz frame**, opening with `HALT` (`interrupts-and-timing` §5). Each pass
does at most three things — a sideways move, a rotation, a one-row fall — and each is a *candidate*
that is validated before anything is drawn. The pass draws exactly once, at `dibujar` (`:139`).

| Step | Lines | What it does |
|---|---|---|
| Read input | `:43-52` | `HALT`, `H = 0`, then `leer_teclas` once — **before** the gravity gates, on purpose (see below) |
| Gravity gate, normal | `:54-60` | Decrement `contador_frames`, held or not; `H = 1` and reload on the pass that owes a row |
| Gravity gate, soft drop | `:61-70` | Only if `E` bit4 (SPACE) is set: decrement `contador_rapido`; `H = 1` and reload when it hits zero. **Adds** a drop opportunity, never replaces the normal one (§6) |
| Erase | `:72` | `borrar_tetromino` at the **current** `(B, C)` with the **current** `IX` |
| Sideways | `:74-102` | `D` = −1/0/+1 from `E` bits0-1; candidate `C`, then `en_rango` **then** `comprobar`; on failure restore `C` and fall through — the pass's gravity still runs |
| Rotate | `:105-114` | `GIRAR` with the direction in `A`, from `E` bits2-3. It validates, kicks and commits **by itself** |
| Gravity apply | `:116-137` | If `H`, `inc b` and `comprobar`; free → committed, blocked → `dec b`, lock, clear lines, score, spawn |
| Draw | `:139-141` | One `pintar_tetromino` of the validated `(B, C, IX)`, then back to `paso` |

Register roles across a pass, from `juego.asm:8-15`: `B` row, `C` column, `IX` piece record, `D` the
sideways delta, `H` the gravity flag. `E` holds `leer_teclas`'s mask and carries **two different
conventions in one byte**: bits0-3 (K/J/Q/W) are edge-triggered — new-press only, consumed by
Sideways and Rotate exactly as before — while bit4 (SPACE) is level-triggered — 1 on **every** pass
it is held, not just the first — consumed only by the soft-drop gate. `HL`, `DE` and `AF` are free
for callees; `B`, `C` and `IX` are not. `H` survives because every routine the loop calls preserves
`HL`.

**Ordering invariants — break any one and the board corrupts:**

1. Erase happens **before** `IX` or `C` changes, so it blanks exactly the cells it drew.
2. Every candidate column passes `en_rango` **and then** `comprobar`; neither alone is enough (§1).
3. `(Medio)` is written on every commit, so `C` and `(Medio)` agree at every `comprobar`.
4. A rejected move or rotation restores the old value and **falls through** to gravity. Only a
   rejected *downward* candidate locks the piece.
5. `GIRAR` is never wrapped in an outer `comprobar` (§6, `piece-rotation` §5).
6. `leer_teclas` runs **before** both gravity gates, not after the erase like the other reads used
   to. It is safe to move earlier because `borrar_tetromino` preserves `DE` (`register-protocol`),
   and it has to run there: the soft-drop gate needs bit4 for *this* pass, not the previous one, or
   pressing and releasing SPACE would each lag by a frame instead of taking effect immediately.

### What this replaced, and why it matters when you edit

The original loop called `comprobar` with the *previous* pass's column and ran `GIRAR` *after* the
check, so it validated a position the piece never occupied; pieces were drawn over the border, the
next erase punched permanent holes in the wall, and `Medio` was unbounded so a piece could be walked
clean off the board. Its labels were inverted too — `cambiar_tetromino` ("change tetromino") was the
keep-falling path. **None of those labels exist any more.** `failure-patterns` §3.5 records the
regression; the reason to remember it is that reintroducing input *after* the check is the single
easiest way to undo this file.

## 3. Game over and the exits

`fin_partida:` (`juego.asm:143`) is `JP Pantalla_Final` — **`JP`, not `CALL`**, because it never
returns. It is reached from two places, both of which test the newly spawned piece at its real
spawn position, row 0: `:35-37` for the first piece of a game and `:135-137` after every lock.

The path back: `Pantalla_Final` (`pantallas.asm:27`) prints, waits for a key, and does
`jp inicializar` (`:53`). `inicializar` (`main.asm:14`) re-sets `SP` before anything else, which is
what keeps a long session from leaking the stack — nothing pops the frames a `CALL`-based restart
would leave, and `LD SP, 0` means there is no BASIC frame to return to anyway.

`main.asm:27` has `fin_del_programa: jr fin_del_programa` after `CALL iniciar`. `iniciar` should
never return; that terminator is there because without it a return fell straight into
`InicioDePantalla`, the first byte of the next `INCLUDE`. **Keep it.** The other exit is **N** at the
menu, which reaches `FinDelJuego` (`pantallas.asm:58`) and its deliberate `fin: JR fin` hang.

## 4. Sideways movement — bounded by two tests, not one

There is no `MOVER` and no `movimiento.asm` any more; the move is inline at `juego.asm:74-102`.
`D` is the delta, `C` becomes the candidate, and **both** tests must pass:

```asm
    ld a, c : add a, d : ld c, a   ; :86-88 candidate column
    call en_rango : or a           ; :89-91 1. still inside columns 7-24?
    jr nz, lat_no
    call comprobar : or a          ; :92-94 2. clear of settled blocks?
    jr z, lat_si
lat_no:
    ld a, c : sub d : ld c, a      ; :95-99 blocked: old column back, gravity still runs
    jr sin_lateral
lat_si:
    ld a, c : ld (Medio), a        ; :100-102 committed: keep Medio in sync
```

`en_rango` is mandatory because `comprobar` is not a bounds test: it sees the border only because
that byte is non-zero, so a candidate that *jumped over* the border reads empty cells outside the
well and would be accepted (§1). The old code had neither test — `Medio` was a free-running byte
that wrapped `255 → 0`.

## 5. What each routine owns

| Concern | Owner | Notes |
|---|---|---|
| Overlap with settled blocks and the border | `comprobar` (`test_col.asm`) | Exact `(B, C, IX)`; no geometry |
| Column bounds for the whole piece | `en_rango` (`entrada.asm:63`) | Uses `(ix+1)`, the width |
| Rotation: recentre, kick, validate, commit | `GIRAR` (`giro.asm`) | Self-contained; do not re-test it |
| Which keys are newly pressed, and whether SPACE is held now | `leer_teclas` (`entrada.asm:24`) | One call per pass, never blocks; bits0-3 edge, bit4 level |
| When a row is owed (normal gravity) | `contador_frames` / `FRAMES_POR_FILA` | `interrupts-and-timing` §5 |
| When a row is owed (soft drop, SPACE held) | `contador_rapido` / `FRAMES_CAIDA_RAPIDA` (`juego.asm:17`) | Only decrements while held; frozen (not reset) on release, so it resumes where it left off next time |
| Clearing and compacting rows | `limpiar_lineas` (`lineas.asm`) | Returns the count in `A` |
| Score, lines, level, speed, display | `anotar_lineas` (`puntuacion.asm`) | Consumes that count |

Adding a new action to the pass means adding a candidate that follows invariant 2 and 3, not a new
place that writes `C`.

## 6. The loop as it stands

> **Rule: test the exact position you are about to draw, with the exact `IX` you are about to draw.**

This is `juego.asm` as shipped, lightly condensed. Read it as the shape any edit must preserve.

```asm
iniciar:
    call iniciar_secuencia  ; seed the LFSR and announce the first piece
    call reiniciar_marcador ; score/lines/level to zero + labels. The ONLY free place to
                            ;   print: no piece exists yet (scoring-and-level §5)
    call seleccionar_pieza  ; IX = piece record, B = 0, C = 15
    call pintar_siguiente   ; show the piece queued behind it
    ld a, c : ld (Medio), a ; Medio always mirrors C
    call comprobar          ; game over test AT THE SPAWN POSITION (row 0), never row 255
    or a : jp nz, fin_partida
    call pintar_tetromino   ; draw once, so the loop's first erase has something to erase
paso:                       ; ---------------- one pass ----------------
    HALT                    ; sleep to the 50 Hz tick; returns in the top border
    ld h, 0                 ; frame gate: H = 1 only when a row is owed this pass

    call leer_teclas        ; §7: A = K/J/Q/W new-press (bits0-3) + SPACE held-NOW (bit4).
    ld e, a : ld d, 0       ; Read BEFORE the gates on purpose: the soft-drop gate below
                            ;   needs bit4 for THIS pass. borrar_tetromino preserves DE,
                            ;   so E survives it (register-protocol). D = sideways delta.

    ld a,(contador_frames) : dec a : ld (contador_frames), a  ; NORMAL gravity: always
    jr nz, comprobar_rapida                                   ;   counts, held or not, so
    ld a,(FRAMES_POR_FILA) : ld (contador_frames), a          ;   releasing SPACE resumes
    ld h, 1                                                   ;   exactly where it left off
comprobar_rapida:
    bit 4, e : jr z, sin_gravedad     ; RAPID gravity (soft drop): ADDS a drop opportunity,
    ld a,(contador_rapido) : dec a    ;   never replaces the normal one. Only ticks while
    ld (contador_rapido), a          ;   SPACE is held -- frozen, not reset, on release, so
    jr nz, sin_gravedad               ;   the next hold resumes this same countdown.
    ld a, FRAMES_CAIDA_RAPIDA
    ld (contador_rapido), a
    ld h, 1
sin_gravedad:
    call borrar_tetromino   ; erase at the CURRENT (B, C) with the CURRENT IX

    bit 0,e : jr z, no_der
    inc d                   ; K -> one column right
no_der: bit 1,e : jr z, lateral
    dec d                   ; J -> one column left (both keys at once cancel: D = 0)
lateral: ld a, d : or a : jr z, sin_lateral
    ld a, c : add a, d : ld c, a  ; C = candidate column
    call en_rango : or a          ; 1. still inside columns 7-24?  (§7)
    jr nz, lat_no
    call comprobar : or a         ; 2. clear of settled blocks?    (§1)
    jr z, lat_ok
lat_no: ld a, c : sub d : ld c, a ; blocked -> old column back; do NOT skip gravity
    jr sin_lateral
lat_ok: ld a, c : ld (Medio), a   ; keep Medio in sync on every commit (register-protocol)
sin_lateral:
    ld a, e : and %00001100 : jr z, sin_giro  ; neither Q nor W is newly pressed
    bit 2,e : ld a, 0       ; Q -> A = 0, rotate left (`ld` does not disturb the flags)
    jr nz, girar_ya
    inc a                   ; W -> A = 1, rotate right
girar_ya: call GIRAR        ; bounds-checks, kicks, validates and COMMITS by itself.
sin_giro:                   ;   NEVER wrap it in comprobar (piece-rotation §5).
    ld a, h : or a
    jr z, dibujar           ; not a gravity pass: input and redraw only
    inc b                   ; B = candidate row (gravity)
    call comprobar
    or a : jr z, dibujar    ; free -> the fall is committed
    dec b                   ; blocked -> undo the fall: the piece rests here
    call pintar_tetromino   ; lock it into the attribute file
    call limpiar_lineas     ; A = rows cleared, 0..4          (`line-clear`)
    call anotar_lineas      ; score, level, speed, scoreboard  (`scoring-and-level`)
    call seleccionar_pieza  ; IX = next piece, B = 0, C = 15
    call pintar_siguiente   ; refresh the preview box
    ld a, c : ld (Medio), a
    call comprobar          ; game over = the new piece does not fit at row 0
    or a : jp nz, fin_partida
dibujar:
    call pintar_tetromino   ; draw the committed (B, C, IX)
    jp paso                 ; jp, not jr: paso is out of an 8-bit relative jump's range
fin_partida:
    jp Pantalla_Final       ; jp, NOT call — it never returns (§3)
```

`FRAMES_CAIDA_RAPIDA` (`juego.asm:17`, `EQU 4`) is chosen faster than any normal-gravity level —
`FRAMES_POR_NIVEL` (`puntuacion.asm:16`) never goes below 6 — but is not instantaneous: 4 frames/row
is a soft drop, not a hard drop (out of scope; flagged as a possible follow-up, not built). The two
`jr`s that became `jp` (`iniciar`'s game-over check and `dibujar`'s loop-back) are a direct
consequence of this code growing: both targets ended up more than 127 bytes away once the soft-drop
gate was inserted between them, and `sjasmplus` refuses to assemble an out-of-range `jr`. If you add
more code to `paso`, watch for this again — it fails loudly at build time, not silently.

A failed sideways move or a failed rotation **restores the old value and falls through** to gravity;
only a failed *downward* candidate locks the piece. **Rotation is self-validating:** an outer
`comprobar` around `GIRAR` re-tests a position it already accepted and committed, and the `push ix` /
`pop ix` rollback around it can never run.

## 7. The two routines the loop leans on — `entrada.asm`

Input used to be read inside `MOVER` and `GIRAR`, each of which then spun in a key-release loop
before returning: one action per keypress, and **holding a key froze gravity and rendering**. Both
routines are gone. `leer_teclas` replaces the reads — one call per pass — and `GIRAR` now takes its
direction in `A`.

`leer_teclas` mixes **two different conventions in one returned byte**. Bits0-3 (K/J/Q/W) report
only the not-pressed → pressed transition, exactly as before: hold the key and they read `0` again
next pass. Bit4 (SPACE, soft drop) is deliberately the opposite — **level-triggered**, `1` on every
single pass the key is down, `0` the instant it releases — because `juego.asm`'s fast-gravity gate
(§2, §6) needs to know "is it down *right now*", not "did it just go down". Reusing the edge
convention for SPACE would make holding it drop one extra row on the press and then do nothing,
which is a one-shot action, not soft drop.

Both routines below are the shipped source (`entrada.asm:24-75`), reproduced so the contracts are
readable here. Edit the file, not this copy.

```asm
; leer_teclas ("read keys") — non-blocking. Call ONCE per pass. Mixes two
;   conventions in the same byte:
;   OUT: A = bit0 K right, bit1 J left, bit2 Q rotate-left, bit3 W rotate-right --
;            EDGE: 1 only on the pass each went UP -> DOWN, like before.
;        A = bit4 SPACE (soft drop) --
;            LEVEL: 1 on EVERY pass it is held, 0 the instant it releases.
;        A = 0 = no new key and SPACE not held.
;   Preserves BC, DE, HL, IX, IY. Destroys AF.
leer_teclas:
    push bc : push de : push hl
    ld bc, $BFFE : in a,(c) ; half-row ENTER L K J H. ACTIVE LOW: a pressed key reads as 0,
    cpl                     ;   so invert — now 1 = down. K is bit2, J is bit3.
    rrca : rrca : and %00000011   ; slide them down: bit0 = K, bit1 = J
    ld e, a
    ld bc, $FBFE : in a,(c) ; half-row Q W E R T: Q is bit0, W is bit1
    cpl
    rlca : rlca : and %00001100   ; slide them up: bit2 = Q, bit3 = W
    or e : ld e, a          ; E = K/J/Q/W, 1 = down NOW
    ld bc, $7FFE : in a,(c) ; half-row SPACE SYM-SHIFT M N B: SPACE is bit0
    cpl
    and %00000001           ; isolate SPACE
    rlca : rlca : rlca : rlca     ; slide it up to bit4
    or e : ld e, a          ; E = current mask, ALL five bits, 1 = down NOW --
                            ;   this is level state, not yet edge-detected
    ld hl, teclas_ant       ; one byte: the same mask from the previous call
    ld a,(hl) : ld (hl), e  ; read the old mask, store the new one
    cpl : and e             ; up last time AND down now = a NEW press -- valid
                            ;   for bits0-3, but bit4 would edge-trigger too
    and %00001111           ; keep only the K/J/Q/W edge bits
    ld d, a
    ld a, e
    and %00010000           ; A = SPACE's CURRENT level state (bit4), not its edge
    or d                    ; bits0-3 edge, bit4 level
    pop hl : pop de : pop bc
    ret

; en_rango ("in range") — is column C legal for the WHOLE piece IX? §1 explains why
;   comprobar cannot answer this. Call it FIRST, then comprobar; both must pass.
;   IN : C = candidate column, IX = record; (ix+1) = the piece's width in cells.
;   OUT: A = 0 legal, A = 1 outside. Preserves BC, DE, HL, IX, IY. Destroys AF.
en_rango:
    ld a, c
    cp COL_IZQ_POZO         ; 7 = leftmost interior column (entrada.asm:6)
    jr c, er_fuera          ; C < 7 -> left of the left wall
    add a,(ix+1)            ; A = C + cols
    jr c, er_fuera          ; 8-bit wrap: C was far out of range
    cp COL_DER_POZO + 2     ; rightmost cell is C+cols-1 and must be <= 24,
    jr nc, er_fuera         ;   i.e. C+cols < 26
    xor a : ret             ; A = 0: every cell is inside columns 7-24
er_fuera:
    ld a, 1 : ret
```

`teclas_ant` is one byte declared in `variables.asm` with every other mutable byte (`memory-map` §6)
— do not add a variable block anywhere else. Its initial value is `0` because `leer_teclas`'s mask
is already inverted: **1 = pressed**, now for all five tracked keys including SPACE. `en_rango` is
unchanged by soft drop — it only ever sees columns, never gravity. `tests/test_entrada.py` covers
the K/J/Q/W edge detection (a held key must not repeat, neighbouring keys on the same half-rows must
not leak), SPACE's level detection (reports held on every pass, not just the first, and clears the
instant it releases, without disturbing the edge bits), and `en_rango`'s boundaries for 1-, 2- and
4-wide pieces.

## Common mistakes

1. Committing a candidate position before testing it. Write `C`, test, and restore on failure.
2. Testing one position and drawing another — the regression this loop was rebuilt to remove (§2).
3. Letting a failed sideways move or rotation skip that pass's gravity. It must fall through.
4. Using `comprobar` as a bounds test, or `en_rango` as a collision test — neither is enough alone.
5. Re-testing `GIRAR`'s result with `comprobar`. It self-validates, kicks and commits (§6).
6. Forgetting `ld (Medio), a` when `C` changes: erase and draw then use different columns → ghosts.
7. "Balancing" `comprobar`'s pushes with `push af`, which destroys its return value.
8. Turning `JP Pantalla_Final` into a `CALL`, or `jp inicializar` into a `call`. Neither returns;
   both would leak stack on every game (§3).
9. Doing work between `HALT` and the erase/redraw pair. That window is the only place a write is
   invisible (`interrupts-and-timing` §2).
10. Reading a keyboard port inside the loop instead of using `E` from the single `leer_teclas` call —
    it reintroduces the blocking freeze and costs `BC` (`memory-map` §7).
11. Treating SPACE (bit4) as edge-triggered like K/J/Q/W, or computing it through the same
    `cpl(old) and new` edge formula. Soft drop needs "is it down *this pass*", not "did it just go
    down"; an edge-triggered SPACE would drop one extra row per press and do nothing while held.
12. Moving the `leer_teclas` call back to after the erase (where every other read used to live).
    `borrar_tetromino` preserves `DE` so the reorder is safe forward, but reordering it back
    introduces a frame of lag on the soft-drop gate, since it would then read last pass's SPACE
    state instead of this pass's.
13. Making `contador_rapido` reset to `FRAMES_CAIDA_RAPIDA` when SPACE is *released*, or decrement
    it while SPACE is *not* held. Either breaks "releasing returns to normal speed immediately" or
    "holding resumes where the last hold left off" (§6).

Related: `register-protocol` (clobbers), `memory-map` (geometry, `variables.asm`), `piece-rotation`
(`GIRAR`), `line-clear` and `scoring-and-level` (the lock-path hooks), `interrupts-and-timing` (frame
gate, `IY` brackets), `failure-patterns` (the regression this loop replaced).
