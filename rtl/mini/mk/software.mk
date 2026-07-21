# Software SDK and application build
CROSS ?= riscv32-unknown-elf-

CP   = $(CROSS)cpp
CC   = $(CROSS)gcc
OBJC = $(CROSS)objcopy
DUMP = $(CROSS)objdump

GCC_FLAGS     := -std=gnu11 -Wall -Wextra \
             -Wl,-Bstatic,-T,$(LINK_TYPE).lds,--strip-debug -O3 \
             -ffreestanding -nostdlib
SW_WARN_FLAGS := -Wformat=2 -Wshadow -Wstrict-prototypes -Wmissing-prototypes \
                 -Wcast-align -Werror=implicit-function-declaration \
                 -Werror=return-type -Werror=incompatible-pointer-types \
                 -Werror=int-conversion -Werror=format

ifeq ($(ISA),RV32E)
ISA_FLAGS := -mabi=ilp32e
else
ISA_FLAGS := -mabi=ilp32
endif

ifeq ($(ISA),RV32E)
ifeq ($(HAVE_CSR),YES)
ISA_FLAGS += -march=rv32e_zicsr
else
ISA_FLAGS += -march=rv32e
endif
else ifeq ($(ISA),RV32I)
ifeq ($(HAVE_CSR),YES)
ISA_FLAGS += -march=rv32i_zicsr
else
ISA_FLAGS += -march=rv32i
endif
else ifeq ($(ISA),RV32IM)
ifeq ($(HAVE_CSR),YES)
ISA_FLAGS += -march=rv32im_zicsr
else
ISA_FLAGS += -march=rv32im
endif
endif

DEF_VAL += -DCORE_$(CORE)
DEF_VAL += -DIP_$(IP)
DEF_VAL += -DAPP_$(APP)
DEF_VAL += -DCOMPILER_NAME='"$(CC)"'
DEF_VAL += -DCOMPILER_CFLAGS='"$(GCC_FLAGS) $(SW_WARN_FLAGS)"'
DEF_VAL += -DCOMPILER_ISA='"$(ISA_FLAGS)"'
ifeq ($(HAVE_CSR),YES)
DEF_VAL += -DCSR_ENABLE
endif

CFLAGS := $(GCC_FLAGS) $(SW_WARN_FLAGS) $(ISA_FLAGS) $(DEF_VAL)

CRT_SRCS := $(ROOT_PATH)/crt/arch/riscv/startup.S \
            $(ROOT_PATH)/crt/arch/riscv/libgcc/clzsi2.c \
            $(ROOT_PATH)/crt/arch/riscv/libgcc/divdi3.c \
            $(ROOT_PATH)/crt/arch/riscv/libgcc/ffssi2.c \
            $(ROOT_PATH)/crt/arch/riscv/libgcc/udivdi3.c \
            $(ROOT_PATH)/crt/arch/riscv/libgcc/umoddi3.c \
            $(ROOT_PATH)/crt/src/lib/stdlib.c \
            $(ROOT_PATH)/crt/src/lib/string.c \
            $(ROOT_PATH)/crt/src/lib/console.c \
            $(ROOT_PATH)/crt/src/lib/printf.c \
            $(ROOT_PATH)/crt/src/core/archinfo.c \
            $(ROOT_PATH)/crt/src/service/bench.c \
            $(ROOT_PATH)/crt/src/service/booter.c \
            $(ROOT_PATH)/crt/src/hal/clock.c \
            $(ROOT_PATH)/crt/src/hal/uart.c \
            $(ROOT_PATH)/crt/src/hal/gpio.c \
            $(ROOT_PATH)/crt/src/hal/timer.c \
            $(ROOT_PATH)/crt/src/hal/pwm.c \
            $(ROOT_PATH)/crt/src/hal/rtc.c \
            $(ROOT_PATH)/crt/src/hal/watchdog.c \
            $(ROOT_PATH)/crt/src/hal/crc.c \
            $(ROOT_PATH)/crt/src/hal/rng.c \
            $(ROOT_PATH)/crt/src/hal/advanced_timer.c \
            $(ROOT_PATH)/crt/src/hal/hpuart.c \
            $(ROOT_PATH)/crt/src/hal/ps2.c \
            $(ROOT_PATH)/crt/src/hal/i2c.c \
            $(ROOT_PATH)/crt/src/hal/onewire.c \
            $(ROOT_PATH)/crt/src/hal/dma.c \
            $(ROOT_PATH)/crt/src/hal/lcd.c \
            $(ROOT_PATH)/crt/src/hal/psram.c \
            $(ROOT_PATH)/crt/src/hal/spisd.c \
            $(ROOT_PATH)/crt/src/hal/qspi.c

ifeq ($(HAVE_CSR),YES)
CRT_SRCS += $(ROOT_PATH)/crt/arch/riscv/system_irq.S
CRT_SRCS += $(ROOT_PATH)/crt/src/core/system_irq_handler.c
CRT_SRCS += $(ROOT_PATH)/crt/src/core/irq.c
endif

APP_SRCS     :=
APP_INC_DIRS :=
APP_MK       := $(ROOT_PATH)/app/apps/$(APP)/app.mk

ifeq ($(wildcard $(APP_MK)),)
$(error Application profile not found: $(APP_MK))
endif
include $(APP_MK)

ifneq ($(findstring MDD,$(CORE) $(IP)),)
APP_INC_DIRS += $(MPW_OUTPUT_DIR)
endif

ifneq ($(filter RV32E RV32I,$(ISA)),)
CRT_SRCS += $(ROOT_PATH)/crt/arch/riscv/libgcc/div.S
CRT_SRCS += $(ROOT_PATH)/crt/arch/riscv/libgcc/muldi3.S
CRT_SRCS += $(ROOT_PATH)/crt/arch/riscv/libgcc/mulsi3.c
endif

INC_PATH          := -I$(SW_BUILD_DIR)/include \
            -I$(MEMORY_MAP_C_DIR) \
            -I$(ROOT_PATH)/crt/include \
            $(addprefix -I,$(APP_INC_DIRS))
SRC_PATH          := $(CRT_SRCS) $(APP_SRCS)
LDS_PATH          := $(ROOT_PATH)/crt/linker/$(LINK_TYPE).lds
MEMORY_REGIONS_LD := $(MEMORY_MAP_LINKER_DIR)/memory_regions.ld
VERSION_HEADER    := $(SW_BUILD_DIR)/include/socver.h
FIRMWARE_ELF      := $(SW_BUILD_DIR)/firmware
ASM_FIRMWARE_NAME ?= retrosoc_asm
SW_HEADERS        := $(shell find $(ROOT_PATH)/crt/include $(ROOT_PATH)/app -type f \
                      \( -name '*.h' -o -name '*.hpp' \) 2>/dev/null)

$(VERSION_HEADER): FORCE_VERSION $(ROOT_PATH)/crt/ver.py $(ROOT_PATH)/crt/ver.tmpl
	@mkdir -p $(dir $@)
	python3 $(ROOT_PATH)/crt/ver.py --root $(ROOT_PATH) --output $@

FORCE_VERSION:

upd_ver_info: $(VERSION_HEADER)

asm: $(MPW_VARIANT_STAMP)
	@mkdir -p $(SW_BUILD_DIR)/asm
	$(MAKE) -C $(ROOT_PATH)/app/asm OUT_DIR=$(SW_BUILD_DIR)/asm
	cp $(SW_BUILD_DIR)/asm/hello-asm.flash $(SW_BUILD_DIR)/$(ASM_FIRMWARE_NAME).hex
	cp $(SW_BUILD_DIR)/asm/hello-asm.bin $(SW_BUILD_DIR)/$(ASM_FIRMWARE_NAME).bin
	cp $(SW_BUILD_DIR)/asm/hello-asm.txt $(SW_BUILD_DIR)/$(ASM_FIRMWARE_NAME)_all.txt

$(FIRMWARE_ELF): $(MPW_VARIANT_STAMP) $(MEMORY_MAP_STAMP) $(VERSION_HEADER) $(SRC_PATH) $(SW_HEADERS) $(LDS_PATH) \
	$(ROOT_PATH)/rtl/mini/mk/software.mk
	@mkdir -p $(SW_BUILD_DIR)
	cd $(SW_BUILD_DIR) && $(CP) -P -o $(LINK_TYPE).lds $(LDS_PATH)
	cp $(MEMORY_REGIONS_LD) $(SW_BUILD_DIR)/memory_regions.ld
	cd $(SW_BUILD_DIR) && $(CC) $(CFLAGS) $(INC_PATH) -o $(@F) $(SRC_PATH)
	cd $(SW_BUILD_DIR) && $(OBJC) -O verilog $(@F) $(FIRMWARE_NAME).hex
	cd $(SW_BUILD_DIR) && $(OBJC) -O binary $(@F) $(FIRMWARE_NAME).bin
	cd $(SW_BUILD_DIR) && $(DUMP) -d $(@F) > $(FIRMWARE_NAME).txt
	cd $(SW_BUILD_DIR) && $(DUMP) -D $(@F) > $(FIRMWARE_NAME)_all.txt

firmware: $(FIRMWARE_ELF)

firmware asm: | manifest

.PHONY: FORCE_VERSION