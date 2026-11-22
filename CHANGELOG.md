# Changelog

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
