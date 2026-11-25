# 验收自查 / Acceptance verification

对照验收标准逐条给出仓库内证据与可复现命令。所有数字都来自真实执行，
不是估计值；如与最新提交有出入，以 `git log` 和 CI 实际输出为准。

## 标准对照

| 验收标准 | 状态 | 证据 |
| --- | --- | --- |
| MoonBit 为主要实现语言，moonc ≥ 0.10.16 | ✅ | 库与 CLI 全部为 `.mbt`（约 3,200 行）；Python 仅用于对拍/CI 脚本。开发环境 `moonc v0.10.22+124d61d05`，`moon version --all` 可查 |
| GitHub 仓库公开、提交记录清晰 | ✅ | https://github.com/PaperY0/conllu 公开；35+ 个提交按功能独立提交，feat/test/docs/ci/chore 分类，无空提交与拆分 |
| 源代码结构清晰，能完成声明的核心功能 | ✅ | 单包多文件：`conllu.mbt`（模型/解析/序列化）、`validate.mbt` + `validate_document.mbt`（校验）、`tree.mbt`（树查询）、`document.mbt`（文档分组）、`coverage.mbt`（覆盖分析）、`metrics.mbt`（评测/统计）、`cmd/main/main.mbt`（CLI） |
| README 含目标、安装、使用方法、示例，可复现 | ✅ | `README.mbt.md`（中文）与 `README.en.md`（英文）均含安装 `moon add PaperY0/conllu`、九个子命令用法、真实输出示例、架构图；文档内代码块是 `mbt check` 文档测试，随 `moon test` 执行 |
| CI 覆盖检查、构建、测试 | ✅ | `.github/workflows/ci.yml`：`check` 矩阵（wasm / wasm-gc / js）依次跑 `moon check` → `moon build` → `moon test`；`interface` job 校验 `.mbti` 与 `moon fmt` 无漂移 |
| 至少一个可运行示例/最小样例 | ✅ | `examples/demo.py` 九步端到端（自动下载语料），`examples/sample.conllu` 最小语料样例；demo 同时作为 CI `integration` 的一步执行 |
| 完整测试覆盖核心功能路径 | ✅ | 37 个单元测试（解析/序列化/校验/树/文档/覆盖/评测/增强依存/JSON）+ 11 个 golden CLI 回归 + 六个 UD 切分差分对拍（6,128 句 / 107,091 行零差异）；覆盖率可量化，见下节 |
| 发布到 mooncakes.io | ✅ | https://mooncakes.io/docs/#/PaperY0/conllu ，0.1.0–0.5.0 共六个版本，`build_status = success` |
| OSI 认可的开源许可证 | ✅ | Apache-2.0，见 `LICENSE` |
| 参考/移植符合原许可证要求 | ✅ | 原创项目，无代码移植；`NOTICE` 列明依赖 moonbitlang/x（Apache-2.0）、测试基准 Python conllu（MIT，仅输出比对）、UD 语料（CC BY-SA 4.0，仅测试夹具，不进仓库与发布包） |

## 一键复现

```bash
git clone https://github.com/PaperY0/conllu.git
cd conllu

moon version --all        # 确认 moonc >= 0.10.16
moon check                # 检查
moon build                # 构建
moon test                 # 37/37，含 README 文档测试

python3 tools/fetch_corpus.py   # 下载 UD 测试语料（CC BY-SA 4.0，gitignored）
python3 tools/diff_test.py      # 与 Python conllu 逐字段对拍，六项检查
python3 tools/golden_test.py    # 11/11 CLI 输出 golden 回归
python3 examples/demo.py        # 九步端到端示例，全过才退出 0

moon test --enable-coverage     # 覆盖率（可选）
moon coverage analyze           # 未覆盖行报告
```

Windows 上把 `python3` 换成 `python` 即可，其余命令相同。

## 测试覆盖量化（实测）

`moon test --enable-coverage` 后 `moon coverage analyze`：共 257 行未覆盖，
分布如下（数字为未覆盖行数）：

| 文件 | 未覆盖行 | 说明 |
| --- | --- | --- |
| `cmd/main/main.mbt` | 148 | CLI 分支：文件 I/O、gzip、进程退出码、表格打印；这部分由 golden（11 例）、差分对拍与 demo 在进程级覆盖，不计入单元测试行覆盖 |
| `conllu.mbt` | 29 | 异常输入分支（列数错误、ID 形态错误等） |
| `metrics.mbt` | 23 | 长度不一致、空文档等边界路径 |
| `validate.mbt` | 21 | 部分罕见诊断码 |
| `coverage.mbt` | 19 | 空标签集等边界 |
| `tree.mbt` | 12 | 成环、越界等防御分支 |
| `validate_document.mbt` | 3 | 个别警告分支 |
| `document.mbt` | 2 | 匿名文档边界 |

即：库内未覆盖 109 行，集中在异常与防御分支；CLI 的 148 行由进程级测试
（golden / 差分 / demo）补足。核心功能路径——解析、序列化、规范校验、树查询、
文档分组、覆盖合并、UAS/LAS 评测、JSON 输出——均有单元测试与真实语料双重验证。

## CI 证据

每次 push 触发 `CI` 工作流（五个 job）：

- `check (wasm)` / `check (wasm-gc)` / `check (js)`：检查 → 构建 → 测试；
- `interface`：`moon info` 与 `moon fmt` 后 `git diff --exit-code`，公开接口与格式不允许漂移；
- `integration`：安装 Python conllu → 下载六个 UD 切分 → 差分对拍 → golden 回归 → 端到端 demo，并上传 `DIFF-REPORT.md` 产物。

最新运行见仓库 Actions 页；README 顶部徽章实时显示状态。
