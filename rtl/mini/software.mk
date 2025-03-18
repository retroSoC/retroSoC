# software
FIRMWARE_NAME := retrosoc_fw

CROSS=riscv32-unknown-elf-

CP   = $(CROSS)cpp
CC   = $(CROSS)gcc
OBJC = $(CROSS)objcopy
DUMP = $(CROSS)objdump

CFLAGS := -mabi=ilp32 \
          -march=rv32im \
          -Wl,-Bstatic,-T,retrosoc_sections.lds,--strip-debug \
          -ffreestanding \
          -nostdlib

PRJ_ROOT_PATH = ../../..

SRC_PATH := $(PRJ_ROOT_PATH)/crt/start.s \
            $(PRJ_ROOT_PATH)/crt/src/tinyuart.c \
            $(PRJ_ROOT_PATH)/crt/src/tinystring.c \
            $(PRJ_ROOT_PATH)/crt/src/tinyprintf.c \
            $(PRJ_ROOT_PATH)/crt/src/tinygpio.c \
            $(PRJ_ROOT_PATH)/crt/src/tinytim.c \
            $(PRJ_ROOT_PATH)/crt/src/tinyarchinfo.c \
            $(PRJ_ROOT_PATH)/crt/src/tinyrng.c \
            $(PRJ_ROOT_PATH)/crt/src/tinyhpuart.c \
            $(PRJ_ROOT_PATH)/crt/src/tinypwm.c \
            $(PRJ_ROOT_PATH)/crt/src/tinyps2.c \
            $(PRJ_ROOT_PATH)/crt/src/tinyi2c.c \
            $(PRJ_ROOT_PATH)/crt/src/tinylcd.c \
            $(PRJ_ROOT_PATH)/crt/src/tinypsram.c \
            $(PRJ_ROOT_PATH)/crt/src/tinybench.c \
            $(PRJ_ROOT_PATH)/crt/src/tinysh.c \
            $(PRJ_ROOT_PATH)/crt/src/firmware.c

LDS_PATH := $(PRJ_ROOT_PATH)/crt/sections.lds

# %.o: %.c %.h $(DEPS)
# 	$(CROSS)

$(FIRMWARE_NAME).elf:
	@mkdir -p .sw_build
	cd .sw_build && ($(CP) -P -o retrosoc_sections.lds $(LDS_PATH))
	cd .sw_build && ($(CC) $(CFLAGS) -I$(PRJ_ROOT_PATH)/crt/inc -o $@ $(SRC_PATH))
	cd .sw_build && ($(OBJC) -O verilog $@ $(FIRMWARE_NAME).hex)
	cd .sw_build && (sed -i 's/@30000000/@00000000/g' $(FIRMWARE_NAME).hex)
	cd .sw_build && ($(OBJC) -O binary $@ $(FIRMWARE_NAME).bin)
	cd .sw_build && ($(DUMP) -d $@ > $(FIRMWARE_NAME).txt)