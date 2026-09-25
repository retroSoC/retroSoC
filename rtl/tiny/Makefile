export CCACHE_DIR := $(CACHE_ROOT)/ccache/verilator
export CCACHE_TEMPDIR := $(CACHE_ROOT)/ccache/verilator/tmp

TINY_GENERATED_DIR       := $(VARIANT_ROOT)/generated/tiny
GENERATED_FL_DIR         := $(FLOW_FILELIST_DIR)
FILELIST_STAMP           := $(GENERATED_FL_DIR)/.stamp
MEMORY_MAP_DIR           := $(TINY_GENERATED_DIR)/memory_map
MEMORY_MAP_C_DIR         := $(MEMORY_MAP_DIR)/include
MEMORY_MAP_LINKER_DIR    := $(MEMORY_MAP_DIR)/linker
MEMORY_MAP_STAMP         := $(FILELIST_STAMP)
PIN_MAP_DIR              := $(TINY_GENERATED_DIR)/pin_map
SOC_TOPOLOGY_INCLUDE_DIR := $(TINY_GENERATED_DIR)/include
SOC_TOPOLOGY_STAMP       := $(FILELIST_STAMP)
SOC_IRQ_METADATA         := $(SOC_TOPOLOGY_INCLUDE_DIR)/retrosoc/generated/irq_metadata.h
USER_EXTENSIONS_DIR      := $(TINY_GENERATED_DIR)
USER_EXTENSIONS_STAMP    := $(FILELIST_STAMP)
ARCHINFO_METADATA_DIR    := $(TINY_GENERATED_DIR)/archinfo
ARCHINFO_METADATA_SCRIPT := $(ROOT_PATH)/rtl/managed/clusterip/archinfo/scripts/generate_metadata.py
ARCHINFO_METADATA_STAMP  := $(ARCHINFO_METADATA_DIR)/.stamp
TINY_MAPS                := $(wildcard $(RTL_PATH)/address_map/*.json $(RTL_PATH)/pin_map/*.json $(RTL_PATH)/integration/*.json)
TINY_TEMPLATES           := $(wildcard $(RTL_PATH)/filelist/*.fl)
TINY_TOOLS               := $(ROOT_PATH)/scripts/generate_tiny.py $(wildcard $(ROOT_PATH)/scripts/rtl/*.py)

$(ARCHINFO_METADATA_STAMP): $(LOCK_FILE) $(wildcard $(ARCHINFO_METADATA_SCRIPT))
	@test -f $(ARCHINFO_METADATA_SCRIPT) || { echo "Run Tiny setup first" >&2; exit 1; }
	$(PYTHON) $(ARCHINFO_METADATA_SCRIPT) --repo-root $(ROOT_PATH) --lock $(LOCK_FILE) \
		--config-digest $(CONFIG_DIGEST) $(if $(filter YES,$(BUILD_RELEASE)),--release) \
		--output-sv $(ARCHINFO_METADATA_DIR)/archinfo_integration_metadata.svh \
		--output-c $(ARCHINFO_METADATA_DIR)/archinfo_integration_metadata.h
	@touch $@

$(FILELIST_STAMP): $(ROOT_PATH)/Makefile $(RTL_PATH)/Makefile $(TINY_MAPS) $(TINY_TEMPLATES) $(TINY_TOOLS) $(ARCHINFO_METADATA_STAMP)
	$(PYTHON) $(ROOT_PATH)/scripts/generate_tiny.py --output $(TINY_GENERATED_DIR) \
		--filelists $(GENERATED_FL_DIR) $(foreach define,$(DEF_LIST),--define $(define))
	@touch $@

$(SOC_IRQ_METADATA): $(FILELIST_STAMP)
	@test -f $@

generate_filelist memory-map pin-map soc-topology user-extensions: $(FILELIST_STAMP)
archinfo-metadata: $(ARCHINFO_METADATA_STAMP)
check-memory-map:
	$(PYTHON) $(ROOT_PATH)/scripts/rtl/generate_memory_map.py --map $(RTL_PATH)/address_map/memory_map.json --check
check-pin-map:
	$(PYTHON) $(ROOT_PATH)/scripts/rtl/generate_pin_map.py --map $(RTL_PATH)/pin_map/pin_map.json --check
check-soc-topology:
	$(PYTHON) $(ROOT_PATH)/scripts/generate_tiny.py --check
check-clock-reset-domains:
	$(PYTHON) $(ROOT_PATH)/scripts/check_clock_reset_domains.py --map $(RTL_PATH)/integration/clock_reset_domains.json --root $(ROOT_PATH)

RTL_FILELISTS    := $(addprefix $(GENERATED_FL_DIR)/,def.fl inc.fl commonip.fl clusterip.fl ip.fl tech.fl core_hazard3.fl top.fl)
RTL_FLIST        := $(foreach filelist,$(RTL_FILELISTS),-f $(filelist))
PDK_FILELIST     := $(GENERATED_FL_DIR)/pdk_ihp130.fl
TINY_TB_FLIST    := -f $(GENERATED_FL_DIR)/tb.fl
TOP_DESIGN       := retrosoc_tiny_asic
RTL_NAME         := retrosoc_tiny_asic
OPENSTA_NETLIST  := $(SYN_BUILD_ROOT)/out/$(RTL_NAME)_yosys.v
OPENSTA_CONFIG   := $(SYN_BUILD_ROOT)/out/$(RTL_NAME)_yosys.config
NETLIST_PATH     := $(OPENSTA_NETLIST)
TINY_CONVERTED   := $(SIM_BUILD_ROOT)/converted_soc.v
TINY_DEPFILE     := $(SIM_BUILD_ROOT)/sources.d
TINY_LINT_LOG    := $(VARIANT_ROOT)/lint/verilator/lint.log
SOC_SIM_TIME     ?= 1800
TINY_SIM_TIMEOUT ?= 20000000
VERILATOR        ?= verilator
IVERILOG         ?= iverilog
VVP              ?= vvp

include $(ROOT_PATH)/rtl/mk/software.mk
-include $(TINY_DEPFILE)

$(TINY_CONVERTED): $(FILELIST_STAMP)
	@mkdir -p $(@D)
	$(PYTHON) $(ROOT_PATH)/scripts/rtl/convt_sv2v.py $(RTL_FLIST) --output $@
	$(PYTHON) $(ROOT_PATH)/scripts/rtl/filelist_deps.py $(RTL_FLIST) \
		--target $@ --output $(TINY_DEPFILE)

ifeq ($(SIMU),VERILATOR)
$(SIM_BUILD_ROOT)/emu: $(FILELIST_STAMP) $(wildcard $(RTL_PATH)/dv/*.sv)
	@mkdir -p $(SIM_BUILD_ROOT) $(CCACHE_TEMPDIR)
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool verilator \
		--log $(SIM_BUILD_ROOT)/compile.log --result $(SIM_BUILD_ROOT)/result-compile.json -- \
		$(VERILATOR) --binary --timing --assert -j $(JOBS) --top-module $(RTL_TOP) \
		-Wno-fatal --timescale 1ns/1ps --Mdir $(SIM_BUILD_ROOT)/obj_dir -o $(SIM_BUILD_ROOT)/emu \
		$(RTL_FLIST) -f $(PDK_FILELIST) $(TINY_TB_FLIST)
	$(PYTHON) $(ROOT_PATH)/scripts/rtl/filelist_deps.py $(RTL_FLIST) $(TINY_TB_FLIST) \
		--target $@ --output $(TINY_DEPFILE)
comp: $(SIM_BUILD_ROOT)/emu
TINY_RUN := timeout --foreground $(SOC_SIM_TIME)s $(SIM_BUILD_ROOT)/emu
else
$(SIM_BUILD_ROOT)/simv: $(TINY_CONVERTED) $(wildcard $(RTL_PATH)/dv/*.sv)
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool iverilog \
		--log $(SIM_BUILD_ROOT)/compile.log --result $(SIM_BUILD_ROOT)/result-compile.json -- \
		$(IVERILOG) -g2012 -gno-specify -s $(RTL_TOP) -o $@ -f $(GENERATED_FL_DIR)/def.fl \
		-f $(GENERATED_FL_DIR)/inc.fl -f $(PDK_FILELIST) $(TINY_TB_FLIST) $(TINY_CONVERTED)
comp: $(SIM_BUILD_ROOT)/simv
TINY_RUN := $(VVP) $(SIM_BUILD_ROOT)/simv
endif

rtl-lint: $(FILELIST_STAMP) | manifest
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool rtl-lint \
		--log $(TINY_LINT_LOG) --result $(VARIANT_ROOT)/lint/verilator/result-rtl-lint.json -- \
		$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps --Wall -Wno-fatal \
		--top-module retrosoc_tiny_asic $(RTL_FLIST) -f $(PDK_FILELIST)
check-rtl-lint: rtl-lint
	$(PYTHON) $(ROOT_PATH)/scripts/analyze_warnings.py check --root $(ROOT_PATH) \
		--profile $(PROFILE_NAME) --variant-root $(VARIANT_ROOT) --tool rtl-lint \
		--output $(META_DIR)/rtl-lint-warnings.json

sim: comp firmware | manifest
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool $(SIM_TOOL_NAME)-sim \
		--log $(SIM_BUILD_ROOT)/sim.log --result $(SIM_BUILD_ROOT)/result-sim.json -- \
		$(TINY_RUN) +firmware=$(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex +max_cycles=$(TINY_SIM_TIMEOUT)
	$(PYTHON) $(ROOT_PATH)/scripts/check_simulation.py --log $(SIM_BUILD_ROOT)/sim.log \
		--result $(SIM_BUILD_ROOT)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

netcomp: $(FILELIST_STAMP)
	@mkdir -p $(NETLIST_SIM_ROOT)
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool iverilog \
		--log $(NETLIST_SIM_ROOT)/compile.log --result $(NETLIST_SIM_ROOT)/result-compile.json -- \
		$(IVERILOG) -g2012 -gno-specify -DRETROSOC_SOC__TINY_NETLIST -s $(RTL_TOP) -o $(NETLIST_SIM_ROOT)/simv \
		-f $(GENERATED_FL_DIR)/def.fl -f $(GENERATED_FL_DIR)/inc.fl -f $(PDK_FILELIST) \
		$(TINY_TB_FLIST) $(NETLIST_PATH)
netsim: netcomp firmware | manifest
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-sim \
		--log $(NETLIST_SIM_ROOT)/sim.log --result $(NETLIST_SIM_ROOT)/result-sim.json -- \
		$(VVP) $(NETLIST_SIM_ROOT)/simv +firmware=$(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex +max_cycles=$(TINY_SIM_TIMEOUT)
	$(PYTHON) $(ROOT_PATH)/scripts/check_simulation.py --log $(NETLIST_SIM_ROOT)/sim.log \
		--result $(NETLIST_SIM_ROOT)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

.PHONY: generate_filelist memory-map pin-map soc-topology user-extensions archinfo-metadata \
	check-memory-map check-pin-map check-soc-topology check-clock-reset-domains comp sim \
	rtl-lint check-rtl-lint netcomp netsim netsim-boot

TINY_BOOT_ELF := $(SW_BUILD_DIR)/tiny_boot.elf
$(TINY_BOOT_ELF): $(ROOT_PATH)/app/asm/tiny_boot.S $(FILELIST_STAMP)
	@mkdir -p $(SW_BUILD_DIR)
	$(CC) -march=rv32im_zicsr -mabi=ilp32 -nostdlib -I$(MEMORY_MAP_C_DIR) -I$(SOC_TOPOLOGY_INCLUDE_DIR) \
		-Wl,-Ttext=0x0,--entry=_start,--build-id=none -o $@ $<
	$(OBJC) -O verilog $@ $(SW_BUILD_DIR)/tiny_boot.hex
	$(OBJC) -O binary $@ $(SW_BUILD_DIR)/tiny_boot.bin

tiny-boot-image: $(TINY_BOOT_ELF)
netsim-boot: netcomp tiny-boot-image | manifest
	$(PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-sim \
		--log $(NETLIST_SIM_ROOT)/sim.log --result $(NETLIST_SIM_ROOT)/result-sim.json -- \
		$(VVP) $(NETLIST_SIM_ROOT)/simv +firmware=$(SW_BUILD_DIR)/tiny_boot.hex +max_cycles=100000
	$(PYTHON) $(ROOT_PATH)/scripts/check_simulation.py --log $(NETLIST_SIM_ROOT)/sim.log \
		--result $(NETLIST_SIM_ROOT)/result-sim-check.json --require 'SIM_TEST_PASS'

.PHONY: tiny-boot-image