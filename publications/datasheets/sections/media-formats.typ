#import "../style.typ": *

==== Data Formats and Peripheral Interoperability <media-interoperability>
Matching names such as RGB565, YUV422 or PCM are only the beginning of an interoperability
check. Compare the exact byte order, container width, stride, alignment, stream boundary and
software lifetime. A shared address space does not convert formats or make an unavailable
transport usable.

#ds-table("media-format-layouts",[Media representations and their storage/stream boundaries],
  ([Representation],[Layout],[Boundary / integration check]),
  data.system_reference.product_details.formats.map(r=>(r.title,r.layout,r.boundary)),
  widths:(1fr,1.45fr,1.7fr))

JPEG raster strides are byte strides and must cover the logical row. Its input/output
addresses and descriptor layout have their own alignment requirements; central-DMA word
alignment is not a substitute. The listed JPEG raster formats describe the codec contract,
while normal SoC private-DMA admission is currently blocked at the native slot documented in
@bus-programming.

The DVP core packs two completed 16-bit pixels per 32-bit word, with the first pixel in the
lower half. Its FIFO also carries framing/byte-qualification metadata. That metadata is not
automatically appended to a memory image by central DMA. Configure camera byte order and the
documented swap controls, then verify a known pattern before handing buffers to a consumer.

===== Source-to-consumer compatibility
#ds-table("media-interoperability",[Format compatibility and actual integration gates],
  ([Composition],[Classification],[Conditions and remaining work]),
  data.system_reference.product_details.interoperability.map(r=>(r.title,r.classification,r.condition)),
  widths:(1.1fr,0.7fr,2.35fr))
"Format-compatible" means the representations can agree under the stated conditions. It is
not a board or full-application pass. "Conversion required" identifies a software transformation
that is not performed by the interface itself. "Blocked" identifies an active implementation
limitation even if the layouts could otherwise match.

===== Buffer preparation and verification
+ Choose source and destination formats explicitly, including component order and per-row stride.
+ Calculate allocation using the actual stored containers and alignment, as in @software-memory-budget.
+ Prepare a small known pattern with distinguishable channels/components. Check the produced
  memory bytes and consumer interpretation before enabling sustained traffic.
+ Preserve frame/line metadata in software when the consumer needs it. Do not interpret every
  TLAST as a frame boundary: DVP uses line boundaries, while I2S RX does not assert TLAST.
+ Transfer buffer ownership with the required fences/cache operations and release it only after
  confirmed completion or completed recovery.

For an odd-pixel camera row, the final stream beat is partial; the current central DMA requires
full-word qualification. Treat that as an unsupported DMA configuration, not harmless padding.
For packed 24-bit audio files, place each sample in the correct low 24 bits of a 32-bit container;
copying three-byte file data directly into a word-stream DMA buffer changes the sample layout.

No automatic RGB/YUV colorspace conversion, sample-rate conversion, codec activation or
frame-ring service is implied by this overview. The current JPEG admission and APU production-job
limitations remain binding. A transport failure and a format mismatch require different recovery:
stop the producer, preserve errors and ownership, and discard or explicitly repair the affected
buffer rather than passing partially valid data onward.
#source-note("rtl/ip/multimedia/dvp_core.sv",title:"Actual DVP pixel packing and framing")
#source-note("crt/src/hal/i2s_math.c",title:"I2S sample-container helpers")
#source-note("docs/ip/jpeg.md",title:"JPEG raster formats, strides and alignment")
#source-note("docs/ip/apu.md",title:"APU transport and production availability boundary")
