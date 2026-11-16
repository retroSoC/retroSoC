# 2026-11-16 科学公式与符号排版复核

本轮主要审阅 Tiny 全册的数学表达，并同步修正 Mini 共用规格组件。
两册设计来源保持 `6f3f3c83e42eab9ce4acfe4afa8093d7e4c7ac87`，
版本与文档日期保持 Tiny v0.2 DRAFT、Mini v0.5 DRAFT / 2026-11-14。
Tiny 主配置为 `configs/ci/ics55-tiny.mk`，兼容配置为
`configs/ci/ihp130-tiny.mk`；Mini 使用 `configs/ci/ihp130.mk`、
`configs/ci/ihp130-hp.mk` 和 `configs/cluster/mini-mpw.mk`。
Mini 的非共用 IP 内容未进行新一轮完整技术审阅。

## 修正范围

- 电流模型：真实指数、I 的 ref 下标与 f 的 MHz 下标；不再印出 Python `**`。
- 传输模型：T 的 ref、f 的 bus、B 的 ideal 和 setup 的 cycles 下标；
  表下注释从集中模型读取 setup / efficiency，保留原数值与计算式。
- GPIO：电气参数表、连接图与曲线统一 OH / OL / IO / out 下标。
- Tiny QFN64：D₂、E₂、A₁ 仅在机械尺寸语境中使用。
- Tiny SPI：算术乘号显示为 ×；SCK、PCLK、DIV 等正式标识符保持原名。
- 单位采用 °C、µA、µF、µs、Ω、kΩ；原始参数单位和 CSV 数字不改写。
- Mini 旧 PDF 的 JPEG 特性中，`2048 脳 2048` 来自默认编码读取。
  特性清单明确按 UTF-8 读取，恢复源码的 `2048 × 2048`，并记录独立修改标记。

软件、寄存器、RTL、引脚和协议标识符，以及代码块、行内代码保持原样。
包括 VDDIO、GPIO17、SCLK_DIV、RESET_N，以及不属于机械图的 D2 / E2 / A1。
英文连字符保留，数学负号转换不会覆盖相邻的 32-bit、end-to-end 等文字。

## 实现和维护规则

[科学显示入口](../scientific_reference.py) 仅生成受限显示 token，不执行公式。
[Typst 组件](../specifications/scientific.typ) 与数值图共用符号和来源身份。
锁定的 Inter 绘制原生上下标；尺寸为父级的 70%，最小 6.3 pt。
正文、表格和普通图表标签保留 9 pt 下限；上下标例外必须匹配已知来源、
文字、角色、字号和紧密区域，不能豁免整张图、整段公式或整页。

共同规则见 [Mini 排版规范](style.md)、[Tiny 补充规范](tiny/style.md) 和
[数据及图表维护规范](../specifications/README.md)。
构建保留 `scientific-notation.json`、`characteristics/scientific-scripts.json`、
`layout-regions.json` 及对应 manifest 哈希。数值图全部文本绑定同一锁定字体实例，
避免相同字体经不同缓存路径进入独立 PDF 时产生不同的字体子集。

## 比较与验证

保留前次交付为比较基线：

| 文档 | 页数 | 基线 PDF SHA-256 |
| --- | --- | --- |
| Tiny | 439 | `9be5adf8d3d0354d9e2a2859bdc3d4b85c5e24cd8b487ebf517d960ebe421bbb` |
| Mini | 792 | `08cf9f2086a607d5ccb129c017e532cc020baf1dc661c89b7ac6f09c77e0dc74` |

输出分别位于 `build/datasheet-tiny-scientific-20261116` 和
`build/datasheet-mini-scientific-20261116`；原始 PDF、manifest 与渲染基线未覆盖。
两册均保留 source/PDF 检查、改页报告、原尺寸彩色/灰度渲染、像素比较、
变化页目视复核、原始参数/CSV 保留证明和离线复建记录。

Tiny 实际变化页为 45、51、52、54–56、59–64、228、230–231、236–237，
共 17 页；其余 422 页彩色和灰度像素与基线一致。
Mini 实际变化页为 91–92、94–95、97、99–102、104、491，共 11 页；
其余 781 页像素一致。第 97 页为曲线附近排版变化，第 491 页为 UTF-8 乘号修正。
两册变化页均以 96 dpi 原尺寸彩色/灰度并列审阅，检查字号、基线、换行、
坐标、图例、表格和 Reference Only 标识。

原始参数的 value、unit、status、formula、dependencies、assumptions 均与基线一致；
每册七份曲线 CSV 与基线逐字节一致。主 PDF、数值曲线 SVG/PDF/CSV 与工程矢量图
在同一锁定环境下离线复建一致。

出版测试、完整仓库测试、Ruff、示例语法、依赖锁、文档检查和源输入身份分别记录在
`build/datasheet-scientific-validation`。完整仓库测试的失败与跳过必须保留，
不得用出版专项成功替代全仓库通过。第一次测试副本受 Windows 导出换行转换影响，
已废弃并按 Git 原始字节重建；独立副本必须保留真实受管源目录，不能以外部符号链接
绕过来源边界检查。

本轮没有修改 RTL、SDK、硬件配置、模型系数、证据状态、依赖版本或资格结论。
出版验证不构成新的仿真、综合、时序、板级、封装或硅片验收。

## 最终检查结果

出版回归 740 项全部通过；Ruff、两册 source/PDF 检查、Tiny 23 份和 Mini 37 份
SDK 示例语法检查、依赖锁、文档链接及 `git diff --check` 通过。
完整仓库长测未完成：执行到非出版硬件用例时，记录 683 passed、17 failed、
5 errors、6 skipped 后停止。失败/错误涉及缺少 sv2v 的转换与仿真路径，
另有 APU 语料运行器用例失败，其原因未在本轮继续诊断；不能记为全仓库通过。
原始 JUnit、日志、执行记录与已停止范围说明均保留在验证目录。
本轮没有以修改 RTL、素材要求、工具检查或证据策略来掩盖这些缺口。

最终 PDF SHA-256：

- Tiny：`13f5de8a93f5eecdaf8cbae73dedcc529ff7dd881106781d80c05f6b6a7bd015`。
- Mini：`6eeb95bb00d577e6e7f4e72b229090e74c10dac7992b0a33c1e8cf8985fc8fbb`。

## 检查入口

在锁定出版环境中执行的两册最终 PDF 检查：

```powershell
.cache/publication-venv/Scripts/python.exe -X utf8 publications/build_tiny_datasheet.py check --pdf build/datasheet-tiny-scientific-20261116/retrosoc-tiny-gen1-datasheet.pdf
.cache/publication-venv/Scripts/python.exe -X utf8 publications/build_datasheet.py check --pdf build/datasheet-mini-scientific-20261116/retrosoc-mini-gen2-gen2plus-datasheet.pdf
```

独立 Ubuntu 22.04 / Python 3.10 检查副本运行 `ruff check .`、两册
`check --source-only`、`check_tiny_examples.py --cc gcc`、
`check_examples.py --cc gcc`、`scripts/dependency_lock.py --lock dependencies/dependencies.lock.json`
和 `scripts/agent_control.py docs --root .`。完整出版测试等价命令为：

```sh
python -m pytest -q tests/test_publication*.py tests/test_script_tools.py::test_python_requirements_are_hash_locked
```

全仓库 `python -m pytest -q` 经既有 `scripts/run_flow.py` 记录，因前述非出版失败停止。
本轮断网复建驱动为 `.cache/retrosoc/publications/verify_scientific_offline.py tiny`
及对应 `mini` 调用；它调用正式 build 入口、阻止网络访问、复建至独立目录并比较字节。
正式构建和检查入口仍为 `publications/build_tiny_datasheet.py` 与
`publications/build_datasheet.py`，Typst 固定为 0.15.1，Matplotlib 为 3.10.7。
