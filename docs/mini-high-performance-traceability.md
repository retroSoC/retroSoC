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
| Bounded QoS and recovery priority | Data crossbar | starvation and emergency-promotion test | partial: priority and aging implemented; full bound proof pending |
| Initiator ACL and first-fault attribution | Data firewall and SYSCTRL fault manager | legal/illegal access and injection tests | implemented |
| Stable memory functional clocks | Memory integration | HP DFS while refresh/protocol engines continue | implemented digitally: SRAM is native HP AXI64; SDRAM AXI64 crosses to stable memory; serial targets retain transitional LP staging |
| Reset epoch and stale-response rejection | Async bridges | unilateral reset and clock-stop matrix | partial: coordinated warm flush and epoch implemented |
| HP normal and forced hot reset | AON lifecycle controller and Resource Controller | cache request/ACK, drain, timeout, flush, and recovery tests | implemented digitally: Zicbom and bounded ACK window exist; range policy and Linux service remain software work |
| Clock monitor and programmable timeout | AON clock/reset subsystem | 8x8 DFS and clock-loss tests | implemented |
| Operational EXT-H ACL, timeout, and data path | Extension subsystem | transfer, denial, hang, and quiesce tests | implemented |
| Ownership-aware IRQ handoff | Resource Controller and HP PLIC | idle handoff, owner lock, LP/HP exclusion, and fault tests | implemented for DMA, USB2, SDIO0/1, SPI-SD, and EXT-H; downstream per-engine reset ACK remains pending |
| Bounded target timeout and isolation | Target guards | pre-/post-accept timeout, burst completion, and late-response isolation | implemented: synthetic SLVERR and fail-closed isolation; physical fault injection pending |
| QPI/OPI pad exclusion and inactive-window error | Memory pad manager | simulation and formal mutual-exclusion proof | implemented |
| Technology clock cells and physical closure | Technology/physical flow | synthesis, MMMC, SDF, CDC/RDC, and PVT | physical-pending |

The architecture report under `/nfs/share/home/miaoyuchi/plan` is the design
input. This matrix and executable configuration are the repository status
sources of truth.

## Current verification evidence

- The complete Python suite passes: 306 tests, including directed AXI64
  crossbar, same-target IDs, target isolation, native AXI64 SRAM, async
  warm-flush, clock monitor, HP lifecycle, Resource Controller, EXT-H DMA,
  topology, clock/reset inventory, and physical macro mapping.
- Generated PRODUCT Vexii manifests select `rv32imafdc_zicbom_max`. IHP130
  PRODUCT Icarus assembly passes at 3.998665187 ms; the matching Verilator
  assembly run passes in 221,756 cycles. Its PR `ci_smoke` Verilator run with
  SVA, fast flash, and the 32 KiB all-SRAM layout passes every peripheral test
  and reports `SIM_TEST_PASS code=0` after 5,679,566 cycles.
- The committed ICS55 no-PLL/no-SRAM PRODUCT profile passes Icarus assembly at
  3.998665187 ms. Both ignored local ICS55 variants, with 32 KiB SRAM and PLL
  respectively off and on, pass the same PRODUCT Icarus test at 3.998665187 ms.
  The local commercial SRAM and PLL sources remain outside Git.
- The committed ICS55 PRODUCT `ci_smoke` Verilator run with SVA, fast flash,
  and the SDRAM execution layout passes every peripheral check and reports
  `SIM_TEST_PASS code=0` after 6,984,536 cycles. GF180, ICS55, and SKY130 use
  this bounded 600-second path in PR regression; serial PSRAM boot remains in
  their Icarus assembly coverage.
- The Yosys/Slang frontend elaborates the corrected downsizer and HP AXI mux
  with zero errors or warnings. The generated IRQ SVA now binds to the LP clock
  and reset, and the top-level unused-domain vector has exact width.
- Repository format, full RTL style audit/readiness, clock/reset-domain,
  embedded-C policy/host, Ruff, and Pytest gates pass. Focused post-CI-fix
  Python/RTL coverage passes 91 tests.
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
