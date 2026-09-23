ENTRY(_start)

SECTIONS
{
    . = 0x38000000;
    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
        *(.srodata*)
    }
    . = ALIGN(8);
    .data :
    {
        *(.data*)
        *(.sdata*)
    }
    . = ALIGN(8);
    __bss_start = .;
    .bss :
    {
        *(.sbss*)
        *(.bss*)
        *(COMMON)
    }
    . = ALIGN(8);
    __bss_end = .;
    . = ALIGN(16);
    .stack :
    {
        . += 0x2000;
        __stack_top = .;
    }
}
