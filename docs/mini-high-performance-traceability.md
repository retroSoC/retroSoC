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
| Target-aware multi-outstanding AXI64 | Data crossbar | Multi-ID, ordering, backpressure, and formal tests | implemented: SRAM/SDRAM use 4R/2W credits; serial targets use 1R/1W; full formal proof pending |
| LP access to every memory window through the data plane | LP data gateway | no-PLL boot and memory-window smoke | implemented |
| Bounded QoS and recovery priority | Data crossbar | starvation and emergency-promotion test | implemented and directed-tested at a reduced four-cycle bound; production bound is 256 cycles and full liveness proof remains pending |
| Initiator ACL and first-fault attribution | Generated data policy, crossbar, SYSCTRL, and Fabric Monitor | target/execute/cache/range denial and injection tests | implemented: fixed policy is topology-generated and the monitor retains the first pulse across APB CDC |
| Stable memory functional clocks | Memory integration | HP DFS while refresh/protocol engines continue | implemented digitally: SRAM is native HP AXI64; SDRAM and all serial targets cross directly from HP to stable memory as AXI64 before local downsizing |
| Reset epoch and stale-response rejection | Async bridges | unilateral reset and clock-stop matrix | partial: coordinated warm flush and epoch implemented |
| HP normal and forced hot reset | AON lifecycle controller and Resource Controller | cache request/ACK, drain, timeout, flush, and recovery tests | implemented digitally: Zicbom and bounded ACK window exist; range policy and Linux service remain software work |
| Clock monitor and programmable timeout | AON clock/reset subsystem | 8x8 DFS and clock-loss tests | implemented |
| Operational EXT-H ACL, timeout, and data path | Extension subsystem | transfer, denial, hang, and quiesce tests | implemented |
| Ownership-aware IRQ handoff | Resource Controller and HP PLIC | idle handoff, owner lock, LP/HP exclusion, and fault tests | implemented for DMA, USB2, SDIO0/1, SPI-SD, EXT-H, and JPEG; downstream per-engine reset ACK remains pending |
| JPEG 1080p60 at 72 MHz | JPEG codec and private AXI4 DMA | complete 1080p encode/decode cycles, randomized AXI stalls, synthesis/STA/power | partial: functional direct/ring codec and cycle benchmark exist; current encode core projects to about 24 fps, and the required multi-lane pipeline remains planned |
| Bounded target timeout and isolation | Target guards | pre-/post-accept timeout, burst completion, and late-response isolation | implemented: synthetic SLVERR and fail-closed isolation; physical fault injection pending |
| Root-visible fabric observability | Fabric Monitor | counters, snapshot, high-water, promotion, timeout, isolation, flush, sticky fault, and RTL/C parity tests | implemented; histogram/interrupt/trace streaming and silicon correlation remain pending |
| QPI/OPI pad exclusion and inactive-window error | Memory pad manager | simulation and formal mutual-exclusion proof | implemented |
| Technology clock cells and physical closure | Technology/physical flow | synthesis, MMMC, SDF, CDC/RDC, and PVT | physical-pending |

The architecture report under `/nfs/share/home/miaoyuchi/plan` is the design
input. This matrix and executable configuration are the repository status
sources of truth.

## Current verification evidence

- The complete Python suite passes 308 tests, including directed AXI64
  multi-ID/ACL/QoS, target isolation, native AXI64 SRAM, Fabric Monitor,
  async warm-flush, clock monitor, HP lifecycle, Resource Controller, EXT-H
  DMA, topology, clock/reset inventory, and physical macro mapping.
- Generated PRODUCT Vexii manifests select `rv32imafdc_zicbom_max`. IHP130
  PRODUCT Icarus assembly reports `SIM_TEST_PASS` at 3.532422647 ms. Its PR
  `ci_smoke` Verilator run with SVA, fast flash, and the 32 KiB all-SRAM layout
  passes ARCHINFO, SRAM, Fabric Monitor HAL/APB, extensions, RNG, CLINT,
  timers, GPIO, SDRAM, crypto, and USB2, then reports `SIM_TEST_PASS code=0`
  after 4,540,766 cycles.
- The committed ICS55 no-PLL/no-SRAM PRODUCT profile reports Icarus
  `SIM_TEST_PASS` at 3.532422647 ms. Both ignored local ICS55 variants with
  32 KiB commercial SRAM and PLL respectively off and on pass at the same
  time. The PLL-on log identifies SYSCTRL PLL clock control; local commercial
  SRAM and PLL sources remain outside Git.
- Strict IHP130 PRODUCT Verilator lint/elaboration completes successfully.
  Repository format, full RTL style audit/readiness, clock/reset inventory,
  embedded-C format/policy/host, Ruff, YAML, Actions, regression dry-runs, and
  Pytest gates pass.
- The 12-target `rib2apb` topology passes its depth-20 SymbiYosys/Bitwuzla
  proof and cover. Product SYSCTRL and PLL/RCU retain their bounded proof and
  cover targets. A complete AXI64 liveness proof remains pending.

The strict IHP130 warning-baseline comparison remains an observation: the
baseline predates the fixed HP/product topology and does not contain many
generated VexiiRiscv, newly enabled peripheral, and PDK signatures. New warning
signatures introduced directly by the data-plane, lifecycle, extension, and
CDC integration were removed; the baseline was intentionally not regenerated
or hand-edited in this change.

Synthesis, netlist simulation, STA, CDC/RDC signoff, gate-level power intent,
and PVT characterization are intentionally outside this delivery, as required
by the implementation scope.
