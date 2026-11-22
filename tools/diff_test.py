#!/usr/bin/env python3
"""Differential test: PaperY0/conllu vs the Python `conllu` reference parser.

Both sides are reduced to the same line-oriented dump so the comparison is
field by field instead of "does it look right":

    D <sentences>
    S <words> <multiword> <empty> <comments>
    <w|m|e> <id> <form> <upos> <head> <deprel>

Usage:
    python3 tools/diff_test.py                 # corpus in data/ or $CONLLU_CORPUS
    python3 tools/diff_test.py --report        # also rewrite DIFF-REPORT.md
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CORPUS_DIR = ROOT / "data" / "ud"


def run_cli(args: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(
        ["moon", "run", "--target", "wasm", "cmd/main", "--", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def reference_dump(text: str) -> str:
    import conllu

    lines: list[str] = []
    sentences = conllu.parse(text)
    lines.append(f"D {len(sentences)}")
    # Comment counts come from the raw blocks: the reference library folds
    # comments into a metadata dict, which loses duplicates.
    blocks = [b for b in re.split(r"\n\s*\n", text.strip()) if b.strip()]
    for index, sentence in enumerate(sentences):
        words = 0
        multi = 0
        empty = 0
        body: list[str] = []
        raw_ids = []
        if index < len(blocks):
            raw_ids = [
                line.split("\t")[0]
                for line in blocks[index].splitlines()
                if line.strip() and not line.startswith("#")
            ]
        for position, token in enumerate(sentence):
            # The reference library decodes an empty node id such as `8.1`
            # as the tuple (8, '-', 1), i.e. as a multiword range. Take the
            # row kind from the raw ID column instead, and keep the library
            # as the source of the field values.
            raw = raw_ids[position] if position < len(raw_ids) else ""
            if "." in raw:
                empty += 1
                body.append(
                    f"e {raw} {token['form']} {token['upos']} _ {token['deprel']}"
                )
            elif "-" in raw or isinstance(token["id"], tuple):
                tid = token["id"]
                mwt_id = raw if raw else f"{tid[0]}-{tid[2]}"
                multi += 1
                body.append(f"m {mwt_id} {token['form']} _ _ _")
            else:
                words += 1
                body.append(
                    f"w {token['id']} {token['form']} {token['upos']} "
                    f"{token['head']} {token['deprel']}"
                )
        comments = 0
        if index < len(blocks):
            comments = sum(1 for line in blocks[index].splitlines() if line.startswith("#"))
        lines.append(f"S {words} {multi} {empty} {comments}")
        lines.extend(body)
    return "\n".join(lines) + "\n"


def counts_from_dump(lines: list[str]) -> tuple[int, int]:
    """Sentence and row counts of the line-oriented dump."""
    sentences = 0
    rows = 0
    for line in lines:
        if line.startswith("S "):
            sentences += 1
        elif line[:2] in ("w ", "m ", "e "):
            rows += 1
    return sentences, rows


def check_json(path: Path, reference_lines: list[str]) -> tuple[bool, str]:
    """The JSON dump must be valid JSON and agree with the line dump."""
    code, out, err = run_cli(["dump", str(path), "--format", "json"])
    if code != 0:
        return False, f"json dump failed ({code}): {(err or out).strip()[:120]}"
    try:
        data = json.loads(out)
    except json.JSONDecodeError as e:
        return False, f"json dump is not valid JSON: {e}"
    sentences = data.get("sentences")
    if not isinstance(sentences, list):
        return False, "json dump has no sentences array"
    expected_sentences, expected_rows = counts_from_dump(reference_lines)
    rows = 0
    for sentence in sentences:
        tokens = sentence.get("tokens")
        if not isinstance(tokens, list):
            return False, f"json sentence {sentence.get('line')} has no tokens array"
        for token in tokens:
            if token.get("kind") not in ("word", "multiword", "empty"):
                return False, f"unknown token kind {token.get('kind')!r}"
            rows += 1
    if len(sentences) != expected_sentences:
        return False, f"json has {len(sentences)} sentences, dump has {expected_sentences}"
    if rows != expected_rows:
        return False, f"json has {rows} tokens, dump has {expected_rows} rows"
    return True, ""


TSV_HEADER = [
    "sentence",
    "sent_line",
    "kind",
    "id",
    "form",
    "lemma",
    "upos",
    "xpos",
    "feats",
    "head",
    "deprel",
    "deps",
    "misc",
]


def check_tsv(path: Path, reference_lines: list[str]) -> tuple[bool, str]:
    """The TSV dump must have the documented header and agree with the dump."""
    code, out, err = run_cli(["dump", str(path), "--format", "tsv"])
    if code != 0:
        return False, f"tsv dump failed ({code}): {(err or out).strip()[:120]}"
    lines = out.splitlines()
    if not lines:
        return False, "tsv dump is empty"
    header = lines[0].split("\t")
    if header != TSV_HEADER:
        return False, f"tsv header is {header!r}"
    body = [line for line in lines[1:] if line.strip()]
    expected_sentences, expected_rows = counts_from_dump(reference_lines)
    if len(body) != expected_rows:
        return False, f"tsv has {len(body)} rows, dump has {expected_rows}"
    kinds = {"w": "word", "m": "multiword", "e": "empty"}
    reference_rows = [
        line.split(" ", 5) for line in reference_lines if line[:2] in ("w ", "m ", "e ")
    ]
    for index, line in enumerate(body):
        fields = line.split("\t")
        if len(fields) != len(TSV_HEADER):
            return False, f"tsv row {index + 1} has {len(fields)} columns"
        if index >= len(reference_rows):
            continue
        kind, rid, form, upos, head, deprel = reference_rows[index]
        if (
            fields[2] != kinds.get(kind, kind)
            or fields[3] != rid
            or fields[4] != form
            or fields[6] != upos
            or fields[9] != head
            or fields[10] != deprel
        ):
            return False, f"tsv row {index + 1} disagrees with the dump"
    return True, ""


def compare(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    reference = reference_dump(text)

    code, out, err = run_cli(["dump", str(path)])
    if code != 0:
        return {
            "file": path.name,
            "ok": False,
            "reason": f"dump failed ({code}): {(err or out).strip()[:200]}",
            "mismatches": -1,
            "lines": 0,
            "sentences": 0,
        }

    ours = out.splitlines()
    theirs = reference.splitlines()
    mismatches = 0
    first: list[str] = []
    for i in range(max(len(ours), len(theirs))):
        a = ours[i] if i < len(ours) else "<missing>"
        b = theirs[i] if i < len(theirs) else "<missing>"
        if a != b:
            mismatches += 1
            if len(first) < 3:
                first.append(f"line {i + 1}: ours={a!r} reference={b!r}")

    vcode, vout, verr = run_cli(["validate", str(path)])
    errors = 0
    for line in vout.splitlines():
        if line.startswith("diagnostics="):
            m = re.search(r"errors=(\d+)", line)
            if m:
                errors = int(m.group(1))

    rcode, rout, rerr = run_cli(["roundtrip", str(path)])
    rcode2, eout, eerr = run_cli(["eval", str(path), str(path)])
    uas = None
    for line in eout.splitlines():
        m = re.search(r"UAS=([\d.]+)%", line)
        if m:
            uas = float(m.group(1))
    las = None
    for line in eout.splitlines():
        m = re.search(r"LAS=([\d.]+)%", line)
        if m:
            las = float(m.group(1))

    # The JSON dump is a second serialization of the same parse: it must be
    # valid JSON and it must agree with the line dump on how many sentences and
    # rows were seen.
    json_ok, json_problem = check_json(path, theirs)
    if not json_ok:
        first.append(json_problem)

    tsv_ok, tsv_problem = check_tsv(path, theirs)
    if not tsv_ok:
        first.append(tsv_problem)

    ok = (
        mismatches == 0
        and errors == 0
        and rcode == 0
        and uas == 100.0
        and las == 100.0
        and json_ok
        and tsv_ok
    )
    return {
        "file": path.name,
        "ok": ok,
        "reason": "; ".join(first) if first else "",
        "mismatches": mismatches,
        "lines": len(theirs),
        "sentences": int(theirs[0].split()[1]) if theirs else 0,
        "errors": errors,
        "roundtrip": rcode == 0,
        "uas": uas,
        "las": las,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="rewrite DIFF-REPORT.md")
    parser.add_argument("files", nargs="*", help="explicit .conllu files")
    args = parser.parse_args()

    if args.files:
        files = [Path(f) for f in args.files]
    else:
        corpus = Path(os.environ.get("CONLLU_CORPUS", DEFAULT_CORPUS_DIR))
        files = sorted(corpus.glob("*.conllu"))
    if not files:
        print(f"no .conllu files found; put treebanks in {DEFAULT_CORPUS_DIR} "
              "or pass paths, or set $CONLLU_CORPUS")
        return 2

    results = [compare(f) for f in files]
    total_mismatch = sum(r["mismatches"] for r in results if r["mismatches"] >= 0)
    failed = [r for r in results if not r["ok"]]

    print(f"{'file':40} {'sent':>6} {'lines':>7} {'diff':>5} {'err':>4} {'UAS':>6} {'LAS':>6}")
    for r in results:
        print(
            f"{r['file']:40} {r['sentences']:>6} {r['lines']:>7} "
            f"{r['mismatches']:>5} {r.get('errors', -1):>4} "
            f"{r.get('uas') or 0:>6.2f} {r.get('las') or 0:>6.2f}"
        )
    for r in failed:
        if r["reason"]:
            print(f"  {r['file']}: {r['reason']}")

    if args.report:
        write_report(results, total_mismatch)
        print("wrote DIFF-REPORT.md")

    return 0 if not failed else 1


def write_report(results: list[dict], total_mismatch: int) -> None:
    rows = "\n".join(
        f"| `{r['file']}` | {r['sentences']} | {r['lines']} | {r['mismatches']} | "
        f"{r.get('errors', '-')} | {r.get('uas') or 0:.2f} | {r.get('las') or 0:.2f} |"
        for r in results
    )
    failed = [r for r in results if not r["ok"]]
    body = f"""# DIFF-REPORT：PaperY0/conllu 对 `conllu` 参考解析器的差分对拍

生成方式：`python3 tools/diff_test.py --report`（脚本在库内，可复现）。

## 一、基准

- 参照实现：PyPI `conllu`（Python 侧 CoNLL-U 解析器，UD 生态里广泛使用）。
- 语料：Universal Dependencies 官方树库（CC BY-SA 4.0，只作测试语料，不随包分发）。
  `python3 tools/fetch_corpus.py` 可复现下载。

## 二、口径

两侧都被压成同一套行式 dump，逐行逐字段比较：

```
D <句数>
S <词数> <多词 token> <空节点> <注释行数>
<w|m|e> <ID> <FORM> <UPOS> <HEAD> <DEPREL>
```

另外每份文件还检查五件事：

1. `validate` 必须 0 error（官方树库本身合法）；
2. `roundtrip` 必须无损（序列化后逐字节一致，允许补上结尾空行）；
3. 自己对自己 `eval` 必须 UAS=LAS=100%，用来证明对齐逻辑没有漏词；
4. `dump --format json` 必须能被 `json.loads` 解析，且句子数、token 数与行式 dump 完全一致；
5. `dump --format tsv` 必须带 13 列固定表头，行数等于 dump 行数，且每行的 kind/id/form/upos/head/deprel 与 dump 逐行一致。

## 三、结果

| 文件 | 句数 | 行数 | 字段不一致 | 校验 error | UAS | LAS |
| --- | --- | --- | --- | --- | --- | --- |
{rows}

- 字段级不一致总数：**{total_mismatch}**
- 失败文件：**{len(failed)}**

## 四、复现

```bash
python3 tools/fetch_corpus.py          # 下载 dev/test 切分到 data/ud/
python3 tools/diff_test.py --report    # 对拍并重新生成本报告
```
"""
    (ROOT / "DIFF-REPORT.md").write_text(body, encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
