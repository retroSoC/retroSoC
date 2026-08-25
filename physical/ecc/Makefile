ECC_FLOW_ROOT     := $(ROOT_PATH)/physical/ecc
ECC_TARGET        ?= core
ECC_RUN_ROOT      := $(VARIANT_ROOT)/physical/ecc/$(ECC_TARGET)
ECC_INPUT_DIR     := $(ECC_RUN_ROOT)/input
ECC_PROJECT_DIR   := $(ECC_RUN_ROOT)/project
ECC_RTL           := $(ECC_INPUT_DIR)/retrosoc_asic_sources.sv
ECC_SDC           := $(ECC_INPUT_DIR)/retrosoc_core.sdc
ECC_CONFIG        := $(ECC_PROJECT_DIR)/ecc.toml
ECC_LOG           := $(ECC_RUN_ROOT)/ecc.log
ECC_RESULT        := $(ECC_RUN_ROOT)/result.json
ECC_VERIFY        := $(ECC_RUN_ROOT)/verification.json
ECC_STATUS        := $(ECC_RUN_ROOT)/status.json
ECC_META_RESULT   := $(META_DIR)/ecc-$(ECC_TARGET).json
ECC_DOCTOR_RESULT := $(META_DIR)/ecc-$(ECC_TARGET)-doctor.json
ECC_ARCHIVE       := $(ECC_RUN_ROOT)/retrosoc-ics55-$(ECC_TARGET).tar.gz
ECC_CACHE_ROOT    := $(CACHE_ROOT)/tools/ecc/v0.1.0-alpha.10
ECC_BIN           := $(ECC_CACHE_ROOT)/ecc
ECC_DOWNLOAD      := $(ROOT_PATH)/.cache/retrosoc/downloads/ecc/ecc-cli-linux-x86_64-v0.1.0-alpha.10.tar.gz
ECC_PDK_ROOT      := $(ROOT_PATH)/physical/pdk/icsprout55-pdk
ECC_H7CR_LIBERTY  := $(CACHE_ROOT)/pdk/ics55/ics55_h7cr_ss.lib
ECC_CLOCK_DOMAINS := $(ROOT_PATH)/rtl/mini/integration/clock_reset_domains.json
ECC_PIN_MAP       := $(ROOT_PATH)/rtl/mini/pin_map/pin_map.json
ECC_SOURCE_PYTHON ?= /usr/bin/python3
ECC_ENV            := XDG_CACHE_HOME=$(CACHE_ROOT)/fontconfig
ECC_TRACKED_RTL   := $(shell git -C $(ROOT_PATH) ls-files \
	'rtl/**/*.sv' 'rtl/**/*.svh' 'rtl/**/*.v' 'rtl/**/*.vh')

ifneq ($(ECC_TARGET),core)
$(error ECC_TARGET must be core, got '$(ECC_TARGET)')
endif

ifneq ($(filter ecc-setup ecc-input ecc-doctor ecc-check ecc-core ecc-status ecc-log ecc-package,$(MAKECMDGOALS)),)
FLOW_PYTHON := $(ECC_SOURCE_PYTHON)
endif

.PHONY: ecc-check-profile ecc-setup ecc-input ecc-doctor ecc-check ecc-core \
	ecc-status ecc-log ecc-package

ecc-check-profile:
	@test '$(PDK)' = ICS55 || { \
		echo 'physical/ecc requires PDK=ICS55' >&2; exit 2; }
	@test '$(HAVE_PLL)' = NO || { \
		echo 'physical/ecc has no qualified PLL hardening configuration' >&2; exit 2; }
	@test '$(HAVE_SRAM_IF)' = NO || { \
		echo 'physical/ecc currently hardens the committed padless ICS55 profile only' >&2; exit 2; }
	@test '$(HAVE_SRAM_MACRO)' = NO || { \
		echo 'physical/ecc currently has no qualified ICS55 SRAM macro configuration' >&2; exit 2; }

$(ECC_BIN): $(LOCK_FILE) $(ECC_FLOW_ROOT)/scripts/setup.py | ecc-check-profile
	$(FLOW_PYTHON) $(ECC_FLOW_ROOT)/scripts/setup.py --root $(ROOT_PATH) \
		--lock $(LOCK_FILE) --output-dir $(ECC_CACHE_ROOT)
	@test -x $@

ecc-setup: setup-pdk $(ECC_BIN)

$(ECC_H7CR_LIBERTY):
	+$(MAKE) setup-pdk
	@test -f $@

$(ECC_RTL): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) $(ECC_TRACKED_RTL) \
		$(ROOT_PATH)/physical/smoke/syn/tools/export_soc_sources.py | ecc-check-profile
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ROOT_PATH)/physical/smoke/syn/tools/export_soc_sources.py sv \
		--output-dir $(@D) --pdk ICS55 --simu $(SIMU) \
		--jtag-idcode $(JTAG_IDCODE) --ext-clk-hz $(EXT_CLK_HZ) \
		--aud-clk-hz $(AUD_CLK_HZ) --clint-timebase-hz $(CLINT_TIMEBASE_HZ) \
		--dynamic-core-filelist $(MPW_OUTPUT_DIR)/core/core.fl \
		--dynamic-ip-filelist $(MPW_OUTPUT_DIR)/ip/ip.fl \
		--memory-map-filelist $(MEMORY_MAP_FILELIST) \
		--soc-topology-filelist $(SOC_TOPOLOGY_FILELIST) \
		--user-extensions-filelist $(USER_EXTENSIONS_FILELIST) \
		--pin-map-filelist $(PIN_MAP_FILELIST) \
		--archinfo-incdir $(ARCHINFO_METADATA_DIR) --librelane-safe

$(ECC_SDC): $(ROOT_PATH)/physical/smoke/sta/opensta/generate_sdc.py \
		$(ECC_CLOCK_DOMAINS) $(ECC_PIN_MAP) | ecc-check-profile
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ROOT_PATH)/physical/smoke/sta/opensta/generate_sdc.py \
		--domains $(ECC_CLOCK_DOMAINS) --pin-map $(ECC_PIN_MAP) --output $@

$(ECC_CONFIG): $(ECC_RTL) $(ECC_SDC) $(ECC_H7CR_LIBERTY) \
		$(ECC_FLOW_ROOT)/scripts/generate_config.py | ecc-check-profile
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ECC_FLOW_ROOT)/scripts/generate_config.py \
		--rtl $(ECC_RTL) --sdc $(ECC_SDC) --pdk-root $(ECC_PDK_ROOT) \
		--h7cr-liberty $(ECC_H7CR_LIBERTY) --ext-clk-hz $(EXT_CLK_HZ) --output $@

ecc-input: ecc-setup $(ECC_CONFIG)

$(ECC_DOCTOR_RESULT): $(ECC_CONFIG) $(ECC_BIN) $(ECC_FLOW_ROOT)/scripts/doctor.py
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ECC_FLOW_ROOT)/scripts/doctor.py --root $(ROOT_PATH) \
		--lock $(LOCK_FILE) --ecc $(ECC_BIN) --project $(ECC_PROJECT_DIR) \
		--pdk-root $(ECC_PDK_ROOT) --sdc $(ECC_SDC) --output $@

ecc-doctor: ecc-setup $(ECC_DOCTOR_RESULT)

ecc-check: ecc-doctor

ecc-core: ecc-doctor manifest
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool ecc --log $(ECC_LOG) \
		--result $(ECC_RESULT) --cwd $(ECC_PROJECT_DIR) -- \
		env $(ECC_ENV) $(ECC_BIN) run --project $(ECC_PROJECT_DIR) --overwrite --json
	$(FLOW_PYTHON) $(ECC_FLOW_ROOT)/scripts/check_outputs.py --ecc $(ECC_BIN) \
		--project $(ECC_PROJECT_DIR) --sdc $(ECC_SDC) --output $(ECC_VERIFY)
	@mkdir -p $(META_DIR)
	@cp $(ECC_RESULT) $(ECC_META_RESULT)

ecc-status: ecc-doctor
	@mkdir -p $(ECC_RUN_ROOT)
	env $(ECC_ENV) $(ECC_BIN) status --project $(ECC_PROJECT_DIR) --json > $(ECC_STATUS)
	@cat $(ECC_STATUS)

ecc-log: ecc-doctor
	env $(ECC_ENV) $(ECC_BIN) log --project $(ECC_PROJECT_DIR)

ecc-package: ecc-core
	$(FLOW_PYTHON) $(ECC_FLOW_ROOT)/scripts/package.py --root $(ROOT_PATH) \
		--variant-root $(VARIANT_ROOT) --run-root $(ECC_RUN_ROOT) --output $(ECC_ARCHIVE)
