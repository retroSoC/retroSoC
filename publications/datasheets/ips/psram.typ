#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"psram",page:here().page()))

===== PSRAM Controller (PSRAM) <psram>

#ip("psram")

#ip-reference("psram","psram",5,legacy:[
The QPI controller addresses four ESP-PSRAM64H devices, each 8 MiB. It uses four SDR data pins
and device-specific initialization, recovery and restricted commands. It does not implement
octal PSRAM, DDR/DTR, DQS or generic CPOL/CPHA selection. The QPI data port uses local
AXI64-to-32 adaptation and an HP-to-memory clock crossing.
])

#context metadata((kind:"ip-end",id:"psram",page:here().page()))
