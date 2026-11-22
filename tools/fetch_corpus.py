#!/usr/bin/env python3
"""Download the UD treebanks used by the differential harness.

The corpora are not redistributed with the package: they are test fixtures
with their own licence (CC BY-SA 4.0 for UD_English-EWT, CC BY-SA 4.0 for
UD_Chinese-GSD). `data/` is gitignored; only the download script is committed.
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "data" / "ud"

# Repo layout of UniversalDependencies/* changed over time; these paths are
# pinned to the current treebank repositories.
SOURCES = [
    (
        "UD_English-EWT",
        "en_ewt",
        ["dev", "test"],
    ),
    (
        "UD_Chinese-GSD",
        "zh_gsd",
        ["dev", "test"],
    ),
]


def fetch(repo: str, prefix: str, split: str) -> Path:
    name = f"{prefix}-ud-{split}.conllu"
    url = f"https://raw.githubusercontent.com/UniversalDependencies/{repo}/master/{name}"
    DEST.mkdir(parents=True, exist_ok=True)
    target = DEST / name
    if target.exists() and target.stat().st_size > 0:
        print(f"have {name}")
        return target
    print(f"get  {name}")
    with urllib.request.urlopen(url, timeout=60) as response:
        target.write_bytes(response.read())
    return target


def main() -> int:
    for repo, prefix, splits in SOURCES:
        for split in splits:
            fetch(repo, prefix, split)
    print(f"corpus ready in {DEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
