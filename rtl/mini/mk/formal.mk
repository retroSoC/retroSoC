FORMAL_DIR                := $(VARIANT_ROOT)/formal
FORMAL_SBY                ?= sby
FORMAL_BITWUZLA           ?= $(shell command -v bitwuzla)
FORMAL_SOLVER             := bitwuzla
FORMAL_SOLVER_DIR         := $(FORMAL_DIR)/bin
FORMAL_SOLVER_WRAPPER     := $(FORMAL_SOLVER_DIR)/bitwuzla
FORMAL_DEPTH              ?= 20
FORMAL_TIMEOUT            ?= 60
FORMAL_TARGETS            := bus rib_adapter ribp2apb sysctrl pll_rcu gpio_user
FORMAL_FILELIST_GENERATOR := $(RTL_PATH)/formal/generate_formal_filelist.py
FORMAL_SBY_GENERATOR      := $(RTL_PATH)/formal/generate_sby_config.py
FORMAL_RESULT_GENERATOR   := $(RTL_PATH)/formal/formal_results.py
FORMAL_SOURCE_FILES       := $(RTL_PATH)/formal/bus_formal.sv \
                             $(RTL_PATH)/formal/bus_formal_props.sv \
                             $(RTL_PATH)/formal/rib_adapter_formal.sv \
                             $(RTL_PATH)/formal/rib_adapter_formal_props.sv \
                             $(RTL_PATH)/formal/ribp2apb_formal.sv \
                             $(RTL_PATH)/formal/ribp2apb_formal_props.sv \
                             $(RTL_PATH)/formal/sysctrl_formal.sv \
                             $(RTL_PATH)/formal/sysctrl_formal_props.sv \
                             $(RTL_PATH)/formal/pll_rcu_formal.sv \
                             $(RTL_PATH)/formal/pll_rcu_formal_props.sv \
                             $(RTL_PATH)/formal/gpio_user_formal.sv \
                             $(RTL_PATH)/formal/gpio_user_formal_props.sv \
                             $(RTL_PATH)/top/bus.sv \
                             $(RTL_PATH)/top/soc_rib_error_slave.sv \
                             $(RTL_PATH)/top/soc_ribl_if.sv \
                             $(RTL_PATH)/top/soc_rib_if.sv \
                             $(RTL_PATH)/top/soc_rib2ram.sv \
                             $(RTL_PATH)/top/soc_rib2ribp.sv \
                             $(RTL_PATH)/top/soc_ribl2rib.sv \
                             $(ROOT_PATH)/rtl/ip/ribp/interconnect/ribp2apb.sv \
                             $(ROOT_PATH)/rtl/ip/ribp/interconnect/ribp_regslice.sv \
                             $(ROOT_PATH)/rtl/ip/ribp/peripheral/gpio.sv \
                             $(ROOT_PATH)/rtl/ip/ribp/peripheral/pll_ctrl_if.sv \
                             $(ROOT_PATH)/rtl/ip/ribp/peripheral/sysctrl.sv \
                             $(RTL_PATH)/top/rcu.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/ribp_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/apb4_pure_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/cdc/cdc_rst_ctrlr.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/cdc/cdc_2phase.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/edge_det.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/register.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/spill_register.sv \
                             $(ROOT_PATH)/scripts/bitwuzla_smt2.py
FORMAL_STAMPS             := $(addsuffix /.stamp,$(addprefix $(FORMAL_DIR)/,$(FORMAL_TARGETS)))
FORMAL_INTERMEDIATES      := $(foreach target,$(FORMAL_TARGETS), \
	$(FORMAL_DIR)/$(target)/formal.fl $(FORMAL_DIR)/$(target)/design.v \
	$(FORMAL_DIR)/$(target)/prove.sby $(FORMAL_DIR)/$(target)/cover.sby \
	$(FORMAL_DIR)/$(target)/prove.stamp \
	$(FORMAL_DIR)/$(target)/cover.stamp) $(FORMAL_SOLVER_WRAPPER)
FORMAL_RESULT             := $(META_DIR)/formal.json

.SECONDARY: $(FORMAL_INTERMEDIATES)

$(FORMAL_DIR)/%/formal.fl: $(FORMAL_FILELIST_GENERATOR) $(FORMAL_SOURCE_FILES) \
	$(MEMORY_MAP_STAMP) $(SOC_TOPOLOGY_STAMP) $(USER_EXTENSIONS_STAMP)
	@mkdir -p $(@D)
	python3 $(FORMAL_FILELIST_GENERATOR) --target $* --output $@ \
		--memory-map-dir $(MEMORY_MAP_DIR) --soc-topology-dir $(SOC_TOPOLOGY_DIR) \
		--user-extensions-dir $(USER_EXTENSIONS_DIR)

$(FORMAL_DIR)/%/design.v: $(FORMAL_DIR)/%/formal.fl $(RTL_PATH)/script/convt_sv2v.py \
	$(RTL_PATH)/script/filelist.py
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sv2v \
		--log $(@D)/sv2v.log --result $(@D)/result-sv2v.json \
		-- python3 $(RTL_PATH)/script/convt_sv2v.py -f $< --output $@

$(FORMAL_DIR)/%/prove.sby: $(FORMAL_DIR)/%/design.v $(RTL_PATH)/formal/%_formal_props.sv \
	$(FORMAL_SBY_GENERATOR)
	python3 $(FORMAL_SBY_GENERATOR) --top $*_formal --input $< \
		--properties $(RTL_PATH)/formal/$*_formal_props.sv --solver $(FORMAL_SOLVER) \
		--mode prove --depth $(FORMAL_DEPTH) --output $@

$(FORMAL_DIR)/%/cover.sby: $(FORMAL_DIR)/%/design.v $(RTL_PATH)/formal/%_formal_props.sv \
	$(FORMAL_SBY_GENERATOR)
	python3 $(FORMAL_SBY_GENERATOR) --top $*_formal --input $< \
		--properties $(RTL_PATH)/formal/$*_formal_props.sv --solver $(FORMAL_SOLVER) \
		--mode cover --depth $(FORMAL_DEPTH) --output $@

$(FORMAL_SOLVER_WRAPPER): $(ROOT_PATH)/scripts/bitwuzla_smt2.py
	@mkdir -p $(@D)
	cp $< $@
	chmod +x $@

$(FORMAL_DIR)/%/prove.stamp: $(FORMAL_DIR)/%/prove.sby $(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-prove \
		--log $(@D)/prove.log --result $(@D)/result-prove.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(FORMAL_TIMEOUT)s $(FORMAL_SBY) \
		-f -d $(@D)/prove $<
	@test "$$(awk '{print $$1}' $(@D)/prove/status)" = PASS
	@touch $@

$(FORMAL_DIR)/%/cover.stamp: $(FORMAL_DIR)/%/cover.sby $(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-cover \
		--log $(@D)/cover.log --result $(@D)/result-cover.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(FORMAL_TIMEOUT)s $(FORMAL_SBY) \
		-f -d $(@D)/cover $<
	@test "$$(awk '{print $$1}' $(@D)/cover/status)" = PASS
	@touch $@

$(FORMAL_DIR)/%/.stamp: $(FORMAL_DIR)/%/prove.stamp $(FORMAL_DIR)/%/cover.stamp
	@touch $@

$(FORMAL_RESULT): $(FORMAL_STAMPS) $(FORMAL_RESULT_GENERATOR)
	python3 $(FORMAL_RESULT_GENERATOR) --output $@ \
		$(foreach target,$(FORMAL_TARGETS),--proof $(target)=$(FORMAL_DIR)/$(target))

formal: $(FORMAL_RESULT) | manifest

formal-bus: $(FORMAL_DIR)/bus/.stamp | manifest

formal-rib-adapter: $(FORMAL_DIR)/rib_adapter/.stamp | manifest

formal-ribp2apb: $(FORMAL_DIR)/ribp2apb/.stamp | manifest

formal-sysctrl: $(FORMAL_DIR)/sysctrl/.stamp | manifest

formal-pll-rcu: $(FORMAL_DIR)/pll_rcu/.stamp | manifest

formal-gpio-user: $(FORMAL_DIR)/gpio_user/.stamp | manifest

formal-doctor:
	$(MAKE) FORMAL=YES SIMU=IVERILOG SYNTH=YOSYS STA=NONE doctor

formal-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(FORMAL_DIR)

.PHONY: formal formal-bus formal-rib-adapter formal-ribp2apb formal-sysctrl formal-pll-rcu formal-gpio-user formal-doctor formal-clean