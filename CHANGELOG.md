# Changelog

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
