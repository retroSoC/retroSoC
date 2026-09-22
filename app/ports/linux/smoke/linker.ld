ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x38000000;
    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    } :text
    .data :
    {
        *(.data*)
        *(.sdata*)
    } :data
    .bss (NOLOAD) :
    {
        . = ALIGN(64);
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(64);
        _bss_end = .;
    } :data
    _stack_top = 0x3807fff0;
    ASSERT(_bss_end < _stack_top, "HP smoke payload exceeds its 512 KiB slot")
}
