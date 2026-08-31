# Mini Commercial SoC Alignment

## Purpose and Research Boundary

This document records the commercial architecture references used for the
Mini high-performance implementation. It is a design input, not a claim that
retroSoC has the qualification, safety case, analogue IP, or software
ecosystem of the referenced devices. Official sources were rechecked on
2026-08-30.

## Selected References

| Reference | Problem and architecture | Dependencies and activity | Reuse / avoid |
| --- | --- | --- | --- |
| [NXP i.MX RT1180](https://www.nxp.com/products/i.MX-RT1180) and [reference manual](https://www.nxp.com/docs/en/reference-manual/IMXRT1180RM.pdf) | Heterogeneous M7/M33 resource isolation and recovery; TRDC assigns initiators to fixed domains and protects memory/peripheral regions, while SRC owns slice reset | Current product; RM Rev 10.0 and data-sheet updates were published in 2026. Depends on TrustZone/security lifecycle and NXP clock/reset IP | Reuse immutable master identity, root-owned policy, fail-closed regions, and slice lifecycle. Avoid pretending a software owner field alone is a security boundary or importing the full secure lifecycle |
| [ST STM32MP resource manager](https://wiki.st.com/stm32mpu/wiki/Resource_manager_for_coprocessing), [coprocessor management](https://wiki.st.com/stm32mpu/wiki/Coprocessor_management_overview), and [RIFSC](https://wiki.st.com/stm32mpu/wiki/RIFSC_internal_peripheral) | Prevents Linux and MCU firmware from driving the same peripheral; boot-time ETZPC/RIF hardware assignment is mirrored in device tree, RemoteProc/RPMsg/mailbox, and resource-manager software | Active STM32MP1/MP2 documentation, updated through 2025-2026. Depends on TF-A, OP-TEE, Linux device tree, mailbox, and remoteproc services | Reuse quiesce-before-owner-change, hardware exclusion, and one-owner IRQ routing. Defer the Linux resource driver; avoid split hardware/software ownership tables without parity checks |
| [TI AM62x host identities](https://software-dl.ti.com/tisci/esd/latest/5_soc_doc/am62x/hosts.html), [firewalls](https://software-dl.ti.com/tisci/esd/11_01_05/5_soc_doc/am62x/firewalls.html), and [RM board configuration](https://software-dl.ti.com/mcu-plus-sdk/esd/AM62X/09_00_00_19/exports/docs/api_guide_am62x/RESOURCE_ALLOCATION_GUIDE.html) | Prevents initiator spoofing and unauthorized memory/resource use; immutable host IDs select boot-configured firewall permissions and resource ranges through system firmware | Current TISCI/Processor SDK pages were published or crawled in 2026. Depends on TIFS/DM firmware, secure proxy, boardcfg, and interconnect privilege IDs | Reuse generated fixed identities, boot policy, explicit read/write/cache permissions, and first-fault evidence. Avoid a privileged message stack and runtime-reprogrammable policy in this MVP |
| [Arm NIC-400 optimization](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Cycle%20Models/White%20Papers/ARM%20CoreLink%20NIC-400%20Optimization.pdf) and [Arm system QoS](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Quality%20of%20Service%20QoS%20in%20Arm%20Systems.pdf) | Scales mixed AXI/AHB/APB widths and clocks while controlling latency and bandwidth; target-local buffering, register slices, outstanding limits, hierarchical gateways, and QoS regulators are topology parameters | NIC-400 is mature rather than new; Arm still published an updated QoS guide in 2026. Commercial use depends on licensed IP/configuration and performance modelling | Reuse target-aware credits, independent channel/CDC boundaries, hierarchical I/O gateways, measurable wait/high-water counters, and bounded promotion. Avoid a packetized NoC, virtual networks, and opaque generated RTL for an 8x6 fabric |

## Technical Selection

Mini remains a small, non-coherent, performance-first SoC. Hazard3 is the
only root-management master. Vexii I/D, DMA, I/O gateways, the LP data gateway,
and EXT-H use an eight-master native AXI64 data plane. APB remains a separate
control plane. Every data initiator has a generated fixed identity, target
permissions, execute/cache-attribute rules, outstanding limit, QoS class, and
fault attribution.

The design combines the references at their smallest useful boundary:

- NXP/TI-style immutable identities and fail-closed policy are generated from
  `soc_topology.json` and enforced before target admission.
- ST-style ownership changes remain quiesce-and-idle gated, with hardware
  exclusive IRQ routing; Linux integration is explicitly deferred.
- Arm-style target-local credits and CDC/width adapters keep slow serial
  memories from setting SRAM/SDRAM concurrency and isolate HP timing from the
  stable memory protocol clock.
- Static QoS is made auditable: normal class 0-15, starvation promotion 16
  after 256 eligible wait cycles, and recovery LP priority 31.
- A root-only Fabric Monitor exposes snapshot counters, wait maxima,
  promotions, high-water marks, timeout/isolation state, warm flushes, and a
  sticky first fault rather than relying on waveform-only evidence.

## System Architecture and MVP

The implemented reliability MVP is:

```text
generated master policy + fixed ID
             |
             v
AXI64 target-local QoS/credits -> target guard -> HP/memory CDC -> controller
             |                       |
             +---- event vectors ----+
                         |
                  Fabric Monitor
                  PCLK -> HP APB
```

MVP scope includes topology-generated ACLs, read-only XPI enforcement,
non-executable DMA/I/O/LP/EXT traffic, non-cacheable attribute enforcement,
EXT-H range checks, recovery priority, bounded aging, direct HP-to-memory
serial paths, lifecycle flush, sticky fault retention, a handwritten HAL, and
directed/full-product simulation.

It excludes an IOMMU, hardware coherency, bandwidth reservation/deadlines,
Linux ownership/monitor drivers, runtime firewall reprogramming, security
worlds, voltage scaling, trace streaming, and percentile histograms. These
exclusions prevent the MVP from acquiring the software and verification
surface of TISCI, OP-TEE, or a commercial NoC without a product requirement.

## Development Order

1. Freeze fixed identities, topology policy, address parity, and truthful
   extension capability bits.
2. Move QPI/OPI/XPI payload from LP staging to direct HP-to-memory CDC and
   include every bridge in lifecycle warm flush.
3. Enforce target/execute/cache ACLs, target-local credits, recovery priority,
   and starvation aging using Common arbiters/FIFOs.
4. Add bounded target isolation and root-visible snapshot/fault monitoring.
5. Prove behavior with directed policy/QoS/timeout tests, both ICS55 PLL modes,
   IHP130 behavior regression, and repository quality gates.
6. Only after stable digital evidence, add Linux policy services and then
   physical QoS/CDC/MMMC characterization as separate releases.

## Commercial Delivery Gaps

The next commercial-alignment increments are a full AXI liveness/property
suite, unilateral reset/clock-stop matrix, per-engine reset acknowledgement,
Linux cache-maintenance/resource/monitor drivers, traffic-distribution and
99/99.9-percentile performance evidence, CDC/RDC signoff, MMMC/STA, gate-level
SDF, memory/PLL PVT models, DFT/MBIST, long-duration stress, and silicon fault
injection. No release may describe the implementation as timing closed, CDC
signed off, silicon qualified, functionally safe, or cache coherent until
that separate evidence exists.
