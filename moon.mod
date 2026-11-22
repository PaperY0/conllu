// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "PaperY0/conllu"

version = "0.5.0"

readme = "README.mbt.md"

repository = "https://github.com/PaperY0/conllu"

license = "Apache-2.0"

keywords = [
  "conllu",
  "universal-dependencies",
  "nlp",
  "dependency-parsing",
  "treebank",
]

preferred_target = "wasm"

description = "CoNLL-U / Universal Dependencies toolchain: lossless parse and serialize, spec validation, tree queries, UAS/LAS evaluation, corpus statistics, document grouping, coverage analysis, per-document evaluation, JSON reports."

import {
  "moonbitlang/x@0.5.8",
}
