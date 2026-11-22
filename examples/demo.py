#!/usr/bin/env python3
"""One-command tour: download UD data, then run every CLI subcommand for real.

    python3 examples/demo.py

Fetches the UD fixtures on first run (tools/fetch_corpus.py, CC BY-SA 4.0, not
committed), then walks the pipeline: stats -> validate -> docs -> analyze ->
eval -> labels -> dump -> roundtrip -> compress. Each step prints its actual
stdout (truncated to keep the tour readable) and any non-zero exit code aborts
the demo, so this doubles as a smoke test of the published workflow.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEV = "data/ud/en_ewt-ud-dev.conllu"
TEST = "data/ud/en_ewt-ud-test.conllu"
SAMPLE = "examples/sample.conllu"
MAX_LINES = 10


def run(title: str, args: list[str], max_lines: int = MAX_LINES) -> None:
    print(f"\n=== {title} ===")
    print("$ moon run cmd/main -- " + " ".join(args))
    proc = subprocess.run(
        ["moon", "run", "cmd/main", "--", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    lines = proc.stdout.replace("\r\n", "\n").splitlines()
    for line in lines[:max_lines]:
        print(line)
    if len(lines) > max_lines:
        print(f"... ({len(lines) - max_lines} more lines)")
    if proc.returncode != 0:
        print(proc.stderr)
        raise SystemExit(f"step failed with exit code {proc.returncode}: {title}")


def main() -> int:
    if not (ROOT / DEV).exists():
        print("UD fixtures missing, downloading (CC BY-SA 4.0 test fixtures)")
        subprocess.run(
            [sys.executable, "tools/fetch_corpus.py"], cwd=ROOT, check=True
        )
    run("1/9 corpus statistics", ["stats", DEV])
    run("2/9 structural + cross-sentence validation", ["validate", DEV, "--documents"])
    run("3/9 document / paragraph structure", ["docs", SAMPLE])
    run("4/9 coverage, two splits merged into TOTAL", ["analyze", DEV, TEST])
    run("5/9 evaluation against the gold parse", ["eval", DEV, DEV])
    run(
        "6/9 per-relation LAS as CSV (self-parse, all 100)",
        ["labels", DEV, DEV, "--format", "csv"],
        max_lines=6,
    )
    run("7/9 TSV dump for pandas", ["dump", SAMPLE, "--format", "tsv"], max_lines=6)
    run("8/9 lossless round-trip", ["roundtrip", DEV])
    with tempfile.TemporaryDirectory() as tmp:
        out = str(Path(tmp) / "en_ewt-ud-dev.conllu.gz")
        run("9/9 gzip write-back with read-back verification", ["compress", DEV, out])
    print("\ndemo finished: all nine steps exited 0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
