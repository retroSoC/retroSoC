# tools & paths
NOVAS      ?= /nfs/tools/synopsys/verdi/V-2023.12-SP1-1/share/PLI/VCS/LINUX64
VCS_RUNNER ?= bsub -Is
VCS        ?= vcs
VERDI      ?= verdi
EXTRA      ?= -P $(NOVAS)/novas.tab $(NOVAS)/pli.a
SIM_TOOL   := $(VCS_RUNNER) $(VCS)
SIM_BINY   := $(VCS_RUNNER) ./simv
VERDI_TOOL := $(VCS_RUNNER) $(VERDI)
COMP_LOG   := -l compile.log
SIM_LOG    := -l sim.log
# netlist file path
NETLIST_PATH := -v $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v
POST_PATH    := -v $(ROOT_PATH)/pd/sdf/retrosoc_asic.v
SDF_PATH     := "$(ROOT_PATH)/pd/sdf/retrosoc_asic_CTS_MIN.sdf.gz"
# testbench filelist
TB_FLIST := -f $(GENERATED_FL_DIR)/tb.fl

## vcs option
# -debug_region=cell+lib
# +lint=TFIPC-H(Timing, Floating Port, Implicit Net Declaration, Parameter, Comparison, High-Level)
# +ling=PCWM-H(Port, Parameter, Unused Wire, Module Instantiation, High-Level)
# -error=all(turn all warning into error)
# +vcs+loopreport+100000 \
# --- Compilation Flags ---
COMMON_OPTS := -full64 +v2k -sverilog -timescale=1ns/10ps \
                $(EXTRA) \
                -kdb \
                -debug_access+all \
                -msg_config=$(GENERATED_FL_DIR)/lint.msg \
                +error+500 \
                +vcs+flush+all \
                -xprop=$(RTL_PATH)/xprop_config \
                -override_timescale=1ns/1ps \
                -reportstats \
                -work DEFAULT

POST_OPTS := -sdf min:retrosoc_tb.u_retrosoc_asic:$(SDF_PATH) \
               +delay_mode_path \
               +sdfverbose \
               +neg_tchk \
               -negdelay \
               +optconfigfile+$(RTL_PATH)/disable_timing_checklist \
               -diag=sdf:verbose \
               +warn=OPD:10,IWNF:10,SDFCOM_UHICD:10,SDFCOM_ANICD:10,SDFCOM_NICD:10,DRTZ:10,SDFCOM_UHICD:10,SDFCOM_NTCDTL:10

TIME_OPTION := +notimingcheck +nospecify
SIM_OPTS    := +vcs+loopreport+1000 -suppress=ASLR_DETECTED_INFO \
               +sim_timeout=$(RTL_SIM_TIMEOUT) +wave_$(WAVE)

VCS_BEHV_DIR     := $(SIM_BUILD_ROOT)/behv
VCS_NETL_DIR     := $(SIM_BUILD_ROOT)/netl
VCS_POST_DIR     := $(SIM_BUILD_ROOT)/post
VCS_BEHV_SIMV    := $(VCS_BEHV_DIR)/simv
VCS_NETL_SIMV    := $(VCS_NETL_DIR)/simv
VCS_POST_SIMV    := $(VCS_POST_DIR)/simv
VCS_BEHV_DEPFILE := $(VCS_BEHV_DIR)/simv.d
VCS_NETL_DEPFILE := $(VCS_NETL_DIR)/simv.d
VCS_POST_DEPFILE := $(VCS_POST_DIR)/simv.d

-include $(VCS_BEHV_DEPFILE) $(VCS_NETL_DEPFILE) $(VCS_POST_DEPFILE)

$(VCS_BEHV_SIMV): DIR   := $(VCS_BEHV_DIR)
$(VCS_BEHV_SIMV): FLIST := $(RTL_FLIST) $(TB_FLIST)
$(VCS_BEHV_SIMV): OPTS  := $(TIME_OPTION)
$(VCS_BEHV_SIMV): DEPFILE := $(VCS_BEHV_DEPFILE)
$(VCS_BEHV_SIMV): DEPS_ARGS := $(RTL_FLIST) -f $(GENERATED_FL_DIR)/tb.fl

$(VCS_NETL_SIMV): DIR   := $(VCS_NETL_DIR)
$(VCS_NETL_SIMV): FLIST := $(NETLIST_PATH) $(NET_FLIST) $(TB_FLIST)
$(VCS_NETL_SIMV): OPTS  := $(TIME_OPTION)
$(VCS_NETL_SIMV): DEPFILE := $(VCS_NETL_DEPFILE)
$(VCS_NETL_SIMV): DEPS_ARGS := $(NET_FLIST) -f $(GENERATED_FL_DIR)/tb.fl --extra $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v

$(VCS_POST_SIMV): DIR   := $(VCS_POST_DIR)
$(VCS_POST_SIMV): FLIST := $(POST_PATH) $(NET_FLIST) $(TB_FLIST)
$(VCS_POST_SIMV): OPTS  := $(POST_OPTS)
$(VCS_POST_SIMV): DEPFILE := $(VCS_POST_DEPFILE)
$(VCS_POST_SIMV): DEPS_ARGS := $(NET_FLIST) -f $(GENERATED_FL_DIR)/tb.fl --extra $(ROOT_PATH)/pd/sdf/retrosoc_asic.v --extra $(ROOT_PATH)/pd/sdf/retrosoc_asic_CTS_MIN.sdf.gz

sim:      DIR   := $(VCS_BEHV_DIR)
netsim:   DIR   := $(VCS_NETL_DIR)
postsim:  DIR   := $(VCS_POST_DIR)

wave:     DIR   := $(SIM_BUILD_ROOT)/behv
netwave:  DIR   := $(SIM_BUILD_ROOT)/netl
postwave: DIR   := $(SIM_BUILD_ROOT)/post

comp: $(VCS_BEHV_SIMV)
netcomp: $(VCS_NETL_SIMV)
postcomp: $(VCS_POST_SIMV)
sim: $(VCS_BEHV_SIMV)
netsim: $(VCS_NETL_SIMV)
postsim: $(VCS_POST_SIMV)

$(VCS_BEHV_SIMV) $(VCS_NETL_SIMV) $(VCS_POST_SIMV): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP)
	@mkdir -p $(DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool vcs --log $(DIR)/driver-compile.log \
		--result $(DIR)/result-compile.json --cwd $(DIR) -- \
		$(SIM_TOOL) $(COMMON_OPTS) $(OPTS) $(FLIST) -top $(RTL_TOP) $(COMP_LOG)
	python3 $(RTL_PATH)/script/filelist_deps.py $(DEPS_ARGS) --target $@ --output $(DEPFILE)

$(VCS_NETL_SIMV): $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v
$(VCS_POST_SIMV): $(ROOT_PATH)/pd/sdf/retrosoc_asic.v $(ROOT_PATH)/pd/sdf/retrosoc_asic_CTS_MIN.sdf.gz

sim netsim postsim:
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(DIR) \
		--firmware $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool vcs-sim --log $(DIR)/driver-sim.log \
		--result $(DIR)/result-sim.json --cwd $(DIR) -- \
		$(SIM_BINY) $(SIM_OPTS) $(if $(filter netsim postsim,$@),+bus_conflict_off) $(SIM_LOG)
	python3 $(ROOT_PATH)/scripts/check_simulation.py --log $(DIR)/driver-sim.log \
		--result $(DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

comp netcomp postcomp sim netsim postsim: | manifest

wave netwave postwave:
	cd $(DIR) && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(SIM_BUILD_ROOT)

.PHONY: comp netcomp postcomp sim netsim postsim wave clean