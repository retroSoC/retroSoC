"""Board-specific settings consumed by the locked RT-Thread build system."""
import os

ARCH = 'risc-v'
CPU = 'retrosoc'
CROSS_TOOL = PLATFORM = 'gcc'
EXEC_PATH = os.environ['RTT_EXEC_PATH']
PREFIX = 'riscv64-unknown-elf-'
CC = AS = LINK = PREFIX + 'gcc'
CXX = PREFIX + 'g++'
AR = PREFIX + 'ar'
TARGET_EXT = 'elf'
DEVICE = '-march=rv64imafdc_zicbom_zicsr_zifencei -mabi=lp64d -mcmodel=medany'
CFLAGS = DEVICE + ' -O2 -g -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -Wall'
AFLAGS = DEVICE + ' -g -x assembler-with-cpp'
LFLAGS = DEVICE + ' -nostdlib -nostartfiles -Wl,--gc-sections,-Map=rtthread.map -T linker.ld'
POST_ACTION = PREFIX + 'objcopy -O binary $TARGET rtthread.bin'
