#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"sdram",page:here().page()))

===== SDRAM Controller (SDRAM) <sdram>

#ip("sdram")

#ip-reference("sdram","sdram",5,legacy:[
The fixed x16 SDR geometry has two bank bits, thirteen row bits and ten column bits. The
controller tracks open rows, accepts native bursts and exposes programmable timing values in
SDRAM-clock cycles. AXI64 crosses into the stable memory domain before local 64-to-32 adaptation.
Firmware must initialize the device and program timings for the fitted part before use.
])

#context metadata((kind:"ip-end",id:"sdram",page:here().page()))
