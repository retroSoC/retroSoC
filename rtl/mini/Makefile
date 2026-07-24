GENERATED_FL_DIR           := $(FLOW_FILELIST_DIR)
MEMORY_MAP_SOURCE          := $(RTL_PATH)/address_map/memory_map.json
MEMORY_MAP_SCRIPT          := $(RTL_PATH)/address_map/generate_memory_map.py
MEMORY_MAP_DIR             := $(VARIANT_ROOT)/generated/memory_map
MEMORY_MAP_STAMP           := $(MEMORY_MAP_DIR)/.stamp
MEMORY_MAP_RTL_DIR         := $(MEMORY_MAP_DIR)/rtl
MEMORY_MAP_C_DIR           := $(MEMORY_MAP_DIR)/include
MEMORY_MAP_LINKER_DIR      := $(MEMORY_MAP_DIR)/linker
MEMORY_MAP_FILELIST        := $(MEMORY_MAP_DIR)/memory_map.fl
PIN_MAP_SOURCE             := $(RTL_PATH)/pin_map/pin_map.json
PIN_MAP_SCRIPT             := $(RTL_PATH)/pin_map/generate_pin_map.py
PIN_MAP_DIR                := $(VARIANT_ROOT)/generated/pin_map
PIN_MAP_STAMP              := $(PIN_MAP_DIR)/.stamp
PIN_MAP_FILELIST           := $(PIN_MAP_DIR)/pin_map.fl
SOC_TOPOLOGY_SOURCE        := $(RTL_PATH)/integration/soc_topology.json
SOC_TOPOLOGY_SCRIPT        := $(RTL_PATH)/integration/generate_soc_topology.py
SOC_TOPOLOGY_DIR           := $(VARIANT_ROOT)/generated/soc_topology
SOC_TOPOLOGY_STAMP         := $(SOC_TOPOLOGY_DIR)/.stamp
SOC_TOPOLOGY_FILELIST      := $(SOC_TOPOLOGY_DIR)/soc_topology.fl
USER_EXTENSIONS_SOURCE     := $(RTL_PATH)/integration/user_extensions.json
USER_EXTENSIONS_SCRIPT     := $(RTL_PATH)/integration/generate_user_extensions.py
USER_EXTENSIONS_DIR        := $(VARIANT_ROOT)/generated/user_extensions
USER_EXTENSIONS_STAMP      := $(USER_EXTENSIONS_DIR)/.stamp
USER_EXTENSIONS_FILELIST   := $(USER_EXTENSIONS_DIR)/user_extensions.fl
CLOCK_RESET_DOMAINS_SOURCE := $(RTL_PATH)/integration/clock_reset_domains.json
CLOCK_RESET_DOMAINS_SCRIPT := $(ROOT_PATH)/scripts/check_clock_reset_domains.py
MPW_STAMP                  := $(CACHE_ROOT)/stamps/mpw-$(LOCK_DIGEST).prepared
MPW_OUTPUT_DIR             := $(VARIANT_ROOT)/generated/mpw/$(SIM_TOOL_NAME)
MPW_VARIANT_STAMP          := $(MPW_OUTPUT_DIR)/.stamp
FILELIST_STAMP             := $(GENERATED_FL_DIR)/.stamp
FILELIST_TEMPLATES         := $(sort $(wildcard $(ROOT_PATH)/rtl/filelist/pdk_*.fl) \
                      $(wildcard $(RTL_PATH)/filelist/*.fl) $(RTL_PATH)/lint.msg)

$(MPW_STAMP):
	@test -d $(ROOT_PATH)/rtl/managed/mpw/.git || { \
		echo "missing $(ROOT_PATH)/rtl/managed/mpw; run 'make setup-mpw' first" >&2; \
		exit 1; \
		}
	python3 $(ROOT_PATH)/scripts/prepare_mpw.py \
		--lock-file $(CACHE_ROOT)/locks/mpw-prepare.lock
	@mkdir -p $(@D)
	@touch $@

$(MPW_VARIANT_STAMP): $(MPW_STAMP) $(ROOT_PATH)/scripts/generate_mpw.py
	python3 $(ROOT_PATH)/scripts/generate_mpw.py --root $(ROOT_PATH) \
		--output $(MPW_OUTPUT_DIR) --simu $(SIMU) --core $(CORE) --ip $(IP) \
		--lock-file $(CACHE_ROOT)/locks/mpw.lock
	@mkdir -p $(@D)
	@touch $@

gen_mpw_code: $(MPW_VARIANT_STAMP)

$(MEMORY_MAP_STAMP): $(MEMORY_MAP_SOURCE) $(MEMORY_MAP_SCRIPT)
	python3 $(MEMORY_MAP_SCRIPT) --map $(MEMORY_MAP_SOURCE) \
		--output-dir $(MEMORY_MAP_DIR) --have-sram-if $(HAVE_SRAM_IF) --ip $(IP)
	@touch $@

memory-map: $(MEMORY_MAP_STAMP)

check-memory-map:
	python3 $(MEMORY_MAP_SCRIPT) --map $(MEMORY_MAP_SOURCE) --check

$(PIN_MAP_STAMP): $(PIN_MAP_SOURCE) $(PIN_MAP_SCRIPT)
	python3 $(PIN_MAP_SCRIPT) --map $(PIN_MAP_SOURCE) --output-dir $(PIN_MAP_DIR)
	@touch $@

pin-map: $(PIN_MAP_STAMP)

check-pin-map:
	python3 $(PIN_MAP_SCRIPT) --map $(PIN_MAP_SOURCE) --check

$(SOC_TOPOLOGY_STAMP): $(SOC_TOPOLOGY_SOURCE) $(SOC_TOPOLOGY_SCRIPT) $(MEMORY_MAP_SOURCE)
	python3 $(SOC_TOPOLOGY_SCRIPT) --map $(SOC_TOPOLOGY_SOURCE) \
		--memory-map $(MEMORY_MAP_SOURCE) --ip $(IP) --output-dir $(SOC_TOPOLOGY_DIR)
	@touch $@

soc-topology: $(SOC_TOPOLOGY_STAMP)

check-soc-topology:
	python3 $(SOC_TOPOLOGY_SCRIPT) --map $(SOC_TOPOLOGY_SOURCE) \
		--memory-map $(MEMORY_MAP_SOURCE) --ip NONE --check
	python3 $(SOC_TOPOLOGY_SCRIPT) --map $(SOC_TOPOLOGY_SOURCE) \
		--memory-map $(MEMORY_MAP_SOURCE) --ip MDD --check

$(USER_EXTENSIONS_STAMP): $(USER_EXTENSIONS_SOURCE) $(USER_EXTENSIONS_SCRIPT)
	python3 $(USER_EXTENSIONS_SCRIPT) --map $(USER_EXTENSIONS_SOURCE) \
		--output-dir $(USER_EXTENSIONS_DIR)
	@touch $@

user-extensions: $(USER_EXTENSIONS_STAMP)

check-user-extensions:
	python3 $(USER_EXTENSIONS_SCRIPT) --map $(USER_EXTENSIONS_SOURCE) --check

check-clock-reset-domains:
	python3 $(CLOCK_RESET_DOMAINS_SCRIPT) --map $(CLOCK_RESET_DOMAINS_SOURCE) --root $(ROOT_PATH)

$(FILELIST_STAMP): $(FILELIST_TEMPLATES) $(RTL_PATH)/script/generate_filelist.py \
	$(RTL_PATH)/script/filelist.py $(MEMORY_MAP_STAMP) $(PIN_MAP_STAMP) $(SOC_TOPOLOGY_STAMP) \
	$(USER_EXTENSIONS_STAMP)
	python3 $(RTL_PATH)/script/generate_filelist.py \
		--output-dir $(GENERATED_FL_DIR) \
		$(foreach define,$(DEF_LIST),--define $(define))
	@touch $@

generate_filelist: $(FILELIST_STAMP)

# software
include $(RTL_PATH)/mk/software.mk

#====================== filelist ======================
ifeq ($(PDK), IHP130)
    PDK_FILELIST := $(GENERATED_FL_DIR)/pdk_ihp130.fl
else ifeq ($(PDK), SKY130)
    PDK_FILELIST := $(GENERATED_FL_DIR)/pdk_sky130.fl
else ifeq ($(PDK), ICS55)
    PDK_FILELIST := $(GENERATED_FL_DIR)/pdk_ics55.fl
else ifeq ($(PDK), GF180)
    PDK_FILELIST := $(GENERATED_FL_DIR)/pdk_gf180.fl
endif

NET_FLIST := -f $(PDK_FILELIST)
NET_FLIST += -f $(GENERATED_FL_DIR)/def.fl
NET_FLIST += -f $(GENERATED_FL_DIR)/sys_def.fl
NET_FLIST += -f $(GENERATED_FL_DIR)/commonip.fl
NET_FLIST += -f $(GENERATED_FL_DIR)/inc.fl

RTL_FLIST := -f $(MEMORY_MAP_FILELIST) -f $(PIN_MAP_FILELIST) -f $(SOC_TOPOLOGY_FILELIST) \
	-f $(USER_EXTENSIONS_FILELIST) $(NET_FLIST)
RTL_FLIST += -f $(GENERATED_FL_DIR)/clusterip.fl
RTL_FLIST += -f $(GENERATED_FL_DIR)/ip.fl
RTL_FLIST += -f $(GENERATED_FL_DIR)/tech.fl

ifeq ($(CORE), PICORV32)
    RTL_FLIST += -f $(GENERATED_FL_DIR)/core_picorv32.fl
else ifeq ($(CORE), HAZARD3)
    RTL_FLIST += -f $(GENERATED_FL_DIR)/core_hazard3.fl
else ifeq ($(CORE), MDD)
    RTL_FLIST += -f $(MPW_OUTPUT_DIR)/core/core.fl
endif

ifeq ($(IP), MDD)
    RTL_FLIST += -f $(MPW_OUTPUT_DIR)/ip/ip.fl
endif

RTL_FLIST += -f $(GENERATED_FL_DIR)/top.fl
#====================== end ======================

ifeq ($(SIMU), VCS)
    include $(RTL_PATH)/mk/vcs.mk
else ifeq ($(SIMU), VERILATOR)
    include $(RTL_PATH)/mk/verilator.mk
else ifeq ($(SIMU), IVERILOG)
    include $(RTL_PATH)/mk/iverilog.mk
endif

.PHONY: gen_mpw_code generate_filelist memory-map check-memory-map pin-map check-pin-map \
	soc-topology check-soc-topology user-extensions check-user-extensions \
	check-clock-reset-domains firmware