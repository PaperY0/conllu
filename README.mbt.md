# PaperY0/conllu

[![CI](https://github.com/PaperY0/conllu/actions/workflows/ci.yml/badge.svg)](https://github.com/PaperY0/conllu/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-PaperY0%2Fconllu-blue)](https://mooncakes.io/docs/#/PaperY0/conllu/)
[![license](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

MoonBit 里的 **CoNLL-U / Universal Dependencies** 工具链：无损解析与序列化、规范校验、依存树查询、UAS/LAS 评测、语料统计，外加一个可直接跑的 CLI。

CoNLL-U 是 UD 树库（Universal Dependencies 项目，200+ 语言树库）的唯一交换格式：每句 10 列制表符分隔，句子之间空行分隔，`#` 开头是注释，ID 可以是 `12`（普通词）、`5-6`（多词 token）、`5.1`（空节点）。生态里做分词、词性的包已经不少，但**句法层**（HEAD/DEPREL 树、投射性、UAS/LAS）此前是空白，这个包补的就是这一层。

## 特性

- **无损**：原始 10 列全部保留在 `Token` 里，`to_string` 能逐字节还原（含多词 token、空节点、注释），不认识的列不会被"顺手规范化"。
- **严格报错**：`parse` 对列数、ID 形态、HEAD 数字性做硬校验，出错抛 `ConlluError(line, message)`，行号直接给到源文件。
- **规范校验**：17 个 UPOS、37 个 UD v2 依存关系（含增强 `ref`）、ID 连续性、单根、自环、成环、DEPS 语法与范围，都按 CoNLL-U 规范检查。
- **评测**：`evaluate(gold, pred)` 给出 UAS / LAS（百分制），按 1-based 词序对齐，长度不等的句子计入 `skipped_sentences` 而不是静默丢掉。
- **树查询**：`children` / `descendants` / `depth` / `is_ancestor` / `is_projective` / `roots`。
- **统计**：句数、词数、多词 token、空节点、注释、最长句、平均句长、涉及的树库。
- **对拍过**：与 Python `conllu` 参考解析器在 UD_English-EWT 与 UD_Chinese-GSD 的 dev/test 四个切分上逐字段零差异，见 [DIFF-REPORT.md](DIFF-REPORT.md)。

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

## 命令行

包自带 `cmd/main`，五个子命令都直接吃文件，纯文本和 `.conllu.gz` 都支持：

```bash
moon run cmd/main -- stats      treebank.conllu   # 句数/词数/多词/空节点/最长句/树库
moon run cmd/main -- validate   treebank.conllu   # 诊断列表，有 error 时退出码 1
moon run cmd/main -- eval       gold.conllu pred.conllu
moon run cmd/main -- labels     gold.conllu pred.conllu   # 按关系拆开的 LAS
moon run cmd/main -- dump       treebank.conllu   # 归一化 dump，用于对拍
moon run cmd/main -- dump       treebank.conllu --format json
moon run cmd/main -- roundtrip  treebank.conllu   # 解析再序列化，校验无损
```

`dump` 的格式是稳定的行式契约（`D/S/w/m/e` 前缀），差分脚本就靠它跟别的实现比对：

```
D 2001
S 7 0 0 4
w 1 From ADP 3 case
```

需要结构化输出时用 `--format json`：一份文件一个 JSON 对象，句子带行号、注释、词/多词/空节点计数，token 保留原始 10 列值，方便别的语言写包装器。

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

**评测与统计**

| 函数 | 说明 |
| --- | --- |
| `evaluate(gold, pred) -> EvalResult` | 对齐后计算 UAS / UUAS / LAS |
| `EvalResult::uas()` / `uuas()` / `las()` | 百分制分数；`uuas` 不计方向 |
| `evaluate_by_label(gold, pred)` | 按 gold 关系拆开的 LAS，最差的排最前 |
| `LabelScore::las()` / `to_string()` | 单关系准确率 |
| `stats(sentences) -> Stats` | 句数、词数、多词、空节点、注释、最长句、树库 |
| `Stats::average_length()` / `to_string()` | 平均句长 / 一行摘要 |

## 许可与语料

代码 Apache-2.0。UD 树库是 CC BY-SA 4.0，只作为测试夹具下载，不进仓库、不进发布包；引用请遵循 Universal Dependencies 项目的署名要求。
