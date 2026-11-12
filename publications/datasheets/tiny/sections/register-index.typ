#import "../style.typ": *
= Appendix: Global Register and Address Index <tiny-register-index>
== Tiny Register Instances
The index is ordered by decoded APB address window. Each absolute address appears once; follow the linked
canonical definition for access, reset and side effects. GPIO views and timer instances retain their own
windows. RCU entries are explicitly named inside SYSCTRL and do not create a second decoded aperture.
#for window in data.regions.filter(r=>r.symbol.starts-with("APB4_")) {
 let rows=data.register_index.filter(r=>r.region==window.symbol).sorted(key:r=>r.address)
 if rows.len()==0 {continue}
 [#heading(level:3,window.symbol)#label("index-"+window.symbol)]
 ds-table("index-"+window.symbol,[#window.symbol register instances],([Absolute address],[Register],[Index],[Access]),
  rows.map(r=>(code(r.address),link(label("reg-"+r.family+"-"+r.key),code(if r.ip=="rcu" {"RCU."+r.name} else {r.name})),r.index,r.access)),widths:(1fr,1.9fr,0.4fr,0.85fr))
}
