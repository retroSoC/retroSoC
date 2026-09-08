#import "../style.typ": *

== Performance and Power Characterization <performance-characterization>
This section defines reproducible measurement conditions for the documented implementation.
No new hardware measurement was performed for this publication update. The current evidence
index contains no matching reviewed performance report, so numerical product results remain
unfilled. Configuration frequencies, analytic ceilings and historical projections are not
substituted for measurements.

A published result or curve must retain its raw report, workload/transfer size, achieved
clock, memory placement and concurrent traffic, together with sample count and measurement
boundaries. Use a distinct series for each configuration and show failed or incomplete runs
in the supporting report. The evidence summary is @release-verification; the currently empty
result fields below remain unmeasured.

=== Measurement record and acceptance
Record the exact source/profile, generated core and cache configuration, firmware/compiler
options, memory placement, external device/model, clock sources and workload. Identify whether
the result comes from behavioral simulation, FPGA hardware, physical analysis or silicon.
State warmup, sample count, start/stop boundaries, uncertainty and the pass/fail conditions.

#ds-table("performance-methods",[Measurement methods and required result context],
  ([Metric],[Method and conditions],[Publication result]),
  (([CPU execution],[Cycle-counted fixed workload; report ISA, compiler, placement and cache state.],[No qualified score attached.]),
   ([Memory bandwidth],[Read/write direction, transfer size, target/device, burst and concurrent traffic.],[TBD per configuration.]),
   ([DMA throughput],[Include descriptor setup, completion and any required cache maintenance separately.],[TBD; no bus-width-times-clock claim.]),
   ([Boot time],[Separate LP entry, memory readiness, image copy, HP release and Linux readiness.],[TBD; exact checkpoints required.]),
   ([Camera / JPEG],[Frame format/size, complete frame cycles, input/output handling and memory stalls.],[No sustained system-rate claim.]),
   ([Audio],[Codec/path, sample format/rate, block size, underruns and end-to-end latency.],[No production APU codec claim.]),
   ([Power],[Per-rail method, workload, clocks, external-device contribution and thermal conditions.],[TBD; see electrical conditions.])),
  widths:(0.85fr,2.4fr,0.9fr))

=== CPU benchmark interpretation
The existing Hazard3 quick CoreMark flow places code/data in SRAM and measures machine cycles.
Its four-iteration regression run checks CRCs, placement and counter/report plumbing. It is
explicitly not a qualified public CoreMark score. The optional standard hardware profile
requires a sufficiently long calibrated run and independent review under the applicable run rules.

Keep quick regression trends separate from externally comparable scores. A result from the
benchmark profile's clock and linker configuration must not be relabeled as the default
publication profile. Retain the structured report, console log and final test verdict together.
Do not extrapolate the LP result to the HP core or infer a dual-core score by addition.

=== Memory, DMA and multimedia experiments
+ Choose one actual target and a bounded buffer range; validate the external device/mode first.
+ Define whether the experiment measures engine service time or the complete software operation,
  including cache maintenance, descriptor setup and notification.
+ Measure uncontended traffic, then a declared contention case with the intended other masters.
  Report useful payload bytes and completed work, not just issued bus beats.
+ Preserve errors, stalls, monitor snapshots and any overflow/underflow; exclude no failed
  samples silently. A timed-out job is not a throughput result.
+ For a multimedia rate, include complete input/output handling and sustained buffering.
  A core-only cycle projection does not establish full-system frames per second.

The Fabric Monitor provides counters and snapshots beside the native data plane. Its hardware
scope and sampling procedure must be recorded. Counter deltas, saturation, reset/snapshot
boundaries and clock changes affect interpretation. A read/write permission matrix describes
admission, not bandwidth or latency guarantees.

=== Boot and power experiments
Use the loader's existing checkpoint messages or a reviewed instrumentation change with defined
timing boundaries. Separate simulator elapsed time from wall-clock tool duration. The current
ready wait has no firmware-local deadline; report the external observation timeout when boot
does not complete. Avoid timing a debugger-halted run as a normal boot.

For power, identify each rail and exclude or separately report the external PHY, memory and
board regulators. Record LP/HP state, active peripherals and duty cycle. Gate-level estimates
must include the analysis assumptions; they are not silicon characterization. Thermal and
electrical conditions remain those of @electrical-specifications.
#source-note("docs/coremark.md",title:"Quick versus standard hardware CoreMark measurement")
#source-note("scripts/check_lp_hp_performance.py",title:"Existing LP/HP performance checking flow")
#source-note("docs/ip/fabric-monitor.md",title:"Counter and snapshot scope")
#source-note("docs/ip/jpeg.md",title:"JPEG functional and performance qualification boundary")

= Known Limitations and Revision Compatibility <known-limitations>
The following items describe the reviewed implementation and its publication boundary. They
are not silicon errata for an identified manufactured part. A new source revision requires
review of both the limitation and the proposed workaround; a document version alone cannot
establish compatibility.

== Implementation and Qualification Limitations
#let limitation-body(item) = {
  heading(level:3,item.title)
  if item.id=="lp-startup-psram-wait" {
    change-start("lp-startup-limitation", "Known limitations: generic LP PSRAM-ready wait", category:"added")
  }
  ds-table("limitation-"+item.id,[#item.title - impact and integration response],
    ([Field],[Description]),
    (([Impact],item.impact),([Trigger],item.trigger),([Integration response],item.workaround),([Applies to],item.applies_to)),
    widths:(0.65fr,3.35fr))
  for (i,path) in item.sources.enumerate() {
    source(path,title:if i==0 {"Implementation / contract"} else {"Additional source"})
    if i < item.sources.len()-1 {[ · ]}
  }
  if item.id=="lp-startup-psram-wait" {
    block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
      #text(size:9pt)[Startup: @lp-runtime · Application results: @firmware-application-results.]
    ]
    change-end("lp-startup-limitation")
  }
}
#for item in data.system_reference.limitations {
  if item.id=="lp-startup-psram-wait" {
    block(breakable:false)[#limitation-body(item)]
  } else {limitation-body(item)}
}

== Revision Identification and Compatibility
Before driver initialization, compare the selected profile and expected ABI with ARCHINFO,
IP identification/version and capability fields where implemented. Some blocks share a register
bank or expose compatibility windows; discover the actual interface rather than assuming every
name denotes another independent peripheral. Gen2/Gen2+ naming does not define an ABI difference.

#ds-table("revision-compatibility",[Compatibility checks before enabling a software interface],
  ([Check],[Required decision]),
  (([Hardware identity],[Bind the document, firmware and board to the reviewed source and selected profile.]),
   ([IP version / capability],[Use only advertised modes and implemented offsets; reject unsupported revisions.]),
   ([Register semantics],[Preserve access width, strobe rules, W1C behavior, reserved fields and dynamic reset meanings.]),
   ([Boot / microcode format],[Match loader and image format; do not substitute a later format because a roadmap describes it.]),
   ([Mode and pad ownership],[Distinguish fixed PRODUCT interfaces from MPW selection and inactive shared-memory routes.]),
   ([Software and evidence],[Match SDK/driver/kernel bindings and validation scope to the hardware actually used.])),
  widths:(1fr,3fr))
On a mismatch, keep the resource inactive and report identity/capability values. Do not try
legacy writes until they happen to succeed. Preserve earlier ABI documentation for users of
that snapshot, and record changed offsets, field meanings or reset behavior in a future release
before claiming backward compatibility. This publication adds no hardware or software ABI.
#source-note("publications/datasheets/system-reference.json",title:"Versioned limitation and evidence index")
#source-note("publications/datasheets/register-profiles.json",title:"Published register extraction boundary")
