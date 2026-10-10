#import "../style.typ": *

#import "../ip-reference.typ": inline, subhead
#import "../diagram-packages.typ": circuit-diagram

#pagebreak(weak:true)

==== HP Interrupt and Mailbox Platform <hp-platform>

#context metadata((kind:"ip-start",id:"hp-aclint",page:here().page()))

===== HP Local Interrupt Controller (ACLINT) <hp-aclint>

#let chapter=data.chapters.at("aclint")
#let r=data.regions.find(r=>r.symbol=="HP_C906_SYS")

The HP local timer and software interrupt function is *internal to the OpenC906 core*: the core
BIU decodes the T-Head c900 CLINT layout inside the reserved system window at #code(r.base_hex)
(size #r.size_label), which never appears as a SoC fabric target. This chapter therefore has
*no SoC register table*; register-bit detail follows the T-Head C906 manuals, which remain
outside this publication's scope together with the CPU ISA/CSR manuals.

#subhead("hp-aclint","Features and Block Diagram",5)
#list(..chapter.at("features",default:()).map(inline))
#block(breakable:false)[
    #figure(circuit-diagram("hp-aclint"),kind:image,supplement:[Figure],caption:[#chapter.title integration boundary.])
    #label("circuit-hp-aclint")
  ]

#subhead("hp-aclint","Functional Description",5)
#for paragraph in chapter.notes { par(inline(paragraph)) }

#subhead("hp-aclint","Software",5)
#enum(..chapter.software_steps.map(inline))
#block(breakable:false)[
  #set text(size:9pt)
  #source("rtl/mini/top/hp_core_wrapper.sv",title:"Internal window and time/counter wiring") ·
  #source("app/ports/linux/opensbi/retrosoc_hp/platform.c",title:"OpenSBI MSWI and timer device") ·
  #source("app/ports/linux/linux/retrosoc_hp.dts",title:"thead,c900-clint declaration")
]

#context metadata((kind:"ip-end",id:"hp-aclint",page:here().page()))
