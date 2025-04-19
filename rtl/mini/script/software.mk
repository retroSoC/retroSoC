# software
FIRMWARE_NAME := retrosoc_fw
EXEC_TYPE     := xip

CROSS=riscv32-unknown-elf-

CP   = $(CROSS)cpp
CC   = $(CROSS)gcc
OBJC = $(CROSS)objcopy
DUMP = $(CROSS)objdump

CFLAGS := -mabi=ilp32 \
          -march=rv32im \
          -Wl,-Bstatic,-T,flash_$(EXEC_TYPE).lds,--strip-debug \
          -ffreestanding \
          -nostdlib

SRC_PATH := $(ROOT_PATH)/crt/startup.s \
            $(ROOT_PATH)/crt/src/tinyuart.c \
            $(ROOT_PATH)/crt/src/tinystring.c \
            $(ROOT_PATH)/crt/src/tinyprintf.c \
            $(ROOT_PATH)/crt/src/tinygpio.c \
            $(ROOT_PATH)/crt/src/tinytim.c \
            $(ROOT_PATH)/crt/src/tinyarchinfo.c \
            $(ROOT_PATH)/crt/src/tinyrng.c \
            $(ROOT_PATH)/crt/src/tinyhpuart.c \
            $(ROOT_PATH)/crt/src/tinypwm.c \
            $(ROOT_PATH)/crt/src/tinyps2.c \
            $(ROOT_PATH)/crt/src/tinyi2c.c \
            $(ROOT_PATH)/crt/src/tinylcd.c \
            $(ROOT_PATH)/crt/src/tinypsram.c \
            $(ROOT_PATH)/crt/src/tinybench.c \
            $(ROOT_PATH)/crt/src/tinysh.c \
            $(ROOT_PATH)/crt/src/firmware.c

LDS_PATH := $(ROOT_PATH)/crt/flash_$(EXEC_TYPE).lds

firmware:
	@mkdir -p .sw_build
	cd .sw_build && ($(CP) -P -o flash_$(EXEC_TYPE).lds $(LDS_PATH))
	cd .sw_build && ($(CC) $(CFLAGS) -I$(ROOT_PATH)/crt/inc -o $@ $(SRC_PATH))
	cd .sw_build && ($(OBJC) -O verilog $@ $(FIRMWARE_NAME).hex)
	cd .sw_build && ($(OBJC) -O binary $@ $(FIRMWARE_NAME).bin)
	cd .sw_build && ($(DUMP) -d $@ > $(FIRMWARE_NAME).txt)
	cd .sw_build && ($(DUMP) -D $@ > $(FIRMWARE_NAME)_all.txt)