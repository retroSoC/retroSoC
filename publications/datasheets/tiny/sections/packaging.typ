#import "../style.typ": *
#import "../../../specifications/components.typ": parameters, characteristics, reference-notice
#import "../../../specifications/figures.typ": visual, connection, board-circuit
#import "../package-figures.typ": qfn-pinout, qfn-pin-view, qfn-mechanical, qfn-copper, qfn-layer
#import "../assembly-references.typ": assembly-reference-table, carrier-tape, reel, reel-box, reflow

#let qfn-layout-change = "tiny-v02-qfn64-layout-20261119-"
#let qfn-assembly-change = "tiny-v02-qfn64-assembly-20261119-"
#let spec = data.specifications

== Packaging <tiny-pins>
QFN64 is the confirmed Tiny product package family: 48 signal terminals and 16 perimeter power/ground terminals.
EP is separate and unnumbered. The frozen target allocation remains authoritative for planning.
Physical die-to-package bonding, pad electrical qualification and the supplier outline are not released.
The target table is not an implemented bond map.

=== Pin Mapping
#change-start(doc.change_prefix + "target-pinout", "QFN64 target pinout with complete alternate functions")
#visual(spec, "qfn-pinout", qfn-pinout(spec), [QFN64 target pinout — top view], anchor: "qfn64-target-pinout")
#change-end(doc.change_prefix + "target-pinout")
#pagebreak(weak: true)
#ds-table("qfn64",[QFN64 pin descriptions - frozen target; physical binding pending],
  ([Pin],[Target / external function],[Mode],[Dir.],[Reset logic],[Bias],[Restrictions / state]),
  data.specifications.qfn.pins.map(p=>(str(p.pin),p.function,p.gpio_mode,p.direction,p.reset,p.bias,p.limitation)),
  widths:(0.35fr,1.65fr,0.65fr,0.45fr,0.75fr,0.85fr,1.1fr),
  notes:[Directions and reset logic describe the current digital function where known. XOUT, BOOT_MODE and TEST_MODE remain unbound targets. All physical pad limits, bond mapping and electrical reset bias remain separate/TBD.])
#block(breakable: false, width: 100%)[
  #change-start(qfn-layout-change + "pin-numbering", "QFN64 top and bottom pin numbering")
  #visual(spec, "qfn-top", qfn-pin-view(spec, "top"), [QFN64 top view and projected terminal numbering])
  #visual(spec, "qfn-bottom", qfn-pin-view(spec, "bottom"), [QFN64 bottom view and unnumbered exposed pad])
  #change-end(qfn-layout-change + "pin-numbering")
]

#ds-table("target-binding",[Target signals versus RTL and physical binding],
  ([Target signal],[Current digital connection],[Physical status / restriction]),(
    ([GPIO0-31],[Canonical GPIO/ALT routes; ALT disabled and output-enable off at reset.],[Target pins allocated; pad-to-bond map pending.]),
    ([XIN],[External 24 MHz input via extclk_i_pad in the reference profile.],[External oscillator example; pad level/duty/jitter limits TBD.]),
    ([XOUT],[Target crystal terminal; no released crystal-amplifier binding.],[Do not assume a passive crystal works; unconnected in this example.]),
    ([AUDIO input],[Current RTL receives the AUDIO reference through GPIO17 ALT0 in the complete I2S group.],[Uses the existing GPIO target. Supply a compatible clock; physical bonding and pad limits remain pending.]),
    ([RESET_N],[External active-low reset and synchronized domain releases.],[Supervisor, strap and passive values require board/pad review.]),
    ([BOOT_MODE / TEST_MODE],[Target allocation; no confirmed production strap decoding or physical binding.],[Intended straps are planning fields; release tie states TBD.]),
    ([EP],[Separate exposed pad; no confirmed wrapper-to-EP binding.],[Intended GND; substrate/die attach/supplier confirmation required.]),
    ([Power / ground],[Target core, analog and digital-I/O rails; wrapper inventory differs.],[All supply/ground connections require rail and bonding approval.])),widths:(0.8fr,1.6fr,1.6fr))
#source-note("docs/ip/tiny-soc.md",title:"QFN64 target, voltage planning and frozen allocation")

The current ASIC compatibility wrapper retains legacy dedicated UART/XPI-CS terminals and an older power-pad inventory.
GPIO8/9 carry active UART0. The wrapper is not another package option or an approved bond map.
#ds-table("pads",[Tiny executable logical pads - traceability inventory],
  ([Signal],[RTL direction],[Pad kind]),
  data.pads.map(p=>(code(p.name),p.direction,p.kind.replace("_"," "))),widths:(2fr,0.8fr,1.2fr))
The wrapper has #data.pads.len() logical signal pads and #data.power_pads.values().sum() power/ground pad cells,
distinct from the QFN64 perimeter target.

=== GPIO Alternate-Function Matrix
The pin-description table above gives external function names and digital reset/bias state. The matrix below retains the raw RTL identifiers for traceability.
#let gpio-mode(mode) = {
  let terms=mode.inputs + if mode.do.contains("'") {()} else {(mode.do,)}
  if terms.len()==0 {[Not routed]} else {code(terms.join(" / "))}
}
#ds-table("gpio-alternates",[Tiny GPIO canonical RTL routes],
  ([GPIO],[ALT0 RTL identifiers],[ALT1 RTL identifiers]),
  data.gpio.map(g=>(str(g.pin),gpio-mode(g.alt0),gpio-mode(g.alt1))),widths:(0.4fr,1.85fr,1.85fr))
Stop/drain the old producer, disable output enables and release ownership before changing routes.
I2C needs external pull-ups and compatible levels. DVP, I2S, PWM, SPI and display routes share GPIO.
Boot XPI and JTAG use dedicated target groups.

#pagebreak(weak: true)
#change-start(qfn-layout-change + "package-drawings", "QFN64 mechanical outline, footprint and assembly layers")
=== Package Dimensions, Reflow and Reliability
==== Package Outline and Mechanical Dimensions <tiny-package-outline>
The preferred planning outline and terminal pitch follow the reference geometry in
#link("https://www.analog.com/media/en/package-pcb-resources/package/pkg_pdf/ltc-legacy-qfn/qfn_64_05-08-1705.pdf")[ADI UP64 05-08-1705 Rev C].
Supplier outline, bond map and pad metallurgy approval remain pending.
#visual(spec, "qfn-mechanical", qfn-mechanical(spec, numbered: true), [QFN64 mechanical outline], kind: image)

#pagebreak(weak: true)
==== Recommended PCB Footprint <tiny-pcb-footprint>
The component-side copper pattern follows the top-view pin numbering. The land-pattern tolerances
apply to the copper dimensions shown. Fabrication dimensions require approval for the selected package.
#visual(spec, "qfn-copper", qfn-copper(spec), [QFN64 copper land pattern])

#pagebreak(weak: true)
==== Assembly Layers and Reliability <tiny-assembly-reliability>
#grid(columns: (84mm, 84mm), column-gutter: 4mm, row-gutter: 3mm,
  visual(spec, "qfn-mask", qfn-layer(spec, "mask"), [QFN64 solder-mask openings]),
  visual(spec, "qfn-paste", qfn-layer(spec, "paste"), [QFN64 solder-paste windows]),
  visual(spec, "qfn-vias", qfn-layer(spec, "vias"), [QFN64 exposed-pad thermal vias]),
  block(width: 84mm, inset: (x: 3mm, y: 4mm))[
    #set text(size: 9pt)
    *Assembly review* #linebreak()
    Paste coverage is the total aperture area divided by the nominal rectangular package EP area.
    The calculation uses the full bounding square. Review stencil release, solder loss into vias,
    voiding, coplanarity and board finish with the assembler. Confirm via fill, capping or another
    approved solder-loss treatment with the fabricator. EP supplements perimeter grounds.
  ],
)

Thermal resistance, MSL, bake/reflow peaks and reliability remain TBD.
#parameters(data.specifications,"thermal",ds-table)
#parameters(data.specifications,"assembly",ds-table)
Assembly organization follows
#link("https://www.analog.com/en/resources/app-notes/smt-assembly-and-pcb-design-guidelines-for-maxims-standard-wirebonded-quad-flatpack.html")[ADI's QFN assembly guidance].
The selected supplier and assembler must release the final process.
#change-end(qfn-layout-change + "package-drawings")

#let tape-source = spec.sources.find(s => s.id == "ti-tusb8041-tape-reel").url
#let box-source = spec.sources.find(s => s.id == "ti-tusb8041-reel-box").url
#let reflow-source = spec.sources.find(s => s.id == "adi-smp-reflow").url

#pagebreak(weak: true)
#change-start(qfn-assembly-change + "carrier-tape", "Carrier tape engineering drawing and reference dimensions")
==== Carrier Tape Dimensions <tiny-carrier-tape>
The component-side view shows the feed direction relative to the sprocket holes and the Pin 1 corner.
The nominal example is for the 64-pin, 9 × 9 mm RGC VQFN in
#link(tape-source)[TI's TUSB8041IRGCR packaging materials information].
#visual(spec, "qfn-carrier-tape", carrier-tape(spec), [Carrier tape and pocket dimensions])
#assembly-reference-table(spec, "carrier-tape", ds-table)
#change-end(qfn-assembly-change + "carrier-tape")

#pagebreak(weak: true)
#change-start(qfn-assembly-change + "reel", "Reel engineering drawing, dimensions and standard pack example")
==== Reel Dimensions <tiny-reel-dimensions>
Outside diameter and axial width are nominal. The standard pack quantity applies to the exact
#link(tape-source)[TI TUSB8041IRGCR orderable device] shown in @tiny-carrier-tape.
#visual(spec, "qfn-reel", reel(spec), [Reel front and axial side views])
#assembly-reference-table(spec, "reel", ds-table)
#change-end(qfn-assembly-change + "reel")

#pagebreak(weak: true)
#change-start("tiny-v02-reel-box-20261120-reel-box", "Tape and reel box drawing and reference dimensions")
==== Tape and Reel Box Dimensions <tiny-reel-box-dimensions>
The nominal outside dimensions describe the carton for the same #link(box-source)[TI TUSB8041IRGCR reference device]
shown in @tiny-reel-dimensions. The height measures the box body up to its lid seating plane.
#visual(spec, "qfn-reel-box", reel-box(spec), [Tape and reel box outside dimensions], anchor: "tiny-reel-box-figure")
#assembly-reference-table(spec, "reel-box", ds-table)
#change-end("tiny-v02-reel-box-20261120-reel-box")

#pagebreak(weak: true)
#change-start(qfn-assembly-change + "reflow", "Pb-free classification profile and reflow limits table")
==== Reflow Soldering Profile <tiny-reflow-profile>
The example uses package body temperature for Pb-free classification and preconditioning.
A Tiny board profile requires the released package, solder paste and measured assembly temperatures.
See #link(reflow-source)[ADI Surface Mount Products Rev J, Tables 2 and 3 and Figure 2].
#visual(spec, "qfn-reflow", reflow(spec), [Pb-free package classification profile])
#assembly-reference-table(spec, "reflow", ds-table)
#change-end(qfn-assembly-change + "reflow")

#pagebreak(weak: true)
=== Minimum System and Board Design Reference <tiny-board-reference>
#visual(data.specifications,"board-minimum",connection(data.specifications,"minimum"),[Minimum-system topology with external 24 MHz XIN.])
The minimum system needs valid core/digital-I/O rails, return paths, XIN, reset, boot NOR and JTAG access.
An audio design also supplies the AUDIO reference on GPIO17 ALT0 and acquires the complete I2S pad group.
Replace target names with the approved bond map and rail definitions before hardware release.
No brownout detector, passive-crystal oscillator, production strap mode or sequencing guarantee is inferred.
#visual(data.specifications,"board-supply",board-circuit(data.specifications,"decoupling"),[Supply and local-decoupling placement.])
#visual(data.specifications,"board-reset",board-circuit(data.specifications,"clock-reset-boot"),[Clock, reset, boot-NOR and JTAG connection examples.])
#visual(data.specifications,"board-layout",connection(data.specifications,"layout"),[Peripheral connection and routing review.])
The passive examples are registered below. Place bypass loops close to supply/ground pins, preserve continuous return paths,
minimize boot-clock/data stubs and review NOR power-up/CS behavior. Match external pull-ups to the approved I/O bank.
Place JTAG ground returns close to signal references; apply series damping only after signal-integrity review.
Do not connect an assumed crystal network to XOUT. Review the entire alternate-function group for every external device.
These figures are not PCB manufacturing files or a production schematic.

== Electrical and Timing Specifications
#reference-notice[No production electrical ratings or measured Tiny curves are attached.
The examples complete the specification structure. They are not stress limits, safe operating ranges,
drive guarantees or PCB release requirements. TBD preserves missing product evidence.]
A real result retains PDK/corner, rail/pad domain, device/package/board identity, source/profile, workload, clock,
load, temperature, measurement boundary, sample count and uncertainty. Stress and operating limits need separate
qualification. Digital timing waveforms show ordering; they do not establish analog limits.
#parameters(data.specifications,"absolute",ds-table)
#parameters(data.specifications,"operating",ds-table)
#parameters(data.specifications,"dc",ds-table)
#parameters(data.specifications,"ac",ds-table)
#characteristics(data.specifications,ds-table)
Dated negative STA observations in @tiny-evidence retain their original source/profile and stage.
Reference graphs and analytic lane rates do not close timing or physical qualification gaps.
