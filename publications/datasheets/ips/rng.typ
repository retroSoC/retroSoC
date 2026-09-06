#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"rng",page:here().page()))

==== Random Number Generator (RNG) <rng>

#ip("rng")

#ip-reference("rng","rng",4,legacy:[
The integration supplies a deterministic diagnostic source with qualification deasserted.
The controller must retain its fail-closed behavior for unqualified entropy. It cannot be
used as a production cryptographic random source until a qualified PDK entropy source and
the associated validation are integrated.
])

#context metadata((kind:"ip-end",id:"rng",page:here().page()))
