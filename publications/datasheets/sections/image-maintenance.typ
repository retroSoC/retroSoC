#import "../style.typ": *

== Programming, Image Maintenance and Service Procedures <image-maintenance>
The existing flow programs external NOR using an SRAM-resident XPI loader and an already
configured OpenOCD/GDB connection. It does not add a hardware JTAG-to-flash master, automatic
OTA service or authenticated update chain. This chapter documents the operation; the publication
build does not connect a debugger or erase/program a device.

=== Inputs and matching configuration
#ds-table("maintenance-inputs",[Inputs required before preparing a programming operation],
  ([Input],[Required property],[Failure response]),
  (([Loader ELF],[Built for the selected SoC/configuration, with SRAM placement and retained probe/update/staging symbols.],[Reject missing/mismatched symbols or placement; do not substitute an arbitrary firmware ELF.]),
   ([Raw image and address],[Reviewed BIN, intended flash destination and range within the supported device.],[Check image/profile identity and bounds before creating commands.]),
   ([Flash device],[Supported ID, erase/page geometry, status and command sequence.],[Do not assume every serial NOR uses the same algorithm.]),
   ([Debug connection],[Correct management target, voltage, pinout and OpenOCD endpoint.],[Stop on identity/transport mismatch.]),
   ([System state],[HP and other masters cannot fetch/use the affected NOR region; relevant interrupts and transfers are quiesced.],[A management halt alone does not establish these system-wide conditions.])),
  widths:(0.8fr,2.05fr,1.3fr))
The committed loader profile is #code("configs/ci/ihp130-xpi-flash-loader.mk"), using the
#code("jtag_sram") linker layout. The ELF and its state must remain in SRAM because the boot
NOR is unavailable during erase/program. A matching loader artifact was not newly built by
this publication task; supply one from a reviewed build before using the host command.

The current algorithm is specialized for the documented 16 MiB Winbond-compatible flash
profile and JEDEC ID. It uses 4 KiB erase sectors and 256-byte pages. A different device needs
reviewed commands, geometry, status bits and timing; the existence of an XPI LUT does not
automatically make this host loader universal.

=== Stop and prepare the system
+ Record hardware/profile, loader and image identity. Preserve any information required to
  restore the board; do not rely on volatile SRAM as a power-loss backup.
+ Stop application submissions, drain relevant DMA/I/O activity and hold HP in a safe state.
  No master may fetch from or consume the region being modified.
+ Establish the approved management debug connection. The generated script uses a management
  halt and loader load; this is not a global peripheral/clock reset or proof of SoC quiescence.
+ Confirm that the loader's execution, stack and staging/cache buffers reside outside NOR.
+ Check flash identity and operation bounds before allowing an erase/program sequence.

=== Generate a reviewable script
Without #code("--execute"), the tool requires a persistent #code("--gdb-script") path. It reads
the staging symbol with the selected #code("nm") tool, splits the image at sector boundaries,
and writes chunk files and GDB commands. It does not launch GDB in that mode.

#code-block[
```sh
python3 scripts/program_xpi_flash.py \
  --loader <reviewed-loader.elf> --image <reviewed-image.bin> \
  --address <reviewed-flash-address> \
  --gdb-script <output/program.gdb> --result <output/result.json>
```
]
The bracketed values are placeholders to be supplied by the operator. Review the selected
endpoint, destination range, loader symbols and generated commands. The mere presence of an
erase/program command in the generated script does not mean it has been executed.

=== Explicit execution and verification
Actual programming requires adding #code("--execute") to the reviewed invocation after all
system/device prerequisites have been met. That flag is deliberately separate because it
permits destructive NOR operations. No command in this chapter is run automatically by the
publication flow.

The SRAM loader reads the complete sector, overlays the requested bytes, erases/programs
the sector and verifies it. This preserves bytes outside the requested BIN range during a
successful completed sector update; it is not an atomic power-loss guarantee. The host checks
the subprocess result and the #code("XPI_FLASH_PROGRAM_PASS") marker. The generated session
detaches at the end; a subsequent reset/boot and application acceptance check are separate steps.

=== Interpret the result file
#ds-table("programming-result-semantics",[Execution state and result interpretation],
  ([executed],[passed],[Meaning]),
  data.system_reference.product_details.service_results.map(r=>(code(r.executed),code(r.passed),r.meaning)),
  widths:(0.65fr,0.65fr,2.85fr))
In particular, #code("passed=true") with #code("executed=false") reports successful script
preparation, not a programmed chip. Even an executed tool pass covers the loader checks and
that session's scope; retain the actual image/loader hashes, command, result and device context
before making a broader board-acceptance claim.

Some errors raise before a result file is written. Missing JSON is not a positive verdict;
if execution was attempted or interrupted, treat the device state as uncertain and inspect
the operation context before retrying.

=== Failure, interruption and service records
If probe, erase, program or readback fails, preserve the loader/host result and affected address
before retrying. An interrupted sector update can leave part of the image invalid. After power
loss or an uncertain transport result, re-establish the safe debug/loader state and inspect or
reprogram the intended image with the reviewed procedure. Do not assume that normal boot or
automatic rollback will succeed.

The flow does not implement A/B slot selection, signed updates, anti-rollback or recovery-image
selection. Those are separate system requirements. Record maintenance actions with device/board
identity, hardware snapshot, profile, loader/image digest, destination, execution state, result
and subsequent boot/acceptance observations. Keep preparation-only records distinguishable
from records of actual device operations.
#source-note("scripts/program_xpi_flash.py",title:"Host flags, command generation and result semantics")
#source-note("app/apps/xpi_flash_loader/main.c",title:"SRAM loader and sector/page verification algorithm")
#source-note("crt/linker/jtag_sram.lds",title:"Loader placement and retained debugger entry points")
#source-note("docs/hazard3-debug.md",title:"Management debug scope and reset boundary")
