BUILD_DIR         := $(RTL_PATH)/.verilator_build
SOC_CSRC_HOME     += $(RTL_PATH)/csrc
SOC_CSRC_LIB_HOME += $(RTL_PATH)/csrc
SOC_CXXFILES      += $(sort $(wildcard $(SOC_CSRC_HOME)/*.cpp))
SOC_CSRC_INCLPATH += -I$(SOC_CSRC_HOME)
SOC_CSRC_INCLPATH += $(foreach val, $(SOC_CSRC_LIB_HOME), -I$(val))

SOC_VSRC_TOP      := retrosoc_top
SOC_VSRC_HOME     += $(RTL_PATH)/vsrc
SOC_COMPILE_HOME  := $(BUILD_DIR)/emu_compile



SOC_VXXFILES      := $(RTL_FLIST)
SOC_VXXFILES      += $(RTL_PATH)/../ip/tb/ESP_PSRAM64H.sv
SOC_VXXFILES      += $(RTL_PATH)/vsrc/flash_read_binder.sv
SOC_VXXFILES      += $(RTL_PATH)/vsrc/QSPIFlash.sv
SOC_VXXFILES      += $(RTL_PATH)/vsrc/retrosoc_top.sv
SOC_VSRC_INCLPATH += -I$(SOC_VSRC_HOME)

VERILATOR          ?= verilator
VERILATOR_CXXFLAGS += -std=c++17 -Wall $(SOC_CSRC_INCLPATH) -DDUMP_WAVE_FST
VERILATOR_FLAGS    += --cc --exe --no-timing --top-module $(SOC_VSRC_TOP)
VERILATOR_FLAGS    += --x-assign unique -O3 -CFLAGS "$(VERILATOR_CXXFLAGS)"
VERILATOR_FLAGS    += --trace-fst --assert --stats-vars --output-split 30000 --output-split-cfuncs 30000
VERILATOR_FLAGS    += --timescale "1ns/1ns" -Wno-fatal
VERILATOR_FLAGS    += -o $(BUILD_DIR)/emu
VERILATOR_FLAGS    += -Mdir $(SOC_COMPILE_HOME)
VERILATOR_FLAGS    += $(SOC_VSRC_INCLPATH) $(SOC_CXXFILES) $(SOC_VXXFILES)

SOC_SIM_TIME ?= 40

CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
export OBJCACHE = ccache
export CCACHE_DIR = $(BUILD_DIR)/ccache
export CCACHE_TEMPDIR = $(BUILD_DIR)/ccache/tmp
endif

lint: gen_mpw_code generate_filelist
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/ccache/tmp

comp: lint 
	$(VERILATOR) $(VERILATOR_FLAGS) > $(BUILD_DIR)/verilating.log 2>&1
	+$(MAKE) VM_PARALLEL_BUILDS=1 OPT_FAST="-O3" -C $(SOC_COMPILE_HOME) \
		-f V$(SOC_VSRC_TOP).mk > $(BUILD_DIR)/compile.log 2>&1

sim: comp
	@test -f $(ROOT_PATH)/.sw_build/$(FIRMWARE_NAME).bin || { \
		echo "firmware image missing; run 'make firmware' first" >&2; exit 1; }
	$(BUILD_DIR)/emu -i $(ROOT_PATH)/.sw_build/$(FIRMWARE_NAME).bin \
		-s $(RTL_SIM_CORESEL) -t $(SOC_SIM_TIME)

wave:

clean:
	rm -rf $(BUILD_DIR)

.PHONY: comp sim clean
