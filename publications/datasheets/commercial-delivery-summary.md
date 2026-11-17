# Tiny／Mini Datasheet 交付总结

本轮出版实现及出版验收已完成。整仓库验收未全绿；硬件相关失败与跳过项单独保留，不作为芯片资格通过。

## 文件与基线

| 册别 | 版本 | 页数 | PDF SHA-256 |
| --- | --- | ---: | --- |
| Tiny Gen1 | v0.2 DRAFT | 439 | 64900eec64e271be01c3c2061a93ee868e52305edb5ed02d009f408510eb5c33 |
| Mini Gen2/Gen2+ | v0.5 DRAFT | 792 | 7a16aa8e605a435725a537369a145e89f8c56c2e66c40f3bc39085ee10c68356 |

冻结设计源为实施开始时的 dev：
6f3f3c83e42eab9ce4acfe4afa8093d7e4c7ac87。
交付前远端 dev 已推进至 27829e2610bc7a90d8e2281bce604f5398ef3aae；
增量为 Agent Skill／任务 DAG 控制、脚本及测试，没有 RTL、SDK、产品配置或出版内容增量。
依照“冻结实施开始时基线”的要求，本轮没有将新 SHA 重新贴到旧构建上。

PR 同步阶段又审阅了 dev 5a9cbf12c5a590ca28f36f71d78200df61da56b8：
增量仍为 Agent/CI 管理与测试，无产品源变更。Mini 对其中的 Makefile
变动增加了绑定完整修订与 blob 的独立审阅记录；后续变动仍会触发来源检查。
产品来源 SHA 与两册正文身份保持原值。

Tiny 主配置为 configs/ci/ics55-tiny.mk，兼容配置为 configs/ci/ihp130-tiny.mk。
Mini 保留 configs/ci/ihp130.mk、ihp130-hp.mk 和 cluster/mini-mpw.mk。

旧 425／796 页 PDF 及 manifest 保留原目录和原始身份。
本轮交付目录：

- [Tiny PDF](../../build/datasheet-tiny-commercial-delivery/retrosoc-tiny-gen1-datasheet.pdf)
- [Tiny manifest](../../build/datasheet-tiny-commercial-delivery/manifest.json)
- [Mini PDF](../../build/datasheet-mini-commercial-delivery/retrosoc-mini-gen2-gen2plus-datasheet.pdf)
- [Mini manifest](../../build/datasheet-mini-commercial-delivery/manifest.json)

## 主要实现

- 两册增加规格／证据状态速查，包装、引脚、电气和板级资料前移，保留原一级章节及 IP／寄存器锚点。
- 表目录按工程资料和寄存器概览分组；字段表从概览与全局地址索引进入，表题包含 IP 上下文。
- Tiny 新增完整 QFN64 64 针主表、顶／底／侧视图及铜、阻焊、锡膏、散热过孔参考。
  EP 独立且不编号；顶、底和 PCB 视图由同一坐标模型转换。
- 两册增加最小系统、供电去耦、时钟／复位／NOR／JTAG 和外设布局参考；Tiny 默认外部 24 MHz XIN。
  AUDIO 已按当前 RTL 说明为 GPIO17 ALT0，不新增引脚或封装决策。
- Tiny 的 SAFE24 首启关闭 PLL，与 R2-P7 条件式排空／park／数字锁定／切换能力分开；
  功能配置不作为时序或物理额定值。
- 理想带宽使用 Tiny SYS AXI32／Mini HP AXI64 所属时钟，MEM 后端时钟单列。
  Mini SDIO 的静态频率发现值与实际 PCLK 差异列入实现勘误。
- 每册增加 7 幅科学曲线；电流、有效传输和 GPIO 模型均为 Reference Only。
  Tiny 另有 11 幅工程图，Mini 有 4 幅工程图，提供 SVG／PDF 及可编辑源；曲线另有 CSV。
- 统一四类数据、来源指纹、条件、假设、公式、依赖、引用位置及替换索引。
  Tiny 共 102 项记录，Mini 共 85 项；各有 13 项 TBD。
- 更新共用规范、Tiny 补充规范、维护指南、结构／导航合同、修订与章节页码记录。
  出版自有文本固定 LF，managed／二进制输入保持各自策略。

## 验证与实际边界

| 检查 | 结果 |
| --- | --- |
| 最终全部出版测试及锁集策略检查 | 692 passed |
| 新增数值／状态／几何负例测试 | 33 passed，包含在上述集合 |
| SDK 示例语法 | Tiny 23／Mini 37，通过；不执行固件 |
| 两册默认源／PDF 检查 | 通过；Tiny 23 IP／626 寄存器定义／140 项导航；Mini 42 IP |
| 字体、9 pt 新标签、边界、书签、链接、续表、关闭页与审计文件 | 通过默认检查及视觉复核 |
| 原尺寸彩色／灰度 | 96 dpi 全页各 1231 张；新增及重排内容逐页核对，保留页按基线正文匹配核对 |
| 灰度图例、标记与线型 | 已复核 |
| 离线复建 | 两册 PDF、曲线及工程矢量字节一致；Python 网络访问被禁用，编译器使用已验证本地资源 |
| Ruff、依赖锁、文档链接、git diff --check | 通过 |
| RTL、SDK、架构、引脚功能修改 | 无 |

整仓库完整 Pytest 已执行并保留其失败与错误；补齐可用锁定工具、模型和历史对象后进行了定向复验。
按连续证据汇总，2728 项已通过，仍有 9 项失败、5 项跳过。
这些剩余项涉及 APU/NPU 工作负载或资产、SDRAM 时序模型、ICS55 SRAM release 模型及相关测试环境；
详见各册 validation-summary.json 和 validation/ 原始日志。
这是多轮全量／定向运行的合并状态，不能写成“一次完整 Pytest 全通过”。

CI 定义未修改，未额外执行 YAML／Actions 定义变更检查。
未进行新的完整产品固件回归、综合／映射、网表功能、CDC/RDC、STA、物理或样片资格活动。
本地单元仿真／出版检查不替代这些门槛，也不更新历史硬件 pass 状态或负时序结果身份。

## 来源与后续替换

[详细实施与参考资料评估](commercial-reference-review.md)列出 ADI UP64 Rev C／QFN 装配指南、
STM32U031 DS14581 Rev 2 和 ESP32-C3 v2.5 的采用范围。
尺寸为原始矢量重绘；没有把参考芯片的测量结果、认证或等级写成 retroSoC 规格。

每册目录内保留：

- specification-data/status/usage/replacement JSON：数据状态、实际引用页、来源及替换条件。
- characteristics/：曲线 CSV／SVG／PDF、字体与工具版本清单。
- engineering/：封装／电路 SVG／PDF 和可编辑导出入口。
- check-report、changed-pages、visual-review、offline-rebuild 及 validation-summary。
- visual/：全页彩色／灰度、基线比较与渲染记录。

仍待真实设计／供应商／测试确认：电气限值、IO 阈值与驱动、模拟时钟／复位参数、
功耗温度特性、有效带宽／应用足迹、bond map、EP、机械／装配公差、PCB 制造文件、
热参数、可靠性／MSL／reflow、订货等级，以及最终完整产品的时序和物理资格。
保留相同参数 ID 更新值、证据、适用条件和状态后，再重算全部引用；参考示例不得直接升格为正式规格。
