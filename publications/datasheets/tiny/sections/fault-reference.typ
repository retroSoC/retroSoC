#import "../style.typ": *
#import "../diagrams.typ": flow

= Appendix: Fault and Status Code Reference <tiny-fault-reference>
== Diagnostic Code Namespaces
SDK return values, SPI fault codes, DMA packed status, AXI responses, RCU fault masks and firmware terminal
codes are separate namespaces. Preserve the owner, source and register name with each numeric observation.
#ds-table("sdk-status",[SDK operation return values],([Value],[Symbol],[Meaning]),
 data.diagnostics.sdk.map(r=>(str(r.value),code(r.name),r.meaning)),widths:(0.45fr,1.1fr,2.4fr))
#source-note("crt/include/retrosoc/core/status.h",title:"SDK status enum")
#ds-table("spi-fault-codes",[SPI session fault codes],([Value],[Symbol]),
 data.diagnostics.spi.map(r=>(str(r.value),code(r.name))),widths:(0.6fr,3.4fr))
#source-note("crt/include/retrosoc/hal/spi_regs.h",title:"SPI fault code ABI")
AXI response 2 is SLVERR and response 3 is DECERR. SYSCTRL FAULT_DETAIL retains the raw response encoding;
FAULT_MASTER identifies CPU slow path 0, central DMA 1 or SDIO private DMA 2. These values are not rs_status_t.

== Status Registers and Capture Points
Capture status and progress before clearing sticky fields. A clear operation acknowledges state; it does not
repair a source clock, drain an outstanding transaction or release buffer ownership.
#for row in data.diagnostics.registers {
 block(breakable:false)[
  #minor-title(row.owner+" / "+row.name)
  #par([#link(label("reg-"+row.family+"-"+row.key))[Canonical register reference]. #row.description])
  #ds-table("fault-fields-"+row.family+"-"+row.key,[#row.owner #row.name capture fields],([Bits],[Field],[Interpretation]),
   row.fields.filter(f=>f.name!="Reserved").map(f=>(str(f.msb)+if f.msb!=f.lsb {":" + str(f.lsb)} else {""},code(f.name),f.description)),widths:(0.5fr,1.2fr,2.3fr))
 ]
}

== Firmware Application Results
The selected application and flags define result-code meaning; the same byte value can belong to different
acceptance sequences. Keep that selection with the result, and consult @tiny-diagnostics for workload scope.
An application function's C return value is not automatically the sticky terminal test result.
#source-note("app/apps/ci_smoke/tiny.c",title:"Tiny acceptance sequence and result publication")

== Automated Completion and Simulator Verdicts
The first valid full-word TEST_STATUS write is sticky until reset. Bit 31 marks valid, bit 0 marks pass,
and bits 15:8 carry the application result code. A later pass cannot overwrite an earlier valid failure.
A simulator pass requires successful process exit, the configured success marker and no FAILED, FATAL,
assertion failed, %Error, SIM_TEST_FAIL or SIM_TEST_TIMEOUT marker. UART startup text is diagnostic only.
#source-note("AGENTS.md",title:"Repository verdict contract")
