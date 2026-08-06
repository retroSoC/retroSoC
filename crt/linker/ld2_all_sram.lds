ENTRY( _start )

INCLUDE memory_regions.ld

SECTIONS {
    .init :
    {
        KEEP (*(SORT_NONE(.init)))
    } >FLASH AT >FLASH

    .flash_wait_s ORIGIN(FLASH) :
    {
        PROVIDE ( _flash_wait_start = .);
    } >FLASH AT >FLASH

    .flash_wait_e ORIGIN(FLASH) + LENGTH(SRAM) :
    {
        PROVIDE ( _flash_wait_end = .);
    } >FLASH AT >FLASH

    .ram_align_lma :
    {
        . = ALIGN(4);
        PROVIDE( _ram_lma = . );
    } >FLASH AT >FLASH

    .ram_align_vma :
    {
        PROVIDE( _ram_vma = . );
    } >SRAM AT >FLASH

    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
        _etext = .;
    } >SRAM AT >FLASH

    .ram_s ORIGIN(SRAM) :
    {
        PROVIDE ( _ram_start = .);
    } >SRAM AT >FLASH

    .data_align_lma :
    {
        . = ALIGN(4);
        PROVIDE( _psram_lma = . );
    } >FLASH AT >FLASH

    .data_align_vma :
    {
        PROVIDE( _psram_vma = . );
    } >SRAM AT >FLASH

    .data :
    {
        . = ALIGN(4);
        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } >SRAM AT >FLASH

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >SRAM

    .heap (NOLOAD) :
    {
        . = ALIGN(4);
        _heap_start = .;
    } >SRAM

    .ram_e ORIGIN(SRAM) + LENGTH(SRAM) :
    {
        PROVIDE ( _stack_point = .);
    } >SRAM
}
