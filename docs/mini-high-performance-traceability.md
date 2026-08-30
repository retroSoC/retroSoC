# Mini High-Performance Traceability

## Status vocabulary

- `implemented`: RTL and software-visible behavior exist and directed tests pass.
- `partial`: a bounded subset is implemented and the missing boundary is stated.
- `verified`: the required simulation and formal evidence pass.
- `physical-pending`: digital behavior exists but synthesis or later evidence is required.
- `planned`: the implementation is not complete.

## Requirement matrix

| Requirement | Implementation owner | Required evidence | Status |
| --- | --- | --- | --- |
| Independent HP I-cache and D-cache paths | HP subsystem and data plane | Concurrent different-target AXI test | implemented |
| Target-aware multi-outstanding AXI64 | Data crossbar | Multi-ID, ordering, backpressure, and formal tests | partial: concurrent across targets; one per target |
| LP access to every memory window through the data plane | LP data gateway | no-PLL boot and memory-window smoke | implemented |
| Bounded QoS and recovery priority | Data crossbar | starvation and emergency-promotion test | partial: priority and aging implemented; full bound proof pending |
| Initiator ACL and first-fault attribution | Data firewall and SYSCTRL fault manager | legal/illegal access and injection tests | implemented |
| Stable memory functional clocks | Memory integration | HP DFS while refresh/protocol engines continue | partial: QPI/OPI/XPI migrated; SRAM/SDRAM remain LP |
| Reset epoch and stale-response rejection | Async bridges | unilateral reset and clock-stop matrix | partial: coordinated warm flush and epoch implemented |
| HP normal and forced hot reset | AON lifecycle controller | drain, timeout, flush, and recovery tests | partial: cache-clean ACK remains software policy |
| Clock monitor and programmable timeout | AON clock/reset subsystem | 8x8 DFS and clock-loss tests | implemented |
| Operational EXT-H ACL, timeout, and data path | Extension subsystem | transfer, denial, hang, and quiesce tests | implemented |
| Ownership-aware IRQ handoff | Lifecycle and IRQ router | pending edge/level migration tests | partial: EXT-H LP/HP route implemented |
| QPI/OPI pad exclusion and inactive-window error | Memory pad manager | simulation and formal mutual-exclusion proof | implemented |
| Technology clock cells and physical closure | Technology/physical flow | synthesis, MMMC, SDF, CDC/RDC, and PVT | physical-pending |

The architecture report under `/nfs/share/home/miaoyuchi/plan` is the design
input. This matrix and executable configuration are the repository status
sources of truth.

## Current verification evidence

- IHP130 `ci_smoke`, Verilator with SVA, the 32 KiB all-SRAM layout, and the
  explicit fast-flash backend: `SIM_TEST_PASS code=0` at 5,770,694 cycles.
- IHP130 no-PLL Icarus assembly regression with the serial flash, QPI PSRAM,
  and SDRAM models: `SIM_TEST_PASS` at 4.014 ms.
- Committed ICS55 compatibility profile with PLL/SRAM disabled: Icarus
  `SIM_TEST_PASS` at 4.014 ms.
- Git-ignored local ICS55 profile with PLL, SRAM interface, SRAM macro, and
  32 KiB enabled: Icarus `SIM_TEST_PASS` at 4.014 ms.
- Directed AXI64 crossbar, async warm-flush bridge, clock-monitor, HP lifecycle,
  and EXT-H DMA tests pass. Repository RTL style/readiness, clock/reset-domain,
  embedded-C policy/host, Ruff, and Pytest gates pass.
- Product-mode SYSCTRL and the current 11-state PLL/RCU controller pass their
  bounded proof and cover targets. The PLL/RCU proof covers successful switch,
  unsupported-PLL failure, and timeout failure paths.

The strict IHP130 warning-baseline comparison remains an observation: the
baseline predates the fixed HP/product topology and does not contain many
generated VexiiRiscv, newly enabled peripheral, and PDK signatures. New warning
signatures introduced directly by the data-plane, lifecycle, extension, and
CDC integration were removed; the baseline was intentionally not regenerated
or hand-edited in this change.

Synthesis, netlist simulation, STA, CDC/RDC signoff, gate-level power intent,
and PVT characterization are intentionally outside this delivery, as required
by the implementation scope.
