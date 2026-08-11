---
name: game-loop-and-collision
description: Use when editing the fall loop in juego.asm, calling or debugging comprobar in test_col.asm, fixing pieces that pass through walls or into settled blocks, ordering input and rotation against the collision check, wiring up game over, or bounding horizontal movement.
---

# Game loop and collision ordering

`juego.asm` (124 lines) is the entire game loop. `test_col.asm` is correct and must not be "fixed".
**Every collision bug is a call-ordering bug.** This file also owns the two routines the loop leans
on, now shipped in `entrada.asm`: the column-bounds test `en_rango` and the non-blocking,
edge-detected key read `leer_teclas` (both in §7).

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
`leer_teclas` = read keys. The attribute file **is** the board: interior = columns 7-24, rows 0-21,
border at columns 6 and 25, floor at row 22 (`tableroJuego.asm:8,19,30`). See `memory-map`.

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

## 2. One pass of the loop (`juego.asm:34-118`)

`paso` runs **once per 50 Hz frame**, opening with `HALT` (`interrupts-and-timing` §5). Each pass
does at most three things — a sideways move, a rotation, a one-row fall — and each is a *candidate*
that is validated before anything is drawn. The pass draws exactly once, at `dibujar` (`:116`).

| Step | Lines | What it does |
|---|---|---|
| Frame gate | `:35-45` | `HALT`, then decrement `contador_frames`; `H = 1` only on the pass that owes a row |
| Erase | `:46` | `borrar_tetromino` at the **current** `(B, C)` with the **current** `IX` |
| Read input | `:48-49` | `leer_teclas` once; `E` holds the new-press mask for the rest of the pass |
| Sideways | `:50-80` | `D` = −1/0/+1; candidate `C`, then `en_rango` **then** `comprobar`; on failure restore `C` and fall through — the pass's gravity still runs |
| Rotate | `:82-91` | `GIRAR` with the direction in `A`. It validates, kicks and commits **by itself** |
| Gravity | `:93-114` | If `H`, `inc b` and `comprobar`; free → committed, blocked → `dec b`, lock, clear lines, score, spawn |
| Draw | `:116-118` | One `pintar_tetromino` of the validated `(B, C, IX)`, then back to `paso` |

Register roles across a pass, from `juego.asm:8-14`: `B` row, `C` column, `IX` piece record, `D` the
sideways delta, `E` the key mask, `H` the gravity flag. `HL`, `DE` and `AF` are free for callees;
`B`, `C` and `IX` are not. `H` survives because every routine the loop calls preserves `HL`.

**Ordering invariants — break any one and the board corrupts:**

1. Erase happens **before** `IX` or `C` changes, so it blanks exactly the cells it drew.
2. Every candidate column passes `en_rango` **and then** `comprobar`; neither alone is enough (§1).
3. `(Medio)` is written on every commit, so `C` and `(Medio)` agree at every `comprobar`.
4. A rejected move or rotation restores the old value and **falls through** to gravity. Only a
   rejected *downward* candidate locks the piece.
5. `GIRAR` is never wrapped in an outer `comprobar` (§6, `piece-rotation` §5).

### What this replaced, and why it matters when you edit

The original loop called `comprobar` with the *previous* pass's column and ran `GIRAR` *after* the
check, so it validated a position the piece never occupied; pieces were drawn over the border, the
next erase punched permanent holes in the wall, and `Medio` was unbounded so a piece could be walked
clean off the board. Its labels were inverted too — `cambiar_tetromino` ("change tetromino") was the
keep-falling path. **None of those labels exist any more.** `failure-patterns` §3.5 records the
regression; the reason to remember it is that reintroducing input *after* the check is the single
easiest way to undo this file.

## 3. Game over and the exits

`fin_partida:` (`juego.asm:120`) is `JP Pantalla_Final` — **`JP`, not `CALL`**, because it never
returns. It is reached from two places, both of which test the newly spawned piece at its real
spawn position, row 0: `:28-30` for the first piece of a game and `:112-114` after every lock.

The path back: `Pantalla_Final` (`pantallas.asm:27`) prints, waits for a key, and does
`jp inicializar` (`:53`). `inicializar` (`main.asm:14`) re-sets `SP` before anything else, which is
what keeps a long session from leaking the stack — nothing pops the frames a `CALL`-based restart
would leave, and `LD SP, 0` means there is no BASIC frame to return to anyway.

`main.asm:27` has `fin_del_programa: jr fin_del_programa` after `CALL iniciar`. `iniciar` should
never return; that terminator is there because without it a return fell straight into
`InicioDePantalla`, the first byte of the next `INCLUDE`. **Keep it.** The other exit is **N** at the
menu, which reaches `FinDelJuego` (`pantallas.asm:58`) and its deliberate `fin: JR fin` hang.

## 4. Sideways movement — bounded by two tests, not one

There is no `MOVER` and no `movimiento.asm` any more; the move is inline at `juego.asm:50-80`.
`D` is the delta, `C` becomes the candidate, and **both** tests must pass:

```asm
    ld a, c : add a, d : ld c, a   ; :63-65 candidate column
    call en_rango : or a           ; :66-67 1. still inside columns 7-24?
    jr nz, lat_no
    call comprobar : or a          ; :69-70 2. clear of settled blocks?
    jr z, lat_si
lat_no:
    ld a, c : sub d : ld c, a      ; :73-75 blocked: old column back, gravity still runs
    jr sin_lateral
lat_si:
    ld a, c : ld (Medio), a        ; :78-79 committed: keep Medio in sync
```

`en_rango` is mandatory because `comprobar` is not a bounds test: it sees the border only because
that byte is non-zero, so a candidate that *jumped over* the border reads empty cells outside the
well and would be accepted (§1). The old code had neither test — `Medio` was a free-running byte
that wrapped `255 → 0`.

## 5. What each routine owns

| Concern | Owner | Notes |
|---|---|---|
| Overlap with settled blocks and the border | `comprobar` (`test_col.asm`) | Exact `(B, C, IX)`; no geometry |
| Column bounds for the whole piece | `en_rango` (`entrada.asm:42`) | Uses `(ix+1)`, the width |
| Rotation: recentre, kick, validate, commit | `GIRAR` (`giro.asm`) | Self-contained; do not re-test it |
| Which keys are newly pressed | `leer_teclas` (`entrada.asm:17`) | One call per pass, never blocks |
| When a row is owed | `contador_frames` / `FRAMES_POR_FILA` | `interrupts-and-timing` §5 |
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
    or a : jr nz, fin_partida
    call pintar_tetromino   ; draw once, so the loop's first erase has something to erase
paso:                       ; ---------------- one pass ----------------
    HALT                    ; sleep to the 50 Hz tick; returns in the top border
    ld h, 0                 ; frame gate: H = 1 only when a row is owed this pass
    ld a,(contador_frames) : dec a : ld (contador_frames), a
    jr nz, sin_gravedad
    ld a,(FRAMES_POR_FILA) : ld (contador_frames), a
    ld h, 1
sin_gravedad:
    call borrar_tetromino   ; erase at the CURRENT (B, C) with the CURRENT IX
    call leer_teclas        ; §7: A = bitmask of NEW presses this pass; never blocks
    ld e, a : ld d, 0       ; E survives comprobar and GIRAR; D = the sideways delta
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
    or a : jr nz, fin_partida
dibujar:
    call pintar_tetromino   ; draw the committed (B, C, IX)
    jr paso
fin_partida:
    jp Pantalla_Final       ; jp, NOT call — it never returns (§3)
```

A failed sideways move or a failed rotation **restores the old value and falls through** to gravity;
only a failed *downward* candidate locks the piece. **Rotation is self-validating:** an outer
`comprobar` around `GIRAR` re-tests a position it already accepted and committed, and the `push ix` /
`pop ix` rollback around it can never run.

## 7. The two routines the loop leans on — `entrada.asm`

Input used to be read inside `MOVER` and `GIRAR`, each of which then spun in a key-release loop
before returning: one action per keypress, and **holding a key froze gravity and rendering**. Both
routines are gone. `leer_teclas` replaces the reads — one call per pass, reporting only the
not-pressed → pressed transition — and `GIRAR` now takes its direction in `A`.

Both routines below are the shipped source (`entrada.asm:17-54`), reproduced so the contracts are
readable here. Edit the file, not this copy.

```asm
; leer_teclas ("read keys") — non-blocking, edge-detected. Call ONCE per pass.
;   OUT: A = bitmask of the keys that went UP -> DOWN since the previous call:
;        bit0 = K right, bit1 = J left, bit2 = Q rotate-left, bit3 = W rotate-right.
;        A = 0 = nothing new. Preserves BC, DE, HL, IX, IY. Destroys AF.
leer_teclas:
    push bc : push de : push hl
    ld bc, $BFFE : in a,(c) ; half-row ENTER L K J H. ACTIVE LOW: a pressed key reads as 0,
    cpl                     ;   so invert — now 1 = down. K is bit2, J is bit3.
    rrca : rrca : and %00000011   ; slide them down: bit0 = K, bit1 = J
    ld e, a
    ld bc, $FBFE : in a,(c) ; half-row Q W E R T: Q is bit0, W is bit1
    cpl
    rlca : rlca : and %00001100   ; slide them up: bit2 = Q, bit3 = W
    or e : ld e, a          ; E = all four keys, 1 = down NOW
    ld hl, teclas_ant       ; one byte: the same mask from the previous call
    ld a,(hl) : ld (hl), e  ; read the old mask, store the new one
    cpl : and e             ; up last time AND down now = a NEW press
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
is already inverted: **1 = pressed**. `tests/test_entrada.py` covers the edge detection (a held key
must not repeat, neighbouring keys on the same half-rows must not leak) and `en_rango`'s boundaries
for 1-, 2- and 4-wide pieces.

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

Related: `register-protocol` (clobbers), `memory-map` (geometry, `variables.asm`), `piece-rotation`
(`GIRAR`), `line-clear` and `scoring-and-level` (the lock-path hooks), `interrupts-and-timing` (frame
gate, `IY` brackets), `failure-patterns` (the regression this loop replaced).
