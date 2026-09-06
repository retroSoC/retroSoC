#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"monitor",page:here().page()))

==== Fabric Monitor <monitor>

#ip("monitor")

#ip-reference("monitor","monitor",4,legacy:[
The monitor observes accepted requests, beats, waits, outstanding high-water marks, aging,
timeouts, isolation and warm flushes. Saturating counters are read through explicit snapshots.
Sticky first-fault attribution keeps source identity and decoded target information. Monitoring
does not alter arbitration or admission policy.
])

#context metadata((kind:"ip-end",id:"monitor",page:here().page()))
