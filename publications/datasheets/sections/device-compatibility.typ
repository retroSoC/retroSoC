#import "../style.typ": *

==== External Memory and Device Compatibility <device-compatibility>
The table distinguishes a controller protocol profile, a simulation model and a qualified
physical component. Geometry or a similar command set is insufficient to establish drop-in
compatibility. Device order codes, supply, speed grade and board timing must be reviewed together.

#ds-table("external-device-profiles",[External-memory profiles and their evidence boundary],
  ([Device / profile],[Protocol and geometry],[Initialization / compatibility condition]),
  data.system_reference.programming.devices.map(r=>(r.name,[#r.protocol \ #r.geometry],r.setup)),
  widths:(1fr,1.4fr,1.75fr))

#ds-table("external-device-evidence",[Model coverage versus physical-device qualification],
  ([Device / profile],[Model evidence indexed],[Board],[Silicon]),
  data.system_reference.programming.devices.map(r=>(r.name,r.model,r.board,r.silicon)),
  widths:(1.1fr,1.85fr,0.6fr,0.6fr))
Model source and test availability are not a reviewed passing run. The fast XPI backend is
specifically narrower than a pin-level flash model: it is useful for selected boot/regression
work and must not qualify erase/program behavior, all LUT modes or board sampling margins.

Before substituting a component, compare its reset state, command/address encoding, mode/dummy
phases, latency configuration, page and chip boundaries, supported sampling clocks and status
bits. Validate the complete initialization and recovery sequence, not only a successful ID read.
For SDRAM, match bank/row/column geometry and convert device timings to the actual memory clock.

The QPI controller is device-specific. The OPI and modified single-clock HyperBus-style paths
use different protocol encoders and are boot/profile-selected; they do not imply generic
compatibility with every commercial octal or HyperBus device. A supplier's maximum device clock
is not the characterized maximum frequency of the Mini-to-board interface.

If no qualified device is listed, retain the profile/model status and obtain the missing
component, board and timing evidence before releasing a BOM. Do not select an arbitrary
commercial part merely to fill this table. Firmware must also respect @resource-conflicts,
because QPI and OPI use mutually exclusive shared pads.
#source-note("docs/ip/xpi.md",title:"XPI slot/LUT and full versus fast flash model")
#source-note("docs/ip/psram.md",title:"ESP-PSRAM64H initialization and device boundaries")
#source-note("docs/ip/opipsram.md",title:"Prototype OPI and single-clock HyperBus-style profiles")
#source-note("docs/ip/sdram.md",title:"SDRAM geometry, clocking and timing configuration")

