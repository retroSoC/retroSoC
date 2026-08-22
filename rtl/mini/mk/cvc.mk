CVC  ?= cvc
SV2V ?= sv2v

# Gate-level netlists have no usable delay data. Disable timing checks during
# compilation while leaving unrelated CVC diagnostics visible.
CVC_TIMING_OPTS ?= +nospecify +notimingchecks

NETLIST_PATH ?= $(SYN_BUILD_ROOT)/out/retrosoc_asic_yosys.v

CVC_ROOT              := $(SIM_BUILD_ROOT)
CVC_NETL_DIR          := $(NETLIST_SIM_ROOT)
CVC_NETL_FLIST        := $(CVC_NETL_DIR)/cvc.fl
CVC_NETL_TB           := $(CVC_NETL_DIR)/retrosoc_tb.v
CVC_NETL_SIMV         := $(CVC_NETL_DIR)/simv
CVC_FILELIST          := $(RTL_PATH)/script/gen_sim_filelist.py
CVC_TB_CONVERT        := $(RTL_PATH)/script/convt_sv2v.py
CVC_FILELISTS         := $(filter-out $(GENERATED_FL_DIR)/commonip.fl $(GENERATED_FL_DIR)/inc.fl,$(NET_FILELISTS))
CVC_TB_FLIST          := $(GENERATED_FL_DIR)/tb.fl
CVC_TB_FILTERED_FLIST := $(CVC_NETL_DIR)/tb-cvc.fl
CVC_TB_SOURCE         := $(RTL_PATH)/dv/tb/retrosoc_tb.sv
CVC_EXT_MODELS        := $(RTL_PATH)/dv/xezim/external_memory_models.sv

$(CVC_TB_FILTERED_FLIST): $(FILELIST_STAMP) $(CVC_FILELIST) $(CVC_TB_FLIST) \
	$(CVC_TB_SOURCE) $(CVC_EXT_MODELS)
	@mkdir -p $(@D)
	python3 $(CVC_FILELIST) --format cvc --filelist $(CVC_TB_FLIST) \
		--exclude-pattern 'at24cxxx\.sv$$' --exclude-pattern 'w25q128jvxim\.sv$$' \
		--exclude-pattern 'ESP_PSRAM64H\.sv$$' --exclude-pattern 'sdr\.v$$' \
		--exclude-pattern 'DVP_CAMERA\.sv$$' --source $(CVC_EXT_MODELS) --output $@

$(CVC_NETL_TB): $(FILELIST_STAMP) $(CVC_TB_CONVERT) $(CVC_TB_FILTERED_FLIST) \
	$(GENERATED_FL_DIR)/def.fl $(GENERATED_FL_DIR)/inc.fl $(PIN_MAP_FILELIST)
	@mkdir -p $(@D)
	python3 $(CVC_TB_CONVERT) -f $(GENERATED_FL_DIR)/def.fl -f $(GENERATED_FL_DIR)/inc.fl \
		-f $(PIN_MAP_FILELIST) -f $(CVC_TB_FILTERED_FLIST) \
		--output $@ --sv2v $(SV2V)

$(CVC_NETL_FLIST): $(FILELIST_STAMP) $(CVC_FILELIST) $(CVC_FILELISTS) $(CVC_NETL_TB) $(NETLIST_PATH)
	@mkdir -p $(@D)
	python3 $(CVC_FILELIST) --format cvc \
		$(foreach filelist,$(CVC_FILELISTS),--filelist $(filelist)) \
		--source $(NETLIST_PATH) --source $(CVC_NETL_TB) --output $@

$(CVC_NETL_SIMV): $(CVC_NETL_FLIST) $(NETLIST_PATH)
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool cvc \
	--log $(CVC_NETL_DIR)/compile.log --result $(CVC_NETL_DIR)/result-compile.json \
	--cwd $(CVC_NETL_DIR) -- $(CVC) -q -Ogate $(CVC_TIMING_OPTS) -o simv -f $<

netcomp comp: $(CVC_NETL_SIMV)

netsim: netcomp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(CVC_NETL_DIR) \
		--firmware $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool cvc-sim --stream-bytes \
	--log $(CVC_NETL_DIR)/sim.log --result $(CVC_NETL_DIR)/result-sim.json \
	--cwd $(CVC_NETL_DIR) -- ./simv +sim_timeout=$(RTL_SIM_TIMEOUT) +wave_$(WAVE)
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/check_simulation.py --log $(CVC_NETL_DIR)/sim.log \
		--result $(CVC_NETL_DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

sim:
	@echo "CVC backend supports synthesized-netlist simulation; use netcomp or netsim" >&2
	@exit 2

postcomp postsim:
	@echo "CVC backend does not support post-layout SDF simulation in this integration" >&2
	@exit 2

wave netwave:
	@echo "CVC wave viewing is not configured; use CVC waveform options explicitly"

clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(CVC_ROOT)

comp netcomp netsim: | manifest

.PHONY: comp netcomp sim netsim postcomp postsim wave netwave clean