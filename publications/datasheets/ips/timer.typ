#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

=== Timers

#context metadata((kind:"ip-start",id:"timer",page:here().page()))

==== General-Purpose Timer (TIM0, TIM1) <timer>

#ip("timer")

#ip-reference("timer","timer",4,software-note:[
  #change-start("timer-api-link", "Timer software: delay budget and timeout-stop links", category:"cross-reference")
  #block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
    #text(9pt)[Delay duration versus polling budget, and stop after timeout: @software-timeouts; @api-completion.]
  ]
  #change-end("timer-api-link")
],legacy:[
Both timers support free-running, periodic and one-shot operation, up/down counting and sticky
interrupt status. An optional debug-freeze input stops counting while management Hazard3 is
halted, without preventing register access. No separate TIM2 advanced timer is integrated.
])

#context metadata((kind:"ip-end",id:"timer",page:here().page()))
