#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"resource",page:here().page()))

==== Resource Controller <resource>

#ip("resource")

#ip-reference("resource","resource",4,legacy:[
*Ten resources* are managed: central DMA, USB2, SDIO0, SDIO1, SPI-SD, EXT-H, JPEG,
APU, GA2D and NPU. Resource ABI 1.2 reports ten slots. Resource 9 owns the native-HP
NPU, including LP vector 33 / HP PLIC 12 steering. Resource 8 routes the GA2D
its IRQ according to its current owner and controls its private AXI64 lifecycle.
GA2D supports FILL, COPY, bit-exact CONVERT, opaque alpha BLEND, A8 fixed-color
foreground masks, and exact equal background/destination in-place composition.
RGB565, RGB888, XRGB8888, and ARGB8888 are color surfaces; A8 is BLEND
foreground-only. Snapshots, pitch, and byte edges remain available. It does not
provide transparent-background/premultiplied-alpha modes, scaling, rendering,
descriptor/ring/queue submission, hardware cache coherency, or a Linux graphics driver.
Ownership changes require *quiesce, completion of accepted traffic and cache-maintenance
handoff*. HP can inspect allowed status but *cannot take over root writes*. An ownership grant
does not bypass the target access policy or EXT-H address bounds.
])

See @ga2d for the independent 2D engine programming, format and register reference.
See @npu for descriptor execution and the distinction between coordinated clock pause,
resource quiesce and cancellation/drain.

#context metadata((kind:"ip-end",id:"resource",page:here().page()))
