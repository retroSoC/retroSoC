BUILD_DIR         := $(RTL_PATH)/.verilator_build
SOC_CSRC_HOME     += $(RTL_PATH)/csrc
SOC_CSRC_LIB_HOME += $(RTL_PATH)/csrc
SOC_CXXFILES      += $(shell find $(SOC_CSRC_HOME) -name "*.cpp")
SOC_CSRC_INCLPATH += -I$(SOC_CSRC_HOME)
SOC_CSRC_INCLPATH += $(foreach val, $(SOC_CSRC_LIB_HOME), -I$(val))

SOC_VSRC_TOP      := retrosoc_top
SOC_VSRC_HOME     += $(RTL_PATH)/vsrc
SOC_COMPILE_HOME  := $(BUILD_DIR)/emu_compile

ifeq ($(PDK), IHP130)
    SOC_VXXFILES := -f $(RTL_PATH)/../filelist/pdk_ihp130.fl
else ifeq ($(PDK), S110)
    SOC_VXXFILES := -f $(RTL_PATH)/../filelist/pdk_s110.fl
else ifeq ($(PDK), ICS55)
    SOC_VXXFILES := -f $(RTL_PATH)/../filelist/pdk_ics55.fl
endif


ifeq ($(CORE), PICORV32)
    SOC_VXXFILES += -f $(RTL_PATH)/filelist/core_picorv32.fl
else ifeq ($(CORE), MDD)
    SOC_VXXFILES += -f $(RTL_PATH)/mpw/.build/core/core.fl
endif

ifeq ($(IP), MDD)
    SOC_VXXFILES += -f  $(RTL_PATH)/mpw/.build/ip/ip.fl
endif

SOC_VXXFILES      += -f $(RTL_PATH)/filelist/def.fl
SOC_VXXFILES      += -f $(RTL_PATH)/filelist/inc_verilator.fl
SOC_VXXFILES      += -f $(RTL_PATH)/filelist/ip.fl
SOC_VXXFILES      += -f $(RTL_PATH)/filelist/top.fl
SOC_VXXFILES      += -f $(RTL_PATH)/filelist/tech.fl
SOC_VXXFILES      += $(RTL_PATH)/../clusterip/uart/model/rs232.sv
SOC_VXXFILES      += $(RTL_PATH)/../ip/native/ESP_PSRAM64H.sv
SOC_VXXFILES      += $(shell find $(SOC_VSRC_HOME) -name "*.sv")
SOC_VSRC_INCLPATH += -I$(SOC_VSRC_HOME)
# SOC_VSRC_INCLPATH += -I$(RTL_PATH)/perip/spi/rtl


VERILATOR_CXXFLAGS += -std=c++17 -static -Wall $(SOC_CSRC_INCLPATH) -DDUMP_WAVE_FST
VERILATOR_FLAGS    += --cc --exe --no-timing --top-module $(SOC_VSRC_TOP)
VERILATOR_FLAGS    += --x-assign unique -O3 -CFLAGS "$(VERILATOR_CXXFLAGS)"
VERILATOR_FLAGS    += --trace-fst --assert --stats-vars --output-split 30000 --output-split-cfuncs 30000
VERILATOR_FLAGS    += --timescale "1ns/1ns" -Wno-fatal
VERILATOR_FLAGS    += -o $(BUILD_DIR)/emu
VERILATOR_FLAGS    += -Mdir $(SOC_COMPILE_HOME)
VERILATOR_FLAGS    += $(SOC_VSRC_INCLPATH) $(SOC_CXXFILES) $(SOC_VXXFILES)

SOC_SIM_TIME ?= -1

CCACHE := $(if $(shell which ccache),ccache,)
ifneq ($(CCACHE),)
export OBJCACHE = ccache
endif

lint: gen_mpw_code
	@mkdir -p $(BUILD_DIR)

comp: lint
	verilator $(VERILATOR_FLAGS) > $(BUILD_DIR)/verilating.log 2>&1
	$(MAKE) VM_PARALLEL_BUILDS=1 OPT_FAST="-O3" -C $(SOC_COMPILE_HOME) -f V$(SOC_VSRC_TOP).mk -j$(nproc) > $(BUILD_DIR)/compile.log 2>&1

sim: comp
	$(BUILD_DIR)/emu -i .sw_build/retrosoc_fw.bin -t 360

# $(BUILD_DIR)/emu -t $(SOC_SIM_TIME) -i $(RTL_PATH)/.sw_build/retrosoc_fw.bin
# $(BUILD_DIR)/emu -i app/asm/hello-asm.bin

wave:

clean:
	rm -rf .verilator_build

.PHONY: comp sim clean

