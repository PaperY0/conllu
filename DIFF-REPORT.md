# DIFF-REPORT：PaperY0/conllu 对 `conllu` 参考解析器的差分对拍

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

另外每份文件还检查四件事：

1. `validate` 必须 0 error（官方树库本身合法）；
2. `roundtrip` 必须无损（序列化后逐字节一致，允许补上结尾空行）；
3. 自己对自己 `eval` 必须 UAS=LAS=100%，用来证明对齐逻辑没有漏词；
4. `dump --format json` 必须能被 `json.loads` 解析，且句子数、token 数与行式 dump 完全一致。

## 三、结果

| 文件 | 句数 | 行数 | 字段不一致 | 校验 error | UAS | LAS |
| --- | --- | --- | --- | --- | --- | --- |
| `en_ewt-ud-dev.conllu` | 2001 | 27513 | 0 | 0 | 100.00 | 100.00 |
| `en_ewt-ud-test.conllu` | 2077 | 27528 | 0 | 0 | 100.00 | 100.00 |
| `ja_gsd-ud-dev.conllu` | 507 | 12795 | 0 | 0 | 100.00 | 100.00 |
| `ja_gsd-ud-test.conllu` | 543 | 13578 | 0 | 0 | 100.00 | 100.00 |
| `zh_gsd-ud-dev.conllu` | 500 | 13166 | 0 | 0 | 100.00 | 100.00 |
| `zh_gsd-ud-test.conllu` | 500 | 12511 | 0 | 0 | 100.00 | 100.00 |

- 字段级不一致总数：**0**
- 失败文件：**0**

## 四、复现

```bash
python3 tools/fetch_corpus.py          # 下载 dev/test 切分到 data/ud/
python3 tools/diff_test.py --report    # 对拍并重新生成本报告
```
