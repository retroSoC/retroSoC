#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"apu",page:here().page()))

==== Audio Processing Unit (APU, partial) <apu>

#ip("apu")

#ip-reference("apu","apu",4,legacy:[
The current APU RTL advertises capability word `0x000001BD` and APB version `0x00010000`. WAV/FLAC transport, job submission and stream paths are integrated; MP3 and KWS are not advertised. Delivery still requires a complete accepted microcode image and the corresponding codec corpus. The later 32 KiB/V1.1 capacity refreeze is not implemented by the current register constants.

])

#context metadata((kind:"ip-end",id:"apu",page:here().page()))
