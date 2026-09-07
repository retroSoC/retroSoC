#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"rcu",page:here().page()))

==== Reset Clock Unit (RCU) <rcu>



#ip-reference("rcu","rcu",4,shared:"sysctrl",register-family:"sysctrl",legacy:[
RCU functionality is accessed through system control and the clock/reset subsystem rather
than an additional standalone APB window. Clock switching, safe fallback and qualification
limits are described in the Clock and Reset section.
#source-note("docs/pll-clock-control.md")
])

#context metadata((kind:"ip-end",id:"rcu",page:here().page()))
