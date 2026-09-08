#import "../style.typ": *
#let cpu = data.system_reference.product_details.cpu

=== Processor Configuration and Software-visible Capabilities <processor-details>
The table separates the actual LP instance arguments, the explicit HP generator settings and
the selected firmware build. It is a configuration summary, not a replacement for the CPU
ISA/CSR manuals. A software compiler option does not remove a hardware extension or CSR block.

#ds-table("processor-config",[Processor settings and the reference software configuration],
  ([Property],[LP: instantiated Hazard3],[HP: explicit VexiiRiscv generator configuration]),
  (([Hart / role],[Hart 0; root management.],[Hart 1; application/Linux platform.]),
   ([Execution width],[RV32 integration.],[XLEN #cpu.hp.xlen / physical address width #cpu.hp.physicalWidth.]),
   ([Configured extensions],cpu.lp_extensions.join(", "),cpu.hp_isa.filter(x=>not(x in ("s","u"))).join(", ")),
   ([Privilege],[Machine-mode configuration, U_MODE = #cpu.lp.U_MODE.],[S and U selected by the generator, in addition to machine-mode operation.]),
   ([MMU / software platform],[No LP MMU is advertised by this integration.],[Supplied software platform declares Sv32; verify agreement with the generated core before deployment.]),
   ([Protection],[PMP_REGIONS = #cpu.lp.PMP_REGIONS.],[PMP entries = #cpu.hp.at("pmpParam.pmpSize") / granularity = #cpu.hp.at("pmpParam.granularity") bytes.]),
   ([Reset entry],code(data.reset_address),code(cpu.hp.resetVector.trim("L",at:end))),
   ([Trap / counter configuration],[MTVEC_INIT: #code(cpu.lp.MTVEC_INIT) \ Machine CSR: #cpu.lp.CSR_M_MANDATORY / counters: #cpu.lp.CSR_COUNTER.],[ASID width #cpu.hp.asidWidth and #cpu.hp.additionalPerformanceCounters additional performance counters. \ Time-read option: #cpu.hp.at("privParam.withRdTime").]),
   ([Debug],[DEBUG_SUPPORT = #cpu.lp.DEBUG_SUPPORT \ Breakpoint triggers: #cpu.lp.BREAKPOINT_TRIGGERS.],[Embedded JTAG/debug configured; triggers #cpu.hp.at("privParam.debugTriggers").]),
   ([Issue configuration],[Use the selected Hazard3 instance and upstream core contract.],[#cpu.hp.decoders decoders and #cpu.hp.lanes lanes configured.])),
  widths:(0.8fr,1.6fr,1.75fr))

The reference LP build uses #code(cpu.build.ISA) with #code("HAVE_CSR="+cpu.build.HAVE_CSR).
Those build choices are separate from the instantiated LP extension and mandatory CSR settings.
The HP profile selects #code(cpu.build.HP_CONFIG). OpenSBI, the device tree and the kernel
configuration must remain consistent with the core that is actually generated and used.

==== Cache geometry and evidence basis
#ds-table("processor-cache-evidence",[Cache and generated-core evidence boundaries],
  ([Item],[Recorded configuration],[Qualification]),
  (([HP instruction cache],[Enable setting #cpu.hp.fetchL1Enable with #cpu.hp.fetchL1Sets sets and #cpu.hp.fetchL1Ways ways; minimum memory data width #cpu.hp.fetchMemDataWidthMin bits.],[Explicit generator settings.]),
   ([HP data cache],[Enable setting #cpu.hp.lsuL1Enable with #cpu.hp.lsuL1Sets sets and #cpu.hp.lsuL1Ways ways; minimum memory data width #cpu.hp.lsuMemDataWidthMin bits.],[Explicit generator settings.]),
   ([Cache total capacity],cpu.hp_cache_capacity,[Sets multiplied by ways is not a byte capacity without the reviewed block size.]),
   ([Cache maintenance],[Zicbom selected; supplied platform metadata declares a 64-byte CBO block.],[Keep platform metadata and the eventual generated implementation consistent.]),
   ([Locked HP source],[#code(cpu.hp_revision.slice(0,12))],[The full dependency revision is recorded in the lock and publication manifest.]),
   ([Generated HP artifact],cpu.generated_artifact_basis,[No new HP RTL generation or independent generated-manifest validation was performed for this publication.])),
  widths:(0.8fr,1.7fr,1.65fr))
The current publication workspace does not supply the locked VexiiRiscv checkout and a matching
generated-core manifest for independent inspection. Only explicit repository generator settings
are listed as such. Upstream defaults, plugin expansion and derived byte capacities remain
unconfirmed until that artifact/source evidence is attached. Do not relabel a configured feature
as a tested generated-core or silicon capability.

==== PMA coverage versus implemented memory
#ds-table("hp-pma-coverage",[Explicit PMA envelopes in the HP generator],
  ([Base],[Inclusive end],[Bytes],[Main memory],[Executable]),
  cpu.pma.map(r=>(code(r.base),code(r.end),str(r.bytes),r.main,r.executable)),
  widths:(1.1fr,1.1fr,0.8fr,0.65fr,0.65fr))
A PMA envelope describes core-side attributes. It does not instantiate RAM or override the
SoC decoder, per-master ACL, resource owner or physical device. In particular, the generator's
SRAM attribute envelope is larger than the reference profile's 32 KiB physical SRAM region.
Use the generated address map and selected profile for capacity and valid access bounds.

Before deploying a new HP image, retain the lock revision, generator source, generated RTL/hash
manifest and software build identity together. Check the core/device-tree feature agreement and
the existing non-coherent buffer protocol. LP and HP configuration differences do not turn the
two harts into a symmetric cache-coherent SMP platform.
#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #source("rtl/mini/top/mgmt_core_wrapper.sv",title:"LP instance") ·
  #source("scripts/vexiiriscv/GenerateRetroSocHp.scala",title:"HP configuration/PMA") ·
  #source("scripts/generate_vexiiriscv.py",title:"Artifact manifest") ·
  #source("app/ports/linux/linux/retrosoc_hp.dts",title:"HP platform properties")
]
