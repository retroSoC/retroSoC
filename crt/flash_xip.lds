ENTRY( _start )

MEMORY
{
    FLASH (rxai!w) : ORIGIN = 0x00000000, LENGTH = 16M
    SRAM  (wxa!ri) : ORIGIN = 0x30000000, LENGTH = 128K
    PSRAM (wxa!ri) : ORIGIN = 0x40000000, LENGTH = 8M
}

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
    } >FLASH AT >FLASH

    /* The program code and other data goes into FLASH */
    .text :
    {
        . = ALIGN(4);
        *(.text)           /* .text sections (code) */
        *(.text*)          /* .text* sections (code) */
        *(.rodata)         /* .rodata sections (constants, strings, etc.) */
        *(.rodata*)        /* .rodata* sections (constants, strings, etc.) */
        *(.srodata)        /* .rodata sections (constants, strings, etc.) */
        *(.srodata*)       /* .rodata* sections (constants, strings, etc.) */
        . = ALIGN(4);
        _etext = .;        /* define a global symbol at end of code */
    } >FLASH AT >FLASH

    .ram_s ORIGIN(SRAM) :
    {
        PROVIDE ( _ram_start = .);
    } >SRAM AT >FLASH

    .ram_e ORIGIN(SRAM) + LENGTH(SRAM) :
    {
        PROVIDE ( _stack_point = .);
    } >SRAM AT >FLASH

    .psram_align_lma :
    {
        . = ALIGN(4);
        PROVIDE( _psram_lma = . );
    } >FLASH AT >FLASH

    .psram_align_vma :
    {
        PROVIDE( _psram_vma = . );
    } >PSRAM AT >FLASH

    /* This is the initialized data section
    The program executes knowing that the data is in the PSRAM
    but the loader puts the initial values in the FLASH (inidata).
    It is one task of the init to copy the initial values from FLASH to PSRAM. */
    .data :
    {
        . = ALIGN(4);
        *(.data)           /* .data sections */
        *(.data*)          /* .data* sections */
        *(.sdata)           /* .sdata sections */
        *(.sdata*)          /* .sdata* sections */
        . = ALIGN(4);
        _edata = .;        /* define a global symbol at data end; used by init code in order to initialise the .data section in PSRAM */
    } >PSRAM AT >FLASH

    /* Uninitialized data section */
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;         /* define a global symbol at bss start; used by init code */
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)

        . = ALIGN(4);
        _ebss = .;         /* define a global symbol at bss end; used by init code */
    } >PSRAM AT >PSRAM

    /* this is to define the start of the heap, and make sure we have a minimum size */
    .heap :
    {
        . = ALIGN(4);
        _heap_start = .;    /* define a global symbol at heap start */
    } >PSRAM AT >PSRAM
}
