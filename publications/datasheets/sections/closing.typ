#import "../style.typ": *

// A separate page scope keeps the normal running furniture on every body page.
#page(paper:"a4", margin:(x:19mm,top:21mm,bottom:24mm),
  header:none, footer:none, numbering:none)[
  #context metadata((kind:"publication-closing-start",page:here().page(),
    total_pages:counter(page).final().first()))
  #change-start("closing-page","Independent closing page",category:"added")
  #v(1fr)
  #block(width:100%,breakable:false)[
    #set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
    #set par(leading:rhythm.small-leading,spacing:5pt)
    #rect(width:60mm,height:14mm,fill:white,stroke:0.6pt + gold)
    #v(7mm)
    #block(below:6pt)[
      #text(13pt,weight:"semibold")[Disclaimer and Copyright Notice]
    ]
    This document describes the reviewed retroSoC Mini implementation and is subject to change.
    DRAFT status does not establish production availability, electrical ratings or qualification.

    Use and redistribution of retroSoC project material are governed by the Mulan Permissive
    Software License, Version 2 (Mulan PSL v2). Refer to the project LICENSE for the complete
    terms, including its disclaimer of warranty and limitation of liability.

    Third-party IP, software, fonts and other materials retain their respective licenses.
    Trademarks and product names belong to their respective owners.

    #text(weight:"semibold")[Copyright (c) 2023-2026 Yuchi Miao]

    #link("https://github.com/retroSoC/retroSoC")[https://github.com/retroSoC/retroSoC]
  ]
  #change-end("closing-page")
  #context metadata((kind:"publication-closing-end",page:here().page(),
    total_pages:counter(page).final().first()))
]
