#import "../style.typ": *

=== Reset-State Summary and Initialization Dependencies <reset-summary>
Distinguish an asserted reset, a reset assignment's initial value and a later software
observation. A counter, event flag or external input can change immediately after local reset
release. A physical supply ramp is also different from a digital reset transition; board
sequencing remains subject to @electrical-specifications.

#ds-table("reset-state-summary",[Initial digital state and observation class],
  ([Block / state],[Class],[Reset or initial observation]),
  data.system_reference.product_details.reset.map(r=>(r.label,r.value_class,r.initial)),
  widths:(0.9fr,0.65fr,2.6fr))

"Fixed" identifies the traced digital reset assignment, not a guarantee that firmware will
read that value after arbitrary elapsed time. "Configured" depends on selected integration
settings. "Input-dependent" requires the external or technology context, and "Dynamic" must
be observed using the IP's live/snapshot rules.

The Resource Controller owner flops reset to LP, while its quiesce and resource-reset request
bits reset clear. Its IRQ outputs combine raw causes with the owner and resource-reset request.
Asserting #code("CONTROL.RESET") masks those owner routes; resetting the controller is not a
separate universal IRQ-enable policy. Check each producer's local reset, cause and enable state.

#ds-table("initialization-dependencies",[First-access prerequisites and safe initialization observations],
  ([Block / state],[Before first use],[Action / observation]),
  data.system_reference.product_details.reset.map(r=>(r.label,r.prerequisites,[#r.action \ #r.observation])),
  widths:(0.85fr,1.15fr,2.15fr))

==== Initialization order
+ Establish the board's approved power, reference clock and external-reset conditions.
+ Wait for the local clock/reset path needed by management MMIO. Confirm identity and clock
  capability before programming frequency-dependent peripherals.
+ Establish pad ownership and memory mode, then initialize/probe the external memory needed by
  the selected linker/image placement. Controller reset alone is not device readiness.
+ Initialize software sections, buffers and descriptors. Prepare handlers and clear only the
  documented stale causes before enabling interrupts or bus mastering.
+ Configure legal idle DMA/peripheral state and verify bounded operations before releasing HP
  or starting a sustained producer.

An initialization dependency is not a fixed delay specification. Prefer documented ready,
idle, lock and error observations with bounded software waits. Keep the existing HP-loader
ready-wait limitation separate: that loader currently has no firmware-local final Linux-ready
deadline, even though other controller waits are bounded.

==== Restart and failure handling
After a debug or local reset, do not assume unrelated peripherals and clocks returned to their
root-reset state. Re-probe actual ownership, pending causes and active transfers before reuse.
After a failed clock or memory initialization, retain diagnostics and stop dependent consumers;
do not infer readiness from a writable register or an allocated address window.

GPIO's initial digital output-enable state does not specify an input voltage, pull strength
or package connection. Likewise, no general SRAM/DRAM zero-content or retention guarantee
follows from controller reset. Use the selected software loader/linker initialization and
approved physical implementation for those properties.
#source-note("rtl/mini/top/hp_lifecycle_controller.sv",title:"Held HP state and release/fault reset assignments")
#source-note("rtl/mini/top/resource_controller.sv",title:"Owner/reset initial state and IRQ equations")
#source-note("rtl/mini/top/clock_config_controller.sv",title:"Clock and pad-mode reset settings")
#source-note("rtl/ip/peripheral/dma_reg.sv",title:"DMA context and interrupt-enable reset assignments")
#source-note("rtl/ip/peripheral/gpio_reg.sv",title:"GPIO control reset-flop connections")

