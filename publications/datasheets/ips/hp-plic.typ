#import "../style.typ": *

#import "../ip-reference.typ": inline, subhead
#import "../diagram-packages.typ": circuit-diagram

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"hp-plic",page:here().page()))

===== HP Platform-Level Interrupt Controller (PLIC) <hp-plic>

#let chapter=data.chapters.at("plic")
#let r=data.regions.find(r=>r.symbol=="HP_C906_SYS")

The HP external interrupt controller is *internal to the OpenC906 core*: the core BIU decodes
the T-Head c900 PLIC layout at the base of the reserved system window at #code(r.base_hex)
(size #r.size_label), which never appears as a SoC fabric target. This chapter therefore has
*no SoC register table*; register-bit detail follows the T-Head C906 manuals, which remain
outside this publication's scope together with the CPU ISA/CSR manuals.

#subhead("hp-plic","Features and Block Diagram",5)
#list(..chapter.at("features",default:()).map(inline))
#block(breakable:false)[
    #figure(circuit-diagram("hp-plic"),kind:image,supplement:[Figure],caption:[#chapter.title integration boundary.])
    #label("circuit-hp-plic")
  ]

#subhead("hp-plic","Functional Description",5)
#for paragraph in chapter.notes { par(inline(paragraph)) }

#subhead("hp-plic","Software",5)
#enum(..chapter.software_steps.map(inline))
#block(breakable:false)[
  #set text(size:9pt)
  #source("rtl/mini/top/hp_core_wrapper.sv",title:"Source wiring into the core") ·
  #source("rtl/mini/top/apb4_periph.sv",title:"SoC external source assignments") ·
  #source("app/ports/linux/linux/retrosoc_hp.dts",title:"thead,c900-plic declaration")
]

#context metadata((kind:"ip-end",id:"hp-plic",page:here().page()))
