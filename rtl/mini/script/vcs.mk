NOVAS        := /nfs/tools/synopsys/verdi/V-2023.12-SP1-1/share/PLI/VCS/LINUX64
EXTRA        := -P $(NOVAS)/novas.tab $(NOVAS)/pli.a


SIM_TOOL     := bsub -Is vcs
SIM_BINY     := bsub -Is ./simv
VERDI_TOOL   := bsub -Is verdi

COMP_LOG     := -l compile.log
SIM_LOG      := -l sim.log

TB_FLIST  := -f $(RTL_PATH)/filelist/tb.fl

## vcs option
# -debug_region=cell+lib
SIM_OPTIONS := -full64 +v2k -sverilog -timescale=1ns/10ps \
                $(EXTRA) \
                -kdb \
                -debug_access+all \
                +vcs+loopreport+10000 \
                +error+500 \
                +vcs+flush+all \
                +lint=TFIPC-L \
                -xprop=../xprop_config \
                -work DEFAULT


TIME_OPTION := +notimingcheck +nospecify

NET_PATH  := -v $(ROOT_PATH)/syn/yosys/.synth_build/out/retrosoc_asic_yosys.v
POST_PATH := -v /nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic.v
SDF_FILE  := "/nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic_CTS_MIN.sdf.gz"

POST_SIM_OPTION := -sdf min:retrosoc_tb.u_retrosoc_asic:$(SDF_FILE) \
                   +delay_mode_path \
                   +sdfverbose \
                   +neg_tchk \
                   -negdelay \
                   +optconfigfile+./disable_timing_checklist \
                   -diag=sdf:verbose \
                   +warn=OPD:10,IWNF:10,SDFCOM_UHICD:10,SDFCOM_ANICD:10,SDFCOM_NICD:10,DRTZ:10,SDFCOM_UHICD:10,SDFCOM_NTCDTL:10

comp:
	@mkdir -p $(RTL_PATH)/.build
	cd $(RTL_PATH)/.build && ($(SIM_TOOL) $(SIM_OPTIONS) $(TIME_OPTION) $(RTL_FLIST) $(TB_FLIST) -top $(RTL_TOP) $(COMP_LOG))

sim: comp
	cd $(RTL_PATH)/.build && ($(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +core_sel=$(RTL_SIM_CORESEL) +behv_$(WAVE) +sim_vcs $(SIM_LOG))

wave:
	cd $(RTL_PATH)/.build && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

netcomp:
	@mkdir -p $(RTL_PATH)/.net_build
	cd $(RTL_PATH)/.net_build && ($(SIM_TOOL) $(SIM_OPTIONS) $(TIME_OPTION) $(NET_FLIST) $(NET_PATH) $(TB_FLIST) -top $(RTL_TOP) $(COMP_LOG))

netsim: netcomp
	$(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +syn_$(WAVE) +sim_vcs +bus_conflict_off $(SIM_LOG)

netwave:
	cd $(RTL_PATH)/.net_build && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

postcomp:
	@mkdir -p $(RTL_PATH)/.post_build
	cd $(RTL_PATH)/.post_build && ($(SIM_TOOL) $(SIM_OPTIONS) $(VPOST_SIM_OPTION) $(RTL_PDK) ./ip/rs232.v ./ip/kdb_model.v ./ip/psram_model.v ./ip/cust/spfs_model/N25Qxxx.v $(RTL_TOP).v -top $(RTL_TOP) $(COMP_LOG) $(VPOST_PATH))

postsim: postcomp
	$(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_vcs $(SIM_LOG)

postwave:
	cd $(RTL_PATH)/.post_build && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

clean:
	rm -rf .build $(RTL_PATH)/.net_build $(RTL_PATH)/.post_build