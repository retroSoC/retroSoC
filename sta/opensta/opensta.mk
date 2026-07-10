
OPENSTA          ?= sta
OPENSTA_NETLIST  ?= $(ROOT_PATH)/syn/yosys/.synth_build/out/retrosoc_asic_yosys.v
OPENSTA_LIBERTY  ?= $(ROOT_PATH)/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
OPENSTA_IO_LIB   ?= $(ROOT_PATH)/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib
OPENSTA_SRAM_LIBS ?= $(wildcard $(ROOT_PATH)/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/lib/*_typ_1p20V_25C.lib)
OPENSTA_SDC      ?= $(ROOT_PATH)/sta/opensta/gen2.sdc
OPENSTA_REPORT   ?= $(ROOT_PATH)/sta/opensta/retrosoc_sta.log
OPENSTA_CONFIG   ?= $(ROOT_PATH)/syn/yosys/.synth_build/out/retrosoc_asic_yosys.config

sta:
	@for input in $(OPENSTA_NETLIST) $(OPENSTA_LIBERTY) $(OPENSTA_IO_LIB) $(OPENSTA_SRAM_LIBS) $(OPENSTA_SDC) $(OPENSTA_CONFIG); do \
		test -f "$$input" || { echo "OpenSTA input missing: $$input" >&2; exit 1; }; \
	done
	@grep -qx 'PDK=$(PDK)' $(OPENSTA_CONFIG) || { \
		echo "OpenSTA netlist configuration does not match PDK=$(PDK); rerun synthesis" >&2; \
		exit 1; \
	}
	OPENSTA_NETLIST=$(OPENSTA_NETLIST) OPENSTA_LIBERTY=$(OPENSTA_LIBERTY) \
	OPENSTA_IO_LIB=$(OPENSTA_IO_LIB) OPENSTA_SRAM_LIBS="$(OPENSTA_SRAM_LIBS)" OPENSTA_SDC=$(OPENSTA_SDC) \
	OPENSTA_REPORT=$(OPENSTA_REPORT) \
	$(OPENSTA) $(ROOT_PATH)/sta/opensta/opensta.tcl -threads max

.PHONY: sta
