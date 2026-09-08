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

A released package mapping must bind each logical signal to a die pad, package pin, supply
bank, pad-cell type and board net. Identify reset drive/enable and applicable electrical
limits separately. Check pin uniqueness, intentional shared power connections and unbonded
signals against the selected profile; row order and an FPGA ball assignment cannot supply
this mapping. The matching physical release evidence is tracked in @release-verification.

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

#include "connection-constraints.typ"

=== Package Dimensions
#placeholder[Package outline and mechanical dimensions]
The old QFN128 and 12.3 × 12.3 mm description is not retained as a qualified mechanical
specification. A package selection, approved outline, pin-1 orientation and thermal-pad
connection must be supplied before a physical pinout is published.

The mechanical record must identify the outline revision, top/bottom view, pin-1 orientation,
body/lead dimensions and tolerances, seating plane and exposed-pad connection. Any CAD
symbol, footprint or 3D model must name the same package revision. Those deliverables remain
unprovided for this digital reference.

=== Graded Reflow Soldering
#tbd[Reflow profile, moisture sensitivity level, storage/bake requirements and permitted
assembly excursions require the selected package supplier's qualified data.]

=== Thermal and Reliability Information
Publish thermal parameters only for an identified die, package and board condition. Junction-to-
ambient, junction-to-case and characterization parameters are not interchangeable, and a
typical board result is not a universal operating limit. No numerical thermal limit is attached
to this digital reference.
#ds-table("thermal-reliability",[Physical release information and required supporting evidence],
  ([Topic],[Required supporting information],[State]),
  (([Thermal],[Package/die, board stackup, airflow, power map, method and applicable parameters.],[TBD]),
   ([ESD / latch-up],[Pad/device configuration, method, stress levels and qualification results.],[TBD]),
   ([Reliability],[Operating grade, lifetime assumptions, qualification plan and reports.],[TBD]),
   ([Assembly],[Package materials, MSL, bake/storage and approved reflow profile.],[TBD]),
   ([Physical identification],[Pin 1, die pads versus package pins, exposed pad and test/power connections.],[TBD])),
  widths:(0.75fr,2.85fr,0.4fr))
Keep these fields separate from digital simulation and FPGA bringup results. Populate them
from the chosen supplier/implementation reports before issuing a physical product specification.

For each qualification entry, retain the method/revision, stress conditions, tested sample
or lot population, result and applicable device/package grades. Thermal characterization
also retains board construction and airflow. The verification summary in @release-verification
keeps those physical records distinct from RTL tests and analytical estimates.

=== Ordering Information
#ds-table("ordering", [Ordering information awaiting qualification],
  ([Field], [Specification]),
  (([Orderable part number], [TBD]),([Package / temperature grade], [TBD]),
   ([Tape/reel and packing], [TBD]),([Availability / silicon revision], [TBD])),
  widths:(1fr,1fr),
)

An orderable-part record must connect its package and temperature grade to a documented
die revision, marking scheme and packing option. Record applicable errata and ordering
availability for that exact part. The source SHA and draft document version identify this
publication; they are not a manufactured-device marking or a sales part number.

#include "electrical-reference.typ"
