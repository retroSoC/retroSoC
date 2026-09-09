#import "../style.typ": *

=== External Interfaces and Connection Constraints <connection-constraints>
Select external components using both the IP protocol contract and the board's electrical
requirements. A logical controller instance does not establish an on-chip PHY, fitted memory
or connector pinout. The pin/alternate-function tables above identify routes, not a complete PCB.

#ds-table("external-dependencies",[External interface dependencies and integration restrictions],
  ([Interface],[Connection requirement]),
  data.system_reference.support.filter(r=>r.id in ("xpi","spisd","sdio0","sdio1","psram","opipsram","sdram","uart0","uart1","i2c","i2s","dvp","usb2","ps2","ws2812"))
    .map(r=>(link(label(r.id),r.title),r.dependencies)),widths:(1fr,3fr))

==== Memory and shared-pin selection
QPI and OPI share a memory-pad route. Reset selects the documented QPI mode, and AON retains
the selected mode and lock across LP/HP changes. Select the mode before accessing the attached
device. The inactive controller receives safe inputs and cannot drive its clock/chip-select/output
enable; mapped accesses to that inactive target return an error. Live QPI-to-OPI switching is
not a supported application operation in this snapshot.

The controller aperture bounds addressability. Confirm actual device count, density, protocol,
command sequence, latency and refresh requirements from the supported controller contract
and selected component. Do not assume arbitrary QSPI or HyperBus devices are interchangeable.
XPI writes use indirect commands; a CPU store into the read-only data-plane flash mapping is
not a programming operation. Verify erase/program completion before making code executable.

#include "device-compatibility.typ"

==== GPIO handoff and signal integrity
+ Reserve a pin group and check alternate-function conflicts before assigning a peripheral.
+ Stop the previous function and wait for its documented idle condition. Establish the
  intended inactive output/enable state before changing ownership or the alternate function.
+ Configure the new function, including divider and open-drain behavior where applicable,
  then enable it only after the route is stable.
+ On a guard, lock or ownership error, inspect the current owner; do not force a conflicting
  output by writing data and enable controls from two independent drivers.

I2C and PS/2 need a suitable open-drain board interface. Pull-up resistance, rise time and
voltage compatibility require the selected pad and external-device specifications. UART,
I2S, DVP and WS2812 connections similarly require compatible levels and the correct ownership
of clocks. This document does not authorize direct connection to a higher-voltage interface.

==== Reset and unused-pin treatment
#ds-table("pin-treatment",[Information required before a board-level connection is approved],
  ([Pin class],[Digital contract to check],[Physical information still required]),
  (([Input / bidirectional],[Input enable, alternate function, synchronizer/filter and reset state.],[Allowed voltage, leakage, pull/keeper behavior and unused-pin termination.]),
   ([Output / open drain],[Output data, output enable, reset polarity and ownership guard.],[Drive strength, load, slew, external pull-up and contention limits.]),
   ([Clock / reset / JTAG],[Clock owner, active polarity, release synchronization and debug scope.],[Pad thresholds, pulse width, frequency/load limits and connector assignment.]),
   ([Power / ground / analog],[Selected technology wrapper and macro requirements.],[Rail names/levels, sequencing, decoupling and approved package connections.])),
  widths:(0.8fr,1.5fr,1.7fr))
Use a reviewed pad specification to decide whether an unused input can be left unconnected,
needs a pull, or must be tied to a defined level. No universal tie-off rule or resistor value
is asserted for the generic RTL wrapper. Reserve physical power and test pins according to
the chosen package; the logical inventory is not a basis for omitting them.

==== Dedicated ULPI and SDIO1 routes
The generic FPGA wrapper intentionally leaves these dedicated groups without approved board
locations. Supply the exact FPGA ball assignment, bank supply, external PHY/card circuit,
clock constraints and input/output timing before claiming a hardware route. ULPI requires an
external PHY and its interface clock; the digital USB controller does not include a USB analog PHY.
VBUS sensing, role/power switching and ESD protection belong to the approved board design.
#source-note("docs/lp-hp-architecture.md",title:"Memory-pad exclusion, inactive-window errors and lock")
#source-note("docs/ip/gpio.md",title:"Pad ownership, guards and alternate-function behavior")
#source-note("docs/ip/usb2.md",title:"ULPI digital/physical interface boundary")
#source-note("fpga/README.md",title:"Board-specific wrapper and constraint ownership")
