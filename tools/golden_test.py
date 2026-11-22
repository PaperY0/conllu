#!/usr/bin/env python3
"""Regression test for the CLI surface: compare stdout against golden files.

`tests/golden/cases.json` lists one command per case, `tests/golden/<name>.out`
holds the expected stdout. Line-oriented formats are brittle on purpose: any
change in a column order, a label, a rounding or a JSON key shows up as a diff,
which is what a golden set is for.

    python3 tools/golden_test.py            # verify
    python3 tools/golden_test.py --update   # rewrite the .out files

Exit code 1 when a case differs, so CI can fail on it.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "tests" / "golden"


def run_case(args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(
        ["moon", "run", "cmd/main", "--", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    # Windows prints CRLF; the golden files are stored with LF only.
    return proc.returncode, proc.stdout.replace("\r\n", "\n")


def main() -> int:
    update = "--update" in sys.argv[1:]
    cases = json.loads((GOLDEN / "cases.json").read_text(encoding="utf-8"))
    failures = 0
    for case in cases:
        name = case["name"]
        expected_exit = case.get("exit", 0)
        code, stdout = run_case(case["args"])
        out_path = GOLDEN / f"{name}.out"
        if update:
            out_path.write_text(stdout, encoding="utf-8")
            print(f"updated {name} (exit {code})")
            continue
        if code != expected_exit:
            print(f"FAIL {name}: exit code {code}, expected {expected_exit}")
            failures += 1
            continue
        if not out_path.exists():
            print(f"FAIL {name}: missing {out_path.name}, run with --update")
            failures += 1
            continue
        expected = out_path.read_text(encoding="utf-8")
        if stdout != expected:
            print(f"FAIL {name}: stdout differs from {out_path.name}")
            for line_no, (want, got) in enumerate(
                zip(expected.splitlines(), stdout.splitlines()), 1
            ):
                if want != got:
                    print(f"  line {line_no}\n    expected: {want}\n    actual:   {got}")
                    break
            else:
                print("  one output has trailing lines the other does not")
            failures += 1
        else:
            print(f"ok   {name}")
    print(f"\n{len(cases) - failures}/{len(cases)} golden cases pass")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
