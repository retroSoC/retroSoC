#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"monitor",page:here().page()))

==== Fabric Monitor <monitor>

#ip("monitor")

#ip-reference("monitor","monitor",4,functional-note:[
  #minor-title("Master counter-bank selection")
  #let bank=data.registers.monitor.groups.find(g=>g.id=="master")
  #ds-table("monitor-master-selection",[Ten implemented master snapshot banks; offsets relative to the monitor window],
    ([Index],[Initiator],[Bank base]),
    data.policies.map(p=>(str(p.index),code(p.name),code("0x"+str(bank.base+p.index*bank.stride,base:16)))),
    widths:(0.35fr,2fr,0.85fr))
  Each bank contains the eight relative counter offsets in the register summary. Master 9
  is the NPU and occupies #code("0x220..0x23F"). A successful snapshot captures all ten banks;
  live collection can continue while software reads that stable view. The monitor counts
  admitted transactions and wait events; it does not establish a latency or throughput guarantee.
  #source-note("rtl/mini/top/soc_data_plane.sv",title:"Instantiated master count and monitor connections")
],legacy:[
The monitor observes accepted requests, beats, waits, outstanding high-water marks, aging,
timeouts, isolation and warm flushes. Saturating counters are read through *explicit snapshots*.
*Sticky first-fault attribution* keeps source identity and decoded target information. Monitoring
does not alter arbitration or admission policy.
])

#context metadata((kind:"ip-end",id:"monitor",page:here().page()))
