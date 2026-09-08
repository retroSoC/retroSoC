#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"apu",page:here().page()))

==== Audio Processing Unit (APU, partial) <apu>

#ip("apu")

#ip-reference("apu","apu",4,legacy:[
The current APU RTL advertises capability word `0x000001BD`, APB version `0x00010001`, and a 32 KiB control store through `CAPABILITY1=0x01827020`. WAV/FLAC transport, job submission and stream paths are integrated; APUMC V1 images remain loadable, while new P5 release images use APUMC V2. MP3 and KWS are not advertised. Delivery still requires the complete accepted codec image and corresponding production corpus evidence.

])

#context metadata((kind:"ip-end",id:"apu",page:here().page()))
