XEZIM          ?= xezim
XEZIM_MAX_TIME ?= $(if $(filter -1,$(RTL_SIM_TIMEOUT)),100000,$(RTL_SIM_TIMEOUT))

XEZIM_ROOT       := $(SIM_BUILD_ROOT)
XEZIM_BEHV_DIR   := $(XEZIM_ROOT)/behv
XEZIM_BEHV_FLIST := $(XEZIM_BEHV_DIR)/xezim.fl
XEZIM_BEHV_STAMP := $(XEZIM_BEHV_DIR)/compile.stamp
XEZIM_FILELIST   := $(RTL_PATH)/script/gen_sim_filelist.py
XEZIM_TB_SOURCE  := $(RTL_PATH)/dv/tb/retrosoc_tb.sv
XEZIM_SRAM_MODEL := $(RTL_PATH)/dv/xezim/ihp130_sram_models.sv
XEZIM_EXT_MODELS := $(RTL_PATH)/dv/xezim/external_memory_models.sv
XEZIM_FILELISTS  := $(filter-out $(PDK_FILELIST),$(RTL_FILELISTS)) $(GENERATED_FL_DIR)/tb.fl

ifeq ($(PDK), IHP130)
else
$(error Xezim backend currently supports PDK=IHP130 only)
endif

$(XEZIM_BEHV_FLIST): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) $(XEZIM_FILELIST) $(XEZIM_FILELISTS) \
	$(XEZIM_TB_SOURCE) $(XEZIM_SRAM_MODEL) $(XEZIM_EXT_MODELS)
	@mkdir -p $(@D)
	python3 $(XEZIM_FILELIST) --format xezim \
		$(foreach filelist,$(XEZIM_FILELISTS),--filelist $(filelist)) \
		--define +define+PDK_BEHAV --define +define+FUNCTIONAL \
		--exclude-pattern 'at24cxxx\.sv$$' --exclude-pattern 'sdr\.v$$' \
		--exclude-pattern 'w25q128jvxim\.sv$$' \
		--exclude-pattern 'ESP_PSRAM64H\.sv$$' --exclude-pattern 'DVP_CAMERA\.sv$$' \
		--source $(XEZIM_SRAM_MODEL) --source $(XEZIM_EXT_MODELS) --output $@

$(XEZIM_BEHV_STAMP): $(XEZIM_BEHV_FLIST)
	@mkdir -p $(@D)
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool xezim \
		--log $(XEZIM_BEHV_DIR)/compile.log --result $(XEZIM_BEHV_DIR)/result-compile.json \
		--cwd $(XEZIM_BEHV_DIR) -- $(XEZIM) --compile -s $(RTL_TOP) -f $<
	@touch $@

comp: $(XEZIM_BEHV_STAMP)

sim: comp
	python3 $(RTL_PATH)/script/prepare_norflash.py --sim-dir $(XEZIM_BEHV_DIR) \
		--firmware $(SW_BUILD_DIR)/$(SIM_FIRMWARE_NAME).hex
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/run_flow.py --tool xezim-sim --stream-bytes \
		--log $(XEZIM_BEHV_DIR)/sim.log --result $(XEZIM_BEHV_DIR)/result-sim.json \
		--cwd $(XEZIM_BEHV_DIR) -- $(XEZIM) --simulate -s $(RTL_TOP) -f $(XEZIM_BEHV_FLIST) \
		--max-time $(XEZIM_MAX_TIME)ns +sim_timeout=$(RTL_SIM_TIMEOUT) +wave_$(WAVE)
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/check_simulation.py --log $(XEZIM_BEHV_DIR)/sim.log \
		--result $(XEZIM_BEHV_DIR)/result-sim-check.json --require '$(SIM_SUCCESS_MARKER)'

netcomp netlcomp:
	@echo "Xezim backend supports RTL behavior simulation only; use SIMU=CVC or SIMU=IVERILOG for netlists" >&2
	@exit 2

netsim postsim:
	@echo "Xezim backend does not support netlist or post-layout simulation in this integration" >&2
	@exit 2

wave:
	@echo "Xezim wave viewing is not configured; use the generated simulator log"

clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(XEZIM_ROOT)

comp sim: | manifest

.PHONY: comp sim netcomp netlcomp netsim postsim wave clean