# PaperY0/conllu

[![CI](https://github.com/PaperY0/conllu/actions/workflows/ci.yml/badge.svg)](https://github.com/PaperY0/conllu/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-PaperY0%2Fconllu-blue)](https://mooncakes.io/docs/#/PaperY0/conllu/)
[![license](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

A **CoNLL-U / Universal Dependencies** toolchain in MoonBit: lossless parsing and serialization, spec validation, dependency-tree queries, document/paragraph grouping, corpus coverage analysis, UAS/LAS evaluation and corpus statistics, plus a ready-to-run CLI with gzip read *and* write.

CoNLL-U is the single interchange format of the UD treebanks (200+ languages): ten tab-separated columns per word, blank lines between sentences, `#` comments, and IDs that can be `12` (word), `5-6` (multiword token) or `5.1` (empty node). The MoonBit ecosystem already has tokenizers and taggers, but the **syntax layer** — HEAD/DEPREL trees, projectivity, UAS/LAS — was empty. This package fills that layer.

[中文 README](README.mbt.md)

## Architecture

One spine: text is parsed into `Array[Sentence]`, every analysis is a pure function over it, and the CLI is a thin shell around those functions.

```
 .conllu / .conllu.gz
        |
        v
   parse(text)  -- lexical errors raise ConlluError(line, message)
        |
        v
 Array[Sentence]                     Token = raw 10 columns + RowKind + line
        |
        +-- validate() --------------> Array[Diagnostic] (17 UPOS / 37 DEPREL / tree shape)
        +-- validate_documents() ----> cross-sentence id uniqueness (sent_id/newdoc/newpar)
        +-- tree.mbt ----------------> children / descendants / depth / path /
        |                              is_projective / roots / is_single_rooted
        +-- documents() -------------> Document -> Paragraph -> Sentence
        +-- stats() -----------------> Stats (sentences / words / multiword / empty / docs)
        +-- coverage() --------------> Coverage (tag hits / projectivity / depth / length)
        |       merge_coverage() merges files; TOTAL is never "average of averages"
        |
        +-- evaluate(gold, pred) ----> EvalResult (UAS / UUAS / LAS)
        +-- evaluate_by_label() -----> per-relation LAS
        +-- evaluate_by_document() --> per-document UAS / LAS
        |
        v
  to_string() / to_json()  serialize back to CoNLL-U text or JSON (one model, two exits)
        |
        v
   cmd/main (CLI)
   stats / validate / eval / labels / docs / analyze / dump / roundtrip / compress
   output: aligned tables | JSON | TSV | CSV | .conllu.gz (read-back verified)

 three test layers: conllu_test.mbt (37 cases) -> tools/golden_test.py (pinned CLI stdout)
                    -> tools/diff_test.py (field-by-field diff vs Python conllu, 6 UD splits)
```

## Features

- **Lossless**: all ten original columns live in `Token`; `to_string` restores the input byte-for-byte (multiword tokens, empty nodes and comments included). Unknown columns are never "helpfully normalized".
- **Strict errors**: `parse` hard-checks column count, ID shape and numeric HEAD, raising `ConlluError(line, message)` pointing at the source line.
- **Spec validation**: 17 UPOS, 37 UD v2 relations (including enhanced `ref`), ID continuity, single root, self-loops, cycles, DEPS syntax and ranges.
- **Cross-sentence validation**: `validate_documents` catches what per-sentence checks cannot — missing `# sent_id`, duplicate `sent_id`, reused `# newdoc id`, reused paragraph ids within one document.
- **Enhanced dependencies**: `Token::enhanced_deps()` splits DEPS into `EnhancedDep(head, rel)`; an empty-node head stays `5.1` instead of collapsing to word index 5.
- **Evaluation**: `evaluate(gold, pred)` gives UAS / LAS (percent), aligned by 1-based word order; length mismatches are counted in `skipped_sentences` rather than silently dropped.
- **Tree queries**: `children` / `descendants` / `depth` / `is_ancestor` / `is_projective` / `roots` / `path` / `is_single_rooted`.
- **Document grouping**: `# newdoc` / `# newpar` reconstruct the `Document → Paragraph → Sentence` hierarchy; files without boundary markers still yield one anonymous document.
- **Coverage analysis**: `coverage` counts UPOS/DEPREL hits, out-of-spec tags, projectivity and tree depth, long sentences and empty nodes in one pass; `merge_coverage` folds dev/test into one table.
- **Per-document evaluation**: `evaluate_by_document` scores each `# newdoc` group, worst first; a document missing entirely from the prediction shows 0 aligned tokens instead of being averaged away.
- **Statistics**: sentences, words, multiword tokens, empty nodes, comments, max/average length, document count; `Stats::to_json()` and `Coverage::to_json()` for other languages to consume.
- **Differentially tested**: field-by-field identical to the Python `conllu` reference parser on six dev/test splits of UD_English-EWT, UD_Chinese-GSD and UD_Japanese-GSD (6,128 sentences, 107,091 rows) — see [DIFF-REPORT.md](DIFF-REPORT.md).
- **Golden outputs**: the full stdout of eleven CLI invocations is pinned in `tests/golden/` and compared on every CI run, so any format change is caught immediately.

## Installation

```bash
moon add PaperY0/conllu
```

Requires `moonc >= 0.10.16` (developed on 0.10.22; check with `moon version --all`).

## Parsing and serialization

```mbt
let text = "1\tI\tI\tPRON\tPRP\t_\t2\tnsubj\t_\t_\n2\tsaw\tsee\tVERB\tVBD\t_\t0\troot\t_\t_\n"
let sentences = @conllu.parse(text)
// serialization restores the canonical blank line after each sentence
@conllu.to_string(sentences) == text + "\n"
```

A `Sentence` keeps both comments and every row: `sentence.rows()` returns `Word` / `Multiword` / `Empty` rows, `sentence.comment("text")` reads the `# text = ...` value.

Enhanced dependencies (the DEPS column) are available as structured values, with empty-node references kept as `5.1`:

```mbt
let deps = sentences[0].word(1).unwrap().enhanced_deps()
// deps[0].head() == "4", deps[1].head() == "5.1", deps[1].rel() == "ref"
```

## Validation

```mbt
let diagnostics = @conllu.validate(sentences)
@conllu.count_errors(diagnostics) // only Error severity
diagnostics[0].code               // e.g. "ROOT_COUNT"
```

Diagnostics are grouped by `code` so a CI step can whitelist or block by category:

| code | meaning |
| --- | --- |
| `ID_SEQUENCE` | word IDs do not increase contiguously from 1 |
| `MULTIWORD_SPAN` | multiword span `5-6` out of range |
| `HEAD_MISSING` / `HEAD_RANGE` / `HEAD_SELF` | HEAD non-numeric, out of range, self-loop |
| `ROOT_COUNT` | not exactly one root |
| `CYCLE` | HEAD chain never reaches the root |
| `DEPS_FORMAT` / `DEPS_RANGE` / `DEPS_DEPREL` / `DEPS_MISSING` | DEPS syntax, range, relation name, empty node without relation |
| `UPOS_UNKNOWN` / `DEPREL_UNKNOWN` | outside the UD v2 tagset |
| `FORM_EMPTY` / `FORM_SPACE` | FORM empty or containing whitespace |
| `SENT_ID_MISSING` / `SENT_ID_DUPLICATE` | missing `# sent_id` (warning) / duplicate (error), reported by `validate_documents` |
| `NEWDOC_ID_DUPLICATE` / `NEWPAR_ID_DUPLICATE` | reused document id / reused paragraph id within one document (warning) |
| `NEWPAR_WITHOUT_DOC` | `# newpar` before any `# newdoc` (warning) |

Per-sentence problems are caught by `validate`, but duplicate ids only exist when you look at the whole file:

```mbt
let diagnostics = @conllu.validate_documents(sentences)
```

## Documents and paragraphs

A treebank is not a flat list of sentences: `# newdoc` and `# newpar` mark which document and paragraph each sentence belongs to. `documents()` restores that hierarchy with ids taken from the comments; a file without boundary markers returns one anonymous document with an empty id, not an empty array.

A `# newdoc` line also opens a new paragraph, so a document never inherits the tail of the previous one. Grouping metadata is plain comments, and `Document::to_string` writes those lines back unchanged.

## Corpus coverage analysis

Sentence and word counts describe size, not quality. `coverage` answers four questions in one pass: how many of the 17 UPOS and 37 DEPREL are actually used; whether any out-of-spec tags appear; how deep the trees are and how many sentences are non-projective; how many long sentences and empty nodes there are.

For multiple files use `merge_coverage`, or hand the CLI several paths: tag sets are unioned, counts added, missing tags recomputed against the spec, and average depth re-weighted by token count — never an "average of averages":

```bash
moon run cmd/main -- analyze data/ud/en_ewt-ud-dev.conllu data/ud/zh_gsd-ud-test.conllu
```

```
file                            sentences   words  upos deprel unknown projective  depth
en_ewt-ud-dev.conllu                2001   25148 17/17  36/37       0     98.35%     11
zh_gsd-ud-test.conllu                500   12010 16/17  29/37       0      97.2%     10
TOTAL                               2501   37158 17/17  37/37       0     98.12%     11
```

## Evaluating UAS / LAS

```mbt
let result = @conllu.evaluate(gold_sentences, pred_sentences)
result.uas()  // percent
result.uuas() // direction ignored
result.las()
```

Aggregate scores hide "these three documents are entirely wrong". `evaluate_by_document` groups by the gold `# newdoc` and scores each group, worst first:

```bash
moon run cmd/main -- eval gold.conllu pred.conllu --by-document
```

The CLI prints one row per document plus an overall total.

## Command line

The package ships `cmd/main`. Every subcommand takes files directly, plain text or `.conllu.gz`; writing to `.gz` compresses automatically:

```bash
moon run cmd/main -- stats      treebank.conllu   # sentences/words/multiword/empty/max length/docs
moon run cmd/main -- stats      treebank.conllu --format json
moon run cmd/main -- validate   treebank.conllu   # diagnostics, exit code 1 on any error
moon run cmd/main -- validate   treebank.conllu --documents   # plus cross-sentence id checks
moon run cmd/main -- validate   treebank.conllu --format json   # one object per diagnostic
moon run cmd/main -- eval       gold.conllu pred.conllu
moon run cmd/main -- eval       gold.conllu pred.conllu --by-document
moon run cmd/main -- labels     gold.conllu pred.conllu   # LAS broken down by relation
moon run cmd/main -- labels     gold.conllu pred.conllu --format csv
moon run cmd/main -- docs       treebank.conllu   # document/paragraph structure and counts
moon run cmd/main -- analyze    treebank.conllu   # coverage report, exit 1 on out-of-spec tags
moon run cmd/main -- analyze    dev.conllu test.conllu   # multi-file table + TOTAL
moon run cmd/main -- analyze    dev.conllu test.conllu --format json
moon run cmd/main -- dump       treebank.conllu   # normalized dump for differential testing
moon run cmd/main -- dump       treebank.conllu --format json
moon run cmd/main -- dump       treebank.conllu --format tsv
moon run cmd/main -- roundtrip  treebank.conllu   # parse then serialize, verify lossless
moon run cmd/main -- compress   treebank.conllu out.conllu.gz   # canonical output + gzip
```

`compress` reads its own output back and compares it — a corrupt write never silently produces a plausible-looking file. UD_English-EWT dev: 1,899,904 → 357,823 bytes (18.83% of input).

`validate --format json` prints `{"file": ..., "diagnostics": [...], "errors": N, "warnings": M}` where each diagnostic is `{"line": 7, "severity": "error", "code": "ROOT_COUNT", "message": "..."}`. Filtering by `code` in CI no longer requires regexing text lines; exit-code semantics are unchanged (any error means 1).

```bash
moon run cmd/main -- validate corpus.conllu --format json | jq -r '.diagnostics[].code' | sort | uniq -c
```

`labels --format csv` prints `label,gold,correct,las` with RFC 4180 quoting, ready for a spreadsheet or pandas; the default is still an aligned terminal table.

The line-oriented `dump` is a stable contract (`D/S/w/m/e` prefixes) that the differential script compares against other implementations:

```
D 2001
S 7 0 0 4
w 1 From ADP 3 case
```

For structured output use `--format json`: one JSON object per file, sentences carrying line numbers, comments and word/multiword/empty counts, tokens keeping the raw ten columns — convenient for wrappers in other languages.

For spreadsheets use `--format tsv`: a fixed 13-column header (`sentence / sent_line / kind / id / form / lemma / upos / xpos / feats / head / deprel / deps / misc`), one row per token. CoNLL-U columns cannot contain tabs, so no quoting is needed:

```python
import pandas as pd
df = pd.read_csv("dump.tsv", sep="\t", dtype=str)
df[df.kind == "word"].groupby("deprel").size().sort_values(ascending=False)
```

## Differential testing

`tools/diff_test.py` compares this package's `dump` against the Python `conllu` reference parser line by line and field by field, and additionally checks zero validation errors, lossless `roundtrip`, and UAS=LAS=100% on self-evaluation.

```bash
python3 tools/fetch_corpus.py   # download official UD data into data/ud/ (never committed)
python3 tools/diff_test.py --report
```

Current results (details in [DIFF-REPORT.md](DIFF-REPORT.md)):

| file | sentences | dump rows | field mismatches |
| --- | --- | --- | --- |
| en_ewt-ud-dev | 2001 | 27513 | 0 |
| en_ewt-ud-test | 2077 | 27528 | 0 |
| zh_gsd-ud-dev | 500 | 13166 | 0 |
| zh_gsd-ud-test | 500 | 12511 | 0 |
| ja_gsd-ud-dev | 507 | 12795 | 0 |
| ja_gsd-ud-test | 543 | 13578 | 0 |

Differential testing caught two real bugs, both fixed: DEPS entries pointing at empty nodes such as `8.1:obj` were parsed as the number `81` (a spurious out-of-range error), and the legal enhanced relation `ref` was flagged as an unknown label.

**Golden regression.** Differential tests need external corpora and only prove "the numbers match", not "the output looks right". `tests/golden/cases.json` pins eleven CLI invocations (`stats` / `validate` / `dump` in three formats / `eval` / `docs` / `analyze` / cross-sentence validation / JSON diagnostics) together with their expected stdout, so column order, label casing, JSON keys and padding width changes are all caught:

```bash
python3 tools/golden_test.py            # compare; 11/11 must pass
python3 tools/golden_test.py --update   # regenerate after an intentional change
```

The golden set runs in CI right after the differential test in the `integration` job, so "unit tests green but CLI text quietly changed" cannot slip through.

## API reference

Full doc comments can be previewed locally with `moon doc --serve` (default `http://127.0.0.1:3000`), and appear on the mooncakes docs page after publishing.

**Parsing and serialization**

| function | description |
| --- | --- |
| `parse(text) -> Array[Sentence] raise ConlluError` | split on blank lines, check 10 columns and ID shape, errors carry line numbers |
| `to_string(sentences) -> String` | serialize the whole document, canonical blank line after each sentence |
| `Sentence::to_string()` | serialize one sentence |
| `Sentence::to_json()` | one sentence as a JSON object (counts, comments, raw columns per token) |
| `to_json(sentences, source?=...)` | whole document as JSON, `{"source": ..., "sentences": [...]}` |
| `Sentence::words()` / `rows()` / `comments()` | word rows / all rows / comments |
| `Sentence::word_count()` | word rows only (excludes multiword and empty nodes) |
| `Sentence::word(i) -> Token?` | 1-based word lookup |
| `Sentence::comment(key)` | value of `# key = value` |
| `Sentence::comment_value(key)` | general form of the above, `Some(value)` / `None` |
| `Token::head() -> Int32?` | HEAD as integer, `None` when non-numeric |
| `Token::is_word()` / `is_multiword()` / `is_empty_node()` | row kind |
| `Token::to_line()` | restore one 10-column line |
| `Token::enhanced_deps() -> Array[EnhancedDep]` | DEPS split into `head:rel`, empty-node heads preserved |
| `EnhancedDep::head()` / `rel()` / `to_string()` | one enhanced dependency |

**Validation**

| function | description |
| --- | --- |
| `validate(sentences) -> Array[Diagnostic]` | whole-document validation |
| `validate_sentence(sentence)` | single-sentence validation |
| `validate_documents(sentences)` | cross-sentence checks: sent_id / newdoc / newpar uniqueness and presence |
| `Diagnostic::to_string()` | `line 7: error [CODE] message` |
| `Diagnostic::to_json()` | one diagnostic as a JSON object |
| `diagnostics_to_json(diagnostics)` | diagnostics as a JSON array |
| `count_errors(diagnostics) -> Int32` | count only `Error` severity |

**Dependency trees**

| function | description |
| --- | --- |
| `children(s, head)` / `descendants(s, node)` | direct children / all descendants |
| `path(s, from, to) -> Array[Int32]?` | HEAD path from `from` up to ancestor `to` (`to = 0` walks to the root) |
| `is_ancestor(s, a, b)` | whether `a` is an ancestor of `b` |
| `depth(s, i)` / `max_depth(s)` | depth / maximum depth |
| `is_projective(s)` | whether no arcs cross |
| `roots(s)` / `is_single_rooted(s)` | roots / exactly one root |

**Documents and paragraphs**

| function | description |
| --- | --- |
| `documents(sentences) -> Array[Document]` | group by `# newdoc` / `# newpar` |
| `Document::id()` / `paragraph_count()` / `sentence_count()` | document id and two-level counts |
| `Document::paragraphs()` / `sentences()` | paragraph list / flattened sentences |
| `Paragraph::id()` / `sentences()` / `sentence_count()` | paragraph id and sentences |
| `Sentence::has_newdoc()` / `has_newpar()` | whether the sentence opens a new document / paragraph |
| `Sentence::newdoc_id()` / `newpar_id()` | id value of the corresponding comment |

**Coverage analysis**

| function | description |
| --- | --- |
| `coverage(sentences) -> Coverage` | tag hits, out-of-spec tags, tree shape and length statistics |
| `merge_coverage(covs) -> Coverage` | merge files: union tags, add counts, re-weight average depth |
| `Coverage::upos_used()` / `deprel_used()` | tags actually present (alphabetical) |
| `Coverage::upos_missing()` / `deprel_missing()` | spec tags never seen |
| `Coverage::projectivity()` | share of projective sentences (percent) |
| `Coverage::full_upos()` / `full_deprel()` | whether the whole spec tagset is covered |
| `Coverage::to_string()` | multi-line report, printed by `analyze` |
| `Coverage::to_json()` | the same data as a JSON object |

**Evaluation and statistics**

| function | description |
| --- | --- |
| `evaluate(gold, pred) -> EvalResult` | aligned UAS / UUAS / LAS |
| `EvalResult::uas()` / `uuas()` / `las()` | percent scores; `uuas` ignores direction |
| `evaluate_by_label(gold, pred)` | per-gold-relation LAS, worst first |
| `evaluate_by_document(gold, pred)` | per-`# newdoc` scores, worst first |
| `DocumentScore::id()` / `sentences()` / `tokens()` / `uas()` / `las()` | one document's scores |
| `LabelScore::las()` / `to_string()` | per-relation accuracy |
| `stats(sentences) -> Stats` | sentences, words, multiword, empty nodes, comments, max length, docs |
| `Stats::average_length()` / `to_string()` | average sentence length / one-line summary |
| `Stats::to_json()` | statistics as a JSON object |

## End to end

One command runs the whole pipeline for you (UD fixtures are downloaded on first run; the script exits 0 only when all nine steps pass):

```bash
python3 examples/demo.py
# 1/9 stats -> 2/9 validate --documents -> 3/9 docs -> 4/9 analyze (two splits + TOTAL)
# 5/9 eval -> 6/9 labels --format csv -> 7/9 dump --format tsv -> 8/9 roundtrip
# 9/9 compress (read-back verified)
# demo finished: all nine steps exited 0
```

The demo is also a step in the CI `integration` job, so the workflow documented here and the workflow that actually runs cannot drift apart.

The same tour on the bundled sample (`examples/sample.conllu`), with real outputs:

```bash
moon run cmd/main -- stats      examples/sample.conllu
# sentences=1 words=5 multiword=0 empty=0 comments=2 max_len=5 avg_len=5 docs=0
# errors=0

moon run cmd/main -- validate   examples/sample.conllu --documents
# diagnostics=0 errors=0 warnings=0

moon run cmd/main -- docs       examples/sample.conllu
# doc    1 id=-                        sentences=    1 paragraphs=1
# documents=1 paragraphs=1

moon run cmd/main -- dump       examples/sample.conllu --format tsv
# sentence	sent_line	kind	id	form	lemma	upos	xpos	feats	head	deprel	deps	misc
# 1	1	word	1	I	I	PRON	PRP	_	2	nsubj	_	_

moon run cmd/main -- compress   examples/sample.conllu /tmp/sample.conllu.gz
# compress: 1 sentences 216 -> 186 bytes (86.11% of input)
# verify: /tmp/sample.conllu.gz reads back identically
```

The evaluation workflow is three steps: `stats` / `validate` to confirm the corpus is usable, `eval` for the aggregate score, then `eval --by-document` and `labels` to locate which documents and relations are wrong:

```bash
moon run cmd/main -- eval   gold.conllu pred.conllu
moon run cmd/main -- eval   gold.conllu pred.conllu --by-document
moon run cmd/main -- labels gold.conllu pred.conllu --format csv
```

## License and data

Code is Apache-2.0. UD treebanks are CC BY-SA 4.0 and are downloaded only as test fixtures — never committed to the repository or included in the published package. Please follow the Universal Dependencies project's attribution requirements when citing them. See [NOTICE](NOTICE) for third-party components and licenses.

**Acceptance verification**: item-by-item evidence against the acceptance criteria, one-command reproduction steps and measured test coverage are in [VERIFICATION.md](VERIFICATION.md).
