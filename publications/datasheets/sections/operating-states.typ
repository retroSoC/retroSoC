#import "../style.typ": *
#import "../system-figures.typ": sequence-diagram

=== System Operating States and Reset Effects <operating-states>
The states below describe the digital control contract. They are not voltage states or
qualified Sleep/Stop/Standby modes. In particular, stopping the HP leaf clock leaves the
fabric and stable memory clock available for management recovery and other masters.

#ds-table("operating-states",[System operating states and transition responsibilities],
  ([State],[Available activity],[Required transition condition]),
  (([LP management; HP held],[LP root control, memory initialization and diagnostics.],[Prepare HP memory and software before release.]),
   ([LP + HP running],[Asymmetric firmware/Linux operation with explicit resource ownership.],[Stop new work before transferring resources or shutting down HP.]),
   ([Clock transition],[AON sequences quiesce, drain, safe source and qualification.],[Run the software transition from safe memory; obey timeout and capability.]),
   ([HP cache / drain phase],[HP receives a cache-clean window before admission is blocked.],[Complete shared-range maintenance and acknowledge before drain.]),
   ([HP stopped / reset],[LP retains recovery authority; fabric and memory remain separately controlled.],[Check actual hardware status before selecting debug or reinitializing HP.]),
   ([Fault recovery],[Sticky status identifies clock, access, drain or target errors.],[Capture evidence, stop affected producers and follow the relevant reset/isolation contract.])),
  widths:(0.9fr,1.55fr,1.65fr))

==== Controlled clock changes
+ Inspect the current clock status and capability. The publication reference profile keeps
  the PLL disabled; the generic eight-selector model does not establish eight silicon speed grades.
+ Place the transition routine and required state in a safe memory region. Disable affected
  interrupts and quiesce frequency-sensitive transfers, DMA and external serial transactions.
+ Use #code("rs_clock_set_frequency()") with a bounded timeout. Let the hardware controller
  perform its safe-source and lock qualification sequence; do not write raw PLL fields in parallel.
+ Read the result and sticky fault state. On success, update peripheral divisors that depend on
  changed clocks before restoring traffic and interrupts.
+ On #code("RS_ENOTSUP"), retain the supported safe configuration. On timeout or lock loss,
  inspect the selected safe source and recover the workload without assuming the requested rate.

The memory functional root is independent of HP frequency changes. This protects ongoing
memory timing, but it does not make peripheral divider settings or external interface limits
independent of their own clocks. External audio, pixel, ULPI and JTAG domains retain their
separate clock and reset contracts.

==== Reset scope and retained state
#ds-table("reset-effects",[Reset operations and their documented scope],
  ([Operation],[Affected scope],[Retention / software consequence]),
  (([System/root reset],[Selected technology and SoC reset tree.],[Re-read reset/capability state; no general RAM-retention guarantee is published.]),
   ([Management debug reset],[Hazard3 hart and management bridge after the bridge becomes idle.],[DTM/DM, RCU and peripherals remain live; firmware must account for their existing state.]),
   ([Controlled HP stop/reset],[Cache request, drain, coordinated bridge flush and HP reset.],[Root authority remains with LP. Inspect actual release/drain/fault status.]),
   ([Forced HP reset],[Bounded shutdown proceeds after missing acknowledgement or stalled drain.],[Dirty cached data and interrupted work are not guaranteed to survive.]),
   ([Resource lifecycle reset request],[Admission and IRQ control for the selected managed resource.],[Not wired to every peripheral engine's internal reset; use its own recovery contract.]),
   ([IP-local reset/recovery],[Only the state described by the individual IP.],[Clear or preserve status exactly as specified; do not assume a system-wide effect.])),
  widths:(1fr,1.5fr,1.65fr))

==== HP stop, recovery and restart
#figure(sequence-diagram((
  [*Stop application work* \ Account for buffers],
  [*Cache-clean window* \ HP maintenance \ LP acknowledges],
  [*Drain and flush* \ Block new addresses \ Retire accepted work],
  [*Confirm stopped* \ Actual release / reset \ Record forced fault],
  [*Reinitialize* \ Restore owned state \ Validate image],
  [*Release and observe* \ Check actual status \ Expected readiness])),caption:[Controlled HP lifecycle and the software checkpoints around reset.])
Distinguish a requested release bit from actual core release. The SYSCTRL HAL exposes
#code("released"), #code("actual_released"), #code("draining") and #code("forced_fault");
a setter's immediate return is not a substitute for supervising the complete asynchronous
lifecycle. Use a bounded status-polling policy in the integration layer and preserve the
fault state before clearing it. That policy is guidance, not a newly added firmware service.

After a forced event, rebuild descriptors and shared-buffer ownership before restart. A warm
restart must not accept stale responses from an old bridge epoch or reuse a queue whose owner
is unknown. The root memory-pad selection/lock has its own retention rules and must be checked
before accessing a serial-memory aperture.
#source-note("docs/pll-clock-control.md",title:"Clock transition sequence and safe-source behavior")
#source-note("docs/lp-hp-architecture.md",title:"AON lifecycle, warm flush and memory-pad retention")
#source-note("docs/hazard3-debug.md",title:"Management debug-reset scope")
#source-note("crt/src/hal/sysctrl.c",title:"Requested and actual HP status exposed by the HAL")
