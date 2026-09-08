#import "../style.typ": *

== Electrical and Timing Specifications <electrical-specifications>
The RTL snapshot and reference configuration establish digital behavior, not production
electrical ratings. The following groups define the information needed for a physical release.
TBD means no reviewed specification is attached; it never means zero or an unrestricted limit.

#change-start("electrical-release-record", "Electrical/timing: report and condition linkage")
Each completed parameter row must identify its supply/pad domain, PVT and load conditions,
unit, Min/Typ/Max interpretation and report revision. Attach setup/hold and output-delay
values to a waveform reference edge and test load. Keep analysis, characterization and
production-test guarantees distinct when the release record in @release-verification is filled.
#change-end("electrical-release-record")

=== Parameter conditions and evidence
Every numerical electrical entry must identify process/PDK and revision, macro/pad implementation,
package, supply, temperature, clock configuration and loading. Label the basis as approved
vendor specification, model/analysis, characterization or production test. Minimum/maximum
guarantees and typical observations must not be interchanged.

#ds-table("electrical-conditions",[Conditions required for a numerical electrical specification],
  ([Condition],[Required record],[Current publication state]),
  (([Device identity],[Source, die/lot revision, technology macro and package.],[Digital reference identity available; physical part identity TBD.]),
   ([Environment],[Rail tolerances, junction/ambient temperature and PVT corner.],[TBD.]),
   ([Measurement],[Instruments/models, bandwidth, probes, board and uncertainty.],[No reviewed characterization setup attached.]),
   ([Loading and activity],[Pin load, external devices, clocks, workload and enabled domains.],[Define per parameter; not inferred from the reference profile.]),
   ([Guarantee basis],[Min/Typ/Max meaning, test coverage and report revision.],[TBD.])),widths:(0.8fr,1.75fr,1.45fr))

=== Power supply and power sequencing
The AON, LP, HP, PCLK and memory names describe functional clock/reset domains. They do not
by themselves identify independent supply rails, retention power islands or physical isolation.
Power connections and sequencing must come from the selected technology and package implementation.

#ds-table("power-sequencing",[Power and reset sequencing information awaiting qualification],
  ([Item],[Required specification],[State]),
  (([Supply map],[Core, I/O-bank, PLL/memory macro and any analog rails, returns and allowed relations.],[TBD]),
   ([Power-up],[Ramp limits, rail order, external clock availability and reset assertion/release timing.],[TBD]),
   ([Power-down],[Reset/clock ordering, outstanding-transfer handling and rail discharge limits.],[TBD]),
   ([Partial power],[Back-power/injection limits and permitted levels when another rail is absent.],[TBD]),
   ([Decoupling],[Approved capacitor network, placement, return path and package-specific requirements.],[TBD])),
  widths:(0.8fr,2.8fr,0.4fr))
Digital initialization begins only after the board has met its approved rail, clock and reset
requirements. Use the clock/reset sequence in @operating-states after that point. No universal
rail ordering, brownout threshold or reset pulse width is specified for the generic SoC here.

=== Absolute maximum ratings
#ds-table("absolute-ratings",[Absolute maximum rating categories],
  ([Parameter],[Conditions / scope],[Min],[Max],[Unit]),
  (([Supply voltage],[Each physical rail; device/package TBD.],[TBD],[TBD],[V]),
   ([Input/output voltage],[Pad/bank, rail state and overshoot duration TBD.],[TBD],[TBD],[V]),
   ([Injection/output current],[Per pad, bank and total device; duration TBD.],[TBD],[TBD],[mA]),
   ([Storage / junction temperature],[Package and material system TBD.],[TBD],[TBD],[deg C])),
  widths:(1.2fr,1.8fr,0.45fr,0.45fr,0.5fr))
Absolute maximum ratings are stress limits, not operating conditions. They cannot be derived
from a synthesis clock constraint, an FPGA bank setting or another manufacturer's SoC rating.

=== Recommended operating conditions and DC characteristics
#ds-table("dc-characteristics",[Operating and DC parameters requiring device-specific data],
  ([Group],[Parameter / condition],[Min],[Typ],[Max],[Unit]),
  (([Supply],[Core and each I/O bank at stated PVT.],[TBD],[TBD],[TBD],[V]),
   ([Temperature],[Approved operating grade and junction limit.],[TBD],[TBD],[TBD],[deg C]),
   ([Input],[VIH/VIL and hysteresis for each pad type.],[TBD],[TBD],[TBD],[V]),
   ([Output],[VOH/VOL at stated source/sink current.],[TBD],[TBD],[TBD],[V]),
   ([Leakage],[Input/tri-state leakage over voltage and temperature.],[TBD],[TBD],[TBD],[uA]),
   ([Pull / keeper],[Resistance or holding current, if implemented.],[TBD],[TBD],[TBD],[ohm / uA])),
  widths:(0.7fr,1.9fr,0.4fr,0.4fr,0.4fr,0.6fr))
Check each pad class separately. A logical output-enable, pull-control or open-drain capability
does not specify its electrical strength. The approved board must meet both sides of an interface.

=== AC and interface timing
The WaveDrom figures in this publication illustrate digital ordering and wait/error behavior.
They do not specify board-level setup/hold times, propagation delay, jitter or maximum rates.

#ds-table("ac-characteristics",[Interface timing specification groups],
  ([Interface],[Parameters and conditions to characterize],[State]),
  (([Reference clocks / reset],[Clock period/duty/jitter, reset pulse and release setup at the actual pads.],[TBD]),
   ([XPI / QPI / OPI],[Clock-to-output, data setup/hold, turnaround, CS timing and sampling margin with selected devices.],[TBD]),
   ([SDRAM / SDIO],[Clock/data/control setup/hold, skew, board load and selected memory/card mode.],[TBD]),
   ([ULPI],[PHY-to-controller and controller-to-PHY timing under the approved clock/board constraints.],[TBD]),
   ([I2S / DVP],[Input/output timing relative to audio/pixel clocks and external device requirements.],[TBD]),
   ([GPIO / UART / I2C / PS2 / WS2812],[Pad delay, load/rise/fall conditions and protocol pulse/bit tolerances.],[TBD]),
   ([JTAG],[TCK rate/duty and TMS/TDI/TDO timing for the chosen package and debugger.],[TBD])),
  widths:(0.95fr,2.65fr,0.4fr))
The IP configuration can express divider counts and protocol-cycle settings before these
physical limits are known. Derive a candidate configuration from the controller and external
device requirements, then validate the actual path under worst-case load and PVT. A passing
behavioral memory model is only one part of that evidence.

=== Current consumption and power
Report power by measured rail and defined operating state. Include clock sources, activity,
external loads and retained state; distinguish SoC power from board/PHY/memory power. HP clock
gating alone does not justify a deep-sleep current claim. Dynamic voltage scaling, power
isolation and retention current are not established by the current digital clock controls.

#ds-table("power-characteristics",[Power characterization conditions],
  ([Scenario],[Conditions to record],[Current / power]),
  (([LP control],[Firmware placement, LP clock, HP state and enabled peripherals.],[TBD]),
   ([Dual-hart application],[Exact Linux/firmware workload, cache state and external memory traffic.],[TBD]),
   ([Media / DMA workload],[Sustained rate, buffers, contention, devices and clocks.],[TBD]),
   ([HP leaf gated],[Fabric/memory activity and retained peripheral state.],[TBD]),
   ([Transition / recovery],[Transient peak, duration and rail measurement bandwidth.],[TBD])),
  widths:(1fr,2.4fr,0.6fr))
#source-note("physical/README.md",title:"Technology, macro and physical-validation boundary")
#source-note("docs/pll-clock-control.md",title:"Digital clock choices and physical qualification")
