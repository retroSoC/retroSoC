# Tiny／Mini IP 框图功能展开与出版验收

本轮完成 65 幅 IP 主图和 36 幅附图的功能展开与布线更新。下述页码、测试和哈希对应 2026-11-18 验收的冻结稿，Tiny Gen1 v0.2 DRAFT 共 455 页，Mini Gen2/Gen2+ v0.5 DRAFT 共 828 页。两册冻结稿的出版日期为 2026-11-17。

## 基线与适用配置

| 产品 | 产品来源 | 文档配置 | 图稿与页数 |
| --- | --- | --- | --- |
| Tiny Gen1 | `903ef1eda3b956864157e6e64319fddde9cd5747` | ICS55 主配置 `configs/ci/ics55-tiny.mk`，IHP130 兼容配置 `configs/ci/ihp130-tiny.mk` | 23 幅主图、12 幅附图，455 → 455 页 |
| Mini Gen2/Gen2+ | `6f3f3c83e42eab9ce4acfe4afa8093d7e4c7ac87` | IHP130 PRODUCT、HP 和 MPW，依次为 `configs/ci/ihp130.mk`、`configs/ci/ihp130-hp.mk`、`configs/cluster/mini-mpw.mk` | 42 幅主图、24 幅附图，830 → 828 页 |

出版工作基线冻结在 `80486b9fe3664c85b17c0ac093f8a9eddc34ba15`。Mini 对 Makefile 及相关仓库控制文件的单独审阅达到该提交，产品来源仍按表中 SHA 生成。交付时另记录到远端 `dev` 的 `a7735acdbe9d3019c1a84f98997bbbc13a8270b1`，供后续分支同步追溯。

七幅系统级 Circuiteria 图与基线中的绘图定义逐项一致。SoC 总架构、时序、寄存器位图、存储格式及封装板级图继续沿用各自原有绘图入口。修改页报告独立记录图稿变化及自动编号、导航页码变化。改动集中于出版实现、图目录、文档规范和验证测试。RTL、SDK、寄存器 ABI、引脚和规格模型沿用冻结配置。

## 功能展开

- **两册 DMA** 展开 APB 配置和通道上下文、请求准入、读写仲裁、TCD 获取、地址和长度更新、各通道 FIFO、流路由、读数据 CRC、AXI 事务及完成／错误反馈。两册保留各自的请求、时钟域和集成条件。
- **Tiny RCU、SPI、SRAM** 分别展示 SAFE24 与条件 PLL 路径、时钟选择和分频复位、SPI GPIO 占用保护与 DMA 信用、收发 FIFO 和位时序，以及四组 SRAM 的访问仲裁、选 bank、响应锁存和外部事务回传。
- **Mini RCU、GA2D、NPU** 分别展示 IHP130 的外部时钟回退、HP／LP／PCLK 与检测复位，GA2D 的前景／背景 FIFO、像素格式处理和私有 DMA，以及 NPU 的描述符调度、PCLK／HP 控制跨域、私有 SRAM、MAC、累加及重定量。
- **Mini PS/2** 展开输入同步／滤波、RX／TX 状态机、两路 FIFO、开漏输出使能、完成和错误中断。Mini 实例选择 16 项 RX 和 16 项 TX，条目宽度分别为 11 位和 8 位。两册 ARCHINFO 用 `PWRITE check` 描述 APB 写访问检查，配合正文的只读寄存器说明。
- 各主图保留现有锚点。附图继续展开适用的 DMA、时钟、计算或协议机制。功能节点通过 RTL 实例或所属模块内的信号和逻辑绑定追溯。未启用、共享和有条件的路径按各册配置标明。

## 布线与维护

新框图参考 RCC 的边界、功能块和跨线表达，采用本项目 RTL 和配置定义功能。[ST RM0486 Rev 4, RCC Figure 34](https://www.st.com/resource/en/reference_manual/rm0486-stm32n647657xx-armbased-32bit-mcus-stmicroelectronics.pdf#page=412)。

共用组件 `ip-block-v2` 使用锁定的 CeTZ 0.5.2、Inter 9 pt 或更大字号、透明文字背景和黑白灰图层。数据、控制、时钟、复位及状态统一用 0.65 pt 黑线和实心箭头，外部总线脊线为 3 pt。先排分区与端口，再记录以毫米为单位的正交线槽。普通线段至少 4 mm，最多四次转折，平行线中心线距至少 3 mm，带标签线槽至少 6 mm。非连接交叉用桥形符号，真实同网分支用实心节点，共用线干只画一次。

几何检查覆盖箭头轮廓、线宽、跨线桥、文字边界与功能框。构建对缺失或不合法的显式布局报错。每幅图的节点、线段、位宽、方向、审阅来源和输出指纹随构建记录生成。见 [共用 IP 绘图规范](ip-block-diagrams.md)、[Mini 排版规范](datasheets/style.md)、[Tiny 补充规范](datasheets/tiny/style.md)、[出版维护说明](README.md) 和 [Tiny 维护说明](datasheets/tiny/README.md)。

## 验证结果

| 检查 | 结果与范围 |
| --- | --- |
| 来源、功能覆盖和几何 | 101 幅均通过，最短普通线段 4 mm，最大转折数 4，普通标签下限 9 pt。每册来源、几何和锚点分别出具报告。Tiny 追溯表含 364 个功能／边界条目和 468 条连线，Mini 为 693 个条目和 891 条连线。 |
| PDF 与改页检查 | Tiny 455 页、2,343 个内部链接与 23 个 IP 章节，Mini 828 页、3,723 个内部链接与 42 个 IP 主图。字体、图目录、来源与深层锚点检查通过。改页报告验证 Tiny 23 个、Mini 42 个标记范围。 |
| 视觉复核 | 全书分别以 144 dpi 生成彩色与灰度，即 Tiny 各 455 页、Mini 各 828 页。逐幅复核 35 和 66 个独立图稿。逐页检查覆盖 Tiny 182 页和 Mini 322 页，其余页面按基线正文比对。最终修订沿用 PNG 哈希相等的审阅记录，并以两种模式复核 Tiny 第 262 页及 Mini 第 363、364、415 页。具体页码、模式与哈希见 `visual-review.json`。 |
| 离线复建 | Windows Python 3.12.14、Typst 0.15.1、锁定字体与本地已核验包。禁止 Python 网络连接，禁用编译器子进程代理。两册主 PDF、独立 IP SVG／PDF 及配套矢量和曲线均字节一致。报告保留实际隔离方式。 |
| Python 与文档检查 | Ubuntu 22.04 上 Ruff、来源检查、SDK 示例语法检查、依赖锁验证、文档检查、`git diff --check` 通过。完整 Pytest 在最后一轮图稿细修前为 2,989 通过、2 跳过、1 个既有弃用告警。最终图稿经 854 项相关出版及调用方测试复核，全部通过。 |

视觉检查涵盖图题、图框、页眉页脚、续表和目录。部分 IP 引介页留白用于让后续大图完整地占页。PDF 解析器保留少量图案色的解析告警，Poppler 26.07.0 渲染可读，PDF 与导航检查通过。两项跳过为 APU P7 并发和 P8 静止状态测试，均需要单独构建的 APU-P5 数据包。本轮验收未包含新的产品级综合、STA、门级、板级或样片资格验证，历史证据继续按原版本和适用条件引用。

复现使用 `publications/build_tiny_datasheet.py` 和 `publications/build_datasheet.py` 的 `build`、`check --source-only` 与 `check --pdf` 入口。改页调用 `publications/report_changes.py --baseline … --pdf …`，色彩复核调用 `publications/review_datasheet.py --baseline … --pdf … --dpi 144`。`publications/check_tiny_examples.py --cc gcc` 与 `publications/check_examples.py --cc gcc` 分别验证示例。完整记录位于 `build/datasheet-ip-detail-validation-20261117/`，其中 `final-complete-pytest.log`、`LF-publication-tests.log`、`final-LF-checks.json` 标明测试范围和结果。早期缺工具／受管输入及 CRLF 来源检查失败的日志一并保留。

## 本地交付与文件身份

| 产品 | 主 PDF SHA-256 | Manifest SHA-256 |
| --- | --- | --- |
| Tiny | `84bb4a9997c528ef5d2389c50fe081eeb6df0cf43c594cc78d713fde7908c57a` | `b7c9c8c53744fc8e0b75226c376370af4e5802f049f10e6ec829247e7c77569a` |
| Mini | `3592f0d7b41470baad683d91146e6c8a58db293323ac98a3dbc5d10d8b4867be` | `80021cc440bdf5caf78a420ad32db07cbbcd03b652f8f208fcd6d682b8cc33ec` |

- Tiny 交付目录为 `build/datasheet-tiny-ip-detail-rcc-accepted-20261117/`，主文件名为 `retrosoc-tiny-gen1-datasheet.pdf`。代表图为 SRAM 第 111 页、DMA 第 135 页、SPI 第 233 页和 RCU 第 282 页。
- Mini 交付目录为 `build/datasheet-mini-ip-detail-rcc-accepted-20261117/`，主文件名为 `retrosoc-mini-gen2-gen2plus-datasheet.pdf`。代表图为 DMA 第 246 页、PS/2 第 363 页、GA2D 第 541 页和 NPU 第 614 页。
- 各目录含 `ip-blocks/` 的独立 SVG、PDF 和 Typst 数据、`ip-block-functional-coverage.csv`、`ip-block-connection-review.csv`、`ip-block-sources.json`、`ip-block-geometry.json`、`check-report.json`、`changed-pages.json`、`visual-review.json` 和 `offline-rebuild.json`。总索引 `build/datasheet-ip-detail-validation-20261117/publication-delivery-index.json` 记录验收文件的 SHA-256。
- 原 455／830 页对照 PDF 及 manifest 保存在 `build/datasheet-tiny-ip-detail-baseline-20261117/` 和 `build/datasheet-mini-ip-detail-baseline-20261117/`。

## PR 与 dev 同步

主题分支随后合入 `dev` 的 `c377c7a99991e80b151a819fef64a16fae48f526`，保留其中既已审阅的两册技术来源 `d9f2781147d7a7c47e5d8c19396fcc2a3de95133`。Mini 延用 `506018b24330f09a05c1f87831ec29e31f7a1cd7` 的独立控制审阅，该次审阅绑定的 Makefile 和 Git 流程文档与同步点内容一致。Mini 的 CI 观察和历史结果随 `dev` 保留原有身份。

Tiny 的应用和路线图章节同步引用既有 PPALite P4 验收，覆盖明确列出的仿真场景。联合 P5 物理及时序验证仍属于单独的产品工作。以上冻结稿的 PDF 和验证记录继续绑定各自原 SHA。 [PPALite P4 验收记录](../docs/ip/ppalite-verification.md#ppalite-p4-human-acceptance-2026-11-17)。
