#import "../style.typ": *
#import "../system-figures.typ": sequence-diagram
#import "../diagram-packages.typ": storage-figures
#let sw = data.system_reference.software

=== LP ordinary startup <lp-runtime>
The firmware's startup implementation is selected before its application entry point. The
generic CRT is used unless the application's manifest supplies an explicit CRT replacement.
Selecting another linker layout changes placement; it does not by itself replace the startup
instructions. The reference bringup build therefore has a different initialization contract
from the dedicated debug and flash-loader images.

#figure(sequence-diagram((
  [*Reset entry* \ Generic CRT selected \ Optional CSR trap setup],
  [*Prepare LP state* \ Initialize registers/stack \ Configure PSRAM pads],
  [*Request PSRAM init* \ Poll READY \ No local deadline],
  [*Relocate initialized content* \ Copy code/data if LMA differs \ Clear BSS],
  [*Optional premain* \ Initialize handler tables \ Enable counters],
  [*Application entry* \ Call main \ Loop if main returns],
)),caption:[Generic LP CRT sequence. Steps describe source order, not guaranteed boot duration.])<lp-runtime-flow>

With CSR support selected, the generic entry disables global and individual interrupt enables
and installs a direct-mode trap vector before the later register/stack initialization. It then
configures the PSRAM alternate-function group, requests initialization and waits for READY.
The loop contains no software timeout. If it does not finish, neither main nor that application's
TEST_STATUS writer has run; an external simulator or debugger may still observe a timeout.

This PSRAM initialization precedes the LMA/VMA comparisons. An in-place image or an SRAM linker
layout does not skip it when using this generic CRT. Check the actual startup selection before
assuming that an SRAM-resident image is independent of external-memory initialization. See
@known-limitations and @connection-constraints for the associated readiness and pad constraints.

#ds-table("runtime-startup-selection",[Committed startup selections and software interrupt inclusion],
  ([Profile / application],[Linker layout],[CRT entry],[CSR / IRQ runtime]),
  sw.profiles.map(p=>([#code(p.profile) \ APP = #code(p.app)],code(p.link_type),
    code(p.startup),[#code("HAVE_CSR="+p.have_csr) \ #p.irq_runtime])),
  widths:(1.25fr,0.8fr,1.25fr,1.15fr))

The debug replacement sets the stack and calls main, without the generic PSRAM initialization,
relocation or BSS loop. The XPI flash-loader replacement sets the stack, clears BSS and calls
main; if main returns it executes EBREAK and loops. Those compact entries are tied to their
application/linker assumptions and do not establish a universal alternative startup sequence.
#source-note("rtl/mini/mk/software.mk",title:"Generic CRT, conditional IRQ objects and application CRT replacement")
#source-note("crt/arch/riscv/startup.S",title:"Actual generic LP entry and PSRAM-ready loop")
#source-note("app/apps/debug/startup.S",title:"Dedicated debug entry")
#source-note("app/apps/xpi_flash_loader/startup.S",title:"Dedicated SRAM flash-loader entry")

=== Linker layout and runtime initialization
LMA identifies the stored load image; VMA identifies where the linked content executes or is
accessed. The generic entry compares the two addresses and copies only when they differ. The
selected linker script and generated memory regions supply these symbols; their names do not
prove that a physical memory device is fitted or ready.

#ds-table("runtime-linker-symbols",[Generic CRT initialization boundaries],
  ([Symbols / stage],[Implemented action],[Integration requirement]),
  ((code("_stack_point"),[Load the initial stack pointer before entering C.],[Use the selected linker region and a suitable stack budget.]),
   (code("_ram_lma / _ram_vma / _etext"),[Copy initialized code/read-only content in words when LMA and VMA differ.],[Keep load image and linked execution placement consistent.]),
   (code("_psram_lma / _psram_vma / _edata"),[Copy initialized data when its load/run locations differ.],[The historical symbol prefix does not replace inspection of the selected linker script.]),
   (code("_sbss / _ebss"),[Zero the BSS word range.],[BSS zeroing is software initialization, not an SRAM hardware reset guarantee.]),
   (code("_premain_init"),[When CSR_ENABLE is compiled, initialize trap-handler tables and enable counters.],[This does not globally enable interrupts.]),
   (code("main"),[Enter the selected application; spin if it returns.],[A C return value is not automatically written to TEST_STATUS.])),
  widths:(1.1fr,1.6fr,1.75fr))

The ld2_psram reference places ordinary code/data and its stack in the PSRAM layout. Other
committed profiles select SRAM-oriented scripts for their own purposes. Keep the actual ELF/map,
generated memory bounds and startup source together when diagnosing an early boot failure.
The heap boundary symbol is an accounting marker; it does not introduce a hosted allocator.
Buffer and stack accounting remain defined in @software-memory-budget.
#source-note("crt/linker/ld2_psram.lds",title:"Reference load/run placement and stack boundary")
#source-note("crt/linker/ld2_all_sram.lds",title:"HP loader's selected SRAM linker layout")

#storage-figures("software-runtime",section:"software")

=== Exception entry and interrupt software support <irq-runtime>
The main publication profile selects HAVE_CSR=NO. Other committed profiles, including the HP
loader, select YES. The build then defines CSR_ENABLE and includes the generic trap assembly,
handler table implementation and IRQ helper. An application's explicit CRT replacement still
controls the final startup/object selection. These software choices are separate from the LP
processor's implemented machine CSRs in @processor-details.

The generic trap assembly saves ABI caller registers and MEPC/MCAUSE/MSTATUS, passes mcause
and the saved stack pointer to the C dispatcher, restores the saved context and returns with
MRET. The non-RV32E assembly frame reserves 20 register words; it is not the total interrupt
stack budget, which also includes C handlers and their callees. No automatic nesting policy,
full exception emulation or per-peripheral interrupt dispatch is provided by that frame.

#ds-table("runtime-irq-support",[Generic LP IRQ API and dispatcher boundaries],
  ([Operation],[Current software behavior],[Required interpretation]),
  ((code("rs_irq_register_exception"),[Accept non-null handlers with an index below #sw.irq.counts.RS_EXCEPTION_COUNT.],[Registers a handler; does not validate or emulate every possible processor exception.]),
   (code("rs_irq_register_core"),[Store a non-null handler below #sw.irq.counts.RS_CORE_IRQ_COUNT.],[Handler-table storage is separate from interrupt-enable state.]),
   (code("rs_irq_enable_core"),[Register the handler, then enable only machine software or timer interrupts; otherwise return RS_ENOTSUP.],[An unsupported valid ID can already have updated the table; it is not a transactional rollback.]),
   (code("rs_irq_register_external"),[Invalid input returns RS_EINVAL; otherwise return RS_ENOTSUP.],[No LP PLIC claim/complete implementation is supplied by this API. HP PLIC hardware remains a separate platform.]),
   ([Global enable],[The caller controls the global interrupt-enable bit separately.],[Complete handler and source setup before enabling delivery.]),
   ([Default exception],[Print diagnostic mcause and stack pointer, then loop.],[No automatic TEST_STATUS failure or instruction recovery is generated.]),
   ([Default / external interrupt],[Print a diagnostic and return. Machine external interrupts use this path.],[No generic peripheral acknowledgement is performed; an asserted source can retrigger.])),
  widths:(1.05fr,1.7fr,1.7fr))

The supplied IRQ example registers machine timer/software handlers, enables global delivery,
updates the compare value in the timer handler and clears the software-pending source in its
handler. Its bounded foreground waits are example-specific. LP vector bits, CPU cause numbers,
handler-table indexes and HP PLIC source IDs are distinct namespaces. See @dma-routing for
hardware routes and @fault-code-reference for interpreting captured results.
#source-note("crt/arch/riscv/system_irq.S",title:"Saved context and direct trap entry")
#source-note("crt/src/core/system_irq_handler.c",title:"Registration, supported enables and default dispatch behavior")
#source-note("crt/src/core/irq.c",title:"Machine timer/software IRQ example")
#include "api-semantics.typ"
