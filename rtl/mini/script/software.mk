# software
CROSS=riscv32-unknown-elf-

CP   = $(CROSS)cpp
CC   = $(CROSS)gcc
OBJC = $(CROSS)objcopy
DUMP = $(CROSS)objdump

GCC_FLAGS := -Wall -Wextra \
             -Wl,-Bstatic,-T,flash_$(LINK_TYPE).lds,--strip-debug -O3 \
             -ffreestanding \
             -nostdlib

ifeq ($(ISA), RV32E)
    ISA_FLAGS := -mabi=ilp32e
else
    ISA_FLAGS := -mabi=ilp32
endif

ifeq ($(ISA), RV32E)
    ifeq ($(HAVE_CSR), YES)
        ISA_FLAGS += -march=rv32e_zicsr
    else
        ISA_FLAGS += -march=rv32e
    endif
else ifeq ($(ISA), RV32I)
    ifeq ($(HAVE_CSR), YES)
        ISA_FLAGS += -march=rv32i_zicsr
    else
        ISA_FLAGS += -march=rv32i
    endif
else ifeq ($(ISA), RV32IM)
    ifeq ($(HAVE_CSR), YES)
        ISA_FLAGS += -march=rv32im_zicsr
    else
        ISA_FLAGS += -march=rv32im
    endif
endif

DEF_VAL += -DCORE_$(CORE)
DEF_VAL += -DIP_$(IP)
DEF_VAL += -DCOMPILER_NAME='"$(CC)"'
DEF_VAL += -DCOMPILER_CFLAGS='"$(GCC_FLAGS)"'
DEF_VAL += -DCOMPILER_ISA='"$(ISA_FLAGS)"'
DEF_VAL += -DSW_$(PROG_TYPE)
ifeq ($(HAVE_CSR), YES)
    DEF_VAL += -DCSR_ENABLE
endif

CFLAGS := $(GCC_FLAGS)
CFLAGS += $(ISA_FLAGS)
CFLAGS += $(DEF_VAL)



TINYLIB_PATH := $(ROOT_PATH)/crt/startup.S \
                $(ROOT_PATH)/crt/src/tinylib.c \
                $(ROOT_PATH)/crt/src/tinyuart.c \
                $(ROOT_PATH)/crt/src/tinystring.c \
                $(ROOT_PATH)/crt/src/tinyprint.c \
                $(ROOT_PATH)/crt/src/tinyprintf.c \
                $(ROOT_PATH)/crt/src/tinygpio.c \
                $(ROOT_PATH)/crt/src/tinyarchinfo.c \
                $(ROOT_PATH)/crt/src/tinyrng.c \
                $(ROOT_PATH)/crt/src/tinytim.c \
                $(ROOT_PATH)/crt/src/tinypwm.c \
                $(ROOT_PATH)/crt/src/tinyrtc.c \
                $(ROOT_PATH)/crt/src/tinywdg.c \
                $(ROOT_PATH)/crt/src/tinycrc.c \
                $(ROOT_PATH)/crt/src/tinyadvtim.c \
                $(ROOT_PATH)/crt/src/tinyhpuart.c \
                $(ROOT_PATH)/crt/src/tinyps2.c \
                $(ROOT_PATH)/crt/src/tinyi2c.c \
                $(ROOT_PATH)/crt/src/tiny1wire.c \
                $(ROOT_PATH)/crt/src/tinydma.c \
                $(ROOT_PATH)/crt/src/tinylcd.c \
                $(ROOT_PATH)/crt/src/tinypsram.c \
                $(ROOT_PATH)/crt/src/tinyspisd.c \
                $(ROOT_PATH)/crt/src/tinyqspi.c \
                $(ROOT_PATH)/crt/src/tinybench.c \
                $(ROOT_PATH)/crt/src/tinybooter.c \
                $(ROOT_PATH)/crt/src/main.c

ifeq ($(HAVE_CSR), YES)
TINYLIB_PATH += $(ROOT_PATH)/crt/system_irq.S
TINYLIB_PATH += $(ROOT_PATH)/crt/src/system_irq_handler.c
endif

ifeq ($(PROG_TYPE), FULL)
TINYLIB_PATH += $(ROOT_PATH)/crt/src/tinysh.c
TINYLIB_PATH += $(ROOT_PATH)/crt/src/tinyi2s.c
endif


ifeq ($(PROG_TYPE), FULL)
APP_PATH :=     $(ROOT_PATH)/app/base/src/at24cxx.c \
                $(ROOT_PATH)/app/base/src/pcf8563b.c \
                $(ROOT_PATH)/app/base/src/es8388.c \
                $(ROOT_PATH)/app/base/src/w25q128jvxim.c \
                $(ROOT_PATH)/app/base/src/wav_audio.c \
                $(ROOT_PATH)/app/base/src/video_player.c \
                $(ROOT_PATH)/app/base/src/donut.c
endif

INC_PATH := -I$(ROOT_PATH)/crt/inc \
            -I$(ROOT_PATH)/app/base/inc


ifneq ($(findstring MDD,$(CORE) $(IP)),)
INC_PATH += -I$(ROOT_PATH)/rtl/min/mpw/.build
endif


ifeq ($(PROG_TYPE), FULL)
# extern app
include $(ROOT_PATH)/app/userip/userip.mk
include $(ROOT_PATH)/app/fatfs/fatfs.mk
include $(ROOT_PATH)/app/coremark/coremark.mk
# include $(ROOT_PATH)/app/lvgl/lvgl.mk
endif

SRC_PATH := $(TINYLIB_PATH)
SRC_PATH += $(APP_PATH)

ifneq ($(filter RV32E RV32I,$(ISA)),)
    SRC_PATH += $(ROOT_PATH)/crt/libgcc/div.S
    SRC_PATH += $(ROOT_PATH)/crt/libgcc/muldi3.S
    SRC_PATH += $(ROOT_PATH)/crt/libgcc/mulsi3.c
endif

LDS_PATH := $(ROOT_PATH)/crt/flash_$(LINK_TYPE).lds

upd_ver_info:
	python3 crt/ver.py

asm: gen_mpw_code
	cd app/asm && make
	cp -rf app/asm/hello-asm.flash .sw_build/retrosoc_fw.hex
	cp -rf app/asm/hello-asm.bin .sw_build/retrosoc_fw.bin

firmware: gen_mpw_code upd_ver_info
	@mkdir -p .sw_build
	cd .sw_build && ($(CP) -P -o flash_$(LINK_TYPE).lds $(LDS_PATH))
	cd .sw_build && ($(CC) $(CFLAGS) $(INC_PATH) -o $@ $(SRC_PATH))
	cd .sw_build && ($(OBJC) -O verilog $@ $(FIRMWARE_NAME).hex)
	cd .sw_build && ($(OBJC) -O binary $@ $(FIRMWARE_NAME).bin)
	cd .sw_build && ($(DUMP) -d $@ > $(FIRMWARE_NAME).txt)
	cd .sw_build && ($(DUMP) -D $@ > $(FIRMWARE_NAME)_all.txt)