/* Software placement over the existing flat 128 KiB aperture, not P4 hardware banks. */
ENTRY(_start)
INCLUDE memory_regions.ld
PHDRS
{
    boot PT_LOAD FLAGS(5);
    code PT_LOAD FLAGS(5);
    cpu PT_LOAD FLAGS(6);
    dma PT_LOAD FLAGS(6);
}
MEMORY
{
    CODE (rx) : ORIGIN = ORIGIN(SRAM), LENGTH = 64K
    CPU (rw) : ORIGIN = ORIGIN(SRAM) + 64K, LENGTH = 32K
    DMA (rw) : ORIGIN = ORIGIN(SRAM) + 96K, LENGTH = 32K
}
SECTIONS
{
    .init : { KEEP(*(.init)) . = ALIGN(4); } > FLASH :boot
    .copy_table : {
        _copy_table_start = .;
        LONG(LOADADDR(.text)); LONG(ADDR(.text)); LONG(SIZEOF(.text));
        LONG(LOADADDR(.dma_data)); LONG(ADDR(.dma_data)); LONG(SIZEOF(.dma_data));
        LONG(LOADADDR(.data)); LONG(ADDR(.data)); LONG(SIZEOF(.data));
        _copy_table_end = .;
        _zero_table_start = .;
        LONG(ADDR(.dma_bss)); LONG(SIZEOF(.dma_bss));
        LONG(ADDR(.bss)); LONG(SIZEOF(.bss));
        _zero_table_end = .;
    } > FLASH :boot
    .text : {
        *(.text*) *(.rodata*) *(.srodata*)
        . = ALIGN(4);
    } > CODE AT> FLASH :code
    /* Consume annotated DMA inputs before the general data/BSS wildcards. */
    .dma_data : ALIGN(64) { *(.data.rs_dma*) . = ALIGN(4); } > DMA AT> FLASH :dma
    .dma_bss (NOLOAD) : ALIGN(64) { *(.bss.rs_dma*) . = ALIGN(4); } > DMA :dma
    .data : ALIGN(4) { *(.data*) *(.sdata*) . = ALIGN(4); } > CPU AT> FLASH :cpu
    .bss (NOLOAD) : ALIGN(4) {
        _sbss = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(16); _ebss = .;
    } > CPU :cpu
    _heap_start = _ebss;
    _stack_point = ORIGIN(CPU) + LENGTH(CPU);
    _stack_bottom = _stack_point - 4096;
    ASSERT(LENGTH(SRAM) == 128K, "Tiny bank placement requires exactly 128 KiB")
    ASSERT(_ebss <= _stack_bottom, "Tiny CPU data overlaps reserved 4 KiB stack")
    ASSERT((ADDR(.dma_bss) + SIZEOF(.dma_bss)) <= (ORIGIN(DMA) + LENGTH(DMA)),
           "Tiny DMA storage overflows B3")
    ASSERT((ADDR(.text) + SIZEOF(.text)) <= (ORIGIN(CODE) + LENGTH(CODE)),
           "Tiny code overflows B0/B1")
}
