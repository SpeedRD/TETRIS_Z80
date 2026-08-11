#!/usr/bin/env python3
"""Check seleccionar_pieza returns upright pieces with a fair shape distribution."""
from collections import Counter
from unit import Unit

u = Unit()
L = u.L
fails = []
SPAWNS = {L[n]: n for n in ("T_0", "T_L1", "T_J1", "T_T1", "T_I1", "T_Z1", "T_S1")}
ALL_RECORDS = {L[n]: n for n in (
    "T_0", "T_L1", "T_L2", "T_L3", "T_L4", "T_J1", "T_J2", "T_J3", "T_J4",
    "T_T1", "T_T2", "T_T3", "T_T4", "T_I1", "T_I2", "T_Z1", "T_Z2", "T_S1", "T_S2")}


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


N = 350
u.call("iniciar_secuencia", limit=3000)   # the game always seeds first
u.poke(L["semilla"], [0xA5])
counts = Counter()
bad_bc = 0
for _ in range(N):
    r = u.call("seleccionar_pieza", limit=3000)
    counts[r["IX"]] += 1
    if r["BC"] != 0x000F:
        bad_bc += 1

print(f"seleccionar_pieza x{N}")
check("every spawn is a canonical upright state",
      all(ix in SPAWNS for ix in counts), True)
unknown = [ALL_RECORDS.get(ix, f"{ix:04X}") for ix in counts if ix not in SPAWNS]
if unknown:
    print("       non-spawn records returned:", unknown)
check("always returns B=0, C=15", bad_bc, 0)
check("all seven shapes appear", len(counts), 7)

print("\n  shape distribution (a fair game is 14.3% each;")
print("  the old code gave L/J/T 25% each and the other four 6.25%)")
worst = 0.0
for ix, name in sorted(SPAWNS.items(), key=lambda kv: kv[1]):
    pct = 100.0 * counts[ix] / N
    worst = max(worst, abs(pct - 100.0 / 7))
    bar = "#" * int(pct * 2)
    print(f"    {name:5s} {counts[ix]:4d}  {pct:5.1f}%  {bar}")
check("every shape within 5 points of 14.3%", worst < 5.0, True)

print("\nLFSR health")
u.poke(L["semilla"], [0xA5])
seen = set()
for _ in range(300):
    u.call("seleccionar_pieza", limit=3000)
    seen.add(u.peek(L["semilla"], 1)[0])
check("seed never reaches 0 (a zero LFSR would freeze)", 0 in seen, False)
check("seed visits most of its 255-state period", len(seen) >= 200, True)

# a zero seed must not be able to enter the game through sembrar_azar
u.poke(L["semilla"], [0x00])
u.call("sembrar_azar", limit=1000)
check("sembrar_azar never leaves a zero seed", u.peek(L["semilla"], 1)[0] != 0, True)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
