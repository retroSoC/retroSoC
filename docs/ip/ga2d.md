# GA2D: Mini 2D Graphics Accelerator

## Purpose and Research Boundary

GA2D offloads rectangular framebuffer fill, copy, pixel-format conversion,
and composition from Mini's LP and HP processors. It is a fixed-function
graphics accelerator with private two-dimensional DMA, APB4 configuration,
and a dedicated AXI64 data-plane master.

Status: **architecture and software ABI frozen on 2026-09-12**, following
explicit approval of the research choices. Phase 0 is documentation only;
Phases 1 through 6 are implementation requirements, not completed work. This
freeze is not an `rtl-freeze` or `verified` readiness claim. There is no
implemented GA2D, measured GA2D PPA, or silicon qualification at this freeze.

The feature slug is `ga2d`; this file is its authoritative specification.
Stable phase headings and `GA2D-PN` identifiers in Development Order name the
same phase and MUST NOT be renamed, renumbered, or reused after this freeze.

### Repository authority and approved changes

The inspected baseline is commit
`10223b93421d842ef10ebebd8ea4c3e34b41fef8`. Executable sources describe that
baseline; this specification defines the approved changes to implement in
the named phases. An unimplemented phase MUST NOT be advertised as present.

Authoritative inputs are:

- [Agent contract](../../AGENTS.md), [engineering workflow](../engineering.md),
  [RTL policy](../rtl-coding-style.md), and
  [RTL compliance process](../rtl-coding-style-compliance.md).
- [LP/HP architecture](../lp-hp-architecture.md),
  [AXI4 contract](../axi4-interconnect.md), [stream contract](../axi4-stream.md),
  [central DMA](dma.md), [JPEG](jpeg.md), and [APU](apu.md).
- [Address map](../../rtl/mini/address_map/memory_map.json),
  [topology](../../rtl/mini/integration/soc_topology.json),
  [clock/reset inventory](../../rtl/mini/integration/clock_reset_domains.json),
  [Resource Controller](resource-controller.md), and
  [Fabric Monitor](fabric-monitor.md).
- [RTL guide](../../rtl/README.md), [integration guide](../../rtl/mini/integration/README.md),
  [Common filelist](../../rtl/mini/filelist/commonip.fl),
  [owned-IP filelist](../../rtl/mini/filelist/ip.fl),
  [SDK guide](../../crt/README.md), and [application guide](../../app/README.md).
- [Dependency lock](../../dependencies/dependencies.lock.json),
  [IHP130 product profile](../../configs/ci/ihp130.mk),
  [HP acceptance profile](../../configs/ci/ihp130-hp.mk),
  [regression runner](../../scripts/regress.py), and
  [reusable CI workflow](../../.github/workflows/_regression.yml).

Confirmed baseline facts:

1. `APB4_GA` is a non-public, reserved 4 KiB region at `0x10012000`; there
   is no active GA peripheral or GA HAL to preserve.
2. The native data plane has eight masters and six targets. Master 6 is
   assigned to JPEG, although some older prose still calls it reserved.
   APU shares I/O gateway A. Neither identity may be taken by GA2D.
3. All 32 LP vector bits are assigned. Bits 0 and 1 are software and timer
   interrupts; bits 2 through 31 feed 30 Hazard3 external inputs. Xh3irq is
   enabled, but the SDK external-registration function returns `RS_ENOTSUP`.
4. Central DMA implements a 32-bit, one-dimensional transfer contract.
   GA2D does not add channels or request selectors to that controller.
5. Mini has no hardware cache coherency. Ownership, fences, and the HP
   64-byte Zicbom cache-maintenance contract remain software obligations.

Phase 1 approves expansion of the LP interrupt platform. Phase 2 approves
the ninth data master, wider global IDs, and resource/observability changes.
Phase 3 approves the address-symbol migration and subsequent activation.
These are explicit amendments to the baseline contracts, not permission to
replace unrelated interconnect, CPU, memory, or power architectures.

## Commercial References

Evidence was checked on 2026-09-12. Vendor behavior informs the architecture;
vendor register encodings, proprietary implementations, and product-specific
performance claims are not GA2D requirements.

| Reference | Relevant architecture and dependencies | Evidence/activity and selected lessons |
| --- | --- | --- |
| ST STM32H7 DMA2D / Chrom-ART | Fill, copy, format conversion, and two-source blending. Private AXI master, AHB configuration, foreground/background/output buffering, completion/error/watermark interrupts, and suspend/abort. RCC clock/reset and accessible memories are platform dependencies; CPU caches need explicit maintenance. | STM32H743 is listed Active/in volume production. The [reference manual](https://www.st.com/resource/en/reference_manual/dm00314099-stm32h742-stm32h743753-and-stm32h750-value-line-advanced-armbased-32bit-mcus-stmicroelectronics.pdf), [official HAL](https://github.com/STMicroelectronics/stm32h7xx-hal-driver/blob/master/Src/stm32h7xx_hal_dma2d.c), [cache-aware example](https://github.com/STMicroelectronics/STM32CubeH7/blob/master/Projects/STM32H7B3I-EVAL/Examples/DMA2D/DMA2D_MemToMemWithBlendingAndCLUT/readme.txt), and [product page](https://www.st.com/en/microcontrollers-microprocessors/stm32h743ii.html) support the functional pattern. Reuse private DMA and direct jobs; use Mini APB4, reset, and cache rules. No comparable standalone area/power or CDC signoff evidence was established. |
| NXP i.MX RT1170 PXP | Raster copy, alpha composition, color conversion, scaling, and fixed-angle rotation. Memory-buffer/register programming, operation loading/completion interrupts, AXI error identity, SDK clock/reset control, and optional LCD handshake. Buffers and display ownership remain system concerns. | Product is [Active](https://www.nxp.com/products/i.MX-RT1170); [Rev.5 manual update](https://www.nxp.com/pcn/202601006I) was announced in February 2026. [PXP API](https://mcuxpresso.nxp.com/api_doc/dev/936/group__pxp__driver.html) and [AN13075, December 2020](https://www.nxp.com/docs/en/application-note/AN13075.pdf) document the pattern and application-level comparisons. Reuse byte pitches, explicit completion, and buffer ownership. Scaling, rotation, LCD coupling, and queues are deferred. Demo FPS is not standalone PXP throughput or Mini evidence; no comparable block area/power or CDC/security qualification was established. |
| TES D/AVE 2D | Commercial BLIT/vector/texture engine; display-list DMA and level IRQ; AXI/AHB master adaptors and APB/AXI4-Lite control adaptors. The documented core has one clock domain and asynchronous active-high reset, with caches and external framebuffer memory. | The current [product/support page](https://www.tes-dst.com/technology-products/gpus/d/ave-2d/) links a [2020-03-12 data sheet](https://www.tes-dst.com/fileadmin/user_upload/PDFs/TD_240201SH_DS_DAVE2D_Data_Sheet.pdf). TS peak is one pixel/cycle; TL takes four. Published TS <100k gates and TL approximately 60k are configuration-dependent estimates, not IHP130 results. FPGA evaluation and software-emulation deliverables are useful validation patterns. Reuse staged buffering and a reference model; do not import its reset polarity, caches, vector engine, or display-list ABI. No transferable power/CDC/security signoff is implied. |
| VeriSilicon Vivante 2D GC620/GC820 family | Larger composition/video-processing IP with RGB/YUV, multiple layers, and framebuffer compression; software ecosystems include HWC, EXA, and DirectFB. | The current, undated [product page](https://www.verisilicon.com/en/IPPortfolio/Vivante2DGPUIP) publishes format and pixel-rate positioning. Complete bus, DMA/IRQ, clock/reset/CDC, coherency/security, area/power, and verification contracts were not publicly established for a selected configuration. Use capability tiers and software delivery as roadmap references only; no external Vivante dependency is selected. |

The selected design remains a private-DMA raster engine. Its dedicated AXI64
identity is approved; no shared JPEG port, I/O gateway client, external stream
endpoint, or central-DMA extension is part of the normative MVP.

Reference retrieval note: ten of the eleven external links were accessible
during freeze validation. Direct retrieval of the large ST RM0433 PDF timed
out; the canonical link is retained from the approved research, and the ST
product/HAL/example links remain available. This retrieval limit is not a
claim that the vendor document is unavailable or that its implementation is
verified for Mini.

## Requirements and Non-goals

MUST and MUST NOT are binding. ACCEPTANCE requires evidence. The selected
Common reuse preference is binding wherever the listed semantics match.

| ID | Class | Frozen requirement |
| --- | --- | --- |
| GA2D-REQ-001 | MUST | Use the `GA2D` / `ga2d` name, migrate the former GA reservation without moving its address, and retain one authoritative ABI. |
| GA2D-REQ-002 | MUST | Configure through 32-bit APB4; access payload through private AXI4 with 64-bit data and 32-bit addresses. |
| GA2D-REQ-003 | MUST | Add dedicated data-master index 8; preserve existing master and target identities, permissions, and memory windows. |
| GA2D-REQ-004 | MUST | Expand the LP vector to 64 bits, implement Xh3irq software dispatch, and allocate exclusive LP/HP GA2D interrupt routes. |
| GA2D-REQ-005 | MUST | Use Resource Controller index 8 with LP reset ownership, lock, quiesce, drain, reset, and owner handoff. |
| GA2D-REQ-006 | MUST | Implement direct, single-job rectangular FILL, COPY, CONVERT, and BLEND with independent byte pitches. |
| GA2D-REQ-007 | MUST | Support RGB565, packed RGB888, XRGB8888, ARGB8888, and A8 foreground masks exactly as specified below. |
| GA2D-REQ-008 | MUST | Implement bit-exact opaque-background composition with pixel alpha multiplied by global alpha; preserve the defined byte order and rounding. |
| GA2D-REQ-009 | MUST | Check dimensions, pixel alignment, address arithmetic, mapped ranges, and overlap before issuing payload traffic. |
| GA2D-REQ-010 | MUST | Respect AXI backpressure, byte lanes, 16-beat/4 KiB boundaries, independent channels, and terminal-response completion. |
| GA2D-REQ-011 | MUST | Make abort, timeout, quiesce, warm flush, and reset preserve transaction ownership and prevent late-response reuse. |
| GA2D-REQ-012 | MUST | Provide set-dominant sticky IRQ events, first-error capture, progress, and atomic counter snapshots. |
| GA2D-REQ-013 | MUST | Reuse compatible locked Common FIFO/register/CDC/arbiter primitives; do not edit managed sources in place. |
| GA2D-REQ-014 | MUST | Handwrite RTL/C register definitions and validate parity; expose bounded freestanding `rs_ga2d_*` HAL APIs. |
| GA2D-REQ-015 | MUST | Enforce explicit shared-buffer ownership, fences, and HP cache maintenance; do not claim coherency or tenant isolation. |
| GA2D-REQ-016 | MUST NOT | Implement graphics in the documentation-freeze stage or change RTL, firmware, build settings, dependencies, warnings, or metric policy in Phase 0. |
| GA2D-REQ-017 | ACCEPTANCE | Pass the functional, protocol, interrupt, lifecycle, software, contention, and physical-evidence gates in this document. |
| GA2D-REQ-018 | ACCEPTANCE | Report measured throughput and latency at recorded clocks and memory configurations; no fixed frame-rate promise is an MVP gate. |
| GA2D-REQ-019 | MUST NOT | Advertise unimplemented functions, add a register generator, hide an error as DONE, or reclaim buffers on a software timeout alone. |

Explicit DEFER items are LVGL integration; descriptor/ring/command queues;
rotation, scaling, negative pitches, general overlapping blits, and hardware
clipping; fully transparent or premultiplied layer composition; CLUT, color
key, dithering, YUV, compressed/tiled formats, and vector/3D graphics; external
AXI4-Stream/video/display ports; IOMMU, coherent caches, safety certification,
DFT/MBIST/ECC extensions, and silicon/physical qualification. None may be
silently added to the MVP acceptance boundary.

## Selected Architecture

### Hierarchy and data flow

The MVP has no processor, microcode, whole-frame local memory, or descriptor
fetcher. One pixel can advance per PCLK after pipeline fill when operands and
output space are available; this is the no-stall pipeline target, not a system
pixel-rate guarantee.

```text
apb4_ga2d
  ga2d_reg             APB response, shadow job, IRQ, error, snapshots
  ga2d_core            validation, job state, stopping and completion
  ga2d_pixel          unpack, format conversion, alpha, destination packing
  ga2d_dma
    ga2d_addr_gen     per-plane row and byte cursors, legal burst splitting
    ga2d_axi4_master  one read + one write transaction, stable AXI channels
    Common FIFOs      foreground, background, output (32 x 64 bits each)

LP/HP MMIO -> existing control bridges -> APB4/PCLK -> GA2D
GA2D AXI64/PCLK -> dedicated axi4_async_bridge -> ID prefix 8
               -> HP data crossbar -> existing memory/target guards
GA2D events -> Resource Controller 8 -> LP vector 32 OR HP PLIC 11
```

These are module responsibilities; private combinational helpers may be
functions. New primary modules/files follow the owned RTL naming rules.
`ga2d_define.svh` holds the handwritten register/field macros;
`ga2d_pkg.sv` holds shared typed job and protocol constants without duplicating
numeric definitions. New sources belong in `rtl/ip/multimedia/` and the
existing ordered filelists. There are no generated register sources.

FILL generates a repeated packed color. COPY moves source bytes unchanged.
CONVERT unpacks a foreground pixel and packs the destination representation.
BLEND consumes matching foreground/background pixels before producing output.
The scheduler alternates required read sources at burst boundaries and MUST
prevent one full input FIFO from starving the other input needed for progress.
For in-place background composition, each pixel's background is acquired
before any destination write covering that pixel is launched.

The three default FIFOs contain 768 payload bytes in total, plus byte-valid
and control metadata. Common's small asynchronous-read FIFO does not imply
SRAM inference. Silicon storage mapping is an evidence item, not a claim.

### Stable integration allocations

| Interface/identity | Frozen allocation |
| --- | --- |
| APB region | `APB4_GA2D`, `0x10012000..0x10012FFF`, 4 KiB |
| APB island/response slot | `apb4_periph`, appended slot 28 |
| Timed/pure APB names | `u_ga2d_apb4_if`, `u_ga2d_apb4_pure_if` |
| Native data master | index 8, topology name `ga2d` |
| Source/global ID widths | 3 / 7 bits; `{master[3:0], source_id[2:0]}` |
| Resource Controller | index 8, resource count 9; bank starts at `0x200` within Resource Controller |
| LP route | peripheral IRQ group bit 24, core-vector bit 32, external ordinal 30 |
| HP route | PLIC source 11, existing PLIC contexts unchanged |
| Peripheral raw/routed IRQ bus | append GA2D at bit 7; EXT-H remains inserted at Resource Controller index 5 |
| Default owner | LP, unlocked |
| Pads and external streams | none |

The APB region becomes `public: true`, `route: apb4_periph`, `kind: active`,
and `user_access: none` only at shell activation in Phase 3. That user-access
classification excludes legacy user cores; it does not replace the existing
product HP-MMIO and root-management policy. Product software coordinates LP/HP
ownership; APB4 alone does not identify the initiating hart.

### Platform expansion contract

Phase 1 parameterizes both `core_wrapper` and `mgmt_core_wrapper` so the Mini
root connects all 64 vector bits. A 32-bit default/compatibility instantiation
retains the original 30 external inputs. The expanded root uses
`NUM_IRQS=62`, `IRQ_PRIORITY_BITS=2`, and zero input-bypass bits. Software and
timer stay on bits 0/1; external ordinal `n` maps to vector bit `n+2`.
Unallocated high vector bits are tied low. MPW user-core connections remain
explicitly 32-bit, consume only the masked low 32 bits, and do not see GA2D.

The topology generator remains the allocation authority. Phase 1 additionally
emits C interrupt metadata under its variant-local
`include/retrosoc/generated/` directory, alongside the existing generated SV
definitions. It supplies vector/external counts and allocated source numbers
to the SDK; it does not generate register definitions. The source mapping
includes `RS_SOC_IRQ_GA2D=32` and `RS_SOC_EXT_IRQ_GA2D=30` when GA2D is wired
in Phase 3. Until then, bit 32 remains unallocated and low.

Phase 2 expands the native fabric to nine masters and six unchanged targets.
Master index width is four; source ID width stays three; global ID width is
seven. Old global IDs retain their numeric values by zero extension. Both
prefix helpers, all crossbar channel/route state, FIFO payloads, guard fault
IDs, target CDCs, downsizers, SRAM/memory frontends, error responders, monitor
signals, and export/test boundaries MUST retain that seventh bit. Merely
changing `NumMasters` is insufficient. Invalid returned master prefixes
9..15 MUST be detected and must never index an out-of-range array or route to
master 0; they require protocol recovery if a transaction remains unresolved.

GA2D's master admission credit is one read and one write; each local channel
uses ID zero. Its normal arbitration class is 8 with `AxQOS=0`. Existing
aging promotion after 256 continuously eligible cycles, equal-class Common
round-robin arbitration, and LP recovery priority are retained. The bound
assumes a progressing target and is not a wall-clock AXI liveness guarantee.

Read targets are SRAM, SDRAM, active QPI/OPI, and XPI; writes exclude XPI.
Instruction accesses, MMIO, exclusive transactions, and nonzero cache
attributes are denied. The root fabric's target error/timeout behavior is
retained; GA2D records the returned response without relabeling it as success.

Resource Controller version becomes 1.1 (`0x00010001`); its old offsets and
indices 0..7 remain unchanged. Resource 8 appends the existing bank layout.
Fabric Monitor version becomes 1.1 and advertises nine master banks; bank 8
occupies `0x200..0x21F`, below the unchanged target banks at `0x300`.
`FAULT[12]` holds master bit 3 while existing master `[4:2]`, target `[7:5]`,
and reason `[11:8]` keep their meanings. Software decodes all four master bits
when version is at least 1.1; older versions imply high bit zero. SYSCTRL's
separate `FAULT_MASTER` readback and internal path expand to four bits at the
same offset. LP-control-fabric fault IDs are zero-extended. No identity may be
truncated. The monitor HAL adds `RS_FABRIC_MASTER_GA2D=8`; the existing
misnamed master-6 enum may retain a compatibility alias to a truthful JPEG
name without changing value 6.

### Common reuse boundary

The inspected Common checkout matches locked revision
`964a54d70cb78e394ba9a25c05f2aa2b02941fb7`; Hazard3 matches
`5b3a34f6955e50e03bdcb964201c91462f7078c3`. This feature requires no dependency
revision change.

| Component | Selected use and limit |
| --- | --- |
| `axi4_if`, `apb4_if` / `apb4_pure_if` | Existing interfaces and control-island wrappers; widths set at integration. |
| `fifo` / `stream_fifo` | Power-of-two depth 32, occupancy/reservation checked; flush only after drain or acknowledged epoch invalidation. |
| `dffer`, `dfferc`, other matching Common registers | Explicit next-state, reset and enable; IRQ next state uses set-dominant logic. |
| `round_robin_arbiter` | Existing arbitration, including nine-client non-power-of-two coverage. |
| `axi4_async_bridge` with Common warm-flush FIFOs | Entire five-channel CDC; use clear-busy and epoch, not separate pulse synchronizers for responses. |
| `cdc_sync`, `rst_sync`, `cdc_2phase` when needed | Stable levels, domain reset release, and acknowledged lifecycle transfers respectively; not arbitrary multi-bit event sampling. |

Common `regfield` gives software clear priority for a same-bit simultaneous
W1C/hardware update. It MUST NOT implement GA2D's IRQ storage unchanged.
Likewise, the existing `dma_axi4_master` hardwires transfer size to its data
width; it cannot satisfy GA2D's narrow edge reads unchanged. Reuse compatible
protocol structure or primitives, but retain a GA2D-owned size-aware master
instead of weakening central DMA or changing managed Common semantics.

## Interfaces

### Pixel and address contract

All surfaces are top-to-bottom raster order. Width and height are integers
1..65535. Addresses are unsigned 32-bit physical byte addresses; pitch is the
unsigned byte distance between row starts. There is no automatic clipping.

| Format code | Name | Bytes/pixel | Memory layout and required pixel alignment |
| ---: | --- | ---: | --- |
| 0 | RGB565 | 2 | Little-endian `rrrrrggggggbbbbb`; address/pitch multiples of 2. |
| 1 | RGB888 | 3 | Increasing addresses R, G, B, matching JPEG; byte alignment. |
| 2 | XRGB8888 | 4 | Little-endian `0xXXRRGGBB`; address/pitch multiples of 4. |
| 3 | ARGB8888 | 4 | Little-endian `0xAARRGGBB`; address/pitch multiples of 4. |
| 4 | A8 | 1 | One coverage byte; byte alignment; foreground of BLEND only. |

COPY requires identical foreground/destination color formats and preserves
every source byte, including X and A. CONVERT accepts any of the four color
formats on both sides, including equal formats. Conversion ignores X on
input, writes X as 255, preserves ARGB alpha only when producing ARGB from
ARGB, supplies alpha 255 for an RGB source, and discards alpha when producing
RGB. It does not apply alpha to color. A8 is not a COPY/CONVERT/output format.

RGB565 channel expansion is `r8=(r5<<3)|(r5>>2)`,
`g8=(g6<<2)|(g6>>4)`, `b8=(b5<<3)|(b5>>2)`. Packing uses
`r5=r8>>3`, `g6=g8>>2`, `b5=b8>>3`; no dithering or gamma conversion occurs.

FILL takes constant `COLOR=0xAARRGGBB`; ARGB output preserves that A, XRGB
writes X=255, and RGB ignores A. GLOBAL_ALPHA is irrelevant to FILL.

BLEND accepts a color or A8 foreground, any color background, and any color
destination. Background alpha/X is ignored: it is an opaque framebuffer.
The foreground alpha `p` is ARGB.A, the A8 sample, or 255 for an RGB/XRGB
source. For A8, foreground RGB comes from COLOR and COLOR.A is ignored.
With global alpha `g`, each channel is computed using unsigned integers:

```text
a = floor((p * g + 127) / 255)
C = floor((F * a + B * (255 - a) + 127) / 255)
```

Intermediate arithmetic MUST retain the complete numerator. ARGB/XRGB
destinations write high byte 255; RGB565 is packed after this calculation.
Alpha 0 preserves background RGB and alpha 255 selects foreground RGB.
The two rounding stages are intentional and MUST match the reference model.

Each used plane has `row_bytes=width*bytes_per_pixel`, pitch at least
`row_bytes`, and natural pixel alignment on both address and pitch. The
exclusive end is `base+(height-1)*pitch+row_bytes`, evaluated without 32-bit
wrap (at least 64-bit unsigned arithmetic), and may equal `2^32` but not
exceed it. The entire conservative interval `[base,end)` MUST fit one
permitted mapped memory region. Actual external-device capacity can be
smaller than an aperture; software checks discovered capacity, and a target
rejection remains a normal DMA error, not proof that the aperture is usable.

Unused foreground/background fields are ignored. FILL uses only destination;
COPY/CONVERT use foreground and destination; BLEND uses all three.
Destination overlap with an input's conservative interval is rejected except
for BLEND with exactly equal background/destination base, pitch, and format.
That exception permits in-place background composition; foreground overlap
with destination remains rejected. Input/input overlap is harmless and allowed.
Identical-address COPY is therefore rejected too; software may skip that no-op.
Padding-inclusive conservative rejection is intentional, not a promise of
general rectangle-overlap analysis. Failed validation issues no AXI request.

### AXI4 protocol

GA2D uses 32-bit addresses, 64-bit data, 8 strobes, 3-bit local IDs, and
one-bit USER fields. ID, USER, LOCK, CACHE, PROT, QOS, and REGION outputs are
zero. PROT zero denotes data, not an executable transaction or a security
qualification. The SoC prefix creates global ID `0x40` for master 8/local 0.

Only INCR is emitted, with 1..16 beats. Full-width aligned reads are used
inside rows. At row heads/tails, aligned 1/2/4-byte single-beat reads cover
exactly the remaining bytes until an 8-byte body can be used. For narrow
responses, select the actual AXI byte lanes rather than assuming low lanes.
No input read may extend outside the logical row, even when padding exists.

Writes use aligned 8-byte transfers with precise head/tail strobes. The
packer can carry a RGB888 pixel across beats, but every enabled write lane
must belong to the requested destination row. All-zero-strobe normal payload
beats are not emitted. A burst never crosses a row's transfer envelope,
4 KiB, a mapped-region boundary, or the 16-beat limit. Head alignment and
partial strobes do not authorize modification of adjacent bytes.

One AR transaction and one AW transaction may be outstanding independently.
The read owner (foreground/background) is latched before ARVALID and remains
fixed through retirement. The full response burst is reserved before ARVALID;
the complete write payload and strobes are buffered/reserved before AWVALID.
The pipeline must not consume storage reserved for an issued write.

AW, AR, and W payloads remain stable while VALID and not READY. A stop request
cannot withdraw a presented address, even before its acceptance. Accepted AW
is followed by its complete W sequence and B drain. Reads drain through their
terminal response; response errors do not turn untrusted pixels into output.
Read/write sides may overlap but W transaction order is fixed and no write
interleaving is permitted. DONE requires all used pixels processed, all
expected responses retired successfully, and no unaccounted bridge transaction.

### APB4 protocol

The port is the existing 32-bit PCLK APB4 target. All accesses are word aligned.
All writes require `PSTRB=4'hF`; unsupported strobes, unknown offsets, RO
writes, reserved command/field bits, and forbidden busy writes return PSLVERR
and have no register/job side effect. No narrow transfer is silently expanded.

Each access is captured once in the access phase and receives a registered
response on the following PCLK edge. PRDATA and PSLVERR remain stable with
PREADY for that transfer. Hardware executes commands once, not once per
cycle that PSEL/PENABLE remains high. APB responses never wait for DMA or a
job to finish. Reads have no destructive side effects; WO reads return zero.

## DMA and Interrupt Contract

GA2D owns its DMA and does not reserve a central-DMA channel, consume an
existing request selector, or expose descriptor memory. One owner serializes
register programming and retains buffer ownership until safe completion.

| Bit | IRQ_STATE / IRQ_ENABLE / IRQ_TEST meaning |
| ---: | --- |
| 0 | DONE: successful terminal job completion. |
| 1 | ERROR: first error detected for the active job, including validation, response, protocol, timeout, or epoch loss. |
| 2 | ABORT_DONE: an explicit abort or resource stop has safely terminated the job. |

IRQ state updates as `(old_state & ~w1c) | hardware_events | test_events`.
New events win over a same-cycle clear. IRQ_TEST exercises routing only; it
does not set STATUS terminal flags, create progress, or complete a DMA job.
The raw level is `|(IRQ_STATE & IRQ_ENABLE)`. Masking does not clear state.
DONE and ABORT_DONE are mutually exclusive outcomes for one job. ERROR can
be asserted before drain completes and can coexist with ABORT_DONE after a
subsequent explicit abort. ERROR always prevents DONE for that job.

Resource Controller owner 0 routes only to LP vector 32; owner 1 routes only
to HP PLIC source 11. Resource reset masks both routes. A pending level is
neither lost nor broadcast during handoff: software normally acknowledges it
before transfer, otherwise the still-pending level follows the new owner.
LP resource-fault IRQ29 retains its ownership-violation meaning; it is not
silently reused as GA2D's completion/error line.

The SDK's existing external IRQ ordinal convention is preserved. Phase 1
implements registration plus enable/disable/priority and machine-external
dispatch using Xh3irq's documented array-CSRs and MEINEXT/MEICONTEXT, not a
new LP PLIC. External ordinals 0..61 are valid; >=62 or null handlers are
invalid. Priorities expose 0..3 with higher values higher priority; enable
uses priority 1 unless explicitly configured. Same-priority hardware
tie-breaking remains the Hazard3 rule. CSR bank addressing must cover 16-bit
enable/pending banks and four-entry priority banks without wide C shifts.

The first software backend is non-nested: it does not re-enable global MIE
inside an ISR, services one selected external source per trap, and returns
through the normal saved context/mret path. A handler clears its peripheral
cause before returning. An enabled source without a handler is masked to
avoid an unbounded default-handler loop. Enable installs/validates the handler
before unmasking that source and enabling `mie.MEIE`; it does not globally
enable interrupts without the caller's normal core-IRQ API. CSR-disabled
builds retain polling support and return RS_ENOTSUP from external IRQ control
APIs without emitting CSR instructions. GA2D's peripheral IRQ registers remain
accessible independently of CPU dispatch.

## Register and Software ABI

### Register map

IP version uses major `[31:16]`, minor `[15:0]`. All unspecified bits read zero
and must be zero on writes. `RW idle` requires BUSY=0; IRQ controls and
snapshots are accessible while busy. Configuration is shadowed and copied
atomically on an accepted START. No parameter edit can affect the active job.

| Offset | Register | Access | Reset / fields |
| ---: | --- | --- | --- |
| 0x000 | IP_ID | RO | `0x47413244` (GA2D). |
| 0x004 | IP_VERSION | RO | `0x00010000` (1.0). |
| 0x008 | CAPABILITY | RO | Implemented feature bits defined below. |
| 0x00C | LIMITS | RO | Implemented DMA geometry; final `0x08202010`. |
| 0x010 | COMMAND | WO | START bit 0, ABORT bit 1, SOFT_RESET bit 2. |
| 0x014 | STATUS | RO | Live/terminal fields below; terminal fields reset zero. |
| 0x018 | IRQ_STATE | RW1C | Bits 2:0, reset 0. |
| 0x01C | IRQ_ENABLE | RW | Bits 2:0, reset 0. |
| 0x020 | IRQ_TEST | WO | Set selected IRQ_STATE bits 2:0. |
| 0x024 | ERROR_STATUS | RO/W1C | Valid bit 0, code [7:1], stage [11:8], AXI response [13:12]. |
| 0x028 | ERROR_ADDRESS | RO | First-error address, reset 0. |
| 0x02C | TIMEOUT_CYCLES | RW idle | PCLK no-progress threshold; reset `0x00100000`; zero invalid. |
| 0x030 | JOB_CONFIG | RW idle | Operation [1:0]: FILL=0, COPY=1, CONVERT=2, BLEND=3; reset 0. |
| 0x034 | GLOBAL_ALPHA | RW idle | [7:0], reset 255. |
| 0x038 | COLOR | RW idle | `0xAARRGGBB`, reset 0. |
| 0x03C | SIZE | RW idle | Width [15:0], height [31:16], reset 0. |
| 0x040 | FG_ADDRESS | RW idle | Byte address, reset 0. |
| 0x044 | FG_PITCH | RW idle | Bytes between rows, reset 0. |
| 0x048 | FG_FORMAT | RW idle | [2:0], reset RGB565. |
| 0x04C | BG_ADDRESS | RW idle | Byte address, reset 0. |
| 0x050 | BG_PITCH | RW idle | Bytes between rows, reset 0. |
| 0x054 | BG_FORMAT | RW idle | [2:0], reset RGB565. |
| 0x058 | DST_ADDRESS | RW idle | Byte address, reset 0. |
| 0x05C | DST_PITCH | RW idle | Bytes between rows, reset 0. |
| 0x060 | DST_FORMAT | RW idle | [2:0], reset RGB565. |
| 0x064 | PERF_SNAPSHOT | WO | Bit 0 copies all live counters to their read banks. |
| 0x068 | FORMAT_CAPABILITY | RO | Foreground formats [4:0], background [12:8], destination [20:16]. |
| 0x080 / 0x084 | SNAP_CYCLES_LO / HI | RO | 64-bit active-job PCLK cycle count. |
| 0x088 / 0x08C | SNAP_READ_BYTES_LO / HI | RO | 64-bit successful logical input bytes. |
| 0x090 / 0x094 | SNAP_WRITE_BYTES_LO / HI | RO | 64-bit bytes acknowledged by successful B responses. |
| 0x098 / 0x09C | SNAP_READ_STALL_LO / HI | RO | 64-bit read-channel stall cycles. |
| 0x0A0 / 0x0A4 | SNAP_WRITE_STALL_LO / HI | RO | 64-bit write-channel stall cycles. |
| 0x0A8 / 0x0AC | SNAP_PIPE_STALL_LO / HI | RO | 64-bit stalled-pixel cycles. |
| 0x0B0 | SNAP_LINES_DONE | RO | [15:0] fully acknowledged destination rows. |

All other offsets are unimplemented and return PSLVERR. Identified future
features do not reserve a second hidden programming path.

CAPABILITY bits are FILL=0, COPY=1, CONVERT=2, BLEND=3, A8_MASK=4,
PRIVATE_DMA=5, IRQ=6, SNAPSHOT=7, TWO_DIMENSIONAL_PITCH=8,
BYTE_EDGES=9, and INPLACE_BACKGROUND=10. A8_MASK requires BLEND;
INPLACE_BACKGROUND also requires BLEND. LIMITS encodes maximum burst beats
[7:0], each input FIFO depth [15:8], output FIFO depth [23:16], and AXI beat
bytes [31:24]. Limits are zero when private DMA is not implemented.

| Implementation milestone | CAPABILITY | LIMITS | FORMAT_CAPABILITY |
| --- | ---: | ---: | ---: |
| Phase 3 shell | 0x00000040 | 0 | 0 |
| Phase 4 fill/copy DMA | 0x000003E3 | 0x08202010 | 0x000F000F |
| Phase 5/6 complete MVP | 0x000007FF | 0x08202010 | 0x000F0F1F |

In Phase 3 the snapshot command returns PSLVERR and counter reads return zero.
An operation missing its capability is rejected on START with PSLVERR and
no side effect. Unknown format codes may be held in their three-bit shadow
fields, but a used invalid/unsupported format fails job validation before DMA.
Reserved bits outside a field are always an APB access error.

### Commands, status, and events

COMMAND zero is a no-op. Exactly one command bit may otherwise be written;
multiple/unknown bits return PSLVERR. START requires BUSY=0, implemented
operation capability, no resource stop, and a recovered/ready data bridge.
It clears the previous STATUS outcome and live counters, sets BUSY, and begins
validation. Validation failure is an accepted job ending in ERROR without AXI
traffic; the START APB transfer itself has already completed successfully.
START does not clear IRQ_STATE, IRQ_ENABLE, or first-error registers.

ABORT on an idle engine is a no-op. During a job it requests stop/drain and
eventually ABORT_DONE; repeated ABORT is idempotent. If an accepted ABORT
coincides with the last successful B response, the outcome is ABORT_DONE,
not DONE. A real error detected on that edge still sets ERROR. SOFT_RESET
requires BUSY=0, no recovery/bridge clear, and proven transport idle; otherwise
it returns PSLVERR. It clears shadow configuration, local counters/snapshots,
terminal flags, and events/errors to their listed resets. It does not reset
Resource Controller ownership or a memory target.

STATUS bits are BUSY=0, DRAINING=1, QUIESCED=2, DATA_READY=3,
DONE=4, ABORTED=5, ERROR=6, and RECOVERY_REQUIRED=7; remaining bits are zero.
BUSY spans validation, processing, and any required drain. DRAINING means a
stop/error is being retired. QUIESCED means a resource stop is requested and
the source plus fabric have acknowledged safe idle. DATA_READY is a qualified
PCLK view of bridge recovery and destination reset release, not HP hart run
state. DONE/ABORTED/ERROR describe the last accepted job and persist until
START or SOFT_RESET. ERROR may become one while BUSY remains one.
RECOVERY_REQUIRED marks unresolved protocol/timeout/epoch cleanup and blocks
START/SOFT_RESET until coordinated recovery proves the old transport obsolete.

ERROR_STATUS accepts only a write of zero (no-op) or one (clear VALID and its
associated fields/address), while BUSY=0 and recovery is complete. Other
writes return PSLVERR. First-error fields are otherwise immutable until clear,
SOFT_RESET, or hard reset. Clearing IRQ_STATE does not clear ERROR_STATUS.

### Handwritten definitions and HAL

The implementation MUST add `rtl/ip/multimedia/ga2d_define.svh` and
`crt/include/retrosoc/hal/ga2d_regs.h`, with matching `APB4_GA2D__*` and
`RS_GA2D_REG_*` offsets and matching namespaced field/opcode/format constants.
`tests/test_ga2d_register_parity.py` checks values, reset/capability encodings,
and both missing and unexpected definitions; checking a small chosen subset
is insufficient. Generated address/interrupt metadata remains separate.

The public include is `<retrosoc/hal/ga2d.h>`. The following types are frozen
source interfaces; their compiler struct layout is not a DMA descriptor ABI:

| Type | Fields / meaning |
| --- | --- |
| `rs_ga2d_operation_t` | `RS_GA2D_OP_FILL=0`, `COPY=1`, `CONVERT=2`, `BLEND=3` with the same prefix. |
| `rs_ga2d_format_t` | `RS_GA2D_FORMAT_RGB565=0`, `RGB888=1`, `XRGB8888=2`, `ARGB8888=3`, `A8=4` with the same prefix. |
| `rs_ga2d_surface_t` | `uintptr_t address; uint32_t pitch; rs_ga2d_format_t format;` |
| `rs_ga2d_job_t` | `operation; foreground, background, destination` surfaces; `uint16_t width, height; uint8_t global_alpha; uint32_t color;` |
| `rs_ga2d_capability_t` | `uint32_t version, features, limits, formats;` |
| `rs_ga2d_status_t` | `bool busy, draining, quiesced, data_ready, done, aborted, error, recovery_required; uint32_t irq_state;` |
| `rs_ga2d_error_t` | `bool valid; uint8_t code, stage, axi_response; uintptr_t address;` |
| `rs_ga2d_stats_t` | `uint64_t cycles, read_bytes, write_bytes, read_stalls, write_stalls, pipe_stalls; uint16_t lines_done;` |

All functions below return `rs_status_t` and do not allocate memory:

Discovery requires the GA2D IP_ID and ABI major 1. Higher minor versions of
major 1 are additive: ignore unknown capability bits and use only known,
advertised operations. A different IP_ID or major returns RS_ENOTSUP. Stage
capabilities, rather than a firmware build assumption, control availability.

```c
rs_status_t rs_ga2d_get_capability(rs_ga2d_capability_t *capability);
rs_status_t rs_ga2d_job_validate(const rs_ga2d_job_t *job);
rs_status_t rs_ga2d_configure(const rs_ga2d_job_t *job);
rs_status_t rs_ga2d_start(void);
rs_status_t rs_ga2d_wait(rs_timeout_t timeout);
rs_status_t rs_ga2d_abort_wait(rs_timeout_t timeout);
rs_status_t rs_ga2d_reset(void);
rs_status_t rs_ga2d_get_status(rs_ga2d_status_t *status);
rs_status_t rs_ga2d_get_error(rs_ga2d_error_t *error);
rs_status_t rs_ga2d_get_stats(rs_ga2d_stats_t *stats);
rs_status_t rs_ga2d_irq_enable(uint32_t mask);
rs_status_t rs_ga2d_irq_pending(uint32_t *pending);
rs_status_t rs_ga2d_irq_clear(uint32_t mask);
```

`irq_enable` replaces the enable mask; zero masks
all events. `irq_pending` returns masked pending bits, while `get_status`
includes raw state. Unknown mask bits and null output pointers return
RS_EINVAL. Operations that require idle reject busy/not-ready/recovery with
RS_EIO; `wait` returns RS_EIO for an aborted or failed job. Query functions
return RS_OK with the reported status, including an error status. An abort
wait keeps draining despite STATUS.ERROR and returns RS_OK once safe idle is
proven, including an already-idle engine. Invalid user geometry returns
RS_EINVAL; unsupported IP version/capability returns RS_ENOTSUP. Bounded waits
use the existing `rs_timeout_t` polling
budget, not an undocumented milliseconds unit. Expiry returns RS_ETIMEOUT and
does not imply safe idle. A successful abort wait means drained buffers may
be reclaimed, not that their previous image was preserved.

`configure` performs pure software validation and capability checks before
MMIO, refuses BUSY, and programs all used fields without starting. It zeros
unused plane fields for deterministic readback. `start` checks safe idle,
clears previous IRQ and first-error state, executes `fence rw,rw`, and issues
START. `wait` tests STATUS ERROR before DONE and must not accept IRQ_TEST as
completion. After successful completion or safe abort it executes a fence;
cache operations remain the buffer owner's responsibility. `get_stats`
performs one snapshot command and then reads the complete read bank.

Phase 1 keeps `rs_irq_register_external(uint32_t, rs_trap_handler_t)` and
adds `rs_irq_enable_external(uint32_t, rs_trap_handler_t)`,
`rs_irq_disable_external(uint32_t)`, and
`rs_irq_set_external_priority(uint32_t, uint8_t)`, each returning rs_status_t
with the ordinal, registration, and priority semantics above. Handler type
and core/exception APIs are unchanged. Resource HAL adds
`RS_RESOURCE_GA2D=8` and changes resource count to 9. No new central-DMA API
or generic peripheral API is implied.

### Buffer ownership and compatibility

The caller owns address translation and DMA-visible allocation. A host
`uintptr_t` above UINT32_MAX is rejected rather than truncated. LP accesses
to a buffer cached by HP still require HP ownership release; LP's own lack of
data cache is not sufficient.

Before submit, the owner cleans source data and cleans/invalidates destination
cache lines, including partial rows and shared edge lines, then fences. It
reserves the complete affected 64-byte cache lines against all CPU access
until DMA retirement. After completion it fences, invalidates destination
lines without writing back stale data, and only then reads results. Uncached
shared memory avoids local CBO operations, but not ownership or fences.
Cache operations must never discard unrelated dirty bytes; sharing a cache
line requires preserving and transferring the whole line. Overlapping
foreground/background cache ranges are maintained once with consistent
ownership. Linux DMA mapping and a Linux graphics driver are deferred.

The rename is performed in two independently reviewable Phase 3 changes:
first rename the reserved symbol and all self-owned consumers while keeping
the address inactive; then activate the APB shell. Update canonical map,
generator consumers, topology tests, firmware discovery, README links, and
publication catalog/prose as applicable. Do not edit generated build products,
third-party identifiers, or substrings such as FPGA. Once all consumers have
moved, do not retain an alias that creates a second GA feature identity.

## Clock, Reset, CDC/RDC, and Lifecycle

| Boundary | Required behavior |
| --- | --- |
| GA2D PCLK | APB, job state, FIFO, arithmetic, DMA and sticky IRQ/error state use `clk_i` / active-low `rst_n_i`. No separate pixel clock or PLL is added. |
| PCLK -> HP data | One dedicated AXI64/ID3 `axi4_async_bridge`; existing Common coordinated FIFOs carry AW/W/B/AR/R. Prefixing to ID7 occurs in HP. |
| Lifecycle controls | PCLK resource requests stop the source; stable idle/block acknowledgements cross with the approved synchronizer/handshake and round trip before ownership changes. |
| HP -> memory targets | Existing CDC, downsizer, guard, and reset paths retain behavior with ID7. GA2D does not modify PHY timing or target timeout policy. |
| Reset release | Each domain uses its existing `rst_sync`; no combinational resource-request signal is wired into a primitive's asynchronous reset pin. |

The wrapper consumes source-domain bridge epoch (8 bits), clear-busy, and
qualified data-ready status in addition to quiesce/resource-reset requests.
It exposes raw IRQ and safe source idle. The integration includes these
signals and the new bridge in flush-busy reduction and the checked
clock/reset inventory. Multi-bit epochs are consumed where the bridge
produces them, not independently synchronized bit by bit into another domain.

Normal resource quiesce/reset follows this order:

1. Assert the PCLK source stop. Reject new START and stop launching additional
   read/write bursts; already-presented VALID and reserved writes still drain.
2. Abandon the remainder of the active job; produce ABORT_DONE only after
   the source accounts for every presented/accepted transaction.
3. Synchronize safe source idle to HP, then block master 8 admission. A
   block request must not prevent the last presented address from handshaking.
4. Wait for HP master idle and a round-trip block acknowledgement before
   asserting combined resource idle/QUIESCED. Changing owner requires both.
5. On release, remove the HP block and qualify its acknowledgement before
   DATA_READY/START can be used again. A stopped job never automatically resumes.

The existing resources' independent/shared-gateway rules are not replaced.
In particular, copying the existing immediate master-block connection for
GA2D would deadlock a presented address and is prohibited.

Resource reset is a drain-and-hold request. It masks routed IRQs in Resource
Controller, stops the job, and holds new starts disabled. It preserves local
first error, terminal status, and progress for diagnosis; a subsequent safe
SOFT_RESET explicitly clears them. Hard PCLK reset clears local state.
Ownership and owner lock remain in Resource Controller and are not reset by
GA2D SOFT_RESET.

During global HP lifecycle/clock changes, the existing controller may block
admission before a source has retired an unaccepted queued request. Its
coordinated global flush, rather than ordinary resource quiesce, invalidates
that transport. GA2D MUST detect the bridge epoch change, fail an active job,
and invalidate stale local work only after the boundary's clear/recovery
protocol completes. It must not wait forever for a response intentionally
discarded by that acknowledged flush. Idle epoch changes are acknowledged
without inventing a failed job. Keep both bridge clocks running through the
handshake; an unresolved stopped clock is a system recovery condition.

Bridge clear-busy becoming zero alone is not proof that the HP crossbar or
target guards have retired old route entries. After any reset/epoch recovery,
the integration MUST establish source recovery and round-trip master-8 idle
before re-arming DATA_READY or clearing RECOVERY_REQUIRED. If a unilateral
PCLK reset left accepted HP-side traffic, keep the source unavailable until
the existing guard/global-recovery path retires or invalidates it. Never
reissue local ID zero into an unresolved old routing context. During ordinary
healthy job execution, DATA_READY does not toggle merely because that job has
an outstanding transaction.

An isolated target remains isolated according to the existing target-guard
contract until hard reset; a GA2D reset cannot reopen it. Unilateral endpoint
reset invalidates old transactions and requires the same reset/epoch recovery
before new work. No warm reset guarantees rollback or preservation of dirty
CPU cache data. Debug halt does not implicitly halt the accelerator; software
must use the explicit stop contract. PCLK reconfiguration is permitted only
after GA2D quiesce, without introducing a new clock-gating policy.

## Errors, Recovery, Security, and Observability

### Error encodings and precedence

| Code | Name | Meaning |
| ---: | --- | --- |
| 0 | NONE | No recorded error. |
| 1 | INVALID_SIZE | Width/height zero. |
| 2 | INVALID_FORMAT | Unsupported used format or operation/format combination. |
| 3 | INVALID_PITCH | Pitch smaller than row bytes or incompatible with pixel alignment. |
| 4 | INVALID_ALIGNMENT | Used base is not pixel aligned. |
| 5 | ADDRESS_OVERFLOW | Full extent calculation exceeds the 32-bit address space. |
| 6 | ADDRESS_RANGE | Used interval is outside a permitted mapped region. |
| 7 | OVERLAP | Destination/input overlap is outside the exact background exception. |
| 8 | AXI_READ | Non-OKAY input response. |
| 9 | AXI_WRITE | Non-OKAY output response. |
| 10 | AXI_PROTOCOL | Unexpected ID, malformed terminal/beat count, or impossible response. |
| 11 | TIMEOUT | No forward progress for TIMEOUT_CYCLES while active. |
| 12 | EPOCH_LOST | Bridge epoch/reset invalidated the active job. |
| 13 | INTERNAL | FIFO conservation, pixel accounting, or state invariant failure. |

Error stages are NONE=0, VALIDATE=1, FOREGROUND=2, BACKGROUND=3,
DESTINATION=4, and LIFECYCLE=5. Record the actual AXI response for codes 8/9;
otherwise response is zero. For address-related validation errors record the
affected plane base; for read/protocol errors record the current transfer byte
address; for B errors record AWADDR; for size/format or lifecycle errors use
zero. Validation checks size, used formats, alignment, pitch, extent overflow,
range, then overlap, in destination/foreground/background order when a check
applies to multiple planes.

First error is time-first. Simultaneous runtime errors select EPOCH_LOST,
AXI_PROTOCOL, AXI_WRITE, AXI_READ, INTERNAL, then TIMEOUT, in that order.
The priority selects diagnostics only: all error paths stop successful
completion. Protocol faults must not index storage with an untrusted ID.

The timeout counter increments only while BUSY and resets on forward progress:
validation advances, an AXI handshake, or a committed pixel-pipeline transfer.
Configuration accesses and IRQ reads do not extend the timeout. Each reset
or accepted START starts a new timeout interval. TIMEOUT_CYCLES is nonzero,
latched at START, and is a watchdog rather than a frame deadline.

An error immediately records STATUS.ERROR and the ERROR event, stops new
bursts, and enters drain. If legal terminal responses arrive, BUSY clears
after safe retirement. A malformed/incomplete response or stopped endpoint
may require coordinated flush/hard reset; until the old epoch is proven
obsolete, BUSY/RECOVERY_REQUIRED must not falsely imply reusable buffers.
The local watchdog does not synthesize bus responses or silently reset the
shared fabric. Software timeout alone never licenses a VALID withdrawal.

Software reads status and first error, requests ABORT if work remains, and
uses bounded abort wait. On successful drain it may snapshot progress, repair
the cause, clear events/error or reset, and resubmit a complete job. If drain
cannot complete, LP management uses the existing platform recovery path;
buffers remain owned until recovery establishes no further writes are
possible. Any target bytes written before an error or abort are potentially
modified; no atomic frame update or retry-in-place guarantee is made.

### Counters and snapshots

All byte, cycle, and stall counters are unsigned saturating 64-bit values;
LINES_DONE saturates at 65535. Counters clear on accepted START, increment
while BUSY including validation/drain, and freeze at safe termination. Read
bytes count only logical lanes of accepted, correctly identified OKAY read
beats; write bytes advance only for a successful B response and equal that
burst's asserted strobes. A failed B may still have changed memory, so the
acknowledged byte count is not a rollback map. LINES_DONE advances only after
all write responses for a destination row have succeeded.

Read stalls count a cycle once if ARVALID&&!ARREADY or RVALID&&!RREADY;
write stalls count a cycle once if AWVALID&&!AWREADY, WVALID&&!WREADY, or
BVALID&&!BREADY. PIPE_STALL counts processing cycles with required pixels
remaining but missing operands or output space. These counters can overlap
and are not additive job-time partitions; response latency with RVALID/BVALID
low appears in total cycles, not these handshake-stall counters.

PERF_SNAPSHOT captures all live counters atomically as observed immediately
before the command's acceptance edge; counter increments on that edge belong
to the next snapshot. Reads remain stable until another snapshot or soft/hard
reset. A new START clears live counters but preserves the previous read bank
until software snapshots again. This permits a consistent low/high read on
RV32 without stopping an active job.

### Security and claim boundary

Trusted privileged LP/HP software is the MVP caller. Resource ownership
coordinates jobs and IRQ routing; it is not proof that an APB requester is
the owner. Immutable master-prefix construction and fabric target/attribute
rules remain mandatory. A malformed job cannot authorize MMIO or XPI writes.
This MVP adds no per-process ACL, IOMMU, secure world, authenticated command
queue, cache snooping, fault-tolerant safety path, or functional-safety claim.
Local diagnostics do not qualify the PDK, external memory, or vendor CPU.

## MVP and Commercial-grade Roadmap

The exact MVP is Phases 1..6: expanded platform, renamed/active APB shell,
one direct job, private AXI64 2D DMA, four color formats plus input A8,
opaque composition, complete interrupt/HAL/recovery contracts, and measured
system/physical evidence. Stage capability bits make partial implementations
discoverable. A shell, a successful picture, or a green behavioral CI alone
does not complete the MVP.

Measured performance uses the following minimum logical traffic model:

| Workload | Effective traffic / output pixel |
| --- | ---: |
| RGB565 fill | 2 bytes |
| RGB565 copy | 4 bytes |
| RGB888 -> RGB565 conversion | 5 bytes |
| ARGB8888 foreground + RGB565 background -> RGB565 | 8 bytes |
| A8 foreground + RGB565 background -> RGB565 | 5 bytes |

At 800x480 and 60 complete compositions/second, the fourth case alone needs
184.32 MB/s, before display scanout, transaction overhead, or competitors.
This arithmetic is a traffic requirement, not an achieved performance number.
AXI64 does not establish external-memory throughput. Measure PCLK, HP,
memory-root, and SDRAM-pad clocks separately; the current memory root and
the SDRAM controller's additional divider must not be conflated.

The target commercial architecture grows from this same memory-to-memory
interface in this order: LVGL drawing backend and software fallback;
versioned job queues and interrupt coalescing; separately approved geometric
operations and additional formats; then broader platform/software packaging
and qualification. Each extension requires a new approved phase/spec update.
No command queue encoding, stream ABI, or future opcode is implemented under
the MVP's reserved bits. Do not repurpose frozen phase IDs to insert work.

## Verification and Software Validation

### Traceability and acceptance matrix

| Evidence ID | Requirements | Required evidence |
| --- | --- | --- |
| GA2D-V01 | 001..005 | Canonical map/topology parity, all old allocations retained, GA2D slot/IRQ/resource/master unique, legacy MPW user vector not widened. |
| GA2D-V02 | 004, 014 | Real Hazard3 external interrupt entry, handler and mret; ordinals 0/15/16/29/30/31/32/61, invalid 62, priority/masking, no-handler masking, timer/software coexistence, CSR-disabled build. |
| GA2D-V03 | 002, 003, 010 | Master 8 read/write across each allowed target; interleaved old/new global IDs, invalid prefixes, data lane conservation, independent R/W, all denial paths and first-fault attribution. |
| GA2D-V04 | 006..009 | Independent software golden model for every legal operation/format combination, exact layout/rounding, A8, odd widths, pitches, maximum geometry arithmetic, and conservative overlap rejection. |
| GA2D-V05 | 009, 010 | Guard bytes around every row; every legal pixel offset modulo 8, 1/2/4/8-byte read edges, RGB888 beat/page splits, 1/15/16-beat boundaries, 4 KiB and mapped ends, no padding reads or writes. |
| GA2D-V06 | 006, 012, 014, 019 | APB wait/response stability, held access executes once, all write strobes, invalid/RO/reserved access, busy protection, stage capabilities, handwritten parity, IRQ_TEST isolation, W1C/new-event races. |
| GA2D-V07 | 010..012, 019 | Random independent AW/W/B/AR/R delays; malformed ID/RLAST/count, SLVERR/DECERR, watchdog expiry, simultaneous errors, no DONE on failure, actual FIFO/byte accounting. |
| GA2D-V08 | 005, 011, 015 | Abort/quiesce/reset at every transaction state, presented-but-not-accepted addresses, both source/destination unilateral reset, epoch/late-response isolation, stopped clocks, HP clock/lifecycle switching. |
| GA2D-V09 | 004, 005, 012 | DONE/ERROR/ABORT routing to LP32 or HP11 exclusively, pending handoff, reset masking, owner lock/illegal handoff, unchanged LP29 fault behavior. |
| GA2D-V10 | 014, 015 | LP/HP acceptance payloads, cache-line edge ownership, CBO clean/invalidate plus fences, bounded waits, no reclaim on timeout, in-place background ownership. |
| GA2D-V11 | 010..013 | Assertions/formal for stability, FIFO bounds/reservation, one R/W owner, terminal isolation, set dominance, prefix routing and stop/drain. Liveness claims list target/clock fairness assumptions and proof bounds. |
| GA2D-V12 | 017, 018 | Small rectangles, long/short rows, 320x240/480x272/800x480, contiguous/strided buffers, no-stall and real-memory tests; record MB/s, pixels/s, job latency and LP/HP CPU cost. |
| GA2D-V13 | 003, 005, 017 | Contention with CPU, central DMA, JPEG, APU, USB/SDIO and memory refresh; competitors must actually make progress, with no new starvation or ownership regression. |
| GA2D-V14 | 013..019 | Owned style/lint, C policy/host tests, product firmware, Verilator/Icarus, full affected regression, synthesis/STA/netlist reports and readiness/evidence review. |

The golden model MUST be independent of the RTL expression arrangement.
Use exact byte comparisons; CRC is only a compact smoke verdict. Exhaustively
check all RGB565 values through expansion/repacking and all pixel/global-alpha
pairs for the effective-alpha formula; use boundary and randomized channel
operands for blending. Include alpha 0, 1, 127, 128, 254, 255 and diagnostic
color ramps. Large-dimension invalid jobs test arithmetic without allocating
impossible full frames. Valid maximum counters can be tested with constrained
models, but successful large-image throughput claims need corresponding runs.

Directed Verilator/Icarus tests and constrained-random AXI scoreboards are
required. A repeatable randomized campaign uses at least ten recorded seeds
and 10,000 small jobs in aggregate. Formal covers must reach success, error,
and abort; vacuous proofs and skipped simulator tests do not count as passes.
Injecting reset does not excuse dropping an active transfer before the
specified reset/epoch boundary.

Pure address/format/rounding validation belongs in host-testable C helpers
and `tests/c/test_runtime.c`. Software remains freestanding and follows
MISRA C:2012 Amendment 2 within the repository ownership policy. This freeze
adds no MISRA deviation; any Required-rule deviation needs its normal reviewed
record during implementation.

LP tests use the existing `ci_smoke` composition with `HAVE_CSR=YES`; longer
measurements use `benchmark`. HP tests use the existing HP boot/mailbox test
transport and the committed HP profile, with a focused GA2D acceptance payload.
This does not require or claim a Linux graphics driver. Completion is the
SYSCTRL TEST_STATUS/SIM_TEST_PASS contract with command success and no failure
markers, not a UART banner. Pin-level memory paths remain part of directed
and Icarus coverage when fast-flash is used for firmware runtime.

## Synthesis, Timing, and Physical Evidence

The primary profile is `configs/ci/ihp130.mk`, PRODUCT, 32 KiB on-chip SRAM,
with the locked tool/PDK inputs. Keep the existing PCLK 20.833333333 ns
(48 MHz) STA constraint and the established LP/HP/memory constraints from
the clock inventory; do not weaken them to make a new path pass. Reset-time
PCLK simulation may be slower. A no-stall one-pixel/PCLK pipeline target
does not imply operation at an unverified higher clock.

Collect both isolated GA2D and full-SoC evidence, separating GA2D costs from
LP interrupt and fabric expansion costs: cell count/area, register and FIFO
mapping, unintentional latches/black boxes, enable/reset implementation,
critical paths, WNS/TNS, high-fanout/reset paths, and runtime/resource use.
Use the same revision, PDK, configuration digest, and build timestamp when
comparing recipes. The full product must be analyzed, including wider ID and
interrupt routing. Report unclosed timing honestly; it blocks a frequency or
verified-readiness claim rather than authorizing a new timing contract.

The existing implementation workflow's final IHP130 command is:

```sh
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

Allow its Yosys run up to 180 minutes before declaring timeout; permit the
runner to continue through STA, warning, and metric stages. Its boot-only
netlist marker `Hello retroSoC!` is explicitly limited to boot evidence.
GA2D still requires a dedicated synthesized-block transaction test with exact
result checks; boot-only execution is not a GA2D netlist functional test.
Use the existing full terminal-status netlist flow where practical for the
complete product and label its scope accurately.

Hosted CI currently uses behavioral-only regression and cannot supply the
missing synthesis, netlist, or STA evidence. `make regress-pr` covers the
four committed PDK matrices; IHP130 is primary and ICS55 commercial model
limitations must be reported. Use `make regress-nightly` for the extended
IHP130 coverage. Warning regeneration is separate reviewed work and metrics
remain in observe mode; this feature does not promote policy to a global gate.

CDC/RDC structural inventory and assertions are required MVP evidence, but
signoff CDC/RDC, MMMC/PVT, placement/routing, extracted parasitics, clock tree,
DFT/scan/MBIST, power isolation/retention, activity-based power, and board/silicon
characterization remain commercial delivery gaps. No mW or mm2 target is
invented from a different vendor's process or marketing figures.

## Development Order

Each phase requires its own implementation preflight and approval. High-risk
interrupt/fabric/reset changes retain the repository's human plan gate.
The names below are frozen. Later inserted work receives a new phase ID with
explicit dependencies, never a renumbering of these phases.

Commands run from the repository root. Paths/targets called **new** below are
deliverables of the named phase and do not exist at Phase 0. No command block
is evidence that a command has already run.

### Phase 0 - Freeze GA2D Architecture and ABI

ID: `GA2D-P0`.

Scope: this specification, approved platform allocations, manual ABI, pixel
math, lifecycle, acceptance matrix, stable phases, and documentation links.
Dependencies: explicitly approved research. Changes: documentation and guides
only; freeze future interfaces without changing executable behavior, address
maps, hardware names, software, dependencies, clock inventory, or CI.

Validation: check all local links and documented current commands, validate
current map/topology/dependency/clock inputs read-only, and run:

```sh
git diff --check
python3 scripts/regress.py --root . --suite pr --dry-run
python3 scripts/regress.py --root . --suite nightly --dry-run
```

Completion: every contract area is specified, references distinguish baseline
from future behavior, and remaining delivery gaps are explicit. No RTL
implementation or ready-for-silicon claim is made.

### Phase 1 - Expand LP Interrupt Platform

ID: `GA2D-P1`.

Dependencies: Phase 0. Scope: 64-bit root vector, parameterized management
wrappers/62 external inputs, generated C/SV IRQ metadata, and working Xh3irq
registration/enable/disable/priority/dispatch. Preserve old source numbers,
timer/software behavior, MPW's 32-bit user interface, and CSR-disabled builds.
GA2D bit 32 remains unallocated/low until Phase 3 wiring.

Changes: topology generator/manifest, management wrappers, SDK core interrupt
backend and build inclusion, host/directed/firmware tests, and integration
guide. Public change: LP vector capacity and working external-IRQ APIs. No
GA2D APB activation, DMA, new PLIC, or managed Hazard3 edit is permitted.
Cover actual ISR entry/return and high/bank-edge ordinals, not wiring alone.

Validation includes new `tests/test_lp_irq.py` and its RTL/firmware fixtures:

```sh
make check-soc-topology check-user-extensions check-clock-reset-domains
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q tests/test_lp_irq.py tests/test_soc_topology.py
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-format-check rtl-style-check rtl-lint
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES APP=ci_smoke SIMU=VERILATOR firmware sim
make CONFIG=configs/cluster/mini-mpw.mk SIMU=VERILATOR comp
```

Completion: GA2D-V01/V02 pass for this boundary; all old IRQ mappings and
debug/timer/exception paths remain usable. Report missing synthesis/timing
evidence for the expanded priority encoder; do not change priority width or
reset behavior to avoid a failure.

### Phase 2 - Expand AXI64 Fabric and Resource Integration

ID: `GA2D-P2`.

Dependencies: Phase 1, plus disposition of baseline gap GA2D-GAP-01 before
claiming working JPEG contention. Scope: ninth master, ID7 propagation,
master-8 credit/class/policy, Resource Controller 8 and version discovery,
Fabric Monitor ninth bank/high ID bit, SYSCTRL master readback, and dedicated
GA2D bridge/lifecycle connections with an idle source placeholder.

Changes: self-owned fabric/prefix/width/guard/monitor/system integration,
topology, filelists/export boundaries, resource/monitor HAL mirrors, CDC
inventory and directed tests. Public changes are the frozen master/resource
counts and additive monitor/IRQ metadata. Old memory windows, source values,
target timing, and ownership semantics stay fixed. No GA2D payload or APB
shell becomes functional in this phase.

Validation includes new `tests/test_ga2d_platform.py`, mixed-ID and stop/drain
fixtures, updated handwritten platform parity, and existing tests:

```sh
make check-memory-map check-soc-topology check-clock-reset-domains
python3 -m pytest -q tests/test_axi4.py tests/test_soc_topology.py tests/test_fabric_monitor.py tests/test_ga2d_platform.py
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-format-check rtl-style-check rtl-lint
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES APP=ci_smoke SIMU=VERILATOR firmware sim
```

Completion: GA2D-V01/V03/V08 platform cases pass with master-8 BFM traffic,
old/new IDs cannot alias, the new source has one credit per direction, and
all target/monitor routes retain ID7. Include affected synthesis/STA and
export/netlist evidence; a parameter-only elaboration pass is insufficient.

### Phase 3 - GA2D Naming Migration and APB4 Shell

ID: `GA2D-P3`.

Dependencies: Phase 2. Scope: independently review the reserved GA -> GA2D
rename, then activate slot 28 with the frozen APB shell, resource/IRQ wiring,
identification/status/event controls, unsupported datapath behavior, discovery
HAL, and complete handwritten register mirror. Update publication catalog
and prose during this implementation phase, not during Phase 0.

Public changes: `APB4_GA2D` active at the retained address; LP32/external30,
HP11 and resource8 routing; peripheral raw IRQ bit7; Phase 3 capabilities.
No arithmetic/DMA capability may be set. Controls, counter stubs, read errors,
owner/reset behavior and IRQ_TEST follow the frozen ABI.

Validation includes new `tests/test_ga2d.py`,
`tests/test_ga2d_register_parity.py`, APB and IRQ testbenches:

```sh
make check-memory-map check-soc-topology
python3 -m pytest -q tests/test_memory_map.py tests/test_soc_topology.py tests/test_ga2d.py tests/test_ga2d_register_parity.py
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-format-check rtl-style-check rtl-lint
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES APP=ci_smoke SIMU=VERILATOR firmware sim
```

Completion: GA2D-V01/V06/V09 pass, the reserved rename has no functional
side effect before activation, all new offsets/fields match, and no retired
GA identity or false datapath capability remains in active self-owned users.

### Phase 4 - Two-Dimensional AXI4 DMA and Fill/Copy

ID: `GA2D-P4`.

Dependencies: Phase 3. Scope: private size-aware AXI engine, used-plane
validator, row/burst/pixel-byte cursors, Common FIFO reservations, stop/drain,
epoch/watchdog/error handling, snapshots, FILL/COPY, and bounded HAL calls.
All four color formats support fill/copy including packed RGB888 edges.

Public changes: Phase 4 capability/format values and operation availability;
no register, address, IRQ, resource, clock, or source-ID allocation change.
CONVERT, BLEND, and A8 remain unavailable. Add new
`tests/test_ga2d_dma.py` and the `formal-ga2d` target/production-RTL harness.

```sh
python3 -m pytest -q tests/test_ga2d.py tests/test_ga2d_dma.py tests/test_ga2d_register_parity.py tests/test_ga2d_platform.py
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-format-check rtl-style-check rtl-lint
make CONFIG=configs/ci/ihp130.mk formal-ga2d
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES APP=ci_smoke SIMU=VERILATOR firmware sim
```

Completion: applicable GA2D-V04..V12 pass for fill/copy. Guard bytes stay
unchanged, no read crosses logical rows, source stop cannot deadlock a
presented request, and safe abort/epoch recovery is demonstrated. Include
both no-stall and real-memory initial measurements without claiming final PPA.

### Phase 5 - Pixel Conversion and Alpha Compositing

ID: `GA2D-P5`.

Dependencies: Phase 4. Scope: bit-exact unpack/convert/alpha/pack pipeline,
A8 fixed-color masks, required two-input read scheduling, and exact in-place
background exception. Extend golden model, host math tests, directed and
randomized coverage and the existing GA2D proof harness.

Public changes: final MVP capability/format bits become available. Existing
register/format/opcode/IRQ encodings and clock/CDC allocations do not change.
No transparent-background normalization, premultiplied mode, scaler, vector
renderer, or queue is introduced.

```sh
python3 -m pytest -q tests/test_ga2d.py tests/test_ga2d_dma.py tests/test_ga2d_register_parity.py
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-format-check rtl-style-check rtl-lint
make CONFIG=configs/ci/ihp130.mk formal-ga2d
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES APP=ci_smoke SIMU=VERILATOR firmware sim
```

Completion: all legal operation/format pairs and defined alpha arithmetic
match the independent model byte-for-byte; starvation, FIFO conservation,
in-place ordering and failure isolation tests remain passing. Report
pipeline initiation interval and stalls separately from bus throughput.

### Phase 6 - HAL, System Verification, and IHP130 Evidence

ID: `GA2D-P6`.

Dependencies: Phase 5 and resolution/evidence of applicable baseline gaps.
Scope: complete HAL/host checks, real LP ISR and HP acceptance payloads,
cache/ownership handoff, deterministic benchmark/report artifacts, randomized
campaign, competing-master progress, full regression, and physical evidence.

Changes: tests, SDK/app acceptance and benchmark integration, documentation
and evidence/readiness records justified by results. No frozen allocation,
format, opcode, arithmetic, or lifecycle change is authorized. LVGL and
Linux graphics remain out of scope. Focused issue fixes follow the approved
phase preflight; a redesign returns to feature design.

```sh
make sw-format-check sw-policy-check sw-host-test
python3 -m pytest -q
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR rtl-format-check rtl-style-check rtl-lint
make CONFIG=configs/ci/ihp130.mk formal-ga2d
make CONFIG=configs/ci/ihp130.mk HAVE_CSR=YES APP=ci_smoke SIMU=VERILATOR firmware sim
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
make regress-pr
make regress-nightly
git diff --check
```

Completion: GA2D-V01..V14 have reviewed results, no required simulator check
is skipped, the synthesized GA2D block processes real jobs, and full-product
area/timing/warning results are recorded against the same configuration.
Report every unrun gate or failed target; do not mark Phase 6 complete from
behavioral CI or boot-only netlist success. Physical/silicon commercial gaps
remain explicitly outside the MVP evidence claim.

## Commercial Delivery Gaps

| Gap | Disposition |
| --- | --- |
| GA2D-GAP-01: JPEG admission baseline | At the inspected revision, topology and JPEG integration assign master 6, but `master_read_limit()` / `master_write_limit()` in `axi4_data_crossbar.sv` return zero for 6. This is an existing integration discrepancy, not a free port or a GA2D architecture choice. It does not block Phase 0/1. Route it to the JPEG/fabric diagnosis and approved repair flow before claiming JPEG contention or final platform closure; do not silently absorb a JPEG redesign into GA2D. |
| No GA2D implementation evidence | Phases 1..6 must supply the matrix, artifacts and results. Research arithmetic is not an achieved throughput number. |
| Memory clock/performance characterization | Record actual memory-root and device clocks, refresh/turnaround and active QPI/OPI device configuration. Existing prose about nominal SDRAM frequency is not a measurement; GA2D does not change the PHY to satisfy a benchmark. |
| Portable software integration | LVGL asynchronous drawing/fallback, a versioned queue ABI, Linux DMA/graphics integration and release examples require later approved phases. |
| Verification closure | Reusable protocol VIP, coverage closure, long-duration stress and unbounded liveness evidence are separate from the directed/bounded MVP checks. |
| Physical and technology signoff | CDC/RDC signoff, DFT/scan/MBIST/ECC, MMMC/PVT, clock trees, power analysis, post-layout extraction and board/silicon correlation remain unqualified. |
| Commercial release | License/SBOM review, reproducible release package, integration guide, errata, support ownership and qualification require reviewed product delivery evidence. |

There is no unresolved MVP architecture option. Remaining entries are
implementation evidence or explicitly deferred work. The first implementation
phase is **Phase 1 - Expand LP Interrupt Platform** (`GA2D-P1`); it begins with
a separate read-only implementation preflight, not implicit authorization to
execute all phases together.
