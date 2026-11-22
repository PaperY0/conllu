# Changelog

## 0.4.0 — 2026-11-22

增强依存的结构化访问、跨句校验与 JSON 输出。

- `Token::enhanced_deps()` / `EnhancedDep`：把 DEPS 拆成 `head:rel`，空节点头保持 `5.1`
  而不折成单词索引；`_` 返回空数组。
- `validate_documents(sentences)`：跨句 checks。缺 `# sent_id`（警告）、`sent_id` 重复（错误）、
  `# newdoc id` 重用、同一文档内段落 id 重用、`# newpar` 出现在 `# newdoc` 之前（警告）。
  CLI `validate <file> --documents` 两层一起跑；UD 三份 dev 语料为 0 诊断。
- `Stats::to_json()` / `Coverage::to_json()`：统计与覆盖报告的对象形式。
  CLI `stats --format json`、`analyze --format json`（`{"files":[...],"total":{...}}`）。
- 报告排序改用按码点比较的 `compare_labels`：`String::compare` 在本版 core 里先比长度，
  标签列表会排成 `X, ADJ, ADP, ...`。

## 0.3.0 — 2026-11-22

按文档评测、多文件覆盖汇总与 TSV 导出。

- `evaluate_by_document(gold, pred)` / `DocumentScore`：按 gold 的 `# newdoc` 分组分别算
  UAS / LAS，最差文档排最前；预测漏掉整篇文档时该行对齐词为 0，不会把分数摊平。
  CLI `eval <gold> <pred> --by-document` 打表并附整体 total。
- `merge_coverage(covs)`：多文件合并，标签取并集、计数相加、缺失标签按规范重算、平均树深
  按词数加权重算；`analyze` 接受多个文件，输出一行一文件加一行 TOTAL。
  六个 UD 切分合计 6,128 句 / 100,238 词，合并后覆盖 17/17 UPOS 与 37/37 DEPREL
  （单独任何一个切分都做不到）。
- CLI `dump --format tsv`：固定 13 列表头，一行一个 token，可直接
  `pandas.read_csv(sep="\t")`。
- 差分脚本新增第五项检查：TSV 表头、行数以及逐行 `kind/id/form/upos/head/deprel`
  必须与行式 dump 一致；六个切分全部通过。

## 0.2.0 — 2026-11-22

文档结构、覆盖分析与压缩写回，新增 API，与 0.1.x 兼容。

- `documents(sentences)`：按 `# newdoc` / `# newpar` 还原 `Document → Paragraph → Sentence`，
  id 取自注释；无边界声明的文件返回一个匿名文档。新增 `Sentence::has_newdoc` /
  `has_newpar` / `newdoc_id` / `newpar_id` / `comment_value`。
- `coverage(sentences)`：一次遍历统计 UPOS / DEPREL 命中与缺失、规范外标签、未标注词、
  投射句占比、最大与平均树深、长句（>50 词）、多词 token、空节点、文档与段落数；
  `Coverage::full_upos()` / `full_deprel()` / `projectivity()` 便于断言。
- CLI `compress <in> <out>`：规范序列化后写回，`<out>` 以 `.gz` 结尾时压缩，写完再读回来比对。
  UD_English-EWT dev 实测 1,899,904 → 357,823 字节（18.83%）。
- CLI `docs <file>`：文档 / 段落结构与句数，多于一段的文档展开列出每段。
- CLI `analyze <file>`：覆盖报告；出现规范外 UPOS 或 DEPREL 时退出码 1，可当语料门槛。
- CLI `labels --format csv`：`label,gold,correct,las` 四列，RFC 4180 引号规则，便于进表格。

## 0.1.1 — 2026-11-22

评测与命令行补强，API 与 0.1.0 兼容。

- `EvalResult::uuas()`：不计方向的附着分数，解析器把方向搞反但仍找对词对时给分。
- `evaluate_by_label()` / `LabelScore`：按 gold 依存关系拆开的 LAS，最差的关系排最前。
- `path(sentence, from, to)`：沿 HEAD 走到指定祖先的路径（`to = 0` 走到根）。
- `is_single_rooted(sentence)`：单根检查。
- CLI 新增 `labels <gold> <pred>`；`dump` 支持 `--format json`。
- CLI 可直接读 `.conllu.gz`（core `compress/gzip` + UTF-8 解码），六个子命令都适用。
- 差分语料增加 UD_Japanese-GSD：六个切分共 6,128 句、107,091 行，零字段差异。
- 差分脚本新增 JSON dump 一致性检查（可解析、句子与 token 数与行式 dump 相同）。
- README 增加 API 参考，`moon doc` 可本地生成文档。

## 0.1.0 — 2026-11-22

首个版本，覆盖 CoNLL-U 的读写、校验、树操作与评测四层能力。

- `parse` / `to_string`：无损解析与序列化，保留原始 10 列、注释、多词 token
  (`5-6`)、空节点 (`5.1`) 和 CRLF；语法错误抛 `ConlluError(line, message)`。
- `validate` / `count_errors`：ID 连续性、多词跨度、HEAD 缺失/越界/自指、单根、
  成环、DEPS 语法与范围、17 个 UPOS 与 37 个 UD v2 依存关系（允许 `ref` 等增强关系）。
- `children` / `descendants` / `depth` / `max_depth` / `is_ancestor` /
  `is_projective` / `roots`：依存树查询与投射性判定。
- `evaluate` / `uas` / `las`：金标与预测对齐后的 UAS/LAS 百分制评测，长度不等的句子
  计入 `skipped_sentences`。
- `stats`：句数、词数、多词 token、空节点、注释、最长句、平均句长、树库来源。
- CLI：`stats` / `validate` / `eval` / `dump` / `roundtrip`。
- 与 Python `conllu` 在 UD_English-EWT、UD_Chinese-GSD 的 dev/test 四个切分上
  逐字段零差异（5,078 句，74,718 行），见 `DIFF-REPORT.md`。
