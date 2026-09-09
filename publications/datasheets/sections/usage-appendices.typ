#import "../style.typ": *
#import "../diagram-packages.typ": storage-figures

= Appendix: Software Memory and Buffer Requirements <software-memory-budget>
Memory-map capacity, image allocation, linked image size and peak runtime use are different
quantities. This appendix supplies source-based layouts and illustrative budgets. No matching
ELF/MAP files or measured stack/runtime high-water report were available for this update;
actual firmware occupation remains unprovided.

== Linker Layout and Runtime Accounting
#ds-table("software-memory-accounting",[Memory quantities and the evidence needed to publish them],
  ([Quantity],[How to obtain it],[Current boundary]),
  (([Physical / mapped capacity],[Selected profile and fitted memory/controller geometry.],[The reference SRAM and address map are configuration data, not an application's usage.]),
   ([Flash load image],[ELF/MAP LMA, initialized sections and the final packaged image.],[Actual built size not supplied. Do not count NOLOAD BSS as stored bytes.]),
   ([Runtime static memory],[VMA for code/rodata/data/BSS in the chosen linker layout.],[Actual section sizes not supplied. Placement differs between SRAM, SDRAM and PSRAM layouts.]),
   ([Stack / working space],[Linker constraints plus reviewed worst-case or measured runtime demand.],[A stack-top symbol does not reserve or measure a safe stack budget.]),
   ([Boot artifacts],[Loader header allocation bounds and actual package entries.],[Maximum allocations are already listed in the boot chapter; actual image lengths must come from the bundle.]),
   ([DMA and media buffers],[Packing, alignment, lifetime, descriptor count and buffer multiplicity.],[The examples below are calculations, not measured allocations.])),
  widths:(1fr,1.7fr,1.5fr))

The all-SRAM script places the main code/rodata/data/BSS in SRAM with initialized content
loaded from flash. Its #code("_stack_point") is at the SRAM-region end, and #code("_heap_start")
is a location symbol after static sections. These symbols do not prove an independently bounded
heap or stack reservation. The freestanding SDK's lack of dynamic allocation does not eliminate
stack, library scratch or application-buffer requirements.

The SDRAM and PSRAM linker variants place application material in their named external memory
regions; inspect the actual script and generated memory regions rather than relying on a
stale comment or filename. Retain both VMA and LMA in a size report. Compare the sum of static
sections, reserved buffers and required stack/scratch margin with the available region before boot.

#change-start("memory-linker-links","Memory accounting links to profile-specific load/run diagrams",category:"cross-reference")
Profile-specific placement diagrams:
#("ld2_psram","ld2_all_sram","ld2_sram","jtag_sram").map(name=>
  link(label("storage-linker-"+name),code(name))).join([; ]).
Each diagram preserves its actual linker regions and selected startup boundary.
#change-end("memory-linker-links")

== Worked Buffer Budgets
The examples use 64-byte allocation alignment for shared HP cache-block ownership. This does
not replace the peripheral's minimum alignment. Each independent buffer receives its own aligned
stride so a maintenance operation does not include another owner's boundary bytes.

#storage-figures("software-memory-budget",section:"software")

#ds-table("buffer-budget-examples",[Payload, stored representation and aligned allocation],
  ([Scenario],[Payload / buffer],[Stored / buffer],[Aligned stride],[Total allocation]),
  data.system_reference.programming.budgets.map(r=>(r.name,str(r.payload_bytes),str(r.storage_bytes),str(r.stride_bytes),str(r.total_bytes))),
  widths:(1.65fr,0.65fr,0.65fr,0.65fr,0.75fr),notes:[All numeric entries are bytes. Total includes the stated buffer count.])

=== DVP RGB565 frame storage
An even-width RGB565 row has two bytes of effective payload per pixel. The current DVP core
collects two 16-bit pixels into a 32-bit stream word. For storage planning, use
#code("row_bytes = ceil(width / 2) * 4") and #code("frame_bytes = row_bytes * height").
The higher FIFO-side framing metadata is not appended to memory by the central DMA.

The VGA example therefore uses 614400 bytes per buffer and 1228800 bytes for two buffers.
This cannot fit in the 32 KiB reference SRAM. Two buffers are an application budgeting example;
the current DVP convenience interface is a single-frame operation, not automatic hardware ping-pong.

The 641-pixel example illustrates partial final words and storage rounding. It is not a
supported central-DMA capture configuration: odd-pixel lines assert partial TKEEP, while the
DMA receiver requires full words. Use the documented PIO path or a separately implemented
extension, and allocate explicit software frame metadata where the application needs it.

=== I2S audio blocks
For stereo, #code("sample_count = Fs * duration_ms / 1000 * 2"). Require a whole sample-frame
count. In 16-bit mode two samples occupy one 32-bit word; in 24-bit mode one sample occupies
one 32-bit word although only 24 bits are payload. A 48 kHz, 10 ms block therefore stores
1920 bytes in 16-bit mode and 3840 bytes in 24-bit mode. Double buffering requires 3840 and
7680 bytes respectively with the stated alignment.

Include application metadata, queue state and scheduling margin separately. The buffer
duration is not an end-to-end latency guarantee and does not establish tolerance to arbitrary
memory stalls. I2S RX has no TLAST; the programmed transfer length and software lifetime remain binding.

=== Descriptor arrays and overflow checks
Each central DMA TCD occupies 64 bytes and must satisfy its alignment. Eight descriptors
occupy 512 bytes. This describes a finite descriptor array; it does not imply supported cyclic
or 2D operation. Account for payload buffers separately from descriptor storage.

Validate nonzero dimensions, sample count and buffer count before multiplication. Check the
range before alignment rounding and before multiplying the aligned stride by the number of
buffers. The publication calculator rejects allocations outside a 32-bit byte range, invalid
alignment and incomplete audio frames; the application must apply equivalent bounds for its ABI.
#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #source("crt/linker/ld2_all_sram.lds",title:"SRAM layout") ·
  #source("crt/linker/ld2_sdram.lds",title:"SDRAM layout") ·
  #source("crt/linker/ld2_psram.lds",title:"PSRAM layout") ·
  #source("rtl/ip/multimedia/dvp_core.sv",title:"DVP packing") ·
  #source("crt/src/hal/i2s_math.c",title:"I2S packing")
]

= Appendix: Terminology, Notation and Document Map <document-map>
== Terminology and Units
#ds-table("system-glossary",[System terminology used in this publication],
  ([Term],[Meaning and boundary]),
  data.system_reference.programming.glossary.map(r=>(r.term,r.meaning)),widths:(0.85fr,3.3fr))

== Reading Numbers and Status
Register offsets are in bytes; bit ranges name inclusive bit indices. Address-map ranges use
the stated inclusive end address. Numeric suffixes in signal names denote signal indices,
not package pin numbers. `_i`, `_o` and `_n` retain their declared direction/polarity meaning.
An RTL `inout` pad wrapper may contain a functionally input-only route.

LP interrupt vector bits, HP PLIC source IDs, DMA request values, software channel contexts
and native master slots are separate namespaces. A matching integer does not connect them.
Clock configuration, nominal calculated rate, model timing and characterized pin timing are
also distinct. Interpret every Min/Typ/Max entry with its stated evidence and conditions.

"Integrated" and "Partial" describe implementation scope. "Source reviewed", "Tests available"
and a matching "Reported pass" describe evidence. None silently implies board or silicon
qualification. Reserved, unsupported and TBD are different states; use the specific meaning
rather than assuming that an absent value is zero or that an address window guarantees a device.

== Document and Evidence Navigation
#ds-table("document-navigation",[Where to find an authoritative answer],
  ([Question],[Primary reference],[How to use this datasheet]),
  (([Addresses, routes and pins],[Canonical memory/topology/pin inputs and generated bindings.],[Use the generated tables and cross-IP route/conflict summaries.]),
   ([Register behavior],[Current RTL, handwritten C definitions and reviewed IP contract.],[Use Register Programming plus the individual register exceptions.]),
   ([Driver sequence],[SDK implementation, platform source and the IP's software contract.],[Follow the supported path and its error/ownership boundaries.]),
   ([LP startup / traps],[Selected CRT, linker and conditional IRQ implementation.],[Use Runtime, SDK and Shell; separate pre-main stalls from application results.]),
   ([Linux readiness],[OpenSBI, generated DTB and rootfs mailbox publisher.],[Follow the platform handoff and distinguish console, ready event and terminal verdict.]),
   ([Diagnostic coverage],[Selected application's actual checks and result branches.],[Use Applications and Firmware Application Results; retain stage logs for repeated codes.]),
   ([Board connection],[Approved board constraints/schematic and selected device/pad specifications.],[Use connection/compatibility tables to identify prerequisites and missing evidence.]),
   ([Validation or performance],[Matching source/profile report, tool versions, device/model and conditions.],[Use the support and characterization sections without promoting source presence to a pass.]),
   ([Publication identity],[This PDF's manifest and matching publication source set.],[Use Sources and Reproducibility for publication-only metadata links.])),
  widths:(0.85fr,1.75fr,1.55fr))
The datasheet presents the reviewed snapshot for integration. Detailed IP contracts explain
local behavior; SDK sources show the implemented calling sequence; board guides define a
particular physical system; result reports establish only the scope actually tested. Where
an old narrative conflicts with current executable integration, use the current implementation
and record the discrepancy rather than silently copying the older statement.
#source-note("publications/datasheets/system-reference.json",title:"Publication content and evidence index")
#source-note("docs/README.md",title:"Engineering document map")
