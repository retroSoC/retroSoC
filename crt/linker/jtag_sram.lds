ENTRY(_start)

INCLUDE memory_regions.ld

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS {
    .text ORIGIN(SRAM) :
    {
        KEEP(*(SORT_NONE(.init)))
        KEEP(*(.text.rs_xpi_flash_probe))
        KEEP(*(.text.rs_xpi_flash_update))
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
        _etext = .;
    } >SRAM :text

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } >SRAM :data

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        KEEP(*(.bss.rs_xpi_flash_staging))
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >SRAM :data

    . = ALIGN(16);
    _heap_start = .;
    _stack_point = ORIGIN(SRAM) + LENGTH(SRAM);

    ASSERT(_heap_start < (_stack_point - 1024), "JTAG SRAM loader exceeds SRAM")
}
