#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"crc",page:here().page()))

==== Cyclic Redundancy Check (CRC) <crc>

#ip("crc")

#ip-reference("crc","crc",4,legacy:[
CRC V2 supports 7-, 8-, 16- and 32-bit widths, programmable polynomial, initial/final XOR,
input/output reflection and byte order. Software or system DMA supplies data; the block has
no private memory master or interrupt. CRC is a data-integrity primitive, not encryption or
authentication. Firmware must use the parameters required by its file, packet or boot format.
])

#context metadata((kind:"ip-end",id:"crc",page:here().page()))
