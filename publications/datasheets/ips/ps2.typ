#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"ps2",page:here().page()))

==== Personal System/2 (PS2) <ps2>

#ip("ps2")

#ip-reference("ps2","ps2",4,legacy:[
GPIO0/1 ALT1 route PS/2 clock/data. The integration binds input sensing and active-low drive
behavior for an open-drain bus. External pull-ups are required. Before changing GPIO ownership,
firmware disables the controller and confirms that both output enables are released.
])

#context metadata((kind:"ip-end",id:"ps2",page:here().page()))
