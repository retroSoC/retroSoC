#import "../engineering-figures.typ": storage-figures
#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow

= Software
== Boot Configuration, Initialization and Recovery <tiny-boot>
Reset enters the Flash alias at #code(data.reset_address). The Tiny runtime excludes the generic PSRAM delay/setup branches.
With CSR support selected it masks interrupts and installs the direct trap entry, initializes registers/stack, copies code
and data when load/run addresses differ, clears BSS, performs the configured premain work, and enters main.
#flow("boot",(
  [Reset / JTAG state established · Fetch from NOR alias],
  [Mask interrupts; establish trap entry and register/stack state],
  [Tiny skips PSRAM setup · Copy initialized code/data into SRAM],
  [Clear SRAM BSS · Perform configured premain initialization],
  [Enter Tiny application · Handle terminal result or watchdog restart]
),[Tiny ordinary startup: source order, not a guaranteed boot-time measurement.])
The `ld2_all_sram` layout places runtime code, data, BSS and stack in SRAM with initialized material loaded from Flash.
Memory-map capacity, load-image bytes, runtime static occupation and stack high-water demand are different quantities.
Inspect the actual ELF/MAP and reserve buffers plus stack/scratch margin before deployment. No matching size/high-water
measurement is supplied by this datasheet build.
#source-note("crt/arch/riscv/startup.S",title:"Tiny conditional startup and relocation")
#source-note("crt/linker/ld2_all_sram.lds",title:"Flash load / SRAM runtime linker layout")

 #storage-figures("tiny-boot",section:"linker")

== Programming, Image Maintenance and Service Procedures <tiny-image-maintenance>
Use the SRAM XPI loader with a matching image, board route and existing OpenOCD GDB endpoint.
The host helper validates the image range, divides it at erase-sector boundaries and prepares GDB commands.
Generate and inspect the script first; only an explicit execute option performs erase/program work.
#code-block(raw("python scripts/program_xpi_flash.py --loader <loader.elf> --image <firmware.bin> --address 0 --gdb-script <review.gdb> --result <result.json>",block:true))
The loader and image are build outputs supplied by the operator, not placeholder files created by the publication.
Stop competing users of XPI and preserve SRAM execution, stack, trap and data dependencies during NOR update.
Verify the actual return code and completion marker. An interrupted update is not a bootable-image guarantee;
retain the result and re-establish device/controller state before recovery.
#source-note("scripts/program_xpi_flash.py",title:"Reviewable script generation and explicit execution gate")

== Runtime, SDK and Shell <tiny-runtime>
=== SDK and Completion Semantics
Consume public headers under #code("<retrosoc/...>") and the #code("rs_") namespace. The Tiny build selects product-specific
application composition and generated address/IRQ/capability metadata. This does not generate replacement IP register ABIs.
Tiny-specific RCU APIs expose the selected clock backend; unsupported profiles and application-hart/selectable-core APIs remain rejected.

*A successful API return describes that API's completion boundary*: a start command can be accepted before its operation
finishes. FIFO acceptance is not completed serial transmission. A timeout can leave work active and buffers owned by a
device. Capture state and complete abort/drain before reuse.

Software timeout arguments are polling budgets, not milliseconds. CPU/compiler work and bus stalls affect elapsed time;
a budget cannot bound a register read that never returns. Hardware counters and device-specific timeouts use their own
documented clock units. Use CLINT or another appropriate timebase when an elapsed-time deadline is required.

=== Linker Placement and Runtime Accounting
The selected linker keeps .init in Flash while runtime text/rodata/data use SRAM virtual addresses and Flash load addresses.
BSS has no load payload. Startup performs the matching relocation and zeroing; stack is part of the same finite SRAM budget.
See @tiny-memory-budget for capacity calculations and @tiny-dma-format for descriptor lifetime.
#source-note("crt/linker/ld2_all_sram.lds",title:"Actual VMA/LMA and NOLOAD sections")
#source-note("crt/README.md",title:"Freestanding runtime and SDK ownership")

== Applications <tiny-diagnostics>
The selected application and acceptance flags determine the executed workload. Ordinary bringup/CI smoke, RCU lifecycle,
PSRAM, DVP, system-performance and SPI display/snapshot images have distinct setup and terminal contracts. A watchdog
reboot path can terminate early; a retained reset count is not proof that this boot replayed all tests.
#ds-table("acceptance-codes",[Selected acceptance paths and completion boundary],([Selection],[Coverage],[Required interpretation]),(
  ([Ordinary Tiny],[CPU, SRAM, faults, shared I/O, streams and watchdog],[Read the current image sequence and controlled reset state.]),
  ([R2-P7],[Profile/gate/reset lifecycle and source failure],[Drain, committed rates and reset barriers; no physical frequency qualification.]),
  ([R2-P8],[NSS1 identity, PSRAM CPU/DMA readback and recovery],[Actual device capacity and mapping validity; preserve NOR boot.]),
  ([R2-P9],[Recovery, QVGA RGB565 and VGA YUV422 snapshots],[Frame and DMA completion, exact bytes, final drain and guards.]),
  ([R2-P10],[Matched/software/audio/camera/backend stages],[Separate profile/source/stage measurements; no aggregate FPS claim.]),
  ([SPI-P4],[Panel patterns, PSRAM/SRAM display and SD snapshot],[Independent pin oracle, exact payload and abort-prefix/recovery checks.])),widths:(0.6fr,1.5fr,2.1fr))
#flow("snapshot",(
  [Initialize NSS1 PSRAM and native SD; configure exclusive camera routes],
  [Capture exact frame with DVP + DMA2; drain and stop camera],
  [Read back every pixel and guard; publish immutable source],
  [Acquire SPI + DMA3; display from PSRAM or bounded SRAM chunks],
  [Save/read back through SDIO bounce buffers; compare; release resources]
),[Accepted snapshot workflow is sequential; no simultaneous camera/display/storage pipeline is inferred.])
The first valid full-word SYSCTRL TEST_STATUS write is sticky. Bit 31 is valid, bit 0 pass and bits 15:8 the result code.
The testbench must emit #code("SIM_TEST_PASS") and the command must succeed without failure/timeout markers. UART startup
text is diagnostic only. The compact assembly netlist boot test has a narrower scope than the full SDK image.
#source-note("app/apps/ci_smoke/tiny.c",title:"Acceptance order, reset-count branch and terminal codes")
#source-note("app/asm/tiny_boot.S",title:"Separate compact netlist boot test")

== Software Support and Validated Configurations <tiny-software-support>
#ds-table("software-support",[Source support and execution evidence],([Path],[Source support],[Validation boundary]),(
 ([Bare-metal firmware],[Tiny profiles, startup, SDK and application composition],[Build and run the selected image; publication examples are syntax checks.]),
 ([Bringup / shell / benchmark],[Application selectors and product-specific composition],[Availability of a selector is not a passing workload result.]),
 ([Debug acceptance],[Dedicated debug-transport image and JTAG tests],[Separate from a user firmware profile.]),
 ([Specialized Tiny campaigns],[RCU, PSRAM, DVP, system-performance and SPI scenarios],[Each retains its own source/profile/tool/workload result.]),
 ([Linux / application CPU],[Not a Tiny execution platform],[No imported Mini driver-support claim.])),widths:(0.9fr,1.7fr,1.7fr))
A validated configuration record must identify source revision, PDK/profile, tool and model versions, application and flags,
commands, exit code, terminal markers and raw artifacts. Do not transfer results across products or model/backend choices.
#source-note("app/README.md",title:"Application composition and supported selectors")
#source-note("docs/ip/tiny-soc-verification.md",title:"Target-specific campaign records")
