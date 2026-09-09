#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"wdg",page:here().page()))

==== Watchdog (WDG) <wdg>

#ip("wdg")

#ip-reference("wdg","wdg",4,legacy:[
The watchdog remains clocked independently of the APB register domain. Early-warning IRQ14
allows software intervention before the reset request. Software starts the watchdog once and
services it with a two-key sequence. Timeout, early-window service and malformed service
sequences request reset. An APB reset does not stop the running watchdog core. The integrated
reset-request pulse parameter is eight watchdog cycles.
])

#context metadata((kind:"ip-end",id:"wdg",page:here().page()))
