# software
CROSS ?= riscv32-unknown-elf-

CP   = $(CROSS)cpp
CC   = $(CROSS)gcc
OBJC = $(CROSS)objcopy
DUMP = $(CROSS)objdump

GCC_FLAGS := -Wall -Wextra \
             -Wl,-Bstatic,-T,$(LINK_TYPE).lds,--strip-debug -O3 \
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
TINYLIB_PATH += $(ROOT_PATH)/crt/src/tinyirq.c
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

INC_PATH := -I$(SW_BUILD_DIR)/include \
            -I$(ROOT_PATH)/crt/inc \
            -I$(ROOT_PATH)/app/base/inc


ifneq ($(findstring MDD,$(CORE) $(IP)),)
INC_PATH += -I$(MPW_OUTPUT_DIR)
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

LDS_PATH := $(ROOT_PATH)/crt/lds/$(LINK_TYPE).lds
VERSION_HEADER := $(SW_BUILD_DIR)/include/socver.h
FIRMWARE_ELF := $(SW_BUILD_DIR)/firmware
ASM_FIRMWARE_NAME ?= retrosoc_asm
SW_HEADERS := $(shell find $(ROOT_PATH)/crt/inc $(ROOT_PATH)/app -type f \
                      \( -name '*.h' -o -name '*.hpp' \) 2>/dev/null)

$(VERSION_HEADER): FORCE_VERSION $(ROOT_PATH)/crt/ver.py $(ROOT_PATH)/crt/ver.tmpl
	python3 $(ROOT_PATH)/crt/ver.py --root $(ROOT_PATH) \
		--output $@

FORCE_VERSION:

upd_ver_info: $(VERSION_HEADER)

asm: $(MPW_VARIANT_STAMP)
	@mkdir -p $(SW_BUILD_DIR)/asm
	$(MAKE) -C $(ROOT_PATH)/app/asm OUT_DIR=$(SW_BUILD_DIR)/asm
	cp $(SW_BUILD_DIR)/asm/hello-asm.flash $(SW_BUILD_DIR)/$(ASM_FIRMWARE_NAME).hex
	cp $(SW_BUILD_DIR)/asm/hello-asm.bin $(SW_BUILD_DIR)/$(ASM_FIRMWARE_NAME).bin
	cp $(SW_BUILD_DIR)/asm/hello-asm.txt $(SW_BUILD_DIR)/$(ASM_FIRMWARE_NAME)_all.txt

$(FIRMWARE_ELF): $(MPW_VARIANT_STAMP) $(VERSION_HEADER) $(SRC_PATH) $(SW_HEADERS) $(LDS_PATH) \
                 $(ROOT_PATH)/rtl/mini/mk/software.mk
	@mkdir -p $(SW_BUILD_DIR)
	cd $(SW_BUILD_DIR) && $(CP) -P -o $(LINK_TYPE).lds $(LDS_PATH)
	cd $(SW_BUILD_DIR) && $(CC) $(CFLAGS) $(INC_PATH) -o $(@F) $(SRC_PATH)
	cd $(SW_BUILD_DIR) && $(OBJC) -O verilog $(@F) $(FIRMWARE_NAME).hex
	cd $(SW_BUILD_DIR) && $(OBJC) -O binary $(@F) $(FIRMWARE_NAME).bin
	cd $(SW_BUILD_DIR) && $(DUMP) -d $(@F) > $(FIRMWARE_NAME).txt
	cd $(SW_BUILD_DIR) && $(DUMP) -D $(@F) > $(FIRMWARE_NAME)_all.txt

firmware: $(FIRMWARE_ELF)

firmware asm: | manifest

.PHONY: FORCE_VERSION
