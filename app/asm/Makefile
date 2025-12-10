.PHONY: all

GCC = riscv32-unknown-elf-

AS = $(GCC)as
LD = $(GCC)ld
OBJDUMP = $(GCC)objdump
OBJCOPY = $(GCC)objcopy
AS_FLAGS = -fno-pic -march=rv32im -mabi=ilp32
LDFLAGS  = -T flash.ld -melf32lriscv
APP ?= hello
APP_ALL = $(APP)-asm

all: $(APP).s
	$(AS) $(AS_FLAGS) $(APP).s -o $(APP_ALL).o
	$(LD) $(LDFLAGS) $(APP_ALL).o -o $(APP_ALL).elf
	$(OBJDUMP) -d $(APP_ALL).elf > $(APP_ALL).txt
	$(OBJCOPY) -S -O binary $(APP_ALL).elf $(APP_ALL).bin
	$(OBJCOPY) -S -I binary -O verilog $(APP_ALL).bin $(APP_ALL).flash

clean:
	rm -rf $(APP_ALL).o $(APP_ALL).elf $(APP_ALL).txt $(APP_ALL).bin $(APP_ALL).flash