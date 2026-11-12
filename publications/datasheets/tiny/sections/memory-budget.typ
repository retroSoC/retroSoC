#import "../engineering-figures.typ": storage-figures
#import "../style.typ": *
#import "../diagrams.typ": flow

= Appendix: Software Memory and Buffer Requirements <tiny-memory-budget>
== Linker Layout and Runtime Accounting
The main SRAM capacity is 131072 bytes. Count runtime text/rodata/data, BSS, stack, heapless workspaces,
descriptors and live payload together. The .init section remains in Flash; text/rodata/data use Flash load
addresses and SRAM runtime addresses. BSS has no load bytes. Names of linker symbols containing PSRAM
do not change the selected Tiny section placement.
#ds-table("linker-accounting",[Selected linker placement],([Section],[Run location],[Load / accounting]),(
 ([.init],[Flash],[Flash-resident entry code.]),([.text / .rodata],[SRAM],[Initialized bytes loaded from Flash.]),
 ([.data],[SRAM],[Initialized bytes loaded from Flash.]),([.bss],[SRAM],[NOLOAD; zeroed by startup.]),
 ([Stack and buffers],[SRAM or explicitly admitted external memory],[Budget live lifetime and worst-case high-water use.])),widths:(1fr,1fr,2fr))
#source-note("crt/linker/ld2_all_sram.lds",title:"Actual section placement")
#source-note("crt/arch/riscv/startup.S",title:"Relocation, BSS and stack setup")

 #storage-figures("tiny-memory-budget",section:"linker")

== Worked Buffer Budgets
These are exact arithmetic examples, not measured memory use or promises that a workload fits after code and stack.
#ds-table("buffer-budgets",[Payload and transport examples],([Example],[Calculation],[Bytes]),(
 ([QVGA RGB565 frame],[320 x 240 x 2],[153600]),([VGA RGB565 frame],[640 x 480 x 2],[614400]),
 ([256 stereo16 frames],[512 samples x 2 bytes; packed into 256 words],[1024]),
 ([256 stereo24 frames],[512 samples in 512 32-bit words],[2048]),
 ([16 DMA descriptors],[16 x 64 bytes; alignment required],[1024])),widths:(1.15fr,2.1fr,0.7fr))
A QVGA RGB565 payload alone exceeds all main SRAM by 22528 bytes. External placement or bounded chunking
is therefore required before accounting for other runtime use. PSRAM needs explicit initialization and retains
its 8 MiB reference-device limit independently of the 64 MiB slot aperture.
DVP dimensions, row stride, transport words and final-byte validity must be checked together. I2S24 has
three useful bytes per sample but four bytes of transport storage. Do not silently mix payload and storage sizes.
#source-note("docs/ip/dvp.md",title:"Pixel formats and capture geometry")
#source-note("crt/src/hal/i2s_math.c",title:"Sample packing and transport word calculations")

 #storage-figures("tiny-memory-budget",section:"budget")

=== DMA Descriptors and Buffer Lifetime <tiny-dma-format>
See @format-dma-tcd in the DMA chapter for the byte layout alongside the channel FIFO and protocol example.
#ds-table("tcd-fields",[Source-derived DMA C descriptor layout],([Byte offset],[Field],[Bytes],[Role]),
  data.tcd.map(f=>(code("0x"+upper(str(f.offset,base:16))),code(f.name),str(f.bytes),f.role)),widths:(0.75fr,1.7fr,0.45fr,1.1fr))
The descriptor is 64 bytes and each descriptor address is 64-byte aligned. Tiny permits only the implemented transfer kind,
request, increment and width combinations. Stride fields remain zero and row count is at most one. A field in the ABI is
not evidence of cyclic or 2D support; stream support follows the implemented endpoint/kind rules. HAL result fields do not imply that hardware directly writes every result word.

#ds-table("tcd-control",[Descriptor control positions and portable Tiny use],([Bits],[Field],[Meaning / restriction]),(
  ([0],[VALID],[Must be set for a submitted descriptor.]),
  ([1 / 2],[SRC_INC / DST_INC],[Increment the corresponding memory address; use the endpoint's required mode.]),
  ([3 / 4],[CRC_ENABLE / CRC_FINAL],[Select the implemented CRC processing/final comparison.]),
  ([5 / 6],[INT_DONE / INT_ERROR],[Declared SDK flags; use the channel event-enable/IRQ registers rather than assuming per-descriptor IRQ gating.]),
  ([10:8],[KIND],[Memory or implemented stream kind; validate endpoint direction and quota.]),
  ([15:12],[REQUEST low bits],[Low nibble of the enabled request selector.]),
  ([25],[REQUEST high bit],[Selector bit 4; required for SPI requests 16/17.]),
  ([17:16],[PRIORITY],[Two-bit software priority value.]),
  ([24:20],[BURST],[0 selects the 16-beat default in descriptor submission; 1 through 16 select a bound. Direct configuration requires 1 through 16.]),
  ([Other bits],[Reserved / unused],[Use zero for compatibility; a field declaration does not establish an extra operation.])),widths:(0.6fr,1.05fr,2.5fr))
The current HAL chain helper submits one descriptor at a time, waits, copies result registers into the descriptor and then
follows #code("next_ptr"), bounded by #code("max_tcds"). It is not an autonomous circular-queue API. On a timeout or error,
the helper records observed progress but the caller must still confirm abort/drain before releasing memory.

Reserve channel, descriptor and payload storage through completion or confirmed recovery. Publish CPU-produced input with
the required fence before starting the non-CPU master. Tiny has no application-hart cache handoff protocol; importing the
Mini HP cache-clean service would describe nonexistent hardware.
#flow("dma-recovery",([Validate channel / request / bounds and reserve storage],
  [Publish descriptor/input and configure while idle], [Start and wait for the required completion boundary],
  [On failure: capture fault/progress, abort, confirm drain], [Release or reuse storage only after ownership is safe]),
  [DMA lifetime and recovery ordering. A polling timeout is not an idle acknowledgement.])
#source-note("crt/include/retrosoc/hal/dma.h",title:"Handwritten descriptor and public HAL ABI")
#source-note("crt/src/hal/dma_math.c",title:"Descriptor validation and unsupported combinations")
