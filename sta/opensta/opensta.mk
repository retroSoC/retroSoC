
OPENSTA          ?= sta
OPENSTA_THREADS  ?= $(JOBS)
OPENSTA_NETLIST  ?= $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v
OPENSTA_LIBERTY  ?= $(ROOT_PATH)/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
OPENSTA_IO_LIB   ?= $(ROOT_PATH)/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib
OPENSTA_SRAM_LIBS ?= $(wildcard $(ROOT_PATH)/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/lib/*_typ_1p20V_25C.lib)
OPENSTA_SDC      ?= $(ROOT_PATH)/sta/opensta/gen2.sdc
OPENSTA_REPORT   ?= $(STA_BUILD_ROOT)/retrosoc_sta.log
OPENSTA_LOG      ?= $(STA_BUILD_ROOT)/opensta.log
OPENSTA_METRICS  ?= $(STA_BUILD_ROOT)/timing_metrics.rpt
OPENSTA_CONFIG   ?= $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.config

sta:
	@mkdir -p $(STA_BUILD_ROOT)
	@for input in $(OPENSTA_NETLIST) $(OPENSTA_LIBERTY) $(OPENSTA_IO_LIB) $(OPENSTA_SRAM_LIBS) $(OPENSTA_SDC) $(OPENSTA_CONFIG); do \
		test -f "$$input" || { echo "OpenSTA input missing: $$input" >&2; exit 1; }; \
	done
	@grep -qx 'PDK=$(PDK)' $(OPENSTA_CONFIG) || { \
		echo "OpenSTA netlist configuration does not match PDK=$(PDK); rerun synthesis" >&2; \
		exit 1; \
	}
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool opensta --log $(OPENSTA_LOG) \
		--result $(STA_BUILD_ROOT)/result-sta.json \
		--env OPENSTA_NETLIST=$(OPENSTA_NETLIST) --env OPENSTA_LIBERTY=$(OPENSTA_LIBERTY) \
		--env OPENSTA_IO_LIB=$(OPENSTA_IO_LIB) --env 'OPENSTA_SRAM_LIBS=$(OPENSTA_SRAM_LIBS)' \
		--env OPENSTA_SDC=$(OPENSTA_SDC) --env OPENSTA_REPORT=$(OPENSTA_REPORT) \
		--env OPENSTA_METRICS=$(OPENSTA_METRICS) -- \
		$(OPENSTA) $(ROOT_PATH)/sta/opensta/opensta.tcl -threads $(OPENSTA_THREADS)

sta: | manifest

.PHONY: sta
