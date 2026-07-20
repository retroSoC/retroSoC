GENERATED_FL_DIR := $(FLOW_FILELIST_DIR)
MEMORY_MAP_SOURCE := $(RTL_PATH)/memory_map.json
MEMORY_MAP_SCRIPT := $(RTL_PATH)/script/generate_memory_map.py
MEMORY_MAP_DIR    := $(VARIANT_ROOT)/generated/memory_map
MEMORY_MAP_STAMP  := $(MEMORY_MAP_DIR)/.stamp
MEMORY_MAP_RTL_DIR := $(MEMORY_MAP_DIR)/rtl
MEMORY_MAP_C_DIR   := $(MEMORY_MAP_DIR)/include
MEMORY_MAP_LINKER_DIR := $(MEMORY_MAP_DIR)/linker
MEMORY_MAP_FILELIST := $(MEMORY_MAP_DIR)/memory_map.fl
MPW_STAMP        := $(CACHE_ROOT)/stamps/mpw-$(LOCK_DIGEST).prepared
MPW_OUTPUT_DIR   := $(VARIANT_ROOT)/generated/mpw/$(SIM_TOOL_NAME)
MPW_VARIANT_STAMP := $(MPW_OUTPUT_DIR)/.stamp
FILELIST_STAMP   := $(GENERATED_FL_DIR)/.stamp
FILELIST_TEMPLATES := $(sort $(wildcard $(ROOT_PATH)/rtl/filelist/pdk_*.fl) \
                      $(wildcard $(RTL_PATH)/filelist/*.fl) $(RTL_PATH)/lint.msg)

$(MPW_STAMP):
	@test -d $(RTL_PATH)/mpw/.git || { \
		echo "missing $(RTL_PATH)/mpw; run 'make setup-mpw' first" >&2; \
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

$(FILELIST_STAMP): $(FILELIST_TEMPLATES) $(RTL_PATH)/script/generate_filelist.py \
                   $(RTL_PATH)/script/filelist.py $(MEMORY_MAP_STAMP)
	python3 $(RTL_PATH)/script/generate_filelist.py \
		--output-dir $(GENERATED_FL_DIR) \
		$(foreach define,$(DEF_LIST),--define $(define))
	@touch $@

generate_filelist: $(FILELIST_STAMP)

# software
include $(RTL_PATH)/mk/software.mk

#====================== filelist ======================
ifeq ($(PDK), IHP130)
    NET_FLIST := -f $(GENERATED_FL_DIR)/pdk_ihp130.fl
else ifeq ($(PDK), SKY130)
    NET_FLIST := -f $(GENERATED_FL_DIR)/pdk_sky130.fl
else ifeq ($(PDK), ICS55)
    NET_FLIST := -f $(GENERATED_FL_DIR)/pdk_ics55.fl
else ifeq ($(PDK), GF180)
    NET_FLIST := -f $(GENERATED_FL_DIR)/pdk_gf180.fl
endif

NET_FLIST  += -f $(GENERATED_FL_DIR)/def.fl
NET_FLIST  += -f $(GENERATED_FL_DIR)/sys_def.fl
NET_FLIST  += -f $(GENERATED_FL_DIR)/commonip.fl
NET_FLIST  += -f $(GENERATED_FL_DIR)/inc.fl

RTL_FLIST  := -f $(MEMORY_MAP_FILELIST) $(NET_FLIST)
RTL_FLIST  += -f $(GENERATED_FL_DIR)/clusterip.fl
RTL_FLIST  += -f $(GENERATED_FL_DIR)/ip.fl
RTL_FLIST  += -f $(GENERATED_FL_DIR)/tech.fl

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

.PHONY: gen_mpw_code generate_filelist memory-map check-memory-map firmware
