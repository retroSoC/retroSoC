#import "../style.typ": *

#import "../ip-reference.typ": ip-reference
#import "../diagram-packages.typ": apu-instruction-diagram, apu-family-figures

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"apu",page:here().page()))

==== Audio Processing Unit (APU, partial) <apu>

#ip("apu")

#ip-reference("apu","apu",4,functional-note:[
  #block(breakable:false)[
    #figure(apu-instruction-diagram(),kind:image,supplement:[Figure],caption:[APU 64-bit internal microcode fields and source-encoded examples.])<apu-instruction-layout>
    #source-note("scripts/apu_isa.py",title:"Instruction fields and encode/decode definitions")
    #source-note("rtl/ip/multimedia/apu_microcode_pkg.sv",title:"RTL instruction slices and legal-encoding checks")
  ]
  #apu-family-figures()
],legacy:[
The current APU RTL advertises capability word `0x000001BD` and APB version `0x00010000`. WAV/FLAC transport, job submission and stream paths are integrated; MP3 and KWS are not advertised. Delivery still requires a complete accepted microcode image and the corresponding codec corpus. The later 32 KiB/V1.1 capacity refreeze is not implemented by the current register constants.

])

#context metadata((kind:"ip-end",id:"apu",page:here().page()))
