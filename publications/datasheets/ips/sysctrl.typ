#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"sysctrl",page:here().page()))

==== System Controller (SYSCTRL) <sysctrl>

#ip("sysctrl")

#ip-reference("sysctrl","sysctrl",4,legacy:[
Root-controlled registers manage lifecycle and faults. Automated firmware reports completion
through TEST_STATUS: bit 31 is valid, bit 0 is pass and bits 15:8 hold the result code.
The first valid full-word write is sticky until reset. UART startup output is diagnostic,
not the acceptance verdict.
])

#context metadata((kind:"ip-end",id:"sysctrl",page:here().page()))
