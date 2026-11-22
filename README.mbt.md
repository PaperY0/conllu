# PaperY0/conllu

[![CI](https://github.com/PaperY0/conllu/actions/workflows/ci.yml/badge.svg)](https://github.com/PaperY0/conllu/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-PaperY0%2Fconllu-blue)](https://mooncakes.io/docs/#/PaperY0/conllu/)
[![license](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

MoonBit 里的 **CoNLL-U / Universal Dependencies** 工具链：无损解析与序列化、规范校验、依存树查询、文档/段落分组、语料覆盖分析、UAS/LAS 评测、语料统计，外加一个可直接跑的 CLI（含 gzip 读与写）。

CoNLL-U 是 UD 树库（Universal Dependencies 项目，200+ 语言树库）的唯一交换格式：每句 10 列制表符分隔，句子之间空行分隔，`#` 开头是注释，ID 可以是 `12`（普通词）、`5-6`（多词 token）、`5.1`（空节点）。生态里做分词、词性的包已经不少，但**句法层**（HEAD/DEPREL 树、投射性、UAS/LAS）此前是空白，这个包补的就是这一层。

## 特性

- **无损**：原始 10 列全部保留在 `Token` 里，`to_string` 能逐字节还原（含多词 token、空节点、注释），不认识的列不会被"顺手规范化"。
- **严格报错**：`parse` 对列数、ID 形态、HEAD 数字性做硬校验，出错抛 `ConlluError(line, message)`，行号直接给到源文件。
- **规范校验**：17 个 UPOS、37 个 UD v2 依存关系（含增强 `ref`）、ID 连续性、单根、自环、成环、DEPS 语法与范围，都按 CoNLL-U 规范检查。
- **评测**：`evaluate(gold, pred)` 给出 UAS / LAS（百分制），按 1-based 词序对齐，长度不等的句子计入 `skipped_sentences` 而不是静默丢掉。
- **树查询**：`children` / `descendants` / `depth` / `is_ancestor` / `is_projective` / `roots` / `path` / `is_single_rooted`。
- **文档分组**：按 `# newdoc` / `# newpar` 还原 `Document → Paragraph → Sentence` 三层结构，没有边界声明的文件仍算一个匿名文档。
- **覆盖分析**：`coverage` 一次遍历统计 UPOS 与 DEPREL 命中率、规范外标签、投射性与树深、长句与空节点，CLI 里可直接当语料门槛用；`merge_coverage` 把 dev/test 合成一张表。
- **按文档评测**：`evaluate_by_document` 按 `# newdoc` 分组算 UAS / LAS，最差的文档排最前；预测漏掉整篇文档时显示为 0 对齐词，不会把分数悄悄摊平。
- **统计**：句数、词数、多词 token、空节点、注释、最长句、平均句长、涉及的树库。
- **对拍过**：与 Python `conllu` 参考解析器在 UD_English-EWT、UD_Chinese-GSD、UD_Japanese-GSD 的 dev/test 六个切分（6,128 句、107,091 行）上逐字段零差异，见 [DIFF-REPORT.md](DIFF-REPORT.md)。

## 安装

```bash
moon add PaperY0/conllu
```

## 解析与序列化

```mbt check
///|
test {
  let text = "1\tI\tI\tPRON\tPRP\t_\t2\tnsubj\t_\t_\n2\tsaw\tsee\tVERB\tVBD\t_\t0\troot\t_\t_\n3\tthe\tthe\tDET\tDT\t_\t4\tdet\t_\t_\n4\tcat\tcat\tNOUN\tNN\t_\t2\tobj\tSpaceAfter=No\t_\n5\t.\t.\tPUNCT\t.\t_\t2\tpunct\t_\t_\n"
  let sentences = @conllu.parse(text) catch { _ => [] }
  assert_eq(sentences.length(), 1)
  let sentence = sentences[0]
  assert_eq(sentence.word_count(), 5)
  assert_eq(sentence.words()[1].lemma, "see")
  // HEAD 是解析过的整数，可直接用于树操作
  assert_eq(sentence.words()[1].head(), Some(0))
  // 序列化补回规范要求的句末空行
  assert_eq(@conllu.to_string(sentences), text + "\n")
}
```

`Sentence` 同时保留注释和全部行：`sentence.rows()` 拿到 `Word` / `Multiword` / `Empty` 三类行，`sentence.comment("text")` 直接取 `# text = ...` 的值。

## 校验

```mbt check
///|
test {
  let broken = "1\ta\ta\tNOUN\tNN\t_\t0\troot\t_\t_\n2\tb\tb\tNOUN\tNN\t_\t0\troot\t_\t_\n"
  let sentences = @conllu.parse(broken) catch { _ => [] }
  let diagnostics = @conllu.validate(sentences)
  assert_eq(@conllu.count_errors(diagnostics), 1)
  assert_eq(diagnostics[0].code, "ROOT_COUNT")
}
```

校验规则按 code 分类，方便 CI 里按类型放行或拦截：

| code | 含义 |
| --- | --- |
| `ID_SEQUENCE` | 词 ID 不是从 1 开始连续递增 |
| `MULTIWORD_SPAN` | 多词 token 的 `5-6` 越界 |
| `HEAD_MISSING` / `HEAD_RANGE` / `HEAD_SELF` | HEAD 非数字、越界、指向自己 |
| `ROOT_COUNT` | 根节点不是恰好 1 个 |
| `CYCLE` | 沿 HEAD 走不到根 |
| `DEPS_FORMAT` / `DEPS_RANGE` / `DEPS_DEPREL` / `DEPS_MISSING` | DEPS 语法、范围、关系名、空节点缺关系 |
| `UPOS_UNKNOWN` / `DEPREL_UNKNOWN` | 不在 UD v2 标签集内 |
| `FORM_EMPTY` / `FORM_SPACE` | FORM 为空或含空白 |

## 文档与段落

树库不是扁平的句子列表：`# newdoc` 与 `# newpar` 行标出每句属于哪个文档、哪一段。`documents()` 把这层关系还原成三层结构，id 直接取自注释；没有边界声明的文件返回一个 id 为空的匿名文档，而不是空数组。

```mbt check
///|
test {
  let text = "# newdoc id = d1\n# newpar id = p1\n# sent_id = 1\n1\ta\ta\tNOUN\tNN\t_\t0\troot\t_\t_\n\n# newpar id = p2\n# sent_id = 2\n1\tb\tb\tNOUN\tNN\t_\t0\troot\t_\t_\n"
  let docs = @conllu.documents(@conllu.parse(text) catch { _ => [] })
  assert_eq(docs.length(), 1)
  assert_eq(docs[0].id(), "d1")
  assert_eq(docs[0].paragraph_count(), 2)
  assert_eq(docs[0].paragraphs()[0].id(), "p1")
  assert_eq(docs[0].paragraphs()[1].id(), "p2")
  assert_eq(docs[0].sentence_count(), 2)
}
```

`# newdoc` 一行同时开启新段落，因此文档不会继承上一段的尾巴；分组信息本身就是普通注释，`Document::to_string` 写回时这些行原样保留。

## 语料覆盖分析

句数词数只能说明体量，说明不了质量。`coverage` 一次遍历回答四个问题：规范里的 17 个 UPOS、37 个 DEPREL 各用到了几个；有没有规范外的标签；树有多深、多少句不投射；长句和空节点有多少。

```mbt check
///|
test {
  let text = "1\ta\ta\tNOUN\tNN\t_\t0\troot\t_\t_\n2\tb\tb\tUNKNOWN\tNN\t_\t1\tweird\t_\t_\n"
  let cov = @conllu.coverage(@conllu.parse(text) catch { _ => [] })
  assert_eq(cov.upos_used.length(), 1)
  assert_eq(cov.unknown_upos[0], "UNKNOWN")
  assert_eq(cov.unknown_deprel[0], "weird")
  assert_false(cov.full_upos())
  assert_eq(cov.projectivity(), 100.0)
}
```

多文件时用 `merge_coverage` 或直接给 CLI 多个路径：标签取并集、计数相加、缺失标签按规范重算，平均树深按词数加权重算，不会出现"平均的平均"：

```bash
moon run cmd/main -- analyze data/ud/en_ewt-ud-dev.conllu data/ud/zh_gsd-ud-test.conllu
```

```
file                            sentences   words  upos deprel unknown projective  depth
en_ewt-ud-dev.conllu                2001   25148 17/17  36/37       0     98.35%     11
zh_gsd-ud-test.conllu                500   12010 16/17  29/37       0      97.2%     10
TOTAL                               2501   37158 17/17  37/37       0     98.12%     11
```

## 评测 UAS / LAS

```mbt check
///|
test {
  let gold = "1\ta\ta\tNOUN\tNN\t_\t2\tnsubj\t_\t_\n2\tb\tb\tVERB\tVB\t_\t0\troot\t_\t_\n"
  let pred = "1\ta\ta\tNOUN\tNN\t_\t0\tnsubj\t_\t_\n2\tb\tb\tVERB\tVB\t_\t0\troot\t_\t_\n"
  let g = @conllu.parse(gold) catch { _ => [] }
  let p = @conllu.parse(pred) catch { _ => [] }
  let result = @conllu.evaluate(g, p)
  assert_eq(result.uas(), 50.0)
  assert_eq(result.las(), 50.0)
}
```

整体分数会掩盖"某几篇文档全错"的情况，`evaluate_by_document` 按 gold 的 `# newdoc` 分组分别算分，最差的排最前：

```mbt check
///|
test {
  let gold = "# newdoc id = d1\n1\ta\ta\tNOUN\tNN\t_\t2\tnsubj\t_\t_\n2\tb\tb\tVERB\tVB\t_\t0\troot\t_\t_\n"
  let pred = "# newdoc id = d1\n1\ta\ta\tNOUN\tNN\t_\t0\troot\t_\t_\n2\tb\tb\tVERB\tVB\t_\t1\tnsubj\t_\t_\n"
  let scores = @conllu.evaluate_by_document(
    @conllu.parse(gold) catch {
      _ => []
    },
    @conllu.parse(pred) catch {
      _ => []
    },
  )
  assert_eq(scores.length(), 1)
  assert_eq(scores[0].id(), "d1")
  assert_eq(scores[0].sentences(), 1)
  assert_eq(scores[0].tokens(), 2)
  // 两条边都接反了：UAS 与 LAS 都是 0。
  assert_eq(scores[0].las(), 0.0)
}
```

CLI 里 `eval <gold> <pred> --by-document` 直接打表，末尾附整体 total。

## 命令行

包自带 `cmd/main`，子命令都直接吃文件，纯文本和 `.conllu.gz` 都支持，输出去 `.gz` 时自动压缩：

```bash
moon run cmd/main -- stats      treebank.conllu   # 句数/词数/多词/空节点/最长句/树库
moon run cmd/main -- validate   treebank.conllu   # 诊断列表，有 error 时退出码 1
moon run cmd/main -- eval       gold.conllu pred.conllu
moon run cmd/main -- eval       gold.conllu pred.conllu --by-document
moon run cmd/main -- labels     gold.conllu pred.conllu   # 按关系拆开的 LAS
moon run cmd/main -- labels     gold.conllu pred.conllu --format csv
moon run cmd/main -- docs       treebank.conllu   # 文档/段落结构与句数
moon run cmd/main -- analyze    treebank.conllu   # 覆盖报告，规范外标签时退出码 1
moon run cmd/main -- analyze    dev.conllu test.conllu   # 多文件表格 + TOTAL
moon run cmd/main -- dump       treebank.conllu   # 归一化 dump，用于对拍
moon run cmd/main -- dump       treebank.conllu --format json
moon run cmd/main -- dump       treebank.conllu --format tsv
moon run cmd/main -- roundtrip  treebank.conllu   # 解析再序列化，校验无损
moon run cmd/main -- compress   treebank.conllu out.conllu.gz   # 规范序列化 + gzip 写回
```

`compress` 会把自己写出的文件再读回来比对，写坏了不会静默产出一个"看着像"的文件。UD_English-EWT dev 实测 1,899,904 → 357,823 字节（18.83%）。

`labels --format csv` 输出 `label,gold,correct,las` 四列，按 RFC 4180 处理引号，可直接喂给表格或 pandas；默认仍是终端对齐表。

`dump` 的格式是稳定的行式契约（`D/S/w/m/e` 前缀），差分脚本就靠它跟别的实现比对：

```
D 2001
S 7 0 0 4
w 1 From ADP 3 case
```

需要结构化输出时用 `--format json`：一份文件一个 JSON 对象，句子带行号、注释、词/多词/空节点计数，token 保留原始 10 列值，方便别的语言写包装器。

要直接进表格就用 `--format tsv`：固定 13 列表头（`sentence / sent_line / kind / id / form / lemma / upos / xpos / feats / head / deprel / deps / misc`），一行一个 token。CoNLL-U 的列本身不允许制表符，所以不用处理引号：

```python
import pandas as pd
df = pd.read_csv("dump.tsv", sep="\t", dtype=str)
df[df.kind == "word"].groupby("deprel").size().sort_values(ascending=False)
```

## 差分对拍

`tools/diff_test.py` 把本包的 `dump` 与 Python `conllu` 的输出逐行逐字段比对，另外检查 `validate` 零 error、`roundtrip` 无损、自评 UAS=LAS=100%。

```bash
python3 tools/fetch_corpus.py   # 下载 UD 官方语料到 data/ud/（语料不随包分发）
python3 tools/diff_test.py --report
```

当前结果（详见 [DIFF-REPORT.md](DIFF-REPORT.md)）：

| 文件 | 句数 | dump 行数 | 字段不一致 |
| --- | --- | --- | --- |
| en_ewt-ud-dev | 2001 | 27513 | 0 |
| en_ewt-ud-test | 2077 | 27528 | 0 |
| zh_gsd-ud-dev | 500 | 13166 | 0 |
| zh_gsd-ud-test | 500 | 12511 | 0 |
| ja_gsd-ud-dev | 507 | 12795 | 0 |
| ja_gsd-ud-test | 543 | 13578 | 0 |

对拍过程里发现并修掉的两个真实 bug：`8.1:obj` 这类指向空节点的 DEPS 被当成数字 `81`（越界误报），以及增强 DEPS 里合法的 `ref` 关系被判成未知标签。

## API 参考

完整文档注释可用 `moon doc --serve` 在本地预览（默认 `http://127.0.0.1:3000`），发布后也会出现在 mooncakes 的文档页。

**解析与序列化**

| 函数 | 说明 |
| --- | --- |
| `parse(text) -> Array[Sentence] raise ConlluError` | 按空行分句，校验 10 列与 ID 形态，出错带行号 |
| `to_string(sentences) -> String` | 序列化整份文档，每句后补规范空行 |
| `Sentence::to_string()` | 单句序列化 |
| `Sentence::words()` / `rows()` / `comments()` | 词行 / 全部行 / 注释 |
| `Sentence::word_count()` | 词行数量（不含多词与空节点） |
| `Sentence::word(i) -> Token?` | 按 1-based 词序取词 |
| `Sentence::comment(key)` | 取 `# key = value` 的 value |
| `Sentence::comment_value(key)` | 同上的通用版本，`Some(value)` / `None` |
| `Token::head() -> Int32?` | HEAD 解析为整数，非数字返回 `None` |
| `Token::is_word()` / `is_multiword()` / `is_empty_node()` | 行类型判定 |
| `Token::to_line()` | 还原一行 10 列 |

**校验**

| 函数 | 说明 |
| --- | --- |
| `validate(sentences) -> Array[Diagnostic]` | 全文档校验 |
| `validate_sentence(sentence)` | 单句校验 |
| `count_errors(diagnostics) -> Int32` | 只数 `Error` 级别 |
| `Diagnostic::to_string()` | `line 12: error [ROOT_COUNT] ...` |

**依存树**

| 函数 | 说明 |
| --- | --- |
| `children(s, head)` / `descendants(s, node)` | 直接孩子 / 全部后代 |
| `path(s, from, to) -> Array[Int32]?` | 从 `from` 沿 HEAD 到祖先 `to`（`to = 0` 走到根） |
| `is_ancestor(s, a, b)` | `a` 是否为 `b` 的祖先 |
| `depth(s, i)` / `max_depth(s)` | 深度 / 最大深度 |
| `is_projective(s)` | 是否无交叉弧 |
| `roots(s)` / `is_single_rooted(s)` | 根节点 / 是否单根 |

**文档与段落**

| 函数 | 说明 |
| --- | --- |
| `documents(sentences) -> Array[Document]` | 按 `# newdoc` / `# newpar` 分组 |
| `Document::id()` / `paragraph_count()` / `sentence_count()` | 文档 id 与两级计数 |
| `Document::paragraphs()` / `sentences()` | 段落列表 / 展开成句子列表 |
| `Paragraph::id()` / `sentences()` / `sentence_count()` | 段落 id 与句数 |
| `Sentence::has_newdoc()` / `has_newpar()` | 是否开启新文档 / 新段落 |
| `Sentence::newdoc_id()` / `newpar_id()` | 对应注释的 id 值 |

**覆盖分析**

| 函数 | 说明 |
| --- | --- |
| `coverage(sentences) -> Coverage` | 标签命中、规范外标签、树形与句长统计 |
| `merge_coverage(covs) -> Coverage` | 合并多文件：标签取并集、计数相加、平均树深按词数重算 |
| `Coverage::upos_used()` / `deprel_used()` | 实际出现的标签（字母序） |
| `Coverage::upos_missing()` / `deprel_missing()` | 规范里没出现的标签 |
| `Coverage::projectivity()` | 投射句占比（百分制） |
| `Coverage::full_upos()` / `full_deprel()` | 是否覆盖全部规范标签 |
| `Coverage::to_string()` | 多行报告，`analyze` 直接打印 |

**评测与统计**

| 函数 | 说明 |
| --- | --- |
| `evaluate(gold, pred) -> EvalResult` | 对齐后计算 UAS / UUAS / LAS |
| `EvalResult::uas()` / `uuas()` / `las()` | 百分制分数；`uuas` 不计方向 |
| `evaluate_by_label(gold, pred)` | 按 gold 关系拆开的 LAS，最差的排最前 |
| `evaluate_by_document(gold, pred)` | 按 `# newdoc` 分组评测，最差的文档排最前 |
| `DocumentScore::id()` / `sentences()` / `tokens()` / `uas()` / `las()` | 单文档分数 |
| `LabelScore::las()` / `to_string()` | 单关系准确率 |
| `stats(sentences) -> Stats` | 句数、词数、多词、空节点、注释、最长句、树库 |
| `Stats::average_length()` / `to_string()` | 平均句长 / 一行摘要 |

## 许可与语料

代码 Apache-2.0。UD 树库是 CC BY-SA 4.0，只作为测试夹具下载，不进仓库、不进发布包；引用请遵循 Universal Dependencies 项目的署名要求。
