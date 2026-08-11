#!/usr/bin/env python3
"""Build, then run every suite. Usage: python3 tests/run_all.py [name ...]"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

SUITES = [
    ("test_entrada",    "leer_teclas / en_rango"),
    ("test_giro",       "GIRAR: cycles, kicks, atomic rollback"),
    ("test_lineas",     "limpiar_lineas / fila_llena / bajar_filas"),
    ("test_bajar_filas", "row-copy count: exact iterations, no pixel-file damage"),
    ("test_puntuacion", "score, lines, level, speed table"),
    ("test_spawn",      "spawn RNG, preview handoff"),
    ("test_pantallas",  "redesigned screens, panels, best score"),
    ("test_relleno",    "game-over fill animation: timing, isolation"),
    ("checklist6",      "build-and-verify section 6, end to end"),
]

BUILD = ["sjasmplus", "--fullpath", "--raw=main.bin",
         "--lst=main.lst", "--sld=main.sld", "main.asm"]


def build():
    # sjasmplus splits its output across stdout and stderr; merge them.
    r = subprocess.run(BUILD, cwd=REPO, capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    last = [l for l in out.splitlines() if l.startswith("Errors:")]
    line = last[-1] if last else (out.strip().splitlines() or ["no output"])[-1]
    print(f"build: {line}")
    # sjasmplus exits 0 even with warnings -- read the line, not the code.
    if "Errors: 0, warnings: 0" not in line:
        print("BUILD NOT CLEAN -- fix that before trusting any suite below.")
        return False
    return True


def main():
    if not build():
        return 1
    wanted = sys.argv[1:] or [n for n, _ in SUITES]
    failed = []
    for name, blurb in SUITES:
        if name not in wanted:
            continue
        print(f"\n=== {name}  ({blurb})")
        r = subprocess.run([sys.executable, "-u", f"{name}.py"],
                           cwd=HERE, capture_output=True, text=True)
        tail = r.stdout.strip().splitlines()
        for l in tail:
            if l.strip().startswith("FAIL") or "ALL PASS" in l or "FAILURES" in l:
                print("   ", l.strip())
        if r.returncode != 0 or "ALL PASS" not in r.stdout:
            failed.append(name)
            if r.stderr.strip():
                print("   ", r.stderr.strip().splitlines()[-1])
    print("\n" + ("EVERY SUITE PASSED" if not failed else f"FAILED: {failed}"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
