#import "../style.typ": *
#import "../system-figures.typ": sequence-diagram
#let platform = data.system_reference.software.platform

=== OpenSBI platform and console path <linux-runtime>
The supplied OpenSBI platform exposes one application hart, with hart ID #platform.hart_id.
LP remains the separate management firmware processor. The platform's ACLINT descriptor covers
two hart-indexed register positions beginning at zero so it can address hart 1; that storage
range is not a declaration that Linux runs on both harts. The kernel configuration disables SMP.

The early platform setup programs UART1, registers its polled console and initializes machine
software-interrupt support. Timer initialization uses the ACLINT machine timer. Console writes
wait while TX is full; this loop has no local timeout. These implemented callbacks do not
establish that all optional SBI services or all peripherals have native Linux drivers.

#figure(sequence-diagram((
  [*LP handoff* \ Existing bundle validation \ Release HP at OpenSBI],
  [*OpenSBI on hart 1* \ UART1 SBI console \ ACLINT platform setup],
  [*FW_JUMP* \ Enter Linux Image \ Pass the prepared DTB],
  [*Kernel / initramfs* \ SBI early console and hvc0 \ Run /init],
  [*Rootfs ready service* \ Print ready text \ Publish mailbox fields],
  [*LP observation* \ Match sequence / event \ Separate from driver coverage],
)),caption:[Supplied OpenSBI/Linux handoff and readiness path. The diagram describes source-level checkpoints.])<linux-runtime-flow>

The kernel uses #code(platform.bootargs). Console text therefore reaches UART1 through the SBI
path in this configuration. The UART1 device-tree node's presence does not substitute for a
native driver. The configured machine timer and software-interrupt path are distinct from
external interrupt-controller and custom peripheral driver integration.
#source-note("app/ports/linux/opensbi/retrosoc_hp/platform.c",title:"Hart mapping, console callbacks and ACLINT setup")
#source-note("app/ports/linux/linux/retrosoc_hp.config",title:"RV64, SBI console and single-hart kernel configuration")

=== Device-tree and image consistency
The device-tree template, OpenSBI build arguments, boot-bundle bounds and actual generated HP
core must agree. The existing image addresses in @boot-configuration remain authoritative;
the following values explain the platform relationship rather than defining a second layout.

#ds-table("linux-platform-consistency",[Supplied Linux platform properties and their consumers],
  ([Property],[Source value],[Consistency boundary]),
  (([CPU identity],[Hart #platform.hart_id],[Match OpenSBI's hart-index map and the generated core.]),
   ([Main memory],[#code(platform.memory_base), #(platform.memory_bytes / 1024 / 1024) MiB],[Device-tree envelope; actual external memory and boot-loader bounds must agree.]),
   ([Timer base rate],[#platform.timebase_hz Hz],[Match ACLINT timebase-frequency and the OpenSBI mtimer declaration.]),
   ([CPU / UART clock declarations],[#platform.clock_hz Hz],[Nominal template values, not measured or dynamically synchronized frequencies.]),
   ([MMU / cache maintenance],[Sv39; #(platform.cbom_bytes)-byte CBO blocks],[Software metadata must be checked against the generated HP artifact.]),
   ([Initial ramdisk],[Start #code("0x"+str(platform.initrd_start,base:16))],[The source template's equal start/end is patched using the built uncompressed CPIO size.]),
   ([Interrupt controllers],[ACLINT CPU causes; PLIC machine/supervisor contexts],[A DT node and binding alone do not demonstrate a complete driver or interrupt acceptance test.])),
  widths:(1fr,1.3fr,2.15fr))

The image builder replaces linux,initrd-end with the start plus the actual rootfs.cpio size.
That value is an end-exclusive boundary; the generated DTB, not the unpatched source template,
must accompany the images. OpenSBI FW_TEXT_START, FW_JUMP_ADDR and FW_JUMP_FDT_ADDR are selected
from the supplied fixed layout. Retain the output DTB, source configuration and bundle manifest
together. A changed device-tree property does not reconfigure clocks or synthesize different RTL.
The resident OpenSBI window at 0x38000000 occupies a 512 KiB no-map reserved-memory
node. Linux must not allocate this firmware memory; the custom platform does not
apply the generic OpenSBI FDT fixups.
#source-note("app/ports/linux/linux/retrosoc_hp.dts",title:"Device-tree template and logical platform bindings")
#source-note("scripts/build_hp_linux.py",title:"Actual initrd-end patch and FW_JUMP build arguments")

=== Kernel and rootfs ready handoff
The dedicated /init mounts procfs, sysfs, devtmpfs and tmpfs, checks file I/O and child execution,
then runs the static hp-ready helper. It prints its ready message and publishes through 32-bit
mailbox writes with an I/O fence before the doorbell. This is a userspace checkpoint, not proof of all drivers, networking,
storage or long-term Linux stability. The text is emitted before the mailbox writes, so the text
alone is not the LP's readiness condition.

#ds-table("linux-ready-writes",[Userspace helper mailbox publication order],
  ([Order],[Address],[Written value],[Purpose]),
  platform.ready_writes.enumerate().map(((i,row))=>(str(i+1),code(row.address),code(row.value),
    ([Linux-ready event],[Argument / ready state],[Sequence],[Interrupt request]).at(i))),
  widths:(0.4fr,1.1fr,1.1fr,1.85fr))

The helper checks open/mmap errors for /dev/mem and reports init failures through event 3
when the mailbox can be mapped. LP validates the expected event, argument and sequence,
then writes TEST_STATUS directly for the Linux workload. GA2D/cache lifecycle is a separate
smoke workload. A rootfs message alone is not the final SYSCTRL verdict.

Resource ownership and non-coherent buffer rules still apply after Linux starts. Follow
@software-support before choosing a driver path, and @multicore-operation for later LP/HP
transactions. This description adds no new successful boot or board-validation claim.
#source-note("app/ports/linux/hp_ready.c",title:"Ready message and actual mailbox write order")
#source-note("app/ports/linux/init",title:"Minimal userspace acceptance checks")
#source-note("app/apps/hp_boot/main.c",title:"LP sequence/event checks and final terminal result")
