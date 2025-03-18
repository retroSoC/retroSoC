# software
FIRMWARE_NAME := retrosoc_fw

CROSS=riscv32-unknown-elf-
CFLAGS := -mabi=ilp32 \
          -march=rv32im \
          -Wl,-Bstatic,-T,retrosoc_sections.lds,--strip-debug \
          -ffreestanding \
          -nostdlib

SRC_PATH := ../../../crt/start.s \
            ../../../crt/tinyuart.c \
            ../../../crt/tinystring.c \
            ../../../crt/tinyprintf.c \
            ../../../crt/tinygpio.c \
            ../../../crt/tinytim.c \
            ../../../crt/tinyarchinfo.c \
            ../../../crt/tinyrng.c \
            ../../../crt/tinyhpuart.c \
            ../../../crt/tinypwm.c \
            ../../../crt/tinyps2.c \
            ../../../crt/tinyi2c.c \
            ../../../crt/tinylcd.c \
            ../../../crt/tinypsram.c \
            ../../../crt/tinybench.c \
            ../../../crt/tinysh.c \
            ../../../crt/firmware.c

LDS_PATH := ../../../crt/sections.lds

$(FIRMWARE_NAME).elf:
	@mkdir -p .sw_build
	cd .sw_build && ($(CROSS)cpp -P -o retrosoc_sections.lds $(LDS_PATH))
	cd .sw_build && ($(CROSS)gcc $(CFLAGS) -I../../../crt -o $@ $(SRC_PATH))
	cd .sw_build && ($(CROSS)objcopy -O verilog $@ $(FIRMWARE_NAME).hex)
	cd .sw_build && (sed -i 's/@30000000/@00000000/g' retrosoc_fw.hex)
	cd .sw_build && ($(CROSS)objcopy -O binary  $@ $(FIRMWARE_NAME).bin)
	cd .sw_build && ($(CROSS)objdump -d $@ > $(FIRMWARE_NAME).txt)