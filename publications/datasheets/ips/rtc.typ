#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"rtc",page:here().page()))

==== Real-Time Clock (RTC) <rtc>

#ip("rtc")

#ip-reference("rtc","rtc",4,legacy:[
RTC V2 provides a 64-bit Unix-epoch counter, 1/256-second resolution, two alarms, a periodic
wake timer and smooth digital calibration. Time reads use an atomic snapshot. The engine uses
the independent audio input frequency selected by the profile rather than assuming a
32.768 kHz crystal. RTC interrupt and wake outputs are distinct integration signals.
#tbd[Battery-backed operation, oscillator accuracy and retention across loss of board power
are not specified by the current digital integration.]
])

#context metadata((kind:"ip-end",id:"rtc",page:here().page()))
