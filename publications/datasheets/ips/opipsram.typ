#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"opipsram",page:here().page()))

===== OPI PSRAM / HyperBus-Style Controller <opipsram>

#ip("opipsram")

#ip-reference("opipsram","opipsram",5,legacy:[
One controller supports a boot-selected octal DDR transaction profile or a single-clock
HyperBus-style profile. Initialization locks the selected protocol until soft reset. The
128 MiB aperture is addressability, not a device-density commitment. QPI and OPI share memory
pads and must not drive them concurrently.
#note[This is a prototype interface. A specific 3.3 V OPI or single-clock HyperBus-style device
still requires electrical, timing, board and silicon qualification. It is not a blanket claim
of compatibility with every HyperBus device.]
])

#context metadata((kind:"ip-end",id:"opipsram",page:here().page()))
