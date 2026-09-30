#import "../style.typ": *

#let ga2d-functional() = [
  #minor-title("Operation and surface contract")
  #ds-table("ga2d-operations",[GA2D P5 operations and admitted surfaces],
    ([Operation],[Inputs],[Destination and boundary]),
    (([FILL],[COLOR; foreground/background surfaces unused.],[Any supported color format; fill alpha follows COLOR for ARGB8888.]),
     ([COPY],[One color foreground.],[Same format as foreground; byte-preserving, *no overlapping source/destination*.]),
     ([CONVERT],[One color foreground.],[Any supported color format; bit replication on RGB565 expansion and high-bit truncation on packing.]),
     ([BLEND],[Color foreground or A8 mask; opaque color background.],[Color destination. Background may equal destination only with *identical address, pitch and format*.])),
    widths:(0.6fr,1.3fr,2.3fr))
  RGB565 stores red in bits 15:11, green in 10:5 and blue in 4:0. RGB888 stores bytes R, G, B
  in increasing memory addresses. XRGB8888 and ARGB8888 store bytes B, G, R, X/A. Conversion
  to XRGB8888 writes X as 255; COPY preserves the original bytes. Conversion retains input
  alpha only for ARGB8888-to-ARGB8888 and otherwise supplies opaque alpha.

  #minor-title("Opaque alpha arithmetic")
  Let #code("Af") be foreground alpha (255 for RGB/XRGB or the mask byte for A8),
  #code("Ag") the global alpha, and #code("F")/#code("B") one foreground/background color channel:
  #code-block(raw("A = floor((Af * Ag + 127) / 255)\nC = floor((F * A + B * (255 - A) + 127) / 255)",block:true))
  The two rounding steps are separate. *A8 supplies alpha only* and takes foreground RGB from
  COLOR. Background alpha is not accumulated; BLEND writes opaque destination alpha.
  #source-note("rtl/ip/multimedia/ga2d_pixel.sv",title:"Implemented byte packing and two-stage alpha rounding")

  #minor-title("Bounded surface example")
  Eight RGB888 pixels occupy 24 bytes per row. A 32-byte pitch leaves eight padding bytes;
  with two rows, the exclusive access envelope ends at base + 56, rather than at base + 64.
  COPY/CONVERT/BLEND access the logical pixel bytes and preserve row padding. Distinct
  foreground and destination envelopes remain required; this is an illustrative layout,
  not a DMA descriptor or a reserved memory allocation.
  #source-note("rtl/ip/multimedia/ga2d_core.sv",title:"Surface geometry, allowed ranges and overlap checks")
  #minor-title("P6 integration and evidence boundary")
  The existing operation/register subset is retained. P6 adds wider directed and randomized
  campaigns, owner-routed interrupt/cache handoff, contention and recovery tests, and block
  physical-flow entrypoints. The benchmark now distinguishes CPU time, PCLK engine time,
  useful pixels and bus traffic across operations, geometry and strides. See
  @performance-characterization and @release-verification for the dated reports and remaining
  gaps; the historical composition target and slow-corner block timing were not achieved.
  Current-source sustained performance and full-product physical closure require matching
  raw artifacts. No queue, scaling, rotation or Linux graphics driver is added by this record.
  #source-note("tests/rtl/ga2d_platform_tb.sv",title:"Platform contention and lifecycle test cases")
  #source-note("docs/ip/ga2d.md",title:"Dated P6 implementation/evidence record")
]

#let ga2d-protocol() = [
  #minor-title("Admission, completion and recovery")
  Configuration is staged through APB4 and latched for one accepted job. START requires a
  ready data path, idle engine and valid geometry; BUSY is *not a queue-space indicator*.
  Completion is reported after the engine's accepted read/write obligations have completed.
  #ds-table("ga2d-recovery",[GA2D completion and recovery decisions],
    ([Observation],[Required software action]),
    (([DONE with no error],[Capture counters, acknowledge the owner IRQ, and transfer destination ownership before CPU reads.]),
     ([Software polling timeout],[*Do not reuse the buffers*. Request abort and wait for accepted bus traffic to drain.]),
     ([ERROR or ABORT_DONE],[Capture first-error code, stage, AXI response and address; verify busy/draining state before release.]),
     ([RECOVERY_REQUIRED or bridge epoch change],[Coordinate resource/HP recovery, wait for the bridge clear and DATA_READY rearm, then establish ownership again.]),
     ([PCLK/HP lifecycle transition],[Block new work, stop/drain, complete bridge flush and acknowledge the new epoch; source idle alone is insufficient.])),
    widths:(1fr,2.8fr))
  #source-note("rtl/ip/multimedia/apb4_ga2d.sv",title:"APB wrapper, bridge epoch and resource lifecycle")
  #source-note("crt/src/hal/ga2d.c",title:"HAL timeout, abort and recovery behavior")
]
