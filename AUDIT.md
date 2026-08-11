# TETRIS_Z80 — Incoming-Engineer Audit

Audit of commit `0a2377e` ("raw state as pulled from Canvas", tag `school-submission`), the
only commit in the repository. Read-only pass; no source file was modified.

Line references are `file:line` against the working tree. Address references are taken from
`main.lst`, the assembler listing of the last full build.

---

## 1. Platform & Toolchain

### Target hardware

**ZX Spectrum 48K.** Identified from code, not assumed:

- `main.asm:3` — `DEVICE ZXSPECTRUM48`.
- `main.sld:2` declares `pages.size:16384, pages.count:4, slots.count:4, slots.adr:0,16384,32768,49152` — a 64K address space of four 16K slots, the 48K Spectrum layout.
- Video RAM at `$4000` (`titulo.asm:12`, `L30.3 - printat.asm:150`), attribute RAM at `$5800` (`pantallas.asm:77`, `tableroJuego.asm:8`), screen size 6912 bytes (`titulo.asm:13`). Spectrum-specific.
- Keyboard read via `IN A,(C)` on half-rows `$FBFE`, `$BFFE`, `$7FFE`, `$FDFE` (`giro.asm:9`, `movimiento.asm:10`, `pantallas.asm:90`, `pantallas.asm:94`). ULA keyboard matrix.
- `CRtoSCREEN` / `CRtoATTR` in `L30.3 - printat.asm` implement the Spectrum's non-linear
  `%010FF000 fffCCCCC` screen addressing.

### Assembler

**sjasmplus.** Evidence:

- `DEVICE ZXSPECTRUM48` is sjasmplus syntax.
- `.sld` files are sjasmplus's Source Level Debug output (`|SLD.data.version|1`).
- The listing format (`line addr bytes source`, `# file opened:` / `# file closed:` markers) is sjasmplus's.
- Warning ID syntax `warning[rdlow]:` in `juego.lst:32` is sjasmplus.
- `giro.asm:19` and `:26` write `LD IX, DE`, which is not a real Z80 instruction. The listing
  (`main.lst`, `A2A7`) shows it assembled to `DD 62 DD 6B` = `LD IXH,D : LD IXL,E`. This is
  sjasmplus's "fake instruction" extension. **The project will not build on an assembler
  without fake instructions enabled** (pasmo, z80asm, etc.). Same for `ld iy, ix`
  (`piezas.asm:44`, `clear.asm:13`, `test_col.asm:14`), assembled as `DD E5 FD E1` = `PUSH IX : POP IY`.

Dialect notes: mixed case throughout, `:` used both as label terminator and as an
instruction separator (`piezas.asm:5`, `pantallas.asm:72`), `#` and `$` both used as hex
prefixes in the same tree (`L30.3 - printat.asm` uses `#40`, everything else uses `$5800`).

### How it is currently built

**There is no build script, makefile, task runner, or editor config in the repository.** No
`Makefile`, `*.sh`, `*.bat`, `*.json`, no `.vscode/`. The build is whatever command the
original authors typed by hand.

What can be reconstructed from the committed artifacts:

- `main.asm` is the single translation unit; it `INCLUDE`s all twelve other `.asm` files
  (`main.asm:19-31`). Include order is load-bearing — see §3.
- Output is `main.bin`, 8903 bytes, `ORG $8000` → occupies `$8000-$A2C6`.
- The assembler was invoked with listing and SLD output enabled (`main.lst`, `main.sld` exist).
- **No `SAVESNA`, `SAVETAP`, `SAVEBIN`, or `EMPTYTAP` directive exists anywhere in the
  source.** The only build product is a raw binary. There is no tape image, snapshot, or
  BASIC loader in the repository.

### How it is actually run / tested today

**There is no test procedure. None. Not a weak one — none at all.** No test files, no test
harness, no assertions, no expected-output fixtures, no emulator scripts.

The run procedure is also not recorded, and must be inferred:

- `.tmp/disasm.list` (present, zero bytes) is an artifact created by **DeZog**, the VS Code
  Z80 debug extension. Together with the `.sld` files (DeZog's preferred symbol format for
  CSpect / ZEsarUX / the internal simulator), this is strong evidence the project was run
  under DeZog in VS Code.
- The DeZog `launch.json` that would specify the emulator, the load address, and the start PC
  **is not in the repository.** Whoever picks this up will have to recreate it.
- Because there is no snapshot or tape output, running requires manually loading `main.bin`
  at `$8000` and setting PC to `$8000`.

Practically: the only "testing" that has ever happened here is a human watching the screen.

### Repository hygiene

Committed build output and junk that should not be in version control:

- `main.bin`, `main.lst`, `main.sld` — build products.
- `caida.{bin,lst,sld}`, `clear.{bin,lst,sld}`, `juego.{bin,lst,sld}`, `pantallas.{bin,lst,sld}`,
  `piezas.{bin,lst,sld}` — **stale** build products from assembling individual files standalone.
  These are the single most valuable forensic artifact in the repo (§4) but are not part of the build.
- `.DS_Store`, `.tmp/disasm.list`.
- `Z80 Assembler mnemonic - Publicada.xlsx` (649 KB) — a course reference spreadsheet.
- `TETRIS2.scr` — a second 6912-byte screen, byte-different from `TETRIS.scr`, **never
  referenced by any source file.** Dead asset.

There is no `.gitignore` and no `README`.

---

## 2. Memory Map & Hardware Interfaces

### Address map

| Range | Contents | Notes |
|---|---|---|
| `$0000-$3FFF` | ZX Spectrum ROM | Not paged out. Relevant — see interrupts below. |
| `$4000-$57FF` | Pixel display file | Written by `CLEARSCR`, `PintarPantalla` (LDIR of `TETRIS.scr`), `Tetris_3D`. |
| `$5800-$5AFF` | Attribute file | **This is the game board.** All piece rendering and all collision detection operate on attribute bytes, not pixels. |
| `$5B00-$6FFF` | Unused | |
| `$7000-$7001` | `TIEMPO_CAIDA` | `caida.asm:10`. Hardcoded absolute address, no reservation, no symbol in the program image. |
| `$7002-$7003` | `NIVEL_ACTUAL` | `caida.asm:11`. **Never written by any code.** Read once at `caida.asm:22` and the value is discarded on the next instruction (§5). |
| `$77EF` area | Accidental scratch | Not intentional. `comprobar` called with `B=255` computes an attribute address of `$77EF` and reads/writes there. See §5. |
| `$8000-$A2C6` | Program image | Code + data + the one mutable variable, interleaved. |
| `$A16F` | `Medio` (1 byte) | Current piece column. **Lives inside the code image**, immediately after the `T_S2` piece record. `piezas.asm:31`. |
| `$9CD2-$9CD6` | `SCR_CUR_PTR`, `SCR_ATTR_PTR`, `PRINT_ATTR` | Print library state, also inside the code image. `L30.3 - printat.asm:158-160`. |
| `$9CD7-$9FD6` | `CHARSET` (768 bytes) | `charset.bin`, 96 glyphs for ASCII 32-127. |
| `$8036-$914F` | `TETRIS.scr` (6912 bytes) | Title screen, `INCBIN` at `titulo.asm:33`. |
| `$FFFF` downward | Stack | `main.asm:5` sets `LD SP, 0`; the first push wraps to `$FFFF/$FFFE`. Grows down through the ROM's UDG area (`$FF58`+). |

Total program state is **one byte** (`Medio`) plus two bytes at `$7000` that are written but
never meaningfully read. There is no piece-position variable, no board array, no score, no
level, no line counter. Position lives entirely in registers `B` (row) and `C` (column) and
is destroyed by any code path that doesn't preserve them.

### Memory-mapped I/O

None in the Spectrum sense — the Spectrum uses port I/O, not MMIO.

**Port I/O in use:**

| Port | Site | Keys read |
|---|---|---|
| `$FBFE` | `titulo.asm:20`, `giro.asm:9` | Q(b0), W(b1), E, R, T |
| `$BFFE` | `movimiento.asm:10` | ENTER(b0), L(b1), K(b2), J(b3), H(b4) |
| `$7FFE` | `pantallas.asm:90` | SPACE(b0), SYMBOL(b1), M(b2), N(b3), B(b4) |
| `$FDFE` | `pantallas.asm:94` | A(b0), S(b1), D, F, G |

Control mapping, as implemented: **Q** = rotate left, **W** = rotate right, **J** = move left,
**K** = move right, **S** = start, **N** = quit, **Q** = dismiss title screen.

Nothing writes to port `$FE` — the border colour is never set and no sound is produced.
There is no beeper code anywhere.

### Interrupt vectors

**Nothing is attached to any interrupt vector, and this is a live hazard.**

- No `DI`, `EI`, `IM 0/1/2`, `HALT`, `RETI`, or `RETN` appears anywhere in the source
  (verified by grep across all `.asm` files — zero matches).
- The program therefore runs in whatever interrupt state it inherits. If it is entered from
  BASIC (`USR 32768`) or from a snapshot made in that state, the machine is in **IM 1 with
  interrupts enabled**, and the ZX Spectrum ROM's `$0038` handler runs 50 times per second.
- The ROM's IM 1 handler requires **`IY = $5C3A`**. It uses `IY`-relative addressing to reach
  the system variables.
- **This code destroys `IY` constantly.** `piezas.asm:44` and `clear.asm:13` and
  `test_col.asm:14` all set `IY` to a piece-data pointer around `$A0xx`; `L35 - Tetris_3D.asm:9`
  sets it to `$9FD7`. `L30.3 - printat.asm` and `pantallas.asm` never restore it either.
  With interrupts enabled, the ROM handler will write to `$A0xx`-relative addresses — i.e. into
  the piece tables and the code image — every 20 ms.

Three of the routines (`pintar_tetromino`, `borrar_tetromino`, `comprobar`) do `PUSH IY` /
`POP IY`, so they restore the caller's `IY` — but the caller's `IY` is already garbage, because
nothing in the program ever sets `IY = $5C3A`, and `Tetris_3D` leaves `$9FDF` in it permanently.

**Verdict:** the program is only safe if run with interrupts disabled. It never disables them.
Whether it works today depends entirely on the launch method, which is not recorded anywhere.
Mark this as the highest-priority correctness question for anyone taking this over.

### Timing-critical code

There is **no** frame synchronisation, no `HALT`, no scanline awareness, and no interrupt-driven
tick. All timing is a software busy-wait, and the code is not written against any cycle budget.

The only timing construct is `Tiempo` (`caida.asm:14-60`), which spins on a 16-bit counter:

```
EsperarLoop: DEC DE / LD A,D / OR A / JR NZ / LD A,E / OR A / JR NZ
```

- Iterations with `D != 0`: 26 T-states. Iterations with `D == 0`: 41 T-states.
- `TIEMPO_BASE` = `$11FF` = 4607. That is `(4607-255) × 26 + 255 × 41` ≈ **123,600 T-states**.
- At 3.5 MHz that is **~35 ms**, or about 1.8 frames at 50 Hz.

So gravity is roughly **28 rows per second** — a piece crosses the entire 22-row board in
under a second. That is not playable. See §4 for why this number is what it is.

Two further consequences of busy-wait timing:

- `Tiempo` is called *between* the erase and the next erase, but `borrar_tetromino` and
  `pintar_tetromino` are not synchronised to the raster. Every piece movement will tear.
- The Spectrum contends `$4000-$7FFF` with the ULA. All game rendering targets `$5800`, which
  **is** contended memory, so the actual wall-clock timing is slower and jittery relative to the
  T-state count above. Nothing in the code accounts for this.

---

## 3. Module Inventory

Tags: **WORKING** / **PARTIAL** / **BROKEN** / **STUB** / **DEAD** (assembled but unreachable) /
**UNCLEAR**.

### `main.asm` — entry point — **BROKEN**

31 lines. Sets `SP`, shows the title screen, then `CALL Pantalla_Ini`, `CALL dibujar_tablero`,
`CALL iniciar`.

**Defect:** there is no `HALT`, `JR $`, or `JP` after `CALL iniciar` (`main.asm:14`). The next
byte in the image is the first byte of `titulo.asm`, i.e. `InicioDePantalla` at `$800F`. When
`iniciar` returns — which it does, via `end: ret` at `juego.asm:48` — **execution falls straight
into the title-screen routine.** Confirmed in `main.lst`: `800C CD 30 A0` immediately followed
by `800F InicioDePantalla:`.

Also note `LD SP, 0` runs before anything else, so there is no way to return to BASIC.

### `titulo.asm` — title screen — **PARTIAL**

`InicioDePantalla` / `PintarPantalla`. LDIRs `TETRIS.scr` into `$4000`, then waits for **Q**.

- Register save/restore is correct (`push bc / push de` … `pop de / pop bc`).
- `titulo.asm:22-23` comment says "check if all keys are released", but the code waits for
  bit 0 of `$FBFE` to *go low* — it waits for Q to be **pressed**. Comment is wrong; code is
  probably what was intended.
- `titulo.asm:24` `ld d, 1` is dead — `D` is never read.
- `PintarPantalla` falls through into `EsperarEntrada`, so it is not reusable as a plain
  "blit a screen" routine despite the name.

### `pantallas.asm` — menus + `CalcularAtributo` — **MIXED**

- `Pantalla_Ini` — **WORKING.** Prints two messages, sets a flashing cursor attribute, waits
  for S or N.
- `CalcularAtributo` (`pantallas.asm:67-80`) — **WORKING.** Takes `B`=row, `C`=column, returns
  `HL` = attribute address. Preserves `AF`. **Clobbers `BC`** (`LD BC,$5800` at line 77) — this
  is undocumented in its header comment and is a real trap, see coupling below.
- `EsperarTecla` / `LeerTecla` / `SoltarTecla` — **WORKING but with a one-way exit.** Pressing
  **N** jumps to `FinDelJuego`, which prints "Gracias por jugar" and enters `fin: JR fin` — a
  hard hang with no way back. That is the only defined program exit.
- `Pantalla_Final` (`pantallas.asm:27-53`) — **DEAD.** The label appears exactly once in the
  entire tree: its own definition. Nothing calls it. The game-over screen is unreachable code.
  It also has two bugs: it prints `MensajeGameOver` twice (line 41 should almost certainly be
  `MensajeReiniciar`), and it restarts with `call inicializar` rather than `jp`, so each
  restart would permanently consume 2 bytes of stack.
- `MensajeReiniciar` — **DEAD.** Defined, never referenced.
- **Text encoding bug affecting all messages with Spanish punctuation.** The source is UTF-8;
  `main.lst:199` shows `MensajeGameOver` beginning `C2 A1` and `main.lst:192` shows
  `MensajeReiniciar` beginning `C2 BF`. `PRINTCHNUM` computes `CHARSET + (code-32)*8`, and
  `CHARSET` is only 768 bytes (`$9CD7-$9FD6`). Code `$C2` resolves to `$A1E7` — inside the
  `test_col`/`clear` machine code. Both strings will render two garbage glyphs before the text.

### `L30.3 - printat.asm` — text library — **WORKING (third-party)**

Attributed to "Daniel León - AOC - UFV 2020" in its header. Course-supplied, not student work.
`PRINTAT`, `PRINTSTR`, `PRINTCHAR`, `CRtoSCREEN`, `CRtoATTR`, `CLEARSCR` all look correct.

- `INK2PAPER` (`:137-144`) — **DEAD.** Never called.
- `PRINTCHAR` advances the cursor with `INC (HL)` on the low byte of the pointer only
  (`:125,127`), so printing past column 31 wraps within the same 256-byte block rather than
  moving to the next row. Not hit by current usage, but it is a latent limit.

### `L35 - Tetris_3D.asm` — background pattern — **WORKING (course-supplied)**

Fills all 6144 bytes of the display file with the 8-byte `Tetro_3D` bevel pattern, giving every
character cell a 3D block outline. Loop structure (`D`=3 thirds × `C`=8 lines × `B`=256 bytes)
is correct; `INC IY` between `DEC C` and `JR NZ` does not disturb flags.

Leaves `IY = $9FDF` on exit — see the interrupt hazard in §2.

### `tableroJuego.asm` — board rendering — **WORKING**

Draws the well: left border at attribute column 6, right border at column 25, both rows 0-21;
floor at row 22, columns 6-25. Border attribute is `6*8+7` = 55 (yellow paper, white ink).

**The playfield is 18 columns wide** (columns 7-24). Standard Tetris is 10. Nothing in the
code depends on 18 specifically, but nothing enforces any width either.

`fin_dibujar_tablero: jr fin_dibujar_tablero` (`:45`) is a leftover debug trap, unreachable
(the `ret` on line 42 precedes it). Harmless, but it is dead weight sitting in the middle of
the image.

### `juego.asm` — main game loop — **BROKEN**

51 lines, and the single most damaged file in the project. Detailed analysis in §5. Summary:

- The rotate and horizontal-move calls happen **after** the collision check, so neither is validated.
- `comprobar` is called with `C` holding the *previous* iteration's column, not the current one.
- The labels are inverted relative to what they do: `cambiar_tetromino` is the *keep falling*
  path, and the fall-through after it is the *land and spawn* path.
- The initial game-over check runs with `B = 255`, reading uninitialised RAM.
- `jr iniciar` re-enters `iniciar`, which re-runs `seleccionar_pieza` — the spawn path.

### `tetromino_next.asm` — piece spawn — **PARTIAL, MISNAMED**

The filename promises a next-piece preview. **There is no preview.** The file contains only
`seleccionar_pieza`, which picks a random piece and returns `B=0, C=15`.

- `ld a, r` (`:7`) as the entropy source. `R` increments once per M1 cycle; because the call
  site is reached by a fixed instruction path with a fixed-length delay loop, successive values
  will be strongly correlated, likely periodic. Piece sequence randomness is **UNCLEAR but suspect**.
- `and 31` then `cp 19` / `sub 19` folds 19-31 back to 0-12. Result: **indices 0-12 are twice
  as likely as 13-18.**
- It selects a **rotation state**, not a piece. The table has 19 entries covering 7 shapes with
  1/4/4/4/2/2/2 rotations, so pieces spawn in a random orientation, and shapes with more
  rotation states (L, J, T) are far more likely to appear than O (1 state).
- `fin_selec_pieza: jr fin_selec_pieza` (`:28`) — another unreachable debug trap.

### `piezas.asm` — piece data + `pintar_tetromino` — **WORKING**

**Data format**, 12 bytes per rotation state:

```
+0  rows        +1  cols        +2..+7  six attribute bytes (row-major, 0 = empty)
+8..+9  pointer to rotate-left state     +10..+11  pointer to rotate-right state
```

`longitud_pieza EQU T_L1 - T_0` = 12 (`tetromino_next.asm:3`). 19 records, `$A08B-$A16E`.
Index 18 lands exactly on `T_S2` at `$A163`, so the `sub 19` clamp does not overrun into
`Medio` at `$A16F` — correct, but by exactly one record's margin, with no assertion protecting it.

Colours are encoded in the pattern bytes: O and I = `6*8` (yellow), L = `4*8` (green),
J = `2*8` (red), T = `5*8` (cyan), **Z and S both = `7*8` (white)**. Z and S are visually
indistinguishable.

`pintar_tetromino` (`:34-73`) is correct. It skips zero bytes (so it composites rather than
blits), writes attribute bytes, and steps `32 - cols` between rows. Preserves `AF/IY/HL/DE/BC`;
does not modify `IX`.

Note the row loop reuses the inner label: `djnz pintar_loop` jumps into the middle of the inner
loop, which happens to be correct only because `C` is reloaded on line 59 immediately before.
Fragile, but not currently wrong.

### `test_col.asm` — collision detection — **WORKING as written, MISUSED**

`comprobar` walks the piece's 6 pattern bytes against the attribute file at `(B,C)`, and
returns `A=1` if any non-empty piece cell overlaps a non-zero attribute byte, `A=0` otherwise.
Register save/restore is balanced and it correctly preserves `IX`.

The routine itself is sound. **Every problem with collision in this game is in how `juego.asm`
calls it** (§5).

One design consequence worth flagging: because "occupied" means "attribute byte != 0", the
border cells (attribute 55) act as walls automatically. That works, but it also means *any*
non-zero attribute anywhere on screen is a solid block. If text is ever printed into the well,
it becomes collidable geometry.

### `clear.asm` — piece erase — **WORKING**

`borrar_tetromino` mirrors `pintar_tetromino`, writing `0` where the pattern byte is non-zero.
Correctly structured with a separate `loop_filas` row label.

**It erases to attribute 0 (black on black), not to a board-background attribute.** Combined
with `Tetris_3D` having painted a bevel pattern into the *pixel* file, erased cells show the
bevel in black-on-black — i.e. invisible. This is consistent with the rest of the design, but
it means the well interior is pure black rather than showing the 3D grid.

### `caida.asm` — drop timing — **BROKEN**

See §5 for the arithmetic. In short: level scaling is computed but the computation is a no-op,
`NIVEL_ACTUAL` is never written by anything, `REDUCCION_TIEMPO` is loaded into `DE` and never
used, the minimum-time clamp is unreachable, and `InicializarTiempo` (`:63`) is **DEAD**.

The routine does correctly busy-wait for a constant interval. That is the entirety of its
working behaviour.

### `movimiento.asm` — horizontal input — **PARTIAL**

Reads J/K, adjusts `Medio` by ±1, then blocks until the key is released.

- **No bounds check and no collision check.** `Medio` is a free-running byte; nothing stops it
  from walking off either side of the well. It will wrap `255 → 0`.
- `movimiento.asm:16-17` — `BIT 0,A` followed by an **unconditional** `JR no_tecla_move`. The
  `BIT` result is discarded. Almost certainly a `JR Z` that lost its condition.
- `movimiento.asm:24-25` and `:32-33` — `POP BC / RET` after an unconditional `JR`. Unreachable.
- `SoltarTeclaMv` blocks the entire game until the key is released. Holding J stalls gravity.

### `giro.asm` — rotation input — **PARTIAL**

Reads Q/W and follows the `+8/+9` or `+10/+11` pointer to the next rotation state.

- **No collision check and no wall kick of any kind.** See §5.
- `giro.asm:19,26` — `LD IX, DE`, an sjasmplus fake instruction (§1). It does produce `IX = DE`.
- `giro.asm:21-22` and `:29-30` — dead `POP BC / RET` after unconditional jumps, same pattern
  as `movimiento.asm`.
- `Soltar_Tecla` blocks until key release, same stall as above.

### Missing entirely

- **Line-clear detection.** No routine scans a row for fullness. Grep the tree: nothing.
- **Row shift after clear.** Nothing.
- **Score.** No variable, no display, no arithmetic.
- **Level progression.** `NIVEL_ACTUAL` is declared and never written.
- **Next-piece preview.** Despite `tetromino_next.asm`.
- **Working game over.** `Pantalla_Final` is dead; the `end:` path falls into the title screen.
- **Sound.** Nothing writes port `$FE`.
- **Soft drop / hard drop.** No down-key handling anywhere.

### Undocumented coupling

This is the part that will bite anyone refactoring.

1. **`B` and `C` are the piece position, globally, implicitly.** There is no position variable.
   `CalcularAtributo`, `comprobar`, `pintar_tetromino`, and `borrar_tetromino` all read the
   current position out of `B`/`C` as an unstated precondition. Any routine that clobbers `BC`
   moves the piece.

2. **`CalcularAtributo` destroys `BC`** (`pantallas.asm:77`) and its header comment does not
   say so. Its callers survive only because they read `(ix)` and `(ix+1)` into `B`/`C`
   *after* calling it — see `piezas.asm:41-43`, `test_col.asm:10-13`, `clear.asm:10-12`.
   Reorder those three lines and the game breaks silently.

3. **`IX` is the current piece, globally.** Set by `seleccionar_pieza`, mutated by `GIRAR`,
   read by `comprobar`/`pintar_tetromino`/`borrar_tetromino`. `PRINTAT` also uses `IX` as its
   string pointer — so **any text output destroys the current piece pointer.** `Pantalla_Ini`
   gets away with it only because it runs before a piece exists. This is a landmine for anyone
   adding a score display.

4. **`Medio` (the column) and `C` (also the column) are two copies of the same state that go
   out of sync by design.** `MOVER` writes `Medio` in memory; it does not touch `C`. The loop
   reconciles them with `ld c, e` — but only *after* the collision check has already run
   against the old `C`. This is the root cause of the movement bugs in §5.

5. **`seleccionar_pieza` returns `B=0, C=15`, and `iniciar` immediately overwrites `B` with
   255** (`juego.asm:6`) and separately writes `Medio = 15` (`:7-8`). The `C=15` return value
   and the `Medio: DB 14` initialiser (`piezas.asm:31`) are both vestigial — three places
   define the spawn column and they disagree (14, 15, 15).

6. **`comprobar` returns its result in `A` and does not preserve `AF`.** Every other routine in
   the tree does preserve it. Easy to break by "consistency" cleanup.

7. **Include order in `main.asm` is load-bearing.** `longitud_pieza EQU T_L1 - T_0`
   (`tetromino_next.asm:3`) is a forward reference resolved because `piezas.asm` is included
   after it — sjasmplus's two-pass resolution handles it, but reordering the includes changes
   `Medio`'s address and the `charset`/piece-table adjacency that the text-encoding bug
   currently lands in.

8. **`Tetris_3D` leaves `IY = $9FDF`** and nothing restores a sane `IY` afterwards. See §2.

---

## 4. Dead Ends and History

### The git log tells you nothing

```
0a2377e  raw state as pulled from Canvas    (tag: school-submission)
```

One commit. One branch (`master`). One tag. No remotes. `git reflog --all`, `git stash list`,
and `git fsck --lost-found` are all empty. **The repository was created by dumping a finished
submission into `git init`; there is no development history in git at all.**

### The real history is in the stale `.lst` files

Five files were assembled standalone at some earlier point and their listings were committed:
`caida.lst`, `clear.lst`, `juego.lst`, `pantallas.lst`, `piezas.lst`. Because a `.lst` embeds
the source it was built from, **these are effectively five committed snapshots of older
versions of those files.** Diffing them against the current `.asm` is the only development
history that exists. This is the most valuable thing in the repository.

Note also that these standalone builds all **failed** — they are full of
`error: Label not found:` because each file was assembled without its dependencies. Someone was
assembling individual files to check syntax, not to produce working output.

### Evidence of at least three machines / contributors

Absolute paths embedded in the listings:

| Path | Files |
|---|---|
| `C:\UFV Segundo~Tercero\Arquitectura\Practicas\TETRIS_E (2)\TETRIS_E\` | `main.lst`, `main.sld` — the final build |
| `C:\Users\pablo\OneDrive\Escritorio\TETRIS_E (2)\TETRIS_E\` | `caida.lst`, `clear.lst`, `juego.lst` |
| `D:\TETRIS\TETRIS_E\` | `pantallas.lst`, `piezas.lst` |

"UFV" = Universidad Francisco de Vitoria; the course is "Arquitectura". The `(2)` suffix on two
of the three paths suggests the project folder was zipped and re-extracted at least once — a
classic sign of passing a zip around instead of using version control.

### What was tried and changed

**a) `piezas.asm` was completely rewritten.** The old version (`piezas.lst`) used generic names
`Tetro1`…`Tetro19` and colours `1*8`-`5*8`; the current version uses semantic names `T_0`,
`T_L1..4`, `T_J1..4`, `T_T1..4`, `T_I1..2`, `T_Z1..2`, `T_S1..2` and colours `2*8`-`7*8`.
Same 19-record layout, same 12-byte format. **The old table had no `Medio` variable** — that
byte was added in the rewrite.

The rewrite also *introduced* the Z/S colour collision: in the old table Z used `5*8` and there
was no S piece at all (the old file has only O, I, L/J-as-8-states, T, Z — the current file
split those into proper L, J, Z, and S). So S was added late, and got handed the same colour
as Z.

**b) `clear.asm` was rewritten, and this one was a genuine bug fix.** The old
`borrar_tetromino` (`clear.lst:16-24`) tested the *screen* byte (`ld a,(hl) / cp 0`) to decide
whether to erase, i.e. it erased based on what was already on screen rather than on the piece
shape. It also had a nonsensical `jr z, haynegro / jr nz, borrar_loop` pair and no per-row
reset of `C`. The current version tests the *pattern* byte and resets `C` per row. Correct fix.

**c) `TIEMPO_BASE` was changed from `$88FF` to `$11FF`** (`caida.lst:5` vs `caida.asm:5`).
That is 35071 → 4607, a **7.6× speed-up**: from ~260 ms per row (≈3.8 rows/sec, reasonable) to
~35 ms per row (≈28 rows/sec, unplayable). Given that there is no level progression and no
line clearing, the most likely explanation is that someone shortened the wait to make manual
testing faster and never changed it back. **This is a strong candidate for a rushed-to-deadline
artifact** and it is a one-constant fix.

**d) The most damaging regression: input handling was moved to the wrong side of the collision
check.** In the old `juego.asm` (`juego.lst:27-29`):

```
    ld e, a
    call MOVER          ; <-- input applied
    call GIRAR          ; <-- rotation applied
    call comprobar      ; <-- THEN validated
```

In the current `juego.asm:26-44`, `MOVER` and `GIRAR` were pulled out of that position and
moved down into `cambiar_tetromino`, which runs **after** `comprobar` has already returned.
The old ordering was not fully correct either (it still checked against a stale `C`), but it at
least ran the collision test after the input was applied. **The current code validates a
position the piece will never occupy.** This is the single change that broke rotation and
horizontal collision, and it is visible as a diff between two committed artifacts.

**e) The game-over check was bolted on late.** The old `juego.asm` had `CALL comprobar / or a`
at the top with **no branch** — the result was computed and thrown away (`juego.lst:10-11`).
The current version added `jr nz, end` (`juego.asm:12`). But `end:` is just `ret`, and because
`main.asm` has no terminator after `CALL iniciar`, that `ret` falls into the title screen (§3).
Someone noticed the missing game-over, added two lines, and did not follow the control flow to
where the `ret` lands.

**f) `Pantalla_Final` was added late and never wired up.** The old `pantallas.lst` shows
`Pantalla_Ini` falling directly into `FinDelJuego` — no `Pantalla_Final` at all, and no
`MensajeReiniciar` / `MensajeGameOver`. Both messages and the whole game-over screen were
written afterwards, and **nothing was ever changed to call them.** Classic deadline artifact:
the feature was built, and the one line that would invoke it was never added.

The same diff shows the start-menu row moved from 13 to 11 and an explicit `LD c, 2` added
before the `MensajeIniciar` print — previously `C` was inherited from whatever `PRINTAT` left
behind. A real fix, made by observation rather than reasoning.

**g) `TETRIS2.scr` — an alternative title screen, byte-different from `TETRIS.scr`, never
referenced.** An abandoned art asset.

**h) Debug traps left in place.** `fin_dibujar_tablero` (`tableroJuego.asm:45`) and
`fin_selec_pieza` (`tetromino_next.asm:28`) are both `jr $` infinite loops placed after a
`ret`, i.e. breakpoints someone used to freeze execution and inspect the screen, then made
unreachable rather than deleting. `.tmp/disasm.list` and the `.sld` files corroborate active
step-debugging under DeZog.

**i) Two routines have dead `POP BC / RET` sequences after unconditional `JR`s**
(`giro.asm:21-22, 29-30`; `movimiento.asm:24-25, 32-33`). The pattern in both files is
identical, which suggests one file was copy-pasted from the other — `giro.asm:3-4`'s comment
literally says "similar to desplazar.asm", and `movimiento.asm:2` calls itself "Desplazar.asm",
though no file by that name exists. **A file named `desplazar.asm` was renamed to
`movimiento.asm` and then cloned into `giro.asm`, and the comments were never updated.**

---

## 5. Known Trouble Spots

Ordered by severity.

### 5.1 Line clearing — **ABSENT**

There is no line-clear detection, no row-shift, and no code that could perform either. This is
not "incomplete" — the feature does not exist. Grep for any loop over 18-20 consecutive
attribute cells testing for fullness: there is none.

**Consequence: the game has no win condition, no progression, and no way to reduce the stack.**
It is a piece-dropper, not Tetris. This is by far the largest gap.

Anything built here will need: a row-scan routine over columns 7-24 of a given attribute row, a
multi-row `LDDR`-based shift of the attribute file (rows must shift *downward*, so copy from
the bottom up), and a decision about whether cleared rows animate.

### 5.2 The collision check validates the wrong position — **BROKEN**

`juego.asm:22-45`. Trace one iteration:

```
siguiente_juego:
    inc b               ; B = candidate row
    ld d, b             ; D written, never read
    ld a, (Medio)
    ld e, a             ; E = intended column
    call comprobar      ; <-- uses B and C. C is LAST iteration's column.
    or a
    jr z, cambiar_tetromino
    ...
cambiar_tetromino:
    ld c, e             ; <-- C only NOW becomes the intended column
    call GIRAR          ; <-- IX only NOW becomes the new rotation
    call pintar_tetromino
    call Tiempo
    call MOVER          ; <-- Medio changes again, after everything
    jr ciclo_juego
```

Three separate failures in eight instructions:

1. **`comprobar` is called with the stale `C`.** The horizontal move requested last iteration
   is applied to `C` *after* the check. So a sideways move is never collision-tested at the
   moment it happens; it is tested one iteration later, at a different row.
2. **`GIRAR` runs after `comprobar`.** The rotated shape is never tested at all. See 5.3.
3. **`D` is loaded and never used**, and `E` is a redundant copy of `Medio` — leftovers from the
   older structure (§4d) that was reorganised without cleaning up.

**Observable result:** pieces can be pushed into and through the side walls and into settled
blocks. Because `Medio` is unbounded (5.4), a piece can be walked entirely off the board.

Also note the labels are backwards. `comprobar` returns `A=0` for *no* collision, so
`jr z, cambiar_tetromino` means **"no collision → go to the routine called *change tetromino*"**.
`cambiar_tetromino` is actually the continue-falling path, and the fall-through below it
(`dec b / ld c,e / pintar / jr iniciar`) is the actual lock-and-spawn path. The logic is
roughly right; the naming is exactly inverted, and it will mislead anyone reading this file.

### 5.3 Rotation — **NO KICK, NO VALIDATION**

`giro.asm`. The rotation model itself is sound and cheap: each of the 19 records stores
pointers to its left- and right-rotated successors at `+8/+9` and `+10/+11`, so rotation is two
loads. The `T_L*`, `T_J*`, `T_T*` cycles were verified against `main.lst` and are consistent
(`T_L1→T_L2→T_L4→T_L3→T_L1` for left, and the reverse for right).

What is missing:

- **No wall kick of any kind.** Not SRS, not the simplified one-cell nudge — nothing. There is
  no code path that, on a failed rotation, tries an offset position.
- **No collision test on rotation at all.** `GIRAR` writes `IX` unconditionally. The caller has
  already run `comprobar`, using the *pre*-rotation shape (5.2). A rotation that would overlap
  the wall or the stack simply happens, and the overlapping cells get painted over settled
  blocks — which then makes those cells collidable, permanently corrupting the board.
- **Rotation is not anchored.** Rotating changes `rows`/`cols` (e.g. 2×3 ↔ 3×2) but the piece
  is always drawn from the same top-left `(B,C)`. There is no offset table, so pieces visibly
  jump when rotated. The I-piece is worst: `T_I1` is 4×1 and `T_I2` is 1×4, both drawn from the
  same corner.
- **Rotating near the right wall** with a widening rotation (3×2 → 2×3) extends the piece one
  cell right with no check, and the erase on the next frame uses the *new* shape, so it will
  erase a cell of the border. The border is not redrawn, so the well develops holes in its
  wall over time.

### 5.4 Horizontal movement is unbounded — **BROKEN**

`movimiento.asm:19-33`. `Medio` is incremented or decremented with **no clamp and no collision
test**. It is a single byte. Held long enough, it walks past column 25, past 31 (wrapping to the
next attribute row), and eventually wraps `255 → 0`. `CalcularAtributo` will happily compute an
address for any `C`, and `pintar_tetromino` will write there.

The `BIT 0,A / JR no_tecla_move` at `:16-17` is an unconditional jump with a discarded `BIT` —
so the "no key pressed" path is taken by falling through from a test whose result is ignored.
It happens to be reached correctly (both key branches jump away first), but it is not what the
author wrote.

### 5.5 Game over never triggers — **BROKEN**

`juego.asm:10-12`:

```
    LD B, 255
    ld a, 15
    LD (Medio), A
    CALL comprobar
    or a
    jr nz, end
```

`comprobar` is called with **`B = 255`**. `CalcularAtributo(255, C)` computes
`H = 255>>3 = $1F`, `L = (255<<5) | C = $E0|C`, giving `HL ≈ $77EF` — **not in the attribute
file at all**, but in uninitialised RAM below the program. The game-over test reads garbage.

Two failure modes, both real:

- If that garbage happens to be non-zero, `jr nz, end` fires, `end: ret` returns to `main.asm:15`,
  and — because `main.asm` has no terminator after `CALL iniciar` — **execution falls into
  `InicioDePantalla` and the title screen reappears.** A random reset at startup.
- If it is zero, play proceeds and there is *no other* game-over check. When the stack reaches
  the top, `comprobar` at row 0 returns collision, the code does `dec b` (→ `B = 255`), paints
  the piece at the garbage address `$77EF`, and `jr iniciar` spawns another piece. **The game
  loops forever, spawning pieces it draws into RAM instead of the screen.**

Note also `Pantalla_Final` — the actual game-over screen — is dead code (§3, §4f).

### 5.6 Scoring and level progression — **ABSENT / DEAD ARITHMETIC**

No score exists anywhere. Level scaling is *written* but is a complete no-op. `caida.asm:22-35`:

```
    LD A, (NIVEL_ACTUAL)   ; read the level...
    LD HL, TIEMPO_BASE
    SUB A                  ; ...and immediately zero A. Level value is destroyed here.
    LD B, 0
    LD C, A                ; BC = 0
    LD DE, REDUCCION_TIEMPO ; loaded, never used
    LD A, 0
    SBC HL, BC             ; HL = TIEMPO_BASE - 0 - 0
    LD A, H
    OR A
    JR NZ, SkipMinCheck    ; H = $11, always non-zero -> ALWAYS taken
    CP L                   ; unreachable
    JR NC, SkipMinCheck    ; unreachable
    LD HL, TIEMPO_MINIMO   ; unreachable
```

Five distinct defects in fourteen instructions:

1. `SUB A` (`A = A - A = 0`) destroys the level immediately after loading it. The author almost
   certainly meant `LD B, 0` / `LD C, A` alone, or a multiply loop.
2. There is **no multiplication** by `REDUCCION_TIEMPO` despite the comment claiming
   `TIEMPO_BASE - (NIVEL_ACTUAL * REDUCCION_TIEMPO)`. `DE` is loaded and discarded.
3. `SBC HL, BC` depends on the carry flag, which is set by `SUB A` (clears carry) — accidentally
   correct, but only by luck; inserting any flag-affecting instruction breaks it.
4. The `TIEMPO_MINIMO` clamp is unreachable for any `TIEMPO_BASE ≥ $0100`.
5. **`NIVEL_ACTUAL` (`$7002`) is never written by any code in the project.** It is read once,
   here, and that read is immediately discarded. There is no level counter.

`InicializarTiempo` (`:63-66`) is dead, so `TIEMPO_CAIDA` at `$7000` is also never initialised —
though it doesn't matter, since `Tiempo` overwrites it every call.

**Net effect: the drop interval is a hard constant of ~35 ms, forever.** See §2 and §4c.

### 5.7 Input handling versus timing — **BLOCKING, NOT INTERRUPT-DRIVEN**

The premise of "interrupt-driven timing" does not apply: **there are no interrupts in this
program** (§2). Input is polled once per gravity tick, and both input routines then *block*:

- `Soltar_Tecla` (`giro.asm:33-38`) and `SoltarTeclaMv` (`movimiento.asm:37-42`) spin until
  `IN A,(C)` reads `$FF`, i.e. until the key is released. **While a key is held, the entire
  game freezes** — no gravity, no rendering. Hold J and the piece stops falling.
- Only one input is sampled per tick, and rotation and movement are sampled in separate
  routines reading *different* keyboard half-rows, so pressing J and Q together is handled
  serially with a one-tick lag.
- With the drop interval at ~35 ms and a key-release wait in the path, the effective input
  model is "one discrete action per keypress, and the game pauses while you press it."
- The keyboard is read raw with no debounce. The release-wait accidentally serves as debounce,
  at the cost of the freeze.

`Soltar_Tecla` compares the port read to `$FF`. On the Spectrum only bits 0-4 are keyboard
data; bits 5-7 are floating. In most emulators they read high so `$FF` works, **but this is
emulator-dependent and may not hold on real hardware or on an accurate ULA model.** Marking
this **UNCLEAR** — it needs testing on the actual target before anyone trusts it.

### 5.8 Rendering artifacts

- **Nothing is synchronised to the raster** (§2). Every erase/redraw pair will tear.
- **Erase-then-draw with no double buffer**: the piece is invisible for the duration of one
  `comprobar` call each frame. At ~28 frames/sec this reads as flicker.
- **The border and floor are never redrawn.** Any piece that overlaps them (which 5.3 and 5.4
  make possible) permanently erases part of the well.
- **Z and S share colour `7*8`** (§3, `piezas.asm:25-29`). Indistinguishable in play.

---

## Summary Table

| Module | State |
|---|---|
| `main.asm` | BROKEN — falls through into title screen after `CALL iniciar` |
| `titulo.asm` | PARTIAL — works; misleading comment, dead `ld d,1` |
| `pantallas.asm` | MIXED — `Pantalla_Ini` + `CalcularAtributo` work; `Pantalla_Final` DEAD; UTF-8 text bug |
| `L30.3 - printat.asm` | WORKING (course-supplied); `INK2PAPER` dead |
| `L35 - Tetris_3D.asm` | WORKING (course-supplied); leaves `IY` corrupt |
| `tableroJuego.asm` | WORKING; 18-wide well; dead debug trap |
| `juego.asm` | BROKEN — validates the wrong position; inverted labels; no working game over |
| `tetromino_next.asm` | PARTIAL — spawns pieces; no preview despite the name; biased RNG |
| `piezas.asm` | WORKING — data + `pintar_tetromino` both correct; Z/S share a colour |
| `test_col.asm` | WORKING as written, MISUSED by its only caller |
| `clear.asm` | WORKING |
| `caida.asm` | BROKEN — level scaling is dead arithmetic; constant ~35 ms interval |
| `movimiento.asm` | PARTIAL — no bounds check, no collision check, blocking |
| `giro.asm` | PARTIAL — no wall kick, no collision check, no rotation anchor, blocking |
| Line clear | ABSENT |
| Row shift | ABSENT |
| Scoring | ABSENT |
| Level progression | ABSENT |
| Next-piece preview | ABSENT |
| Sound | ABSENT |
| Soft/hard drop | ABSENT |
| Build script | ABSENT |
| Tests | ABSENT |

---

## Corrections & Notes (from skill-authoring pass)

Added after the original audit, during construction of `.claude/skills/`. The findings above are
unchanged; these are corrections and additions verified against the code at the same commit.

### C1. Not all five standalone builds failed — `caida.lst` is clean

§4 states the five stale listings "all **failed**". Four did. `caida.asm` has no external
references and assembles cleanly on its own:

```
sjasmplus caida.asm   ->  Errors: 0, warnings: 0, compiled: 67 lines
sjasmplus juego.asm   ->  Errors: 11
```

The conclusion in §4 is otherwise intact — the embedded source is still valid history, and
standalone assembly is still not a way to check a file. Only `main.asm` assembles the real program.

### C2. Two colour collisions, and the Z/S one was carried over rather than introduced

§4a states the `piezas.asm` rewrite introduced the Z/S collision and that the old table "had no
S piece at all". Recovering the old table from `piezas.lst` shows both S (`Tetro16`/`Tetro18`)
and Z (`Tetro17`/`Tetro19`) already present and already sharing `5*8`. The collision was
**carried over**, not created.

What the rewrite actually changed:

- **Improvement:** the old single 8-record `3*8` L/J group was split into distinct L (`4*8`) and
  J (`2*8`).
- **Regression:** O and I were put on the same value `6*8` (previously `1*8` and `2*8`).

So there are **two** collisions in the current tree, not one: Z/S share `7*8`, O/I share `6*8`.
§3's `piezas.asm` entry lists the `6*8` value for both O and I correctly but flags only Z/S as a
defect.

### C3. `CalcularAtributo` was also rewritten, and the current version is the fix — do not revert

Not covered in §4. The old form (`pantallas.lst:49`) built the row into `H` using `and $F8`
followed by three `rlca` — a **rotate**, not a shift, so bits wrapped and the computed address
was wrong. The current form uses `SRL H` x3 / `SLA A` x5 (`pantallas.asm:71-74`).

Every draw, erase, and collision test in the game routes through this routine. It belongs in the
same "do not revert" category as the `clear.asm` erase-test fix identified in §4b.

### C4. `main.asm` has no trailing newline — appended `INCLUDE`s are silently dropped

Not covered anywhere in the original audit, and it is the first thing anyone adding a new source
file will hit. The last byte of `main.asm` is the closing quote of `INCLUDE "giro.asm"` (`0x22`),
with no newline after it. Appending a line without first adding one produces:

```
    INCLUDE "giro.asm"    INCLUDE "lineas.asm"
```

sjasmplus honours the first `INCLUDE` and **discards the second without any diagnostic** — the
build reports `Errors: 0, warnings: 0, compiled: 852 lines`, identical to a clean baseline, and
the new file is simply never assembled. Verified by test.

The cheapest detection is the `compiled: N lines` figure: if it has not moved off 852, the new
file did not participate in the build.

### C5. Two routines in the skill library are written but unexecuted

`.claude/skills/game-loop-and-collision/SKILL.md` §7 supplies two routines that do not exist
anywhere in the source tree:

- `leer_teclas` — non-blocking, edge-detected keyboard read, replacing the blocking
  key-release waits in `giro.asm:33-38` and `movimiento.asm:37-42`.
- `en_rango` — well-bounds column predicate, needed because `comprobar` cannot reject a
  candidate that has jumped clear of the border (a two-cell rotation kick from column 24 tests
  column 26, finds zeros, and accepts).

Both assemble at 0 errors / 0 warnings against this tree. **Neither has ever been executed.**
They are designs that compile, not verified code, and should be treated as such until run under
the emulator.

The same caveat applies more broadly: every playbook in `.claude/skills/` was verified against
the source and `main.lst`, and its code blocks were test-assembled, but **none of it has been
confirmed by running the game.** `build-and-verify` §6 holds the manual checklist for closing
that gap.
