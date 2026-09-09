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
  [*Kernel / initramfs* \ SBI early console and hvc0 \ Run /sbin/init],
  [*Rootfs ready service* \ Print ready text \ Publish mailbox fields],
  [*LP observation* \ Match sequence / event \ Separate from driver coverage],
)),caption:[Supplied OpenSBI/Linux handoff and readiness path. The diagram describes source-level checkpoints.])<linux-runtime-flow>

The kernel uses #code(platform.bootargs). Console text therefore reaches UART1 through the SBI
path in this configuration. The UART1 device-tree node's presence does not substitute for a
native driver. The configured machine timer and software-interrupt path are distinct from
external interrupt-controller and custom peripheral driver integration.
#source-note("app/ports/linux/opensbi/retrosoc_hp/platform.c",title:"Hart mapping, console callbacks and ACLINT setup")
#source-note("app/ports/linux/linux/retrosoc_hp.config",title:"RV32, SBI console and single-hart kernel configuration")

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
   ([MMU / cache maintenance],[Sv32; #(platform.cbom_bytes)-byte CBO blocks],[Software metadata must be checked against the generated HP artifact.]),
   ([Initial ramdisk],[Start #code("0x"+str(platform.initrd_start,base:16))],[The source template's equal start/end is patched using the built compressed rootfs size.]),
   ([Interrupt controllers],[ACLINT CPU causes; PLIC machine/supervisor contexts],[A DT node and binding alone do not demonstrate a complete driver or interrupt acceptance test.])),
  widths:(1fr,1.3fr,2.15fr))

The image builder replaces linux,initrd-end with the start plus the actual rootfs.cpio.gz size.
That value is an end-exclusive boundary; the generated DTB, not the unpatched source template,
must accompany the images. OpenSBI FW_TEXT_START, FW_JUMP_ADDR and FW_JUMP_FDT_ADDR are selected
from the supplied fixed layout. Retain the output DTB, source configuration and bundle manifest
together. A changed device-tree property does not reconfigure clocks or synthesize different RTL.
#source-note("app/ports/linux/linux/retrosoc_hp.dts",title:"Device-tree template and logical platform bindings")
#source-note("scripts/build_hp_linux.py",title:"Actual initrd-end patch and FW_JUMP build arguments")

=== Kernel and rootfs ready handoff
The rootfs service S99retrosoc-hp prints its ready message and then performs four 32-bit mailbox
writes. The published event is an init-service checkpoint, not proof of all drivers, networking,
storage or long-term Linux stability. The text is emitted before the mailbox writes, so the text
alone is not the LP's readiness condition.

#ds-table("linux-ready-writes",[Rootfs service mailbox publication order],
  ([Order],[Address],[Written value],[Purpose]),
  platform.ready_writes.enumerate().map(((i,row))=>(str(i+1),code(row.address),code(row.value),
    ([Sequence],[Linux-ready event],[Argument / ready state],[Interrupt request]).at(i))),
  widths:(0.4fr,1.1fr,1.1fr,1.85fr))

The script uses devmem from the supplied userland with CONFIG_DEVMEM enabled in the kernel.
It contains no explicit readback or per-write failure handling. The LP loader checks the
expected sequence/event in its existing mailbox loop; that final wait has no firmware-local
deadline. A rootfs message, process exit, mailbox publication and final SYSCTRL TEST_STATUS are
different observations. Preserve them with their stage and use an external timeout when a
required checkpoint never arrives.

Resource ownership and non-coherent buffer rules still apply after Linux starts. Follow
@software-support before choosing a driver path, and @multicore-operation for later LP/HP
transactions. This description adds no new successful boot or board-validation claim.
#source-note("app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp",title:"Ready message and actual mailbox write order")
#source-note("app/apps/hp_boot/main.c",title:"LP sequence/event checks and final terminal result")
