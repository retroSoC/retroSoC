#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"gpio",page:here().page()))

=== General-Purpose Input Output (GPIO) <gpio>

#ip("gpio")

#ip-reference("gpio","gpio",3,legacy:[
Software controls per-pin mode, output data, output enable, open-drain behavior, input filtering
and interrupt configuration. Alternate-function and user-IP paths share the same 32 physical
GPIOs. Atomic set/clear/toggle operations avoid software read-modify-write races.

==== System IO / Management Window
The administration window owns pad mode, electrical controls, filters, user access masks and
configuration locks. The user access mask resets to zero. Configuration ownership and lock
semantics apply to the single controller; this window is not a separate GPIO bank.

==== User Custom IO / User Window
The restricted window exposes only the data and interrupt operations permitted by the
management mask. MPW user-IP handoff uses the same ownership boundary. The old GPIO0/GPIO1
section names must not be interpreted as two independent sets of pads. See @gpio-mux for
the generated alternate-function matrix.
])

#context metadata((kind:"ip-end",id:"gpio",page:here().page()))
