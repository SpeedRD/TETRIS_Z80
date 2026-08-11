---
name: game-loop-and-collision
description: Use when editing the fall loop in juego.asm, calling or debugging comprobar in test_col.asm, fixing pieces that pass through walls or into settled blocks, ordering input and rotation against the collision check, wiring up game over, or bounding horizontal movement in movimiento.asm.
---

# Game loop and collision ordering

`juego.asm` (51 lines) is the entire game loop and the most damaged file in the project.
`test_col.asm` is correct and must not be "fixed". **Every collision bug is a call-ordering bug.**
This file also owns the two routines the loop needs and nobody has written: the column-bounds test
`en_rango` and the non-blocking, edge-detected key read `leer_teclas` (both in §7).

## Vocabulary

`B`/`C` are 8-bit registers holding the piece's row (0 = top) and column (0 = left); `IX` points at
the current piece's 12-byte record (`piece-data-and-spawn`). An attribute byte describes one 8x8
screen cell at `$5800 + row*32 + col`; non-zero = solid. `or a` sets the zero flag when `A` is 0 and
does not change `A`; `jr z, L` jumps when that flag is set, `jr nz, L` when it is clear; `0 - 1`
wraps to `255`. Spanish: `iniciar` = start, `ciclo_juego` = game cycle, `siguiente_juego` = next
step, `cambiar_tetromino` = change tetromino, `comprobar` = check (the collision routine), `MOVER` =
move, `GIRAR` = rotate, `Medio` = middle (the current column, `piezas.asm:31`), `Tiempo` = time
(busy-wait), `en_rango` = in range, `leer_teclas` = read keys. The attribute file **is** the board:
interior = columns 7-24, rows 0-21, border at columns 6 and 25, floor at row 22
(`tableroJuego.asm:8,19,30`). See `memory-map`.

## 1. `comprobar` — the contract (verified `test_col.asm:3-55`)

**In:** `B` = row, `C` = column, `IX` = piece record. **Out:** `A = 1` if any non-empty piece cell
overlaps a **non-zero** attribute byte, else `A = 0`. **Preserves** `BC`, `DE`, `HL`, `IX`, `IY`
(pushed `:4-8`, popped `:49-53`); **destroys `AF` only**, deliberately — `A` is the return channel,
so `AF` is not pushed and you must never add `push af` to "balance" it (`register-protocol`).

**Invariant: "occupied" means "attribute byte != 0".** The border and floor are walls for free, and
*any* non-zero attribute is solid geometry, including printed text — never print into rows 0-22 /
columns 6-25. `comprobar` tests exactly the `(B, C, IX)` you hand it, correctly; if a piece goes
*through* a wall, you called it with the wrong `B`, `C` or `IX`.

**It is not a bounds test.** It sees the border only because that byte is non-zero, so a candidate
that *jumped over* the border reads empty cells outside the well and is **accepted** — a ±2 rotation
kick from column 24 with a 1-wide record tests column 26 and passes. `en_rango` (§7) catches that.
Use both, never one instead of the other.

## 2. The current loop, traced (`juego.asm:14-45`)

```asm
ciclo_juego:
    ld a, b
    cp $FF
    jr z, siguiente_juego  ; :18 skip erase on the first step (row 255, nothing drawn yet)
    CALL borrar_tetromino: ; :20 erase at (B,C) with current IX — this part is consistent
siguiente_juego:
    inc b                  ; :23 B = candidate row. Good: gravity IS tested as a candidate.
    ld d, b                ; :24 DEAD — D is written here and never read anywhere.
    ld a, (Medio)
    ld e, a                ; :26 E = redundant copy of Medio; its only use is "ld c, e".
    call comprobar         ; :29 uses B (new row) and C (LAST iteration's column) <-- DEFECT 1
    or a                   ; :30 zero flag set when A = 0, i.e. NO collision
    jr z, cambiar_tetromino ; :32 no collision -> "change tetromino"?? see section 3
    dec b                  ; :34 collision: undo the fall. This is the LOCK path.
    ld c, e                ; :35 column committed only now, after the test
    call pintar_tetromino  ; :36 paint the landed piece
    jr iniciar             ; :37 spawn the next piece (re-enters iniciar — see section 4)
cambiar_tetromino:         ; this is the KEEP FALLING path
    ld c, e                ; :40 column committed only now, after the test
    call GIRAR             ; :41 IX changed AFTER comprobar ran <-- DEFECT 2
    call pintar_tetromino  ; :42 draws a new column and a new shape; neither was tested
    call Tiempo            ; :43 busy-wait
    call MOVER             ; :44 reads keys, writes (Medio); applied on the NEXT iteration
    jr ciclo_juego
```

- **Defect 1 — stale `C`.** `MOVER` (`:44`) updates `Medio`, but `C` receives it at `:35`/`:40` *after*
  `comprobar` ran, so a sideways move is tested one iteration later, at a different row.
- **Defect 2 — `GIRAR` after `comprobar`.** The rotated shape is never tested (`piece-rotation`).
- **Defect 3 — dead registers.** `D` (`:24`) written, never read; `E` (`:26`) a redundant copy of
  `Medio` — leftovers from the pre-regression ordering (`failure-patterns` §3.5).

**Result:** a piece walked into the border is drawn over the wall, the next erase punches a permanent
hole in it, and the piece is deposited *outside* the well.

## 3. The labels are inverted — do not trust them

`comprobar` returns **0 for no collision**, so `jr z` is the "free" branch. `cambiar_tetromino`
(`:39`) does **not** change the tetromino: it is the **keep-falling** path (commit, rotate, draw,
wait, read keys, loop), and the fall-through at `:34-37` is **lock-and-spawn**. Rename while editing:
`cambiar_tetromino` -> `keep_falling`, `:34` -> `lock_and_spawn`, `siguiente_juego` -> `gravity_step`,
`end` -> `game_over`.

## 4. Game over is broken twice, and its exit is a trap

**(a) The check reads RAM outside the screen** (`juego.asm:3-12`):

```asm
    CALL seleccionar_pieza ; :4  returns IX = piece, B = 0, C = 15 (tetromino_next.asm:24-25)
    LD B, 255              ; :6  B overwritten with 255; C is left at 15
    CALL comprobar         ; :10 tests (B=255, C=15)
    or a : jr nz, end      ; :11-12 non-zero -> "game over" -> the ret at :48
```

`C` is **not** uninitialised: `seleccionar_pieza` sets it to 15 on every spawn (`tetromino_next.asm:25`).
`CalcularAtributo` (`pantallas.asm:67-80`) with `B=255, C=15` gives `H = 255>>3 = $1F`, `A = 255<<5 =
$E0`, `L = $E0 or $0F = $EF`, so `HL = $1FEF + $5800 =` **`$77EF`** — outside the attribute file
(`$5800-$5AFF`), i.e. uninitialised RAM, read on **every** spawn (`:37` jumps back to `iniciar`):

- Garbage non-zero -> `jr nz, end` -> `ret` -> the game "ends" at startup.
- Garbage zero -> play proceeds with **no other game-over check anywhere**. When the stack reaches the
  top, `comprobar` at row 0 reports collision, `:34` does `dec b` (`0 -> 255`), and `pintar_tetromino`
  paints at `$77E0 + Medio` — into RAM — forever. With `Medio = 15` that write lands on `$77EF` itself,
  so after one overflow the startup check can start firing at random.

**(b) `main.asm` has no terminator.** `CALL iniciar` is `main.asm:14`; the next line is
`INCLUDE "titulo.asm"` (`main.asm:19`), whose first byte is `InicioDePantalla` (`titulo.asm:3`), so
when `iniciar` returns execution **falls into the title-screen routine**. Fix: put
`fin_del_programa: jr fin_del_programa` (or `halt`) immediately after `CALL iniciar`. `LD SP, 0`
(`main.asm:5`) destroyed the BASIC return address, so it must be a halt or an infinite loop, **never
a `ret`**.

**(c) The game-over screen exists but never comes back.** `Pantalla_Final` (`pantallas.asm:27`) is
complete and never called (`failure-patterns` §3.7); wiring it up is one instruction. But it ends with
`call inicializar` (`pantallas.asm:53`), which **restarts the whole game** from `main.asm:9`: anything
after `call Pantalla_Final` — a following `jr game_over` included — is **dead code**, and each restart
pushes a return address nobody pops, leaking stack under `LD SP, 0`. Use **`jp Pantalla_Final`**.
`LeerTecla` (`pantallas.asm:89-93`) likewise jumps to `FinDelJuego` on **N** and never returns.
`failure-patterns` §3.7 has both defects, plus the duplicated `MensajeGameOver` load (`:34`, `:41`).

## 5. Movement is unbounded (`movimiento.asm`)

`Medio` is incremented at `:20-22` and decremented at `:28-30` with **no clamp and no collision
test**. It is one byte: it walks past column 25, past 31 into the next attribute row, and wraps
`255 -> 0`; `CalcularAtributo` computes an address for any `C` and `pintar_tetromino` writes there.
`movimiento.asm:16-17` is `BIT 0,A` followed by an **unconditional** `JR no_tecla_move` — the flag
`BIT` just set is discarded, almost certainly a `JR Z` that lost its condition (`:24-25` and `:32-33`
are unreachable `POP BC / RET` after unconditional jumps). Do not patch `movimiento.asm` in place:
§6 replaces it with a *tested candidate* column and §7 replaces its blocking key read. Every
candidate column — sideways moves and rotation kicks alike — must pass `en_rango` (§7) **as well as**
`comprobar`, which still owns overlap with settled blocks.

## 6. The playbook — the correct loop

> **Rule: test the exact position you are about to draw, with the exact `IX` you are about to draw.**

```asm
iniciar:
    call seleccionar_pieza  ; IX = piece record, B = 0, C = 15
    ld a, c : ld (Medio), a ; Medio always mirrors C
    call comprobar          ; game over test AT THE SPAWN POSITION (row 0), never row 255
    or a : jr nz, game_over
    call pintar_tetromino   ; draw once, so the loop's first erase has something to erase
paso:                       ; ---------------- one pass ----------------
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
    ; FRAME GATE goes here: HALT + gravity frame counter (`interrupts-and-timing` §5). Until
    ; it ships, gravity runs every pass and `call Tiempo` below is the (bad) delay.
    inc b                   ; B = candidate row (gravity)
    call comprobar
    or a : jr z, dibujar    ; free -> the fall is committed
    dec b                   ; blocked -> undo the fall: the piece rests here
    call pintar_tetromino   ; lock it into the attribute file
    ; HOOK: call limpiar_lineas (`line-clear`), then score / level (`scoring-and-level`)
    call seleccionar_pieza  ; IX = next piece, B = 0, C = 15
    ld a, c : ld (Medio), a
    call comprobar          ; game over = the new piece does not fit at row 0
    or a : jr nz, game_over
dibujar:
    call pintar_tetromino   ; draw the committed (B, C, IX)
    call Tiempo             ; TODO: delete when the frame gate ships
    jr paso
game_over:
    jp Pantalla_Final       ; jp, NOT call — it never returns (§4c)
```

A failed sideways move or a failed rotation **restores the old value and falls through** to gravity;
only a failed *downward* candidate locks the piece. **Rotation is self-validating:** an outer
`comprobar` around `GIRAR` re-tests a position it already accepted and committed, and the `push ix` /
`pop ix` rollback around it can never run.

## 7. The two routines the loop needs

`MOVER` (`juego.asm:44`) and `GIRAR` (`:41`) are polled once per gravity tick and each spins in a
key-release loop (`movimiento.asm:37-40`, `giro.asm:33-36`) before returning: one action per keypress,
and **holding a key freezes gravity and rendering** (`interrupts-and-timing` §6). `leer_teclas`
replaces both reads — one call per pass, reporting only the not-pressed -> pressed transition.

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
    ld a, c : cp 7          ; 7 = leftmost interior column
    jr c, er_fuera          ; C < 7 -> left of the left wall
    add a,(ix+1)            ; A = C + cols
    jr c, er_fuera          ; 8-bit wrap: C was far out of range
    cp 26                   ; rightmost cell is C+cols-1, and must be <= 24
    jr nc, er_fuera
    xor a : ret             ; A = 0: every cell is inside columns 7-24
er_fuera:
    ld a, 1 : ret
```

`teclas_ant` is one byte declared in `variables.asm` with every other new variable (`memory-map` §6)
— do not add a variable block anywhere else. Put both routines in a new `entrada.asm` ("input") and
`INCLUDE` it in `main.asm`; `assembler-conventions` has the trailing-newline trap that silently drops
a new `INCLUDE`. Verified: sjasmplus 1.23.1, 0 errors / 0 warnings.

## Common mistakes

1. Committing a candidate position before testing it (`ld c, e` then `call comprobar`).
2. Testing the old position and drawing the new one — the current `:29` / `:36` pairing.
3. Letting a failed sideways move or rotation skip that pass's gravity. It must fall through.
4. Trusting the Spanish label names. `cambiar_tetromino` does not change the tetromino.
5. Using `comprobar` as a bounds test, or `en_rango` as a collision test — neither is enough alone.
6. Re-testing `GIRAR`'s result with `comprobar`. It self-validates, kicks and commits (§6).
7. Changing `LD B, 255` to `LD B, 0` and stopping — the `ret` at `juego.asm:48` still falls into the
   title screen until `main.asm:14` gets a terminator.
8. Forgetting `ld (Medio), a` when `C` changes: erase and draw then use different columns → ghosts.
9. "Balancing" `comprobar`'s pushes with `push af`, which destroys its return value.

Related: `register-protocol` (clobbers), `memory-map` (geometry, `variables.asm`), `piece-rotation`
(`GIRAR`), `line-clear` and `scoring-and-level` (the hooks), `interrupts-and-timing` (frame gate,
blocking-input timing), `failure-patterns` (the regression behind defects 1-3).
