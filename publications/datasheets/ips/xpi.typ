#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

== Peripherals
Each IP chapter begins on a new page. Shared register layouts are documented once and linked from related instances.

=== Memory Interface

==== Non-Volatile Memory (NVM)

#context metadata((kind:"ip-start",id:"xpi",page:here().page()))

===== XPI Universal Controller (XPI) <xpi>

#ip("xpi")

#ip-reference("xpi","xpi",5,legacy:[
XPI V2 supports programmable command sequences, SDR serial phases and independent chip-select
configuration. The command LUT supports serial flash reads and indirect transfers without
embedding one device's opcode sequence into software-visible hardware policy. Memory reads,
command programming, DMA and status polling share a controlled transaction engine.

The boot alias begins at address zero. The main XPI data aperture is 256 MiB, while the boot
alias is 16 MiB; these are decoder windows, not fitted flash capacities. Data-plane writes are
denied. Firmware uses indirect transactions for flash programming and erase. DTR and a qualified
maximum SCK are not specified for this implementation.
])

#context metadata((kind:"ip-end",id:"xpi",page:here().page()))
