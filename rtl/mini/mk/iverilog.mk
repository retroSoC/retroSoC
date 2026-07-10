IVERILOG       ?= iverilog
VVP            ?= vvp
GTKWAVE        ?= gtkwave

NETLIST_PATH   ?= $(ROOT_PATH)/syn/yosys/.synth_build/out/retrosoc_asic_yosys.v
POST_PATH      ?= $(ROOT_PATH)/pd/sdf/retrosoc_asic.v
SDF_PATH       ?= $(ROOT_PATH)/pd/sdf/retrosoc_asic_CTS_MIN.sdf.gz
SDF_SCOPE      ?= $(RTL_TOP).u_retrosoc_asic

IVERILOG_ROOT       := $(RTL_PATH)/.iverilog_build
IVERILOG_BEHV_DIR   := $(IVERILOG_ROOT)/behv
IVERILOG_NETL_DIR   := $(IVERILOG_ROOT)/netl
IVERILOG_POST_DIR   := $(IVERILOG_ROOT)/post
IVERILOG_BEHV_FLIST := $(IVERILOG_BEHV_DIR)/iverilog.fl
IVERILOG_NETL_FLIST := $(IVERILOG_NETL_DIR)/iverilog.fl
IVERILOG_POST_FLIST := $(IVERILOG_POST_DIR)/iverilog.fl
CONVERTED_SOC       := $(IVERILOG_BEHV_DIR)/converted_soc.v

IVERILOG_COMMON_OPTS := -g2012
IVERILOG_TIME_OPTS   := -gno-specify
IVERILOG_POST_OPTS   := -gspecify -Tmin
IVERILOG_SIM_OPTS    := +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) \
	+core_sel=$(RTL_SIM_CORESEL) +sim_timeout=$(RTL_SIM_TIMEOUT) +wave_$(WAVE)

$(CONVERTED_SOC): gen_mpw_code generate_filelist
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/convt_sv2v.py $(RTL_FLIST) --output $@

$(IVERILOG_BEHV_FLIST): generate_filelist $(CONVERTED_SOC)
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/gen_iverilog_filelist.py \
		--mode behv --pdk $(PDK) --output $@ --converted $(CONVERTED_SOC)

$(IVERILOG_NETL_FLIST): generate_filelist
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/gen_iverilog_filelist.py \
		--mode netl --pdk $(PDK) --output $@ --netlist $(NETLIST_PATH)

$(IVERILOG_POST_FLIST): generate_filelist
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/gen_iverilog_filelist.py \
		--mode post --pdk $(PDK) --output $@ --netlist $(POST_PATH) --sdf $(SDF_PATH) \
		--sdf-scope $(SDF_SCOPE)

convt_sv2v: $(CONVERTED_SOC)
gen_iverilog_filelist: $(IVERILOG_BEHV_FLIST)

comp: $(IVERILOG_BEHV_FLIST)
	@mkdir -p $(IVERILOG_BEHV_DIR)
	@cd $(IVERILOG_BEHV_DIR) && set -o pipefail && \
		$(IVERILOG) $(IVERILOG_COMMON_OPTS) $(IVERILOG_TIME_OPTS) -f $< \
		-o simv -s $(RTL_TOP) 2>&1 | tee compile.log

netcomp: $(IVERILOG_NETL_FLIST)
	@mkdir -p $(IVERILOG_NETL_DIR)
	@cd $(IVERILOG_NETL_DIR) && set -o pipefail && \
		$(IVERILOG) $(IVERILOG_COMMON_OPTS) $(IVERILOG_TIME_OPTS) -f $< \
		-o simv -s $(RTL_TOP) 2>&1 | tee compile.log

postcomp: $(IVERILOG_POST_FLIST)
	@mkdir -p $(IVERILOG_POST_DIR)
	@cd $(IVERILOG_POST_DIR) && set -o pipefail && \
		$(IVERILOG) $(IVERILOG_COMMON_OPTS) $(IVERILOG_POST_OPTS) -f $< \
		-o simv -s $(RTL_TOP) -s retrosoc_sdf_annotator 2>&1 | tee compile.log

sim: comp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(IVERILOG_BEHV_DIR) \
		--firmware $(ROOT_PATH)/.sw_build/$(FIRMWARE_NAME).hex
	@cd $(IVERILOG_BEHV_DIR) && set -o pipefail && \
		stdbuf -oL -eL $(VVP) simv -fst $(IVERILOG_SIM_OPTS) 2>&1 | tee sim.log

netsim: netcomp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(IVERILOG_NETL_DIR) \
		--firmware $(ROOT_PATH)/.sw_build/$(FIRMWARE_NAME).hex
	@cd $(IVERILOG_NETL_DIR) && set -o pipefail && \
		stdbuf -oL -eL $(VVP) simv -fst $(IVERILOG_SIM_OPTS) 2>&1 | tee sim.log

postsim: postcomp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(IVERILOG_POST_DIR) \
		--firmware $(ROOT_PATH)/.sw_build/$(FIRMWARE_NAME).hex
	@cd $(IVERILOG_POST_DIR) && set -o pipefail && \
		stdbuf -oL -eL $(VVP) simv -fst $(IVERILOG_SIM_OPTS) 2>&1 | tee sim.log

wave:
	cd $(IVERILOG_BEHV_DIR) && $(GTKWAVE) $(RTL_TOP).fst &
netwave:
	cd $(IVERILOG_NETL_DIR) && $(GTKWAVE) $(RTL_TOP).fst &
postwave:
	cd $(IVERILOG_POST_DIR) && $(GTKWAVE) $(RTL_TOP).fst &

clean:
	rm -rf $(IVERILOG_ROOT)

.PHONY: convt_sv2v gen_iverilog_filelist comp netcomp postcomp sim netsim postsim wave netwave postwave clean
