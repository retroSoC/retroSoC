# Tiny／Mini IP 框图重构交付评估

本轮从出版基线 `4315f7d7c5ff5a04d1a83a2a45fc595b11ab4c41` 实施。
两册产品设计来源继续冻结在 `6f3f3c83e42eab9ce4acfe4afa8093d7e4c7ac87`，
文档日期保留 2026-11-14。复核与交付日期为 2026-11-17。

| 文档 | 版本／代际 | 主参考配置 | IP 主图 | 新细节图 | PDF 页数 |
| --- | --- | --- | ---: | ---: | ---: |
| Tiny | v0.2 DRAFT／Gen1 | ICS55／SAFE24、显式 IHP130 兼容 | 23 | 12 | 455 |
| Mini | v0.5 DRAFT／Gen2/Gen2+ | IHP130 PRODUCT、HP、MPW 分别限定 | 42 | 24 | 830 |

交付目录为仓库 `build/datasheet-tiny-ip-block-delivery-20261117/` 和
`build/datasheet-mini-ip-block-delivery-20261117/`。439 页 Tiny、792 页 Mini
旧 PDF 及 manifest 保留在各自 `datasheet-*-scientific-pr-20261116/` 目录。
新增页面主要来自更大的主图和紧邻的功能细节图；章节、IP、寄存器和主图锚点保留。

## 两册具体修改

Tiny 的全部 23 个 IP 主图改为统一黑白灰矢量表达。SPI 分开寄存器、DMA
节拍与信用、GPIO 归属保护、字打包／FIFO、会话及串行引擎；RCU 展示实际
SAFE24、条件 PLL 路径、选择、分频和各域复位同步。PPALite 的 Tiny 路由和
DMA2 准入保护放到 IP 边界之外。存储器、DVP、I2S、Crypto 等保留其真实
数据宽度、CDC、共享资源与使用限制。CRC／RNG 的形式验证属性模块不作为硬件绘制。

Mini 的全部 42 个 IP 主图采用同一绘图语言，功能和配置沿用自己的来源。
RCU 细节按 HP／LP 时钟选择、PCLK／MEM 分频、频率与存活监测、请求／切换
控制、各域复位同步组织，补画现有 RTL 的静态与动态分频单元。
IHP130 无 PLL 的条件明确保留，数字控制器不被画成 PLL 宏或新增电源域。

GA2D 展示前景／背景／输出 FIFO、像素转换、行／突发规划和读尺寸辅助逻辑，
注明辅助单元写侧绑零／未连接；NPU 展示控制 CDC、HP 原生 DMA、私有 SRAM、
打包、MAC、向量、累加、重量化及本地调度关系。APU 私有 AXI 为 32 位，
DMA TX/RX、I2S TX/RX 四个流接口分别标明方向。SDRAM 五个 AXI 通道队列和
USB2 的 ULPI／RX／TX／事务／包存储路径按真实功能组织。
Mini SRAM 的 PRODUCT 目标按实际 `u_onchip_ram`／`u_data_sram_axi4_if`
标注 HP 域 AXI64／ID7；退役 LP 32 位接口不作为 SRAM 数据口。
HP CLINT／PLIC 明确为 C906 核内视图；Resource、Monitor、扩展槽的来源范围和
显示信号收窄到相应模块／实例，避免把整个子系统接口带入单个 IP。

两册的 7 幅系统 Circuiteria 图、SoC 总架构、时序、寄存器位图、存储格式、
封装／PCB 图保持原有设计。规格数据、参考模型系数、引脚功能、RTL、SDK 和
硬件资格结论均不在本轮变更范围。范围核对记录见
`build/datasheet-ip-block-validation/scope-audit.json`。

## 共用出版实现与规范

[共用 IP 设计规范](ip-block-diagrams.md) 约束符号语义、边界、来源、布线、
图例、字号、分组、分页及维护；[通用排版规范](datasheets/style.md)、
[Tiny 补充规范](datasheets/tiny/style.md) 和两册维护说明同步更新。

新增 `ip-block-diagrams.typ` 使用锁定 CeTZ 0.5.2；
`ip_block_reference.py` 负责字体度量、确定性正交布线、几何检查、追溯和导出。
两册原有入口作为适配层；第三方包及依赖锁版本不变。
功能数据仍位于现有两册 circuit catalog 及 Mini 的三个内嵌记录中，细节通过
成员 ID 引用已有单元事实，不复制一套独立 IP 规格。

边界／功能块使用 0.9／0.6 pt 黑线，外部总线脊线 3 pt，内部数据箭身 2 mm，
控制／时钟／复位／状态使用 0.65 pt 实线。标签为透明背景的 9 pt Inter，
图题居上、居中、9 pt Bold；金灰品牌保留在页面其余部分。

不同信号禁止共线重叠、共用转角或形成假节点；真实源端口／网络扇出才允许
合并并标节点。预留端点出线区，数据通路优先布线，并从固定策略中选择通过
全部几何检查的结果。图例只在可唯一识别的端点／类型关系下代替图内标签。
不降低字号，不按实例顺序任意切片，不自动增加硬件或删除连接以求排版通过。

科学上下标渲染和审计继续执行；本轮显式关闭科学排版的“新增修改页”标记，
避免将已经完成的公式排版误报为本轮修改。关闭标记不豁免未知显示项或字号检查。
最终视觉复核还将 DVP 的 `Configuration CDC` 简化为 `Config CDC`，并调整
Mini CLINT、Resource 外部标签的换行／`ack` 简称，避免英文单词被逐字拆行。

## 逐图追溯与可编辑交付

每册交付目录包含：

- `ip-blocks/<ID>.svg`、`.pdf`：主图及细节图，共 101 幅、202 个独立矢量文件。
- `ip-blocks/ip-views.typ`、`data.json`：可编辑、可复建的绘图入口和数据。
- `ip-block-sources.json`：功能分组、边界、符号、RTL 实例／端口／参数、条件、
  来源文件指纹和连接绑定。
- `ip-block-geometry.json`：最终坐标、路由策略、文字、箭头、端口和节点。
- `ip-block-coverage.json`、`ip-block-traceability.csv`：实际图页与逐单元来源清单。
- `manifest.json`：产品配置、源文件／资源／图表／PDF 哈希和工具身份。
- `check-report.json`、`changed-pages.json`、`visual/`、`offline-rebuild.json`：
  PDF 检查、改页、原尺寸彩色／灰度、视觉复核和离线复建证据。

Tiny PDF SHA-256：
`ec969e6f3ce2fb73f36af5e9ba43484983ad0395532e75fe839dd1d3c06e687d`。

Mini PDF SHA-256：
`d820bcd2fb9e46c5023ba4fb6d3861a6938f0f91a6eab475fe85b89ce2397370`。

## 验证与已保留记录

最终检查状态与汇总以 `build/datasheet-ip-block-validation/delivery-validation.json`
和两册交付目录的实际报告为准。保留实施中失败、输入恢复失败、源夹具修正和
串行完整测试的超时记录；它们不被重写成通过。

来源检查覆盖两册实际 IP、寄存器、地址、IRQ、引脚、时钟与集成参数。
负例覆盖错误方向／位宽、虚构单元、边界／产品混用、来源漂移、遗漏／重复图、
假扇出、异网共线、转角误连、字号与文字／图框／线路冲突。
完整 Pytest 使用仓库四分片规则，在独立输入副本中运行，并由现有
`pytest_shards.py verify` 检查用例集合、重复／遗漏及意外跳过。

完整四分片首次运行共 2,932 项：2,915 通过、15 失败、2 项按既有策略跳过。
其中 14 项失败是环境缺少锁定 Verible，另 1 项为 Tiny P5 Icarus 用例的
180 秒超时。通过原有 `install_toolchain.py --tool verible` 恢复锁定版本后，
完整 RTL 风格测试与该 Icarus 用例共 16 项复验全部通过（99.39 秒）。
未修改超时阈值、RTL、断言、测试跳过规则或依赖锁。
首次四分片汇总仍为 `failed`；后续通过记录独立保存，不替换原始 JUnit。
冻结全量测试输入之后的变更仅涉及出版显示／来源标注及对应出版回归用例，
最终全部出版测试另行执行，记录见 `publication-label-parity.xml`。
不得将这些分阶段证据表述为一次未经失败的完整测试。
最终出版测试为 **778 项通过**（104.29 秒）。按最终收集的 2,934 项逐项匹配
完整四分片、定向复验及最终出版 JUnit 后，2,932 项有通过记录、2 项符合
现有允许跳过策略；没有遗漏或未解决失败。该追溯结果保存为
`staged-test-resolution.json`，与原生四分片 `failed` 报告分别保留。
两项跳过分别为 APU P7 concurrent、P8 quiesced-loader 用例，原因为该完整测试
副本未构建 APU-P5 bundle；不是本轮新增跳过。

两册 PDF 已执行字体嵌入、字号／裁切、续表、链接／书签、图目录、源绑定和
覆盖检查。原尺寸彩色与灰度渲染覆盖每页；101 幅独立图逐幅审阅，中性灰
像素检查证明其灰度表达与彩色表达相同。重排页面及保留内容的核对范围在
各册视觉复核记录中列明，自动渲染本身不作为目视通过结论。
相对保留基线，Tiny 有 279 页、Mini 有 473 页正文归一化后完全匹配，
Mini 另有 2 页近似匹配；其余 176／355 页分别检查重排与图文关系。
最后一轮标签调整的像素比较仅涉及 Tiny 第 309 页、Mini 第 453／469／500 页，
四页再次逐页复核，其他页面继承已核对且栅格哈希一致的视觉记录。

同一锁定环境关闭 Python 网络入口及子进程代理后离线复建，核对主 PDF、
全部 IP SVG／PDF、原有工程矢量及曲线输出的字节一致性。
`pdfminer` 对既有图案色空间的 p0/p1/p2 解析警告保留；Typst 构建检查和
独立 Poppler 渲染记录分别保留，未通过降低图表检查要求处理这些提示。

本轮没有运行新的整 SoC `regress-pr`／`regress-nightly`、综合、物理实现或
样片资格签核；完整 Pytest 中的定向 RTL 对照用例与这些完整产品活动分开记录。
无新增 MISRA 偏离。文档通过不改变已有负时序记录和硬件资格缺口。

## 复建与核对命令

从仓库根目录使用已锁定的出版 Python 环境；本机 Windows 解释器为
`.cache/publication-venv/Scripts/python.exe`，编译器为 Typst 0.15.1。
下面两套入口没有改变；`--typst` 可显式传入锁定编译器路径。

```powershell
.cache/publication-venv/Scripts/python.exe publications/build_tiny_datasheet.py build --output-dir build/datasheet-tiny-ip-block-delivery-20261117
.cache/publication-venv/Scripts/python.exe publications/build_datasheet.py build --output-dir build/datasheet-mini-ip-block-delivery-20261117
.cache/publication-venv/Scripts/python.exe publications/build_tiny_datasheet.py check --pdf build/datasheet-tiny-ip-block-delivery-20261117/retrosoc-tiny-gen1-datasheet.pdf
.cache/publication-venv/Scripts/python.exe publications/build_datasheet.py check --pdf build/datasheet-mini-ip-block-delivery-20261117/retrosoc-mini-gen2-gen2plus-datasheet.pdf
```

来源、SDK 示例、Ruff、完整 Pytest 及锁／文档检查在 Ubuntu 22.04 的独立
输入副本与 Python 3.10 验证环境执行。实际命令及退出码保留在
`final-preflight.json`、`result-publication-label-parity.json`、四个分片的
`result-pytest.json`、`result-failed-case-retest.json` 和相应日志中。
逐页渲染使用 `review_datasheet.py --pdf <交付 PDF> --baseline <保留 PDF>`，
改页检查使用 `report_changes.py` 的同一参数。
原尺寸图、CSV 和追溯数据由最终 manifest 绑定；补充审阅／打包脚本随交付包保留。

## 参考资料

视觉参考为 ST
[RM0486 Rev 4，May 2026](https://www.st.com/resource/en/reference_manual/rm0486-stm32n647657xx-armbased-32bit-mcus-stmicroelectronics.pdf)：
第 412 页 RCC Figure 34、第 2154 页 GPU2D Figure 449，全文 4669 页。
所审阅官方 PDF SHA-256：
`83cb7e9c7f784a4c5dbbedec428adf58d2cbac8cd802d11e2cdc4d504cceaa86`。
采用其工程绘图语言，所有硬件结构、接口和限制依据 retroSoC 自身设计重新组织。

## PR 同步审阅

开 PR 前合并远端 dev `b0ac5ee36d408b448de07b69788d87e5d16f3079`。
该增量仅涉及 Agent／CI／缓存／交付及其测试，没有 RTL、SDK、硬件配置或依赖锁
变化。复核 Makefile 的两处增量（合并预检参数和 check-fast 用例）及 Git 工作流的
预检／监视说明后，仅更新 Mini `build_control_review` 的完整提交／文件指纹。
产品来源仍为 `6f3f3c83`，旧交付 PDF、manifest 和全部失败／复验记录继续保留。
PR 同步检查与复建记录独立存于 `build/datasheet-ip-block-pr-validation-20261117/`。
