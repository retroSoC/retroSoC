# PS/2 V2 SoC Integration

The Mini SoC integrates the managed PS/2 host controller at
`RS_SOC_APB_PS2_BASE`. The standalone IP owns the transport RTL, register ABI,
device model, freestanding controller/keyboard/mouse software, formal proof,
and release documentation under `rtl/managed/clusterip/ps2`.

## SoC Binding

The controller is APB target slot 4 and reports its combined level interrupt at
management interrupt vector 12. The APB wrapper uses the configured external
clock frequency for reset timing defaults and instantiates 16-entry RX and TX
FIFOs.

GPIO0 and GPIO1 ALT1 select PS/2 clock and data respectively. Each ALT1 path
binds all three signals as one function: resolved pad input, constant-zero pad
output data, and active-high drive-low enable. Board and pad integration must
provide pull-ups. Firmware must disable the controller and confirm both output
enables are released before changing GPIO ownership.

## Software Binding

`<retrosoc/hal/ps2.h>` wraps the managed base-address API in the `rs_`
namespace and maps IP status values to `rs_status_t`. The HAL exposes bounded
controller I/O and command operations, keyboard Set-2 decoding, and standard,
wheel, and five-button mouse packet decoding. It does not preserve the former
receive-only `reg_ps2_*` ABI.

The active APB clock must be supplied to `rs_ps2_init`. When software changes
the system clock, it must disable or quiesce PS/2, reconfigure timing using the
new active frequency, and only then resume device traffic.

## Sources of Truth

- Register and protocol specification:
  `rtl/managed/clusterip/ps2/doc/datasheet.md`
- Electrical and CDC integration:
  `rtl/managed/clusterip/ps2/doc/integration.md`
- Standalone verification and release criteria:
  `rtl/managed/clusterip/ps2/doc/verification.md`
- GPIO and interrupt topology: `rtl/mini/integration/soc_topology.json`
- APB address allocation: `rtl/mini/address_map/memory_map.json`
