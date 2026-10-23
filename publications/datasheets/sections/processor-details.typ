#import "../style.typ": *
#change-start("v05-emphasis-processor-details","Selected body emphasis: processor details")
#let cpu = data.system_reference.product_details.cpu

=== Processor Configuration and Software-visible Capabilities <processor-details>
The table separates the actual LP instance arguments, the fixed HP OpenC906 integration and
the selected firmware build. It is a *configuration summary*, not a replacement for the CPU
ISA/CSR manuals. A software compiler option does not remove a hardware extension or CSR block.

#ds-table("processor-config",[Processor settings and the reference software configuration],
  ([Property],[LP: instantiated Hazard3],[HP: locked OpenC906 default configuration]),
  (([Hart / role],[Hart 0; root management.],[Hart #cpu.hp.hartId; application/Linux platform.]),
   ([Execution width],[RV32 integration.],[RV64 (#code(cpu.hp_isa_base) base); the core drives 40-bit addresses over a 32-bit physical fabric.]),
   ([Configured extensions],cpu.lp_extensions.join(", "),[#cpu.hp_isa.join(", ") (the RV64GC set).]),
   ([Privilege],[Machine-mode configuration, U_MODE = #cpu.lp.U_MODE.],[M/S/U per the C906 default configuration; the supplied software platform declares #cpu.hp_mmu.]),
   ([Protection],[PMP_REGIONS = #cpu.lp.PMP_REGIONS.],[PMP per the T-Head C906 manuals; entry geometry is not separately extracted in this publication.]),
   ([Reset entry],code(data.reset_address),code(cpu.hp.resetVector)),
   ([Trap / counter configuration],[MTVEC_INIT: #code(cpu.lp.MTVEC_INIT) \ Machine CSR: #cpu.lp.CSR_M_MANDATORY / counters: #cpu.lp.CSR_COUNTER.],[No memory-mapped mtime; HP software reads the time CSR.]),
   ([Debug],[DEBUG_SUPPORT = #cpu.lp.DEBUG_SUPPORT \ Breakpoint triggers: #cpu.lp.BREAKPOINT_TRIGGERS.],[JTAG debug through the core-internal Debug Module and the external DTM; the debug system-bus master is unconnected.]),
   ([Bus interfaces],[Use the selected Hazard3 instance and upstream core contract.],[One #(cpu.hp.coreAxiDataWidth)-bit AXI4 master, downsized to the #(cpu.hp.fabricAxiDataWidth)-bit HP fabric; internal CLINT/PLIC window at #code(cpu.hp.sysWindowBase).])),
  widths:(0.8fr,1.6fr,1.75fr))

The reference LP build uses #code(cpu.build.ISA) with #code("HAVE_CSR="+cpu.build.HAVE_CSR).
Those build choices are separate from the instantiated LP extension and mandatory CSR settings.
The HP core is the dependency-locked OpenC906 pre-generated RTL in its default configuration;
there is no Mini-side generator selection. OpenSBI, the device tree and the kernel
configuration *must remain consistent with the core that is actually integrated and used*.

==== Cache geometry and evidence basis
#ds-table("processor-cache-evidence",[Cache and vendored-core evidence boundaries],
  ([Item],[Recorded configuration],[Qualification]),
  (([HP instruction cache],[32 KiB in the default OpenC906 configuration.],[Vendored default configuration; see the qualification note below.]),
   ([HP data cache],[32 KiB in the default OpenC906 configuration; 64-byte lines.],[Vendored default configuration; see the qualification note below.]),
   ([Cache total capacity],cpu.hp_cache_capacity,[Do not relabel a configured feature as a tested or silicon capability.]),
   ([Cache maintenance],[T-Head extended operations (XTheadCmo custom-0 dcache clean/invalidate by address) on 64-byte lines; no Zicbom CBO block.],[Used by the supplied HP smoke image; the extended instruction set must be enabled in the machine status CSR first.]),
   ([Locked HP source],[#code(cpu.hp_revision.slice(0,12))],[The full dependency revision is recorded in the lock and publication manifest.]),
   ([Vendored HP RTL],cpu.generated_artifact_basis,[The Mini mhartid = #cpu.hp.hartId assignment comes from the reviewed override file, not from editing the vendored checkout.])),
  widths:(0.8fr,1.7fr,1.65fr))
The vendored OpenC906 checkout is a locked, managed input; the C906 user and integration
manuals ship with it and remain the register/CSR reference. This publication lists only
integration-visible settings and does not re-derive upstream implementation parameters.

==== System window and address decode
The HP core decodes its internal CLINT/PLIC window at #code(cpu.hp.sysWindowBase) inside the
core BIU; the matching 128 MiB SoC range is reserved and never reaches the external fabric.
The reset vector #code(cpu.hp.resetVector) and the 32-bit physical fabric are unchanged by the
core swap. Per-hart identity is fixed at integration time: the LP Hazard3 reports mhartid 0
and the HP OpenC906 reports mhartid 1 through the reviewed override.

Before deploying a new HP image, retain the lock revision, vendored source identity, override
file and software build identity together. Check the core/device-tree feature agreement and
the existing non-coherent buffer protocol. LP and HP configuration differences do not turn the
two harts into a symmetric cache-coherent SMP platform.
#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #source("rtl/ip/core/mgmt_core_wrapper.sv",title:"LP instance") ·
  #source("rtl/mini/top/hp_core_wrapper.sv",title:"HP OpenC906 integration") ·
  #source("scripts/generate_openc906.py",title:"Vendored filelist and hart-ID override") ·
  #source("app/ports/linux/linux/retrosoc_hp.dts",title:"HP platform properties")
]

#change-end("v05-emphasis-processor-details")
