#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"jpeg",page:here().page()))

==== JPEG Encoder / Decoder <jpeg>

#ip("jpeg")

#ip-reference("jpeg","jpeg",4,legacy:[
The block implements 8-bit Baseline Sequential JPEG for images up to 2048 × 2048. Encoding and
decoding are mutually exclusive in one instance. Direct jobs and a scatter-gather ring use a
private 64-bit DMA master. Resource ownership, interrupts and bounded error completion are
part of the integration. Progressive JPEG and a sustained video-rate claim are not specified.
])

#context metadata((kind:"ip-end",id:"jpeg",page:here().page()))
