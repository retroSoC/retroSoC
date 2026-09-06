#import "../style.typ": *

== Packaging
=== Pin Mapping
The following inventory describes the logical signal-pad ABI. It does not assign package pin
numbers, die-pad sequence numbers or FPGA ball locations. Numeric suffixes in bus signal names
identify signal indices only. Power pads are technology-wrapper additions and are not assigned
physical package numbers here.

The reference profile disables PLL-dependent pads. Full GPIO pads carry data, output-enable
and electrical controls. A top-level Verilog direction of `inout` may describe a pad-wrapper
connection even for a functionally input-only signal; use the pad kind and interface contract
together. Reset electrical properties require the selected PDK and board specification.

#note[SDIO1 and USB2 ULPI have dedicated pad groups that are intentionally unbound in the generic
FPGA wrapper until board pin locations, 3.3 V I/O-bank allocation and timing are approved.
Do not derive a package drawing from the order of rows in this table.]

#ds-table("pads", [Logical signal-pad inventory - reference profile],
  ([Signal pad], [RTL direction], [Pad kind]),
  data.pads.map(p=>(code(p.name),p.direction,p.kind.replace("_"," "))),
  widths:(2.1fr,0.8fr,1.1fr),
  notes:[Physical Package Pin, Die Pad, power domain and electrical reset values: TBD.
  The inventory is generated from the canonical pin map.],
)

#pagebreak()
=== GPIO Alternate-Function Matrix <gpio-mux>
Each GPIO has software-controlled and alternate-function ownership. ALT0/ALT1 names below
are normalized signal labels from the canonical topology. Shared names denote the same
peripheral route; switching function also changes its input and output-enable connections.

#ds-table("gpio-alt", [GPIO alternate functions],
  ([GPIO], [ALT0], [ALT1]),
  data.gpio.map(g=>(str(g.pin),code(g.alt0_label),code(g.alt1_label))),
  widths:(0.35fr,1.55fr,1.55fr),
  notes:[GPIO0/1 multiplex UART0 flow control and PS/2. QPI and OPI share memory pads.
  Drivers must quiesce the old owner before changing pad mode.],
)

=== Package Dimensions
#placeholder[Package outline and mechanical dimensions]
The old QFN128 and 12.3 × 12.3 mm description is not retained as a qualified mechanical
specification. A package selection, approved outline, pin-1 orientation and thermal-pad
connection must be supplied before a physical pinout is published.

=== Graded Reflow Soldering
#tbd[Reflow profile, moisture sensitivity level, storage/bake requirements and permitted
assembly excursions require the selected package supplier's qualified data.]

=== Ordering Information
#ds-table("ordering", [Ordering information awaiting qualification],
  ([Field], [Specification]),
  (([Orderable part number], [TBD]),([Package / temperature grade], [TBD]),
   ([Tape/reel and packing], [TBD]),([Availability / silicon revision], [TBD])),
  widths:(1fr,1fr),
)

== Electrical and Timing Specifications
The RTL snapshot and configuration files do not establish absolute maximum ratings,
recommended operating limits or production test coverage. Digital clock choices and
simulation assertions are not substitutes for measured electrical characteristics.

#ds-table("electrical", [Electrical characterization placeholders],
  ([Parameter group], [Conditions], [Min], [Typ], [Max], [Unit]),
  (([Core supply], [PDK / corner TBD], [TBD],[TBD],[TBD],[V]),
   ([I/O supply and thresholds], [Pad / bank TBD], [TBD],[TBD],[TBD],[V]),
   ([Operating temperature], [Grade TBD], [TBD],[TBD],[TBD],[°C]),
   ([Power consumption], [Workload TBD], [TBD],[TBD],[TBD],[mW]),
   ([Input/output timing], [Load / corner TBD], [TBD],[TBD],[TBD],[ns])),
  widths:(1.4fr,1.25fr,0.5fr,0.5fr,0.5fr,0.5fr),
  notes:[TBD means unavailable, not zero. No numerical operating limit is asserted by this table.],
)
#placeholder[Pad timing and reset waveforms]
Absolute maximum ratings, ESD/latch-up, PLL jitter and memory/ULPI board timing will be added
only with their applicable device, PDK, test conditions and supporting evidence.
