LIBRELANE_FLOW_ROOT      := $(ROOT_PATH)/physical/librelane
LIBRELANE_RUN_ROOT       := $(VARIANT_ROOT)/physical/librelane/chip
LIBRELANE_INPUT_DIR      := $(LIBRELANE_RUN_ROOT)/input
LIBRELANE_RTL            := $(LIBRELANE_INPUT_DIR)/retrosoc_asic_sources.sv
LIBRELANE_SDC            := $(LIBRELANE_INPUT_DIR)/retrosoc_asic.sdc
LIBRELANE_BONDPAD_GDS    := $(LIBRELANE_INPUT_DIR)/bondpad_70x70.gds
LIBRELANE_BONDPAD_LEF    := $(LIBRELANE_FLOW_ROOT)/bondpad/bondpad_70x70.lef
LIBRELANE_CHIP_CONFIG    := $(LIBRELANE_RUN_ROOT)/config.json
LIBRELANE_LOG            := $(LIBRELANE_RUN_ROOT)/librelane.log
LIBRELANE_RESULT         := $(LIBRELANE_RUN_ROOT)/result.json
LIBRELANE_META_RESULT    := $(META_DIR)/librelane-chip.json
LIBRELANE_DOCTOR_RESULT  := $(META_DIR)/librelane-doctor.json
LIBRELANE_FINAL_DIR      := $(LIBRELANE_RUN_ROOT)/final
LIBRELANE_RUN_TAG        ?= current
LIBRELANE_PDK_ROOT       := $(ROOT_PATH)/physical/pdk/IHP-Open-PDK
LIBRELANE_PDK            := ihp-sg13g2
LIBRELANE_SCL            := sg13g2_stdcell
LIBRELANE_PAD            := sg13g2_io
LIBRELANE_KLAYOUT_PATH   := $(LIBRELANE_PDK_ROOT)/$(LIBRELANE_PDK)/libs.tech/klayout
LIBRELANE_BONDPAD_SCRIPT := $(LIBRELANE_PDK_ROOT)/$(LIBRELANE_PDK)/libs.tech/klayout/tech/scripts/bondpad.py
LIBRELANE_PDN            := $(LIBRELANE_FLOW_ROOT)/pdn_cfg.tcl
LIBRELANE_SRAM_VH        := $(LIBRELANE_FLOW_ROOT)/sram_blackboxes.vh
LIBRELANE_CLOCK_DOMAINS  := $(ROOT_PATH)/rtl/mini/integration/clock_reset_domains.json
LIBRELANE_PIN_MAP        := $(ROOT_PATH)/rtl/mini/pin_map/pin_map.json
LIBRELANE_TRACKED_RTL    := $(shell git -C $(ROOT_PATH) ls-files \
	'rtl/**/*.sv' 'rtl/**/*.svh' 'rtl/**/*.v' 'rtl/**/*.vh')

LIBRELANE_SOURCE_PYTHON ?= /usr/bin/python3
LIBRELANE_PYTHON        ?= python3

ifneq ($(filter librelane-input librelane-doctor librelane-chip librelane-openroad \
	librelane-klayout librelane-package,$(MAKECMDGOALS)),)
FLOW_PYTHON := $(LIBRELANE_SOURCE_PYTHON)
endif

LIBRELANE_FEATURE_ARGS := \
	$(if $(filter YES,$(HAVE_PLL)),--have-pll) \
	$(if $(filter YES,$(HAVE_SRAM_IF)),--have-sram-if) \
	$(if $(filter YES,$(HAVE_SRAM_MACRO)),--have-sram-macro) \
	$(if $(filter YES,$(HAVE_SVA)),--have-sva)

.PHONY: librelane-check-pdk librelane-input librelane-doctor librelane-chip \
	librelane-openroad librelane-klayout librelane-package

librelane-check-pdk:
	@test '$(PDK)' = IHP130 || { \
		echo 'physical/librelane currently implements only PDK=IHP130' >&2; exit 2; }
	@test '$(HAVE_PLL)' = NO || { \
		echo 'the IHP130 LibreLane pad-ring flow has no qualified crystal PAD' >&2; exit 2; }

$(LIBRELANE_RTL): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) $(LIBRELANE_TRACKED_RTL) \
		$(ROOT_PATH)/physical/smoke/syn/tools/export_soc_sources.py | librelane-check-pdk
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ROOT_PATH)/physical/smoke/syn/tools/export_soc_sources.py sv \
		--output-dir $(@D) --pdk IHP130 --simu $(SIMU) \
		--jtag-idcode $(JTAG_IDCODE) \
		--ext-clk-hz $(EXT_CLK_HZ) --aud-clk-hz $(AUD_CLK_HZ) \
		--clint-timebase-hz $(CLINT_TIMEBASE_HZ) \
		--dynamic-core-filelist $(MPW_OUTPUT_DIR)/core/core.fl \
		--dynamic-ip-filelist $(MPW_OUTPUT_DIR)/ip/ip.fl \
		--memory-map-filelist $(MEMORY_MAP_FILELIST) \
		--soc-topology-filelist $(SOC_TOPOLOGY_FILELIST) \
		--user-extensions-filelist $(USER_EXTENSIONS_FILELIST) \
		--pin-map-filelist $(PIN_MAP_FILELIST) \
		--archinfo-incdir $(ARCHINFO_METADATA_DIR) \
		--librelane-safe \
		$(LIBRELANE_FEATURE_ARGS)

$(LIBRELANE_SDC): $(LIBRELANE_FLOW_ROOT)/scripts/generate_sdc.py \
		$(LIBRELANE_CLOCK_DOMAINS) $(LIBRELANE_PIN_MAP) | librelane-check-pdk
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(LIBRELANE_FLOW_ROOT)/scripts/generate_sdc.py \
		--domains $(LIBRELANE_CLOCK_DOMAINS) --pin-map $(LIBRELANE_PIN_MAP) \
		--ext-clk-hz $(EXT_CLK_HZ) --aud-clk-hz $(AUD_CLK_HZ) \
		$(if $(filter YES,$(HAVE_PLL)),--have-pll) --output $@

$(LIBRELANE_BONDPAD_GDS): $(LIBRELANE_BONDPAD_SCRIPT) | librelane-check-pdk
	@mkdir -p $(@D)
	KLAYOUT_PATH=$(LIBRELANE_KLAYOUT_PATH) klayout -n sg13g2 -zz \
		-r $(LIBRELANE_BONDPAD_SCRIPT) -rd diameter=70.0 -rd shape=square \
		-rd output=$@
	@test -s $@

$(LIBRELANE_CHIP_CONFIG): $(LIBRELANE_RTL) $(LIBRELANE_SDC) \
		$(LIBRELANE_BONDPAD_GDS) $(LIBRELANE_BONDPAD_LEF) $(LIBRELANE_PDN) \
		$(LIBRELANE_SRAM_VH) $(LIBRELANE_FLOW_ROOT)/scripts/generate_chip_config.py
	$(FLOW_PYTHON) $(LIBRELANE_FLOW_ROOT)/scripts/generate_chip_config.py \
		--pin-map $(LIBRELANE_PIN_MAP) --rtl $(LIBRELANE_RTL) --sdc $(LIBRELANE_SDC) \
		--pdn $(LIBRELANE_PDN) --bondpad-gds $(LIBRELANE_BONDPAD_GDS) \
		--bondpad-lef $(LIBRELANE_BONDPAD_LEF) --sram-vh $(LIBRELANE_SRAM_VH) \
		--ext-clk-hz $(EXT_CLK_HZ) \
		--aud-clk-hz $(AUD_CLK_HZ) $(if $(filter YES,$(HAVE_PLL)),--have-pll) \
		--output $@

librelane-input: $(LIBRELANE_CHIP_CONFIG)

$(LIBRELANE_DOCTOR_RESULT): $(LIBRELANE_CHIP_CONFIG) \
		$(LIBRELANE_FLOW_ROOT)/scripts/doctor.py
	@mkdir -p $(@D)
	$(LIBRELANE_PYTHON) $(LIBRELANE_FLOW_ROOT)/scripts/doctor.py \
		--root $(ROOT_PATH) --config $(LIBRELANE_CHIP_CONFIG) --lock $(LOCK_FILE) \
		--pdk-root $(LIBRELANE_PDK_ROOT) --output $@

librelane-doctor: $(LIBRELANE_DOCTOR_RESULT)

librelane-chip: librelane-doctor manifest
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool librelane \
		--log $(LIBRELANE_LOG) --result $(LIBRELANE_RESULT) --cwd $(LIBRELANE_RUN_ROOT) -- \
		librelane $(LIBRELANE_CHIP_CONFIG) --manual-pdk --pdk $(LIBRELANE_PDK) \
		--pdk-root $(LIBRELANE_PDK_ROOT) --scl $(LIBRELANE_SCL) --pad $(LIBRELANE_PAD) \
		--run-tag $(LIBRELANE_RUN_TAG) --overwrite --jobs $(JOBS) --condensed \
		--hide-progress-bar --save-views-to $(LIBRELANE_FINAL_DIR)
	@mkdir -p $(META_DIR)
	@cp $(LIBRELANE_RESULT) $(LIBRELANE_META_RESULT)

librelane-openroad: librelane-doctor
	cd $(LIBRELANE_RUN_ROOT) && librelane $(LIBRELANE_CHIP_CONFIG) --manual-pdk \
		--pdk $(LIBRELANE_PDK) --pdk-root $(LIBRELANE_PDK_ROOT) \
		--scl $(LIBRELANE_SCL) --pad $(LIBRELANE_PAD) \
		--run-tag $(LIBRELANE_RUN_TAG) --last-run --flow OpenInOpenROAD

librelane-klayout: librelane-doctor
	cd $(LIBRELANE_RUN_ROOT) && librelane $(LIBRELANE_CHIP_CONFIG) --manual-pdk \
		--pdk $(LIBRELANE_PDK) --pdk-root $(LIBRELANE_PDK_ROOT) \
		--scl $(LIBRELANE_SCL) --pad $(LIBRELANE_PAD) \
		--run-tag $(LIBRELANE_RUN_TAG) --last-run --flow OpenInKLayout

librelane-package: librelane-chip
	$(FLOW_PYTHON) $(LIBRELANE_FLOW_ROOT)/scripts/package.py \
		--root $(ROOT_PATH) --variant-root $(VARIANT_ROOT) \
		--run-root $(LIBRELANE_RUN_ROOT) --output $(LIBRELANE_RUN_ROOT)/retrosoc-ihp130-chip.tar.gz