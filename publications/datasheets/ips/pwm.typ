#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"pwm",page:here().page()))

==== Pulse Width Modulation (PWM) <pwm>

#ip("pwm")

#ip-reference("pwm","pwm",4,legacy:[
Four PWM outputs, two capture inputs, a fault input and a synchronization input are routed
through the GPIO alternate-function matrix. The managed V2 implementation includes interrupt
reporting and management-debug halt integration.
Program divider and waveform parameters against the active peripheral clock; a register field
width alone does not establish a qualified output frequency.
])

#context metadata((kind:"ip-end",id:"pwm",page:here().page()))
