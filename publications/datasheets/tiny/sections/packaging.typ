#import "../style.typ": *
#import "../../../specifications/components.typ": parameters, pin-table, characteristics, reference-notice
#import "../../../specifications/figures.typ": visual, qfn-view, qfn-side, pcb-view, connection, board-circuit

== Packaging <tiny-pins>
QFN64 is the confirmed Tiny product package family: 48 signal terminals and 16 perimeter power/ground terminals.
EP is separate and unnumbered. The frozen target allocation remains authoritative for planning.
Physical die-to-package bonding, pad electrical qualification and the supplier outline are not released.
The target table is not an implemented bond map.

=== Pin Mapping
#ds-table("qfn64",[QFN64 pin descriptions - frozen target; physical binding pending],
  ([Pin],[Target / external function],[Mode],[Dir.],[Reset logic],[Bias],[Restrictions / state]),
  data.specifications.qfn.pins.map(p=>(str(p.pin),p.function,p.gpio_mode,p.direction,p.reset,p.bias,p.limitation)),
  widths:(0.35fr,1.65fr,0.65fr,0.45fr,0.75fr,0.85fr,1.1fr),
  notes:[Directions and reset logic describe the current digital function where known. XOUT, BOOT_MODE and TEST_MODE remain unbound targets. All physical pad limits, bond mapping and electrical reset bias remain separate/TBD.])
#visual(data.specifications,"qfn-top",qfn-view(data.specifications,"Top"),
  [Tiny QFN64 top view and pin numbering. Numbers follow the target table; geometry is a reference outline.])
#visual(data.specifications,"qfn-bottom",qfn-view(data.specifications,"Bottom",dimensions:true),
  [Tiny QFN64 bottom view and exposed pad; mirrored from the top coordinate model.])

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

=== Package Dimensions, Reflow and Reliability
#reference-notice[The preferred 9 × 9 mm / 0.5 mm pitch planning outline is redrawn from
ADI UP64, 05-08-1705 Rev C, using one dimension set. It is not the Tiny manufacturing drawing.
Every mechanical, land-pattern and assembly number below is Reference Only.]
#parameters(data.specifications,"mechanical",ds-table)
#visual(data.specifications,"qfn-side",qfn-side(data.specifications),[QFN64 side view and seating plane.])
#visual(data.specifications,"qfn-copper",pcb-view(data.specifications,"copper"),[Copper land pattern, component-side view.])
#visual(data.specifications,"qfn-mask",pcb-view(data.specifications,"mask"),[Solder-mask openings; expansion is a fabrication example.])
#visual(data.specifications,"qfn-paste",pcb-view(data.specifications,"paste"),[Paste windows and calculated exposed-pad coverage.])
#visual(data.specifications,"qfn-vias",pcb-view(data.specifications,"thermal vias"),[Exposed-pad via array; fabrication approval pending.])

Paste coverage = aperture count × aperture area / nominal rectangular EP bounding area.
This illustration excludes the small chamfer/radii from its area denominator; it is not a process guarantee.
Review stencil release, solder loss into vias, voiding, coplanarity and board finish with the assembler.
Mask, paste and copper are separate layers. Filled/capped vias or another approved solder-loss treatment may be needed.
EP supplements perimeter grounds. Thermal resistance, MSL, bake/reflow peaks and reliability remain TBD.
#parameters(data.specifications,"thermal",ds-table)
#parameters(data.specifications,"assembly",ds-table)
Assembly organization follows
#link("https://www.analog.com/en/resources/app-notes/smt-assembly-and-pcb-design-guidelines-for-maxims-standard-wirebonded-quad-flatpack.html")[ADI's QFN assembly guidance].
The selected supplier and assembler must release the final process.

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
