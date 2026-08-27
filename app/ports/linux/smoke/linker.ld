ENTRY(_start)

SECTIONS
{
    . = 0x38000000;
    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    }
}
