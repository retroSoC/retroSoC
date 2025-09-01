WAVE_FORMAT ?= NONE

ROOT_PATH         := $(shell pwd)/..
BUILD_DIR         := $(ROOT_PATH)/.verilator_build
SOC_CSRC_HOME     += $(ROOT_PATH)/csrc
SOC_CSRC_LIB_HOME += $(ROOT_PATH)/csrc
SOC_CXXFILES      += $(shell find $(SOC_CSRC_HOME) -name "*.cpp")
SOC_CSRC_INCLPATH += -I$(SOC_CSRC_HOME)
SOC_CSRC_INCLPATH += $(foreach val, $(SOC_CSRC_LIB_HOME), -I$(val))

SOC_VSRC_TOP      := retrosoc_top
SOC_VSRC_HOME     += $(ROOT_PATH)/vsrc
SOC_VSRC_LIB_HOME += $(ROOT_PATH)/vsrc
SOC_COMPILE_HOME  := $(BUILD_DIR)/emu-compile
SOC_VXXFILES      += $(shell find $(SOC_VSRC_HOME) -name "*.sv")
SOC_VSRC_INCLPATH += -I$(SOC_VSRC_HOME)
SOC_VSRC_INCLPATH += -I$(ROOT_PATH)/perip/uart16550/rtl
SOC_VSRC_INCLPATH += -I$(ROOT_PATH)/perip/spi/rtl


SOC_CXXFLAGS += -std=c++11 -static -Wall $(SOC_CSRC_INCLPATH) -DDUMP_WAVE_$(WAVE_FORMAT)
SOC_FLAGS    += --cc --exe --top-module $(SOC_VSRC_TOP)
SOC_FLAGS    += --x-assign unique -O3 -CFLAGS "$(SOC_CXXFLAGS)"
SOC_FLAGS    += --trace-fst --assert --stats-vars --output-split 30000 --output-split-cfuncs 30000 
SOC_FLAGS    += --timescale "1ns/1ns" -Wno-fatal
SOC_FLAGS    += -o $(BUILD_DIR)/emu
SOC_FLAGS    += -Mdir $(BUILD_DIR)/emu-compile
SOC_FLAGS    += $(SOC_VSRC_INCLPATH) $(SOC_CXXFILES) $(SOC_VXXFILES)

SOC_SIM_TIME ?= -1

CCACHE := $(if $(shell which ccache),ccache,)
ifneq ($(CCACHE),)
export OBJCACHE = ccache
endif

comp:
	verilator $(SOC_FLAGS)
	$(MAKE) VM_PARALLEL_BUILDS=1 OPT_FAST="-O3" -C $(SOC_COMPILE_HOME) -f V$(SOC_VSRC_TOP).mk -j$(nproc)

sim:
	$(BUILD_DIR)/emu -t $(SOC_SIM_TIME) -i $(ROOT_PATH)/.sw_build/retrosoc_fw.bin

clean:
	rm -rf .verilator_build

.PHONY: comp sim clean

