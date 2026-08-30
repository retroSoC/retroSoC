# Mini Commercial SoC Alignment

## Purpose

This document records the commercial architecture references used for the
Mini high-performance implementation. It is a design input, not a claim that
retroSoC has the qualification, safety case, analogue IP, or software
ecosystem of the referenced devices.

## Selected references

| Reference | Problem addressed | Architecture reused by Mini | Boundary |
| --- | --- | --- | --- |
| [NXP i.MX RT1180](https://www.nxp.com/products/i.MX-RT1180) | Heterogeneous lifecycle control, external-memory boot, and DVFS | Management-owned lifecycle, stable peripheral clocks while changing a CPU PLL, and resource-domain access control | Mini does not implement voltage scaling or the NXP security lifecycle |
| [ST STM32H7R/S RM0477](https://www.st.com/resource/en/reference_manual/rm0477-stm32h7rx7sx-armbased-32bit-mcus-stmicroelectronics.pdf) | Concurrent CPU, DMA, graphics, and external-memory traffic | Layered AXI/AHB/APB planes, independent memory targets, programmable QoS, and functional clock roots | Mini adds starvation aging instead of relying on unbounded static priority |
| [TI AM263x](https://www.ti.com/product/AM2632) | Freedom from interference and recoverable interconnect faults | Initiator/target firewalls, initiator identity, first-fault attribution, clock monitoring, and directed fault injection | Mini does not claim lockstep, ASIL, SIL, or redundant-bus coverage |
| [Arm CoreLink NIC-400](https://developer.arm.com/community/arm-community-blogs/b/soc-design-and-simulation-blog/posts/corelink-nic-400-a-great-interconnect-for-wearables-and-entry-level-smartphones) | Scalable AXI integration across widths and clock domains | Target-aware outstanding credits, independent channel buffering, register slices, and hierarchical I/O gateways | Mini remains a small crossbar and does not use a packetized NoC |

Primary sources are the NXP i.MX RT1180 product documentation, ST RM0477,
the [TI AM263x TRM](https://www.ti.com/lit/ug/spruj17h/spruj17h.pdf), and Arm
CoreLink Network Interconnect documentation. Web references were reviewed on
2026-08-30. The referenced products and documentation were active at review
time; this date is retained so a later architecture review can detect changes.

## Mini selection

Mini uses a performance-first, non-coherent architecture. Hazard3 retains
root lifecycle control. VexiiRiscv caches, DMA, I/O gateways, the LP data
gateway, and EXT-H use a 64-bit memory plane. APB remains a separate control
plane. Every data-plane initiator has a fixed identity, an outstanding-credit
limit, a QoS class, an access policy, and fault attribution.

The independent Resource Controller applies the RT1180/TRDC-style resource
domain idea without claiming a security lifecycle: six fixed resources have
idle-gated owner changes, sticky owner lock, fault attribution, and mutually
exclusive LP/HP IRQ delivery. The AON shutdown sequence uses a 64-byte Zicbom
cache-maintenance request/ACK before blocking HP traffic. This is explicit
software-managed coherency, not a coherent interconnect.

The first delivery contract is target-aware rather than uniform: SRAM/SDRAM
admit four reads and two writes, while serial memory targets advertise lower
credits. A queued target guard bounds stalls and fail-closes after accepted
timeouts. Stable target-specific functional clocks keep SDRAM refresh and
serial-memory timing independent of HP DFS.

No release may describe the implementation as timing closed, CDC signed off,
silicon qualified, functionally safe, or cache coherent until the separate
physical and product evidence exists.
