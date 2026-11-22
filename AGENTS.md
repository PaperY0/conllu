# AGENTS.md

CoNLL-U / Universal Dependencies toolchain for MoonBit. The library is the root
package, `cmd/main` is the CLI, `tools/` holds the Python differential harness.
Everything else is packaging. MoonBit conventions (block style, `.mbti`
interfaces, snapshot tests) apply as usual.

## Commands

```bash
export PATH="$HOME/.moon/bin:$PATH"   # toolchain is not on PATH by default
moon check                            # exits 0 even with type errors — read the output
moon test                             # also type-checks the ```mbt check``` blocks in README.mbt.md
moon run --target wasm cmd/main -- stats examples/sample.conllu
moon run --target wasm cmd/main -- analyze data/ud/en_ewt-ud-dev.conllu data/ud/zh_gsd-ud-dev.conllu
moon run --target wasm cmd/main -- eval examples/sample.conllu examples/sample.conllu --by-document
moon run --target wasm cmd/main -- compress examples/sample.conllu /tmp/sample.conllu.gz
moon info && moon fmt                 # run last; commit the .mbti diff
```

Modules: `conllu.mbt` (model, parse, serialize), `validate.mbt` (spec checks and
the tag inventories), `tree.mbt` (tree queries), `metrics.mbt` (UAS/LAS, per-label
scores, stats), `document.mbt` (`# newdoc`/`# newpar` grouping), `coverage.mbt`
(corpus coverage report). `coverage.mbt` reads `upos_tags` / `deprel_tags` /
`base_deprel` from `validate.mbt` — same package, no `pub` needed, but moving
those inventories means updating both call sites.

The default target is wasm and `moonbitlang/x/fs` works there, so the CLI reads
local files without a native build.

## Differential testing

`tools/diff_test.py` compares `cmd/main dump` field by field against the Python
`conllu` package, plus `validate` (zero errors), `roundtrip` (lossless) and
`eval file file` (UAS = LAS = 100%).

```bash
python3 -m pip install conllu
python3 tools/fetch_corpus.py        # UD treebanks land in data/ud/, gitignored
python3 tools/diff_test.py --report  # rewrites DIFF-REPORT.md
```

Two rules when touching the parser or `cmd_dump`:

- The dump format (`D n` / `S words multi empty comments` / `w|m|e id form upos
  head deprel`) is a contract shared with `tools/diff_test.py`. Change both
  sides in the same commit.
- UD treebanks are CC BY-SA 4.0 test fixtures. Never commit `data/` or any
  corpus `.conllu` file; only the download script belongs in the repo.

## Non-obvious facts for this codebase

- `String::length()` returns `Int32`, so sentence IDs and counts are `Int32`
  on purpose. `String::split` returns an `Iter`: use `.to_array()`, not
  `.length()`.
- Use `.to_owned()` on `StringView`; `.to_string()` is deprecated.
- Struct fields are immutable by default. `Stats` and `EvalResult` fields are
  `mut` because the CLI accumulates into them.
- `ConlluError` is a suberror carrying `(line, message)`: destructure it with
  `match e { ConlluError(line, _) => ... }`, not with labelled payloads.
- Not every unknown DEPS relation is an error: enhanced dependencies legitimately
  use `ref`, and empty-node heads are written `8.1`, not `81`.
