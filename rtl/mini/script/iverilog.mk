# tools & paths
SIM_TOOL     := iverilog
SIM_BINY     := vvp simv -fst
GTKWAVE_TOOL := gtkwave
COMP_LOG     := compile.log
SIM_LOG      := sim.log
# netlist file path
NETLIST_PATH := -v $(ROOT_PATH)/syn/yosys/.synth_build/out/retrosoc_asic_yosys.v
POST_PATH    := -v $(ROOT_PATH)/pd/sdf/retrosoc_asic.v
SDF_PATH     := "$(ROOT_PATH)/pd/sdf/retrosoc_asic_CTS_MIN.sdf.gz"
# testbench filelist
TB_FLIST     := -f $(RTL_PATH)/.generate_verilogd_fl/tb.fl


# --- Compilation Flags ---
COMMON_OPTS  := -g2012

POST_OPTS    := -ghello

TIME_OPTS    := -gno-specify
SIM_OPTS     := +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +core_sel=$(RTL_SIM_CORESEL) +sim_timeout=$(RTL_SIM_TIMEOUT) \
                +wave_$(WAVE)


comp:     DIR   := .iverilog_build/behv
comp:     FLIST := -f $(RTL_PATH)/.generated_fl/iverilog.fl
comp:     OPTS  := $(TIME_OPTS)

netcomp:  DIR   := .iverilog_build/netl
netcomp:  FLIST := $(NETLIST_PATH) $(NET_FLIST) $(TB_FLIST)
netcomp:  OPTS  := $(TIME_OPTS)

postcomp: DIR   := .iverilog_build/post
postcomp: FLIST := $(NET_FLIST) $(TB_FLIST)
postcomp: OPTS  := $(POST_OPTS)

sim:      DIR   := .iverilog_build/behv
netsim:   DIR   := .iverilog_build/netl
postsim:  DIR   := .iverilog_build/post

wave:     DIR   := .iverilog_build/behv
netwave:  DIR   := .iverilog_build/netl
postwave: DIR   := .iverilog_build/post


sim: comp prepare_norflash
netsim: netcomp prepare_norflash
postsim: postcomp prepare_norflash

convt_sv2v: generate_filelist
	python3 $(RTL_PATH)/filelist/convt_sv2v.py $(RTL_FLIST)

gen_iverilog_filelist:
	python3 $(RTL_PATH)/filelist/gen_iverilog_filelist.py $(PDK)

prepare_norflash:
	python3 $(RTL_PATH)/filelist/prepare_norflash.py

comp netcomp postcomp: convt_sv2v gen_iverilog_filelist
	@mkdir -p $(RTL_PATH)/$(DIR)
	cd $(RTL_PATH)/$(DIR) && ($(SIM_TOOL) $(COMMON_OPTS) $(OPTS) $(FLIST) -o simv -s $(RTL_TOP)) 2>&1 | tee $(COMP_LOG)


sim netsim postsim:
	cd $(RTL_PATH)/$(DIR) && (stdbuf -oL -eL $(SIM_BINY) $(SIM_OPTS)) 2>&1 | tee $(SIM_LOG)

wave netwave postwave:
	cd $(RTL_PATH)/$(DIR) && ($(GTKWAVE_TOOL) $(RTL_TOP).fst &)

clean:
	rm -rf .iverilog_build/behv $(RTL_PATH)/.iverilog_build/netl $(RTL_PATH)/.iverilog_build/post

.PHONY: comp netcomp postcomp sim netsim postsim wave clean