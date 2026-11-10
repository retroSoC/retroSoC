#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow

= Implementation
== SoC Integration
Start from the committed ICS55 Tiny profile; select IHP130 compatibility explicitly when needed. Use the existing locked dependency setup and doctor flow, then build the
Tiny firmware and selected simulator. The publication pipeline itself does not perform an EDA campaign.
#code-block(raw("make CONFIG=configs/ci/ics55-tiny.mk setup\nmake CONFIG=configs/ci/ics55-tiny.mk doctor\nmake CONFIG=configs/ci/ics55-tiny.mk firmware sim\nmake CONFIG=configs/ci/ics55-tiny.mk SIMU=IVERILOG firmware sim\nmake CONFIG=configs/ci/ics55-tiny.mk regress-pr",block:true))
Tiny source lists exclude Mini product RTL, RIB/RIBP, application-CPU generation and accelerator inputs. Common RTL and
Hazard3 remain revision-locked. Keep generated files in the selected build variant; missing unrelated accelerator corpora
must not become prerequisites for the Tiny publication.

== RTL Simulation
Use the selected Tiny generated source list and matching pin/device models. Verilator and Icarus have separate results;
unsupported or missing-model cases remain explicit. A passing command also needs its configured terminal success marker
and no fatal/failure/timeout marker. UART startup output alone is not a verdict.
#source-note("docs/engineering.md",title:"Regression and artifact contracts")

== FPGA Verification
The repository FPGA guide describes the Mini wrapper. It does not provide a qualified Tiny board implementation.
A Tiny FPGA result requires an explicit Tiny wrapper, board pin/clock constraints, device-model assumptions and retained tool/board evidence.
#source-note("fpga/README.md",title:"Current FPGA integration ownership")

== Physical Design
Synthesis, mapping, netlist-function checks, STA and physical implementation have distinct inputs and verdicts.
For Tiny and its phased extensions, pre-final timing observations retain attempted/failed/unrun evidence;
the final combined complete-product campaign still requires timing closure. This publication does not waive any gate.
#source-note("physical/README.md",title:"Physical implementation and flow ownership")
#source-note("docs/ip/tiny-soc-verification.md",title:"Dated Tiny implementation evidence")

== PCB Hardware
The approved QFN64 target and executable ASIC wrapper are separate inventories. No complete bond map,
qualified PCB, power/clock design or measured interface margin is established here. Record the board revision,
BOM, external devices, voltage, clock and measurement setup before attributing a hardware result.
