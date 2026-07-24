
OPENSTA            ?= sta
OPENSTA_THREADS    ?= $(JOBS)
OPENSTA_NETLIST    ?= $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v
OPENSTA_REPORT     ?= $(STA_BUILD_ROOT)/retrosoc_sta.log
OPENSTA_LOG        ?= $(STA_BUILD_ROOT)/opensta.log
OPENSTA_METRICS    ?= $(STA_BUILD_ROOT)/timing_metrics.rpt
OPENSTA_CONFIG     ?= $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.config
OPENSTA_SDC        ?= $(STA_BUILD_ROOT)/retrosoc_core.sdc
OPENSTA_SDC_GEN    := $(ROOT_PATH)/sta/opensta/generate_sdc.py
OPENSTA_DOMAIN_MAP := $(ROOT_PATH)/rtl/mini/integration/clock_reset_domains.json
OPENSTA_PIN_MAP    := $(ROOT_PATH)/rtl/mini/pin_map/pin_map.json

include $(ROOT_PATH)/sta/opensta/pdk_timing.mk

$(OPENSTA_SDC): $(OPENSTA_SDC_GEN) $(OPENSTA_DOMAIN_MAP) $(OPENSTA_PIN_MAP) | manifest
	@mkdir -p $(dir $@)
	python3 $(OPENSTA_SDC_GEN) --domains $(OPENSTA_DOMAIN_MAP) --pin-map $(OPENSTA_PIN_MAP) --output $@

sta: $(OPENSTA_SDC) | manifest
	@mkdir -p $(STA_BUILD_ROOT)
	@for input in $(OPENSTA_NETLIST) $(OPENSTA_LIBERTY) $(OPENSTA_LINK_LIBS) $(OPENSTA_SRAM_LIBS) $(OPENSTA_SDC) $(OPENSTA_CONFIG); do \
		test -f "$$input" || { echo "OpenSTA input missing: $$input" >&2; exit 1; }; \
	done
	@grep -qx 'PDK=$(PDK)' $(OPENSTA_CONFIG) || { \
		echo "OpenSTA netlist configuration does not match PDK=$(PDK); rerun synthesis" >&2; \
		exit 1; \
		}
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool opensta --log $(OPENSTA_LOG) \
		--result $(STA_BUILD_ROOT)/result-sta.json \
		--env OPENSTA_NETLIST=$(OPENSTA_NETLIST) --env OPENSTA_LIBERTY=$(OPENSTA_LIBERTY) \
		--env 'OPENSTA_LINK_LIBS=$(OPENSTA_LINK_LIBS)' --env 'OPENSTA_SRAM_LIBS=$(OPENSTA_SRAM_LIBS)' \
		--env OPENSTA_SDC=$(OPENSTA_SDC) --env OPENSTA_REPORT=$(OPENSTA_REPORT) \
		--env OPENSTA_METRICS=$(OPENSTA_METRICS) -- \
		$(OPENSTA) $(ROOT_PATH)/sta/opensta/opensta.tcl -threads $(OPENSTA_THREADS)

.PHONY: sta