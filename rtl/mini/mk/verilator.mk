BUILD_DIR         := $(SIM_BUILD_ROOT)
RTL_LINT_DIR      := $(VARIANT_ROOT)/lint/verilator
SOC_CSRC_HOME     += $(RTL_PATH)/dv/verilator/csrc
SOC_CSRC_LIB_HOME += $(RTL_PATH)/dv/verilator/csrc
SOC_CXXFILES      += $(sort $(wildcard $(SOC_CSRC_HOME)/*.cpp))
SOC_CSRC_INCLPATH += -I$(SOC_CSRC_HOME)
SOC_CSRC_INCLPATH += $(foreach val, $(SOC_CSRC_LIB_HOME), -I$(val))

SOC_VSRC_TOP     := retrosoc_top
SOC_VSRC_HOME    += $(RTL_PATH)/dv/verilator/rtl
SOC_COMPILE_HOME := $(BUILD_DIR)/emu_compile

SOC_VXXFILES      := $(RTL_FLIST)
SOC_VXXFILES      += $(RTL_PATH)/dv/model/ESP_PSRAM64H.sv
SOC_VXXFILES      += $(RTL_PATH)/dv/verilator/rtl/flash_read_binder.sv
SOC_VXXFILES      += $(RTL_PATH)/dv/verilator/rtl/QSPIFlash.sv
SOC_VXXFILES      += $(RTL_PATH)/dv/verilator/rtl/retrosoc_top.sv
SOC_VSRC_INCLPATH += -I$(SOC_VSRC_HOME)

VERILATOR          ?= verilator
VERILATOR_JOBS     ?= $(JOBS)
VERILATOR_CXXFLAGS += -std=c++17 -Wall $(SOC_CSRC_INCLPATH) -DDUMP_WAVE_FST
VERILATOR_FLAGS    += --cc --exe --no-timing --top-module $(SOC_VSRC_TOP)
VERILATOR_FLAGS    += --x-assign unique -O3 -CFLAGS "$(VERILATOR_CXXFLAGS)"
VERILATOR_FLAGS    += --trace-fst --assert --stats-vars --output-split 30000 --output-split-cfuncs 30000
VERILATOR_FLAGS    += --timescale "1ns/1ns" -Wno-fatal
VERILATOR_FLAGS    += -o $(BUILD_DIR)/emu
VERILATOR_FLAGS    += -Mdir $(SOC_COMPILE_HOME)
VERILATOR_FLAGS    += $(SOC_VSRC_INCLPATH) $(SOC_CXXFILES) $(SOC_VXXFILES)

RTL_LINT_FLAGS := --lint-only --no-timing --top-module $(SOC_VSRC_TOP)
RTL_LINT_FLAGS += --assert --Wall --timescale "1ns/1ns" -Wno-fatal
RTL_LINT_FLAGS += $(SOC_VSRC_INCLPATH) $(SOC_VXXFILES)

SOC_SIM_TIME            ?= 180
VERILATOR_STAMP         := $(BUILD_DIR)/verilate.stamp
VERILATOR_DEPFILE       := $(BUILD_DIR)/verilate.d
VERILATOR_EMU           := $(BUILD_DIR)/emu
RTL_LINT_STAMP          := $(RTL_LINT_DIR)/rtl-lint.stamp
RTL_LINT_DEPFILE        := $(RTL_LINT_DIR)/rtl-lint.d
VERILATOR_EXTRA_SOURCES := $(RTL_PATH)/dv/model/ESP_PSRAM64H.sv \
                           $(RTL_PATH)/dv/verilator/rtl/flash_read_binder.sv \
                           $(RTL_PATH)/dv/verilator/rtl/QSPIFlash.sv \
                           $(RTL_PATH)/dv/verilator/rtl/retrosoc_top.sv \
                           $(SOC_CXXFILES) $(wildcard $(SOC_CSRC_HOME)/*.h) \
                           $(wildcard $(SOC_CSRC_HOME)/*.hpp)

-include $(VERILATOR_DEPFILE) $(RTL_LINT_DEPFILE)

CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
export OBJCACHE = ccache
export CCACHE_DIR = $(CACHE_ROOT)/ccache/verilator
export CCACHE_TEMPDIR = $(CACHE_ROOT)/ccache/verilator/tmp
endif

$(VERILATOR_STAMP): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) $(VERILATOR_EXTRA_SOURCES)
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(CCACHE_TEMPDIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool verilator \
		--log $(BUILD_DIR)/verilating.log --result $(BUILD_DIR)/result-verilate.json \
		-- $(VERILATOR) $(VERILATOR_FLAGS)
	python3 $(RTL_PATH)/script/filelist_deps.py $(RTL_FLIST) \
		$(foreach source,$(VERILATOR_EXTRA_SOURCES),--extra $(source)) \
		--target $@ --output $(VERILATOR_DEPFILE)
	@touch $@

$(VERILATOR_EMU): $(VERILATOR_STAMP)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool verilator-compile \
		--log $(BUILD_DIR)/compile.log --result $(BUILD_DIR)/result-compile.json \
		-- make -j$(VERILATOR_JOBS) VM_PARALLEL_BUILDS=1 OPT_FAST=-O3 -C $(SOC_COMPILE_HOME) \
		-f V$(SOC_VSRC_TOP).mk

$(RTL_LINT_STAMP): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) $(VERILATOR_EXTRA_SOURCES)
	@mkdir -p $(RTL_LINT_DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool rtl-lint \
		--log $(RTL_LINT_DIR)/lint.log --result $(RTL_LINT_DIR)/result-rtl-lint.json \
		-- $(VERILATOR) $(RTL_LINT_FLAGS)
	python3 $(RTL_PATH)/script/filelist_deps.py $(RTL_FLIST) \
		$(foreach source,$(VERILATOR_EXTRA_SOURCES),--extra $(source)) \
		--target $@ --output $(RTL_LINT_DEPFILE)
	@touch $@

rtl-lint: $(RTL_LINT_STAMP) | manifest

check-rtl-lint: rtl-lint
	python3 $(ROOT_PATH)/scripts/analyze_warnings.py check --root $(ROOT_PATH) \
		--profile $(PROFILE_NAME) --variant-root $(VARIANT_ROOT) --tool rtl-lint \
		--output $(META_DIR)/rtl-lint-warnings.json

lint: rtl-lint
comp: $(VERILATOR_EMU)

sim: comp
	@test -f $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).bin || { \
		echo "firmware image missing; run 'make firmware' first" >&2; exit 1; }
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool verilator-sim --stream-bytes \
		--log $(BUILD_DIR)/sim.log --result $(BUILD_DIR)/result-sim.json \
		--cwd $(BUILD_DIR) -- $(BUILD_DIR)/emu -i $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).bin \
		-t $(SOC_SIM_TIME)
	python3 $(ROOT_PATH)/scripts/check_simulation.py --log $(BUILD_DIR)/sim.log \
		--result $(BUILD_DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

comp sim: | manifest

wave:

clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(BUILD_DIR)
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(RTL_LINT_DIR)

.PHONY: lint rtl-lint check-rtl-lint comp sim clean