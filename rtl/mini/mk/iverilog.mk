IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave

NETLIST_PATH ?= $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v
POST_PATH    ?= $(ROOT_PATH)/pd/sdf/retrosoc_asic.v
SDF_PATH     ?= $(ROOT_PATH)/pd/sdf/retrosoc_asic_CTS_MIN.sdf.gz
SDF_SCOPE    ?= $(RTL_TOP).u_retrosoc_asic

IVERILOG_ROOT         := $(SIM_BUILD_ROOT)
IVERILOG_BEHV_DIR     := $(IVERILOG_ROOT)/behv
IVERILOG_NETL_DIR     := $(IVERILOG_ROOT)/netl
IVERILOG_POST_DIR     := $(IVERILOG_ROOT)/post
IVERILOG_BEHV_FLIST   := $(IVERILOG_BEHV_DIR)/iverilog.fl
IVERILOG_NETL_FLIST   := $(IVERILOG_NETL_DIR)/iverilog.fl
IVERILOG_POST_FLIST   := $(IVERILOG_POST_DIR)/iverilog.fl
CONVERTED_SOC         := $(IVERILOG_BEHV_DIR)/converted_soc.v
CONVERTED_DEPFILE     := $(IVERILOG_BEHV_DIR)/converted_soc.d
IVERILOG_BEHV_SIMV    := $(IVERILOG_BEHV_DIR)/simv
IVERILOG_NETL_SIMV    := $(IVERILOG_NETL_DIR)/simv
IVERILOG_POST_SIMV    := $(IVERILOG_POST_DIR)/simv
IVERILOG_BEHV_DEPFILE := $(IVERILOG_BEHV_DIR)/simv.d
IVERILOG_NETL_DEPFILE := $(IVERILOG_NETL_DIR)/simv.d
IVERILOG_POST_DEPFILE := $(IVERILOG_POST_DIR)/simv.d
IVERILOG_FILELIST_GEN := $(RTL_PATH)/script/gen_iverilog_filelist.py
NETLIST_SIM_MODELS    := $(ROOT_PATH)/rtl/tech/netlist_sim_cells.v $(ROOT_PATH)/rtl/tech/gf180_sim_cells.v
TECH_CELL_TEST        := $(ROOT_PATH)/tests/rtl/tc_pdk_cells_tb.sv
TECH_CELL_TEST_DIR    := $(IVERILOG_ROOT)/tech-cells

-include $(CONVERTED_DEPFILE) $(IVERILOG_BEHV_DEPFILE) $(IVERILOG_NETL_DEPFILE) $(IVERILOG_POST_DEPFILE)

IVERILOG_COMMON_OPTS := -g2012
IVERILOG_TIME_OPTS   := -gno-specify
IVERILOG_POST_OPTS   := -gspecify -Tmin
IVERILOG_SIM_OPTS    := +sim_timeout=$(RTL_SIM_TIMEOUT) +wave_$(WAVE)

$(CONVERTED_SOC): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP)
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/convt_sv2v.py $(RTL_FLIST) --output $@
	python3 $(RTL_PATH)/script/filelist_deps.py $(RTL_FLIST) --target $@ \
		--output $(CONVERTED_DEPFILE)

$(IVERILOG_BEHV_FLIST): $(FILELIST_STAMP) $(CONVERTED_SOC) $(IVERILOG_FILELIST_GEN)
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/gen_iverilog_filelist.py \
		--mode behv --pdk $(PDK) --generated-dir $(GENERATED_FL_DIR) \
		--pin-map-rtl-dir $(PIN_MAP_DIR)/rtl --output $@ --converted $(CONVERTED_SOC)

$(IVERILOG_NETL_FLIST): $(FILELIST_STAMP) $(NETLIST_PATH) $(IVERILOG_FILELIST_GEN) $(NETLIST_SIM_MODELS)
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/gen_iverilog_filelist.py \
		--mode netl --pdk $(PDK) --generated-dir $(GENERATED_FL_DIR) \
		--pin-map-rtl-dir $(PIN_MAP_DIR)/rtl --output $@ --netlist $(NETLIST_PATH)

$(IVERILOG_POST_FLIST): $(FILELIST_STAMP) $(POST_PATH) $(SDF_PATH) $(IVERILOG_FILELIST_GEN) $(NETLIST_SIM_MODELS)
	@mkdir -p $(@D)
	python3 $(RTL_PATH)/script/gen_iverilog_filelist.py \
		--mode post --pdk $(PDK) --generated-dir $(GENERATED_FL_DIR) \
		--pin-map-rtl-dir $(PIN_MAP_DIR)/rtl --output $@ --netlist $(POST_PATH) --sdf $(SDF_PATH) \
		--sdf-scope $(SDF_SCOPE)

convt_sv2v: $(CONVERTED_SOC)
gen_iverilog_filelist: $(IVERILOG_BEHV_FLIST)

tech-cell-test: $(FILELIST_STAMP) $(TECH_CELL_TEST) $(ROOT_PATH)/rtl/tech/tc_io.sv \
	$(ROOT_PATH)/rtl/tech/tc_clk.sv
	@case "$(PDK)" in \
		GF180|SKY130) ;; \
		*) echo "tech-cell-test supports PDK=GF180 or PDK=SKY130" >&2; exit 2 ;; \
	esac
	@mkdir -p $(TECH_CELL_TEST_DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-tech-cells \
		--log $(TECH_CELL_TEST_DIR)/compile.log --result $(TECH_CELL_TEST_DIR)/result-compile.json \
		--cwd $(TECH_CELL_TEST_DIR) -- $(IVERILOG) $(IVERILOG_COMMON_OPTS) $(IVERILOG_TIME_OPTS) \
		-f $(GENERATED_FL_DIR)/def.fl -f $(PDK_FILELIST) $(ROOT_PATH)/rtl/tech/tc_io.sv \
		$(ROOT_PATH)/rtl/tech/tc_clk.sv $(TECH_CELL_TEST) -o simv -s tc_pdk_cells_tb
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-tech-cells-sim \
		--log $(TECH_CELL_TEST_DIR)/sim.log --result $(TECH_CELL_TEST_DIR)/result-sim.json \
		--cwd $(TECH_CELL_TEST_DIR) -- $(VVP) simv

$(IVERILOG_BEHV_SIMV): $(IVERILOG_BEHV_FLIST)
	@mkdir -p $(IVERILOG_BEHV_DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog \
		--log $(IVERILOG_BEHV_DIR)/compile.log --result $(IVERILOG_BEHV_DIR)/result-compile.json \
		--cwd $(IVERILOG_BEHV_DIR) -- $(IVERILOG) $(IVERILOG_COMMON_OPTS) \
		$(IVERILOG_TIME_OPTS) -f $< -o simv -s $(RTL_TOP)
	python3 $(RTL_PATH)/script/filelist_deps.py -f $(IVERILOG_BEHV_FLIST) \
		--target $@ --output $(IVERILOG_BEHV_DEPFILE)

$(IVERILOG_NETL_SIMV): $(IVERILOG_NETL_FLIST)
	@mkdir -p $(IVERILOG_NETL_DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog \
		--log $(IVERILOG_NETL_DIR)/compile.log --result $(IVERILOG_NETL_DIR)/result-compile.json \
		--cwd $(IVERILOG_NETL_DIR) -- $(IVERILOG) $(IVERILOG_COMMON_OPTS) \
		$(IVERILOG_TIME_OPTS) -f $< -o simv -s $(RTL_TOP)
	python3 $(RTL_PATH)/script/filelist_deps.py -f $(IVERILOG_NETL_FLIST) \
		--target $@ --output $(IVERILOG_NETL_DEPFILE)

$(IVERILOG_POST_SIMV): $(IVERILOG_POST_FLIST)
	@mkdir -p $(IVERILOG_POST_DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog \
		--log $(IVERILOG_POST_DIR)/compile.log --result $(IVERILOG_POST_DIR)/result-compile.json \
		--cwd $(IVERILOG_POST_DIR) -- $(IVERILOG) $(IVERILOG_COMMON_OPTS) \
		$(IVERILOG_POST_OPTS) -f $< -o simv -s $(RTL_TOP) -s retrosoc_sdf_annotator
	python3 $(RTL_PATH)/script/filelist_deps.py -f $(IVERILOG_POST_FLIST) \
		--target $@ --output $(IVERILOG_POST_DEPFILE)

comp: $(IVERILOG_BEHV_SIMV)
netcomp: $(IVERILOG_NETL_SIMV)
postcomp: $(IVERILOG_POST_SIMV)

sim: comp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(IVERILOG_BEHV_DIR) \
		--firmware $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-sim \
		--log $(IVERILOG_BEHV_DIR)/sim.log --result $(IVERILOG_BEHV_DIR)/result-sim.json \
		--cwd $(IVERILOG_BEHV_DIR) -- stdbuf -oL -eL $(VVP) simv -fst $(IVERILOG_SIM_OPTS)
	python3 $(ROOT_PATH)/scripts/check_simulation.py --log $(IVERILOG_BEHV_DIR)/sim.log \
		--result $(IVERILOG_BEHV_DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

netsim: netcomp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(IVERILOG_NETL_DIR) \
		--firmware $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-sim \
		--log $(IVERILOG_NETL_DIR)/sim.log --result $(IVERILOG_NETL_DIR)/result-sim.json \
		--cwd $(IVERILOG_NETL_DIR) -- stdbuf -oL -eL $(VVP) simv -fst $(IVERILOG_SIM_OPTS)
	python3 $(ROOT_PATH)/scripts/check_simulation.py --log $(IVERILOG_NETL_DIR)/sim.log \
		--result $(IVERILOG_NETL_DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

postsim: postcomp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(IVERILOG_POST_DIR) \
		--firmware $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-sim \
		--log $(IVERILOG_POST_DIR)/sim.log --result $(IVERILOG_POST_DIR)/result-sim.json \
		--cwd $(IVERILOG_POST_DIR) -- stdbuf -oL -eL $(VVP) simv -fst $(IVERILOG_SIM_OPTS)
	python3 $(ROOT_PATH)/scripts/check_simulation.py --log $(IVERILOG_POST_DIR)/sim.log \
		--result $(IVERILOG_POST_DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

comp netcomp postcomp sim netsim postsim: | manifest

wave:
	cd $(IVERILOG_BEHV_DIR) && $(GTKWAVE) $(RTL_TOP).fst &
netwave:
	cd $(IVERILOG_NETL_DIR) && $(GTKWAVE) $(RTL_TOP).fst &
postwave:
	cd $(IVERILOG_POST_DIR) && $(GTKWAVE) $(RTL_TOP).fst &

clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(IVERILOG_ROOT)

.PHONY: convt_sv2v gen_iverilog_filelist tech-cell-test comp netcomp postcomp sim netsim postsim wave netwave postwave clean