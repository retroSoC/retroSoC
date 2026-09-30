OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x38000000, LENGTH = 512K }
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > RAM :text
  .data : { . = ALIGN(16); __global_pointer$ = . + 0x800; *(.sdata*) *(.data*) } > RAM :data
  .bss (NOLOAD) : {
    . = ALIGN(16); __bss_start = .;
    *(.sbss*) *(.bss*) *(COMMON)
    . = ALIGN(16); __bss_end = .;
  } > RAM
  .stack (NOLOAD) : { . = ALIGN(16); . += 8192; __rt_rvstack = .; } > RAM
  /DISCARD/ : { *(.eh_frame*) *(.comment*) }
  ASSERT(. <= ORIGIN(RAM) + LENGTH(RAM), "RT-Thread exceeds HP RAM budget")
}
