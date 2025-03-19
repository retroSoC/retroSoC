    .section .init
    .global  _start
    .type    _start,@function

_start:
# ===== Startup Stage 1 =====
# init the regfile

# zero-initialize register file
    li       x1, 0
# x2 (sp) is initialized by hardware
    la       x2, _stack_point
    li       x3, 0
    li       x4, 0
    li       x5, 0
    li       x6, 0
    li       x7, 0
    li       x8, 0
    li       x9, 0
    li       x10, 0
    li       x11, 0
    li       x12, 0
    li       x13, 0
    li       x14, 0
    li       x15, 0
    li       x16, 0
    li       x17, 0
    li       x18, 0
    li       x19, 0
    li       x20, 0
    li       x21, 0
    li       x22, 0
    li       x23, 0
    li       x24, 0
    li       x25, 0
    li       x26, 0
    li       x27, 0
    li       x28, 0
    li       x29, 0
    li       x30, 0
    li       x31, 0

# ===== Startup Stage 2 =====
# Load code section frm FLASH to RAM
# when code LMA is different with VMA
app_loader_start:
    la       a0, _ram_lma
    la       a1, _ram_vma
    beq      a0, a1, app_loader_end
    la       a2, _etext
    bgeu     a1, a2, app_loader_end
app_loader:
    lw       t0, (a0)
    sw       t0, (a1)
    addi     a0, a0, 4
    addi     a1, a1, 4
    bltu     a1, a2, app_loader
    j        data_loader_start
app_loader_end:

ram_cleaner_start:
# zero initialize entire scratchpad memory
    li       a0, 0x00000000
ram_cleaner:
    sw       a0, 0(a0)
    addi     a0, a0, 4
    blt      a0, sp, ram_cleaner
ram_cleaner_end:

data_loader_start:
    la       a0, _psram_lma
    la       a1, _psram_vma
    beq      a0, a1, data_loader_end
    la       a2, _edata
    bgeu     a1, a2, data_loader_end
data_loader:
    lw       t0, (a0)
    sw       t0, (a1)
    addi     a0, a0, 4
    addi     a1, a1, 4
    bltu     a1, a2, data_loader
data_loader_end:

bss_cleaner_start:
    la       a0, _sbss
    la       a1, _ebss
    bge      a0, a1, bss_cleaner_end
bss_cleaner:
    sw       zero, 0(a0)
    addi     a0, a0, 4
    blt      a0, a1, bss_cleaner
bss_cleaner_end:

# call main
    call     main
loop:
    j        loop
