#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

=== Product Extension Slots

#context metadata((kind:"ip-start",id:"ext-l",page:here().page()))

==== Low-Bandwidth Extension (EXT-L) <ext-l>

#ip("ext-l")

#ip-reference("ext-l","ext-l",4,shared:"ext-h",register-family:"extensions",legacy:[
EXT-L is a fixed APB4 control slot with one interrupt. Its current capability declaration has
no data master, stream interface or local SRAM.
])

#context metadata((kind:"ip-end",id:"ext-l",page:here().page()))
