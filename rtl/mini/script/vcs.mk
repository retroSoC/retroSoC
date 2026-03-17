# tools & paths
NOVAS        := /nfs/tools/synopsys/verdi/V-2023.12-SP1-1/share/PLI/VCS/LINUX64
EXTRA        := -P $(NOVAS)/novas.tab $(NOVAS)/pli.a
SIM_TOOL     := bsub -Is vcs
SIM_BINY     := bsub -Is ./simv
VERDI_TOOL   := bsub -Is verdi
COMP_LOG     := -l compile.log
SIM_LOG      := -l sim.log
# netlist file path
NETLIST_PATH := -v $(ROOT_PATH)/syn/yosys/.synth_build/out/retrosoc_asic_yosys.v
POST_PATH    := -v /nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic.v
SDF_PATH     := "/nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic_CTS_MIN.sdf.gz"
# testbench filelist
TB_FLIST     := -f $(RTL_PATH)/filelist/tb.fl

## vcs option
# -debug_region=cell+lib
# +lint=TFIPC-H(Timing, Floating Port, Implicit Net Declaration, Parameter, Comparison, High-Level)
# +ling=PCWM-H(Port, Parameter, Unused Wire, Module Instantiation, High-Level)
# -error=all(turn all warning into error)
# --- Compilation Flags ---
COMMON_OPTS  := -full64 +v2k -sverilog -timescale=1ns/10ps \
                $(EXTRA) \
                -kdb \
                -debug_access+all \
                -msg_config=../lint.msg \
                +error+500 \
                +vcs+loopreport+1000 \
                +vcs+flush+all \
                -xprop=../xprop_config \
                -override_timescale=1ns/1ps \
                -reportstats \
                -work DEFAULT

POST_OPTS   := -sdf min:retrosoc_tb.u_retrosoc_asic:$(SDF_PATH) \
               +delay_mode_path \
               +sdfverbose \
               +neg_tchk \
               -negdelay \
               +optconfigfile+./disable_timing_checklist \
               -diag=sdf:verbose \
               +warn=OPD:10,IWNF:10,SDFCOM_UHICD:10,SDFCOM_ANICD:10,SDFCOM_NICD:10,DRTZ:10,SDFCOM_UHICD:10,SDFCOM_NTCDTL:10

TIME_OPTION := +notimingcheck +nospecify
SIM_OPTS    := +vcs+loopreport+1000 -suppress=ASLR_DETECTED_INFO \
               +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +core_sel=$(RTL_SIM_CORESEL) \
               +wave_$(WAVE)


comp:     DIR   := .build
comp:     FLIST := $(RTL_FLIST) $(TB_FLIST)
comp:     OPTS  := $(TIME_OPTION)

netcomp:  DIR   := .net_build
netcomp:  FLIST := $(NETLIST_PATH) $(NET_FLIST) $(TB_FLIST)
netcomp:  OPTS  := $(TIME_OPTION)

postcomp: DIR   := .post_build
postcomp: FLIST := $(NET_FLIST) $(TB_FLIST)
postcomp: OPTS  := $(POST_OPTS)

sim:      DIR   := .build
netsim:   DIR   := .net_build
postsim:  DIR   := .post_build

wave:     DIR   := .build
netwave:  DIR   := .net_build
postwave: DIR   := .post_build


sim: comp
netsim: netcomp
postsim: postcomp


comp netcomp postcomp:
	@mkdir -p $(RTL_PATH)/$(DIR)
	cd $(RTL_PATH)/$(DIR) && ($(SIM_TOOL) $(COMMON_OPTS) $(OPTS) $(FLIST) -top $(RTL_TOP) $(COMP_LOG))

sim netsim postsim:
	cd $(RTL_PATH)/$(DIR) && ($(SIM_BINY) $(SIM_OPTS) $(if $(filter netsim postsim,$@),+bus_conflict_off) $(SIM_LOG))

wave netwave postwave:
	cd $(RTL_PATH)/$(DIR) && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

clean:
	rm -rf .build $(RTL_PATH)/.net_build $(RTL_PATH)/.post_build

.PHONY: comp netcomp postcomp sim netsim postsim wave clean