# Tiny／Mini Datasheet：2026-11-14 实施与评估记录

本轮冻结 dev：6f3f3c83e42eab9ce4acfe4afa8093d7e4c7ac87。
Tiny 保持 v0.2 DRAFT / Gen1；Mini 保持 v0.5 DRAFT / Gen2/Gen2+。
本轮只修改出版实现、出版依赖、文档规范和相应测试，没有修改 RTL、产品引脚功能或 SDK 实现。

## 设计基线与增量审阅

- Tiny：ICS55 主参考配置及 IHP130 兼容配置均保留。23 个 IP、626 个寄存器定义、
  1210 个展开地址由原有提取器与覆盖合同检查。PIO-lite 仍未集成；PPALite 已集成的范围
  与阶段证据保留。SAFE24 启动时 PLL 关闭；当前 R2-P7 RTL 允许满足后端能力、
  数字锁定及排空条件后请求 PLL192／PLL240，功能能力不等于时序／物理资格。
- Mini：从旧出版源 9ab05c64 审阅到本轮冻结源。APB 外设实例更新了共享 DMA／DVP
  端口；Mini 的 SPI admission 仍绑零，PPALite 路由仍未集成。新增共享 DMA
  abort-wait／reset 和 DVP bounded-start／stop 的软件语义已补充，特别说明
  “命令提交”“轮询预算耗尽”与“确认空闲／排空”的差别。
- Mini 保持 IHP130 PRODUCT／HP／MPW 配置、独立 REF24／EXT72／audio 输入、
  LP／HP CDC 和 GPIO21-31 的 QPI／OPI 物理复用限制。
- Mini SDIO 的频率发现值使用固定 72 MHz 参数，线时钟实际跟随 PCLK；h=0
  在时钟发生器中钳位为 1，而发现值为零。已记录实现勘误及软件计算条件，没有改 RTL。
- 冻结提交的 7 个 push 工作流在采样时均为 success。该观察只代表各工作流范围，
  不替代精确配置的硬件报告或物理资格。之前的 CI 采样记录保留原 SHA／时间和状态。

## 文档与阅读组织

两册继续采用单册分层结构和原有一级章节，稳定 IP／寄存器锚点保留。
前部增加规格及证据状态速查；封装、引脚、电气及板级资料前移至完整外设参考之前。
表目录分为工程资料和 IP 寄存器概览，字段表仍可通过概览与全局地址索引访问；
字段表标题补充 IP 上下文。Tiny 继续只对括号中的全大写后缀加粗，
PPALITE／CRYPTO 保持正确拼写，架构连线标签保持透明背景。

Tiny 增加 QFN64 顶／底／侧视图、编号及 EP 关系、铜焊盘、阻焊、锡膏和散热过孔图。
所有视图共享坐标模型；底视图镜像；EP 不占第 65 个编号。采用既有 64 个周边引脚
目标分配，分别说明目标分配、RTL 连接与物理绑定。QFN64 是确认的产品封装形式，
尺寸、bond map、EP 绑定和制造过程不因此成为已确认规格。

两册增加最小系统、去耦、电源回流、时钟／复位／NOR／JTAG 及外设布局参考。
Tiny 默认使用外部 24 MHz XIN，未暗示被动晶体、XOUT 放大器、生产 strap
解码或批准的电源顺序。Mini 图中不使用 Tiny 的 QFN64 编号。

## 参考厂商与采用范围

| 官方资料 | 版本／定位 | 本轮采用 |
| --- | --- | --- |
| [ADI UP64 图纸](https://www.analog.com/media/en/package-pcb-resources/package/pkg_pdf/ltc-legacy-qfn/qfn_64_05-08-1705.pdf) | 05-08-1705 Rev C，第 1 页 | 同一套 QFN64 轮廓、EP、公差和推荐铜焊盘尺寸；重新绘制，不复制原图 |
| [ADI QFN 装配指南](https://www.analog.com/en/resources/app-notes/smt-assembly-and-pcb-design-guidelines-for-maxims-standard-wirebonded-quad-flatpack.html) | 官方网页，已记录获取指纹 | 铜／阻焊／锡膏层区分、钢网及过孔的装配表达与确认条件 |
| [STM32U031 Datasheet](https://www.st.com/resource/en/datasheet/stm32u031k8.pdf) | DS14581 Rev 2，2024-03 | 规格速查、引脚、电气条件和封装章节的组织方式 |
| [ESP32-C3 Datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-c3_datasheet_en.pdf) | v2.5 | RISC-V SoC 的功能、引脚、接口条件和电气规格表达 |

外部资料的标题、版本、定位、URL 和原始来源 SHA-256 集中登记。
没有把这些芯片的功耗、速度、电气等级或认证结果当作 retroSoC 数据。

## 数据机制、计算与图表

共享规格收集器与两册独立参数目录区分 confirmed／calculated／reference／tbd。
确认项还区分产品目标、配置、RTL、仿真和物理测量证据。
引用参考输入的计算继承 Reference Only；未知值保留显式 null／TBD。
来源、条件、假设、依赖、引用位置和替换条件集中审计。

- CPU 图只展示固定 IPC、无停顿前提下的理想相对主频比，不是 CoreMark／DMIPS。
- 总线图使用 Tiny SYS AXI32／Mini HP AXI64 数据阶段的实际所属时钟。
  MEM／后端时钟单独列出，不混用于 fabric 理想带宽。有效传输模型另外标为参考。
- SPI／SDIO 使用实际半周期分频；I2S 使用真实 AUDIO 输入和两个除数，
  区分 preset 名称与本产品实际采样率。
- 电流采用用户指定的核心域构造模型；电压／温度扫描不是允许工作范围。
  WFI 和外设叶时钟门控不意味着深睡、掉电隔离或保持电流。
- 有效传输采用 16 周期启动与 60% 效率模型；GPIO 采用 3.3 V、40 Ω 电阻模型。
  它们均非实测值或性能保证。
- 图像、音频等载荷采用透明参考场景；DMA TCD 容量采用当前 HAL 结构。
  未提供匹配 ELF／MAP 的软件静态占用保持 TBD。
- 0.10 mm 钢网、4×4 个 1.4 mm 窗口及 0.30 mm 间隔是参考示例，
  覆盖率按标称矩形 EP 外包面积（不扣除小倒角／圆角）计算为约 61.34%。
  阻焊扩展和过孔同样不是制造要求。

曲线输出 SVG／PDF／CSV；封装与电路输出同源 CeTZ 源及独立 SVG／PDF。
统一 Inter、金灰配色和至少 9 pt 新标签，灰度使用线型／标记／填充纹理区分。
独立图、表头和续页均保留数据状态标识。

## 维护、验证与资格缺口

通用排版规范、Tiny 补充规范、两册指南及结构／导航合同同步更新。
模型参数只在共享模型目录维护，产品私有事实不串用。
出版环境使用带哈希的隔离锁集；Windows／Python 3.12 与 Ubuntu／Python 3.10
均执行实际安装检查。出版自有文本统一 LF，managed／二进制输入不改写。

实际构建、检查、测试、改页、视觉和离线复建结论记录在最终各册 build 目录。
本文件不把准备动作或未完成步骤预记为通过。来源、数值／状态负例、几何、字号、
链接、书签、续表和越界检查相互独立，视觉审阅不以自动检查替代。

仍待确认：芯片／PDK 各电源域的实际限值、IO 阈值／驱动／负载、时钟及复位
模拟参数、PLL／完整产品时序、功耗／温度特性、真实应用和存储带宽、
die-to-pad／package 绑定、EP／散热、供应商机械公差、PCB footprint、装配／MSL／
reflow、器件等级、订货代码及样片统计。最终完整产品的功能、综合／映射、
网表功能与时序／物理资格，不由本轮文档工作替代。
