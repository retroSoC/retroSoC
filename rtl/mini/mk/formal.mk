FORMAL_DIR                := $(VARIANT_ROOT)/formal
FORMAL_SBY                ?= sby
FORMAL_BITWUZLA           ?= $(shell command -v bitwuzla)
FORMAL_SOLVER             := bitwuzla
FORMAL_SOLVER_DIR         := $(FORMAL_DIR)/bin
FORMAL_SOLVER_WRAPPER     := $(FORMAL_SOLVER_DIR)/bitwuzla
FORMAL_DEPTH              ?= 20
FORMAL_WS2812_DEPTH       ?= 120
FORMAL_I2C_DEPTH          ?= 80
FORMAL_CLINT_DEPTH        ?= 32
FORMAL_PSRAM_DEPTH        ?= 32
FORMAL_TIMEOUT            ?= 60
FORMAL_WS2812_TIMEOUT     ?= 120
FORMAL_I2C_TIMEOUT        ?= 300
FORMAL_TARGETS            := bus rib_adapter rib2apb sysctrl pll_rcu gpio ws2812 uart i2c timer clint dvp psram
FORMAL_FILELIST_GENERATOR := $(RTL_PATH)/formal/generate_formal_filelist.py
FORMAL_SBY_GENERATOR      := $(RTL_PATH)/formal/generate_sby_config.py
FORMAL_RESULT_GENERATOR   := $(RTL_PATH)/formal/formal_results.py
FORMAL_SOURCE_FILES       := $(RTL_PATH)/formal/bus_formal.sv \
                             $(RTL_PATH)/formal/bus_formal_props.sv \
                             $(RTL_PATH)/formal/rib_adapter_formal.sv \
                             $(RTL_PATH)/formal/rib_adapter_formal_props.sv \
                             $(RTL_PATH)/formal/rib2apb_formal.sv \
                             $(RTL_PATH)/formal/rib2apb_formal_props.sv \
                             $(RTL_PATH)/formal/sysctrl_formal.sv \
                             $(RTL_PATH)/formal/sysctrl_formal_props.sv \
                             $(RTL_PATH)/formal/pll_rcu_formal.sv \
                             $(RTL_PATH)/formal/pll_rcu_formal_props.sv \
                             $(RTL_PATH)/formal/gpio_formal.sv \
                             $(RTL_PATH)/formal/gpio_formal_props.sv \
                             $(RTL_PATH)/formal/ws2812_formal.sv \
                             $(RTL_PATH)/formal/ws2812_formal_props.sv \
                             $(RTL_PATH)/formal/uart_formal.sv \
                             $(RTL_PATH)/formal/uart_formal_props.sv \
                             $(RTL_PATH)/formal/i2c_formal.sv \
                             $(RTL_PATH)/formal/i2c_formal_props.sv \
                             $(RTL_PATH)/formal/timer_formal.sv \
                             $(RTL_PATH)/formal/timer_formal_props.sv \
                             $(RTL_PATH)/formal/clint_formal.sv \
                             $(RTL_PATH)/formal/clint_formal_props.sv \
                             $(RTL_PATH)/formal/dvp_formal.sv \
                             $(RTL_PATH)/formal/dvp_formal_props.sv \
                             $(RTL_PATH)/formal/psram_formal.sv \
                             $(RTL_PATH)/formal/psram_formal_props.sv \
                             $(RTL_PATH)/top/rib_bus.sv \
                             $(RTL_PATH)/top/rib_error_slave.sv \
                             $(RTL_PATH)/top/rib_if.sv \
                             $(RTL_PATH)/top/rib2ram.sv \
                             $(RTL_PATH)/top/rib2ribp.sv \
                             $(RTL_PATH)/top/rib2apb.sv \
                             $(RTL_PATH)/top/ribp2rib.sv \
                             $(ROOT_PATH)/rtl/ip/interconnect/ribp_regslice.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/gpio_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/user_gpio_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/gpio_core.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/gpio_reg.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/apb4_gpio.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/pll_ctrl_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/sysctrl_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/sysctrl_define.svh \
                             $(ROOT_PATH)/rtl/ip/peripheral/sysctrl_reg.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/sysctrl_core.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/apb4_sysctrl.sv \
                             $(ROOT_PATH)/rtl/ip/serial/ws2812_if.sv \
                             $(ROOT_PATH)/rtl/ip/serial/ws2812_reg.sv \
                             $(ROOT_PATH)/rtl/ip/serial/ws2812_core.sv \
                             $(ROOT_PATH)/rtl/ip/serial/apb4_ws2812.sv \
                             $(ROOT_PATH)/rtl/ip/serial/uart_if.sv \
                             $(ROOT_PATH)/rtl/ip/serial/uart_baudgen.sv \
                             $(ROOT_PATH)/rtl/ip/serial/apb4_uart_tx.sv \
                             $(ROOT_PATH)/rtl/ip/serial/apb4_uart_rx.sv \
                             $(ROOT_PATH)/rtl/ip/serial/uart_flow_ctrl.sv \
                             $(ROOT_PATH)/rtl/ip/serial/uart_core.sv \
                             $(ROOT_PATH)/rtl/ip/serial/uart_reg.sv \
                             $(ROOT_PATH)/rtl/ip/serial/apb4_uart.sv \
                             $(ROOT_PATH)/rtl/ip/serial/i2c_filter.sv \
                             $(ROOT_PATH)/rtl/ip/serial/i2c_core.sv \
                             $(ROOT_PATH)/rtl/ip/serial/i2c_reg.sv \
                             $(ROOT_PATH)/rtl/ip/serial/apb4_i2c.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/i2c/rtl/i2c_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/timer_core.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/timer_define.svh \
                             $(ROOT_PATH)/rtl/ip/peripheral/timer_reg.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/apb4_timer.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/clint_define.svh \
                             $(ROOT_PATH)/rtl/ip/peripheral/clint_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/clint_reg.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/clint_core.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/apb4_clint.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/dvp_define.svh \
                             $(ROOT_PATH)/rtl/ip/multimedia/dvp_core.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/dvp_reg.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/axi4s_dvp.sv \
                             $(ROOT_PATH)/rtl/ip/memory/psram_pkg.sv \
                             $(ROOT_PATH)/rtl/ip/memory/psram_axi4.sv \
                             $(ROOT_PATH)/rtl/ip/memory/psram_phy.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/clkrst/counter.sv \
                             $(RTL_PATH)/top/rcu.sv \
                             $(RTL_PATH)/top/pll_rcu_controller.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/apb4_if.sv \
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
		--mode prove --depth $(if $(filter ws2812,$*),$(FORMAL_WS2812_DEPTH),$(if $(filter i2c,$*),$(FORMAL_I2C_DEPTH),$(if $(filter clint,$*),$(FORMAL_CLINT_DEPTH),$(if $(filter psram,$*),$(FORMAL_PSRAM_DEPTH),$(FORMAL_DEPTH))))) --output $@

$(FORMAL_DIR)/%/cover.sby: $(FORMAL_DIR)/%/design.v $(RTL_PATH)/formal/%_formal_props.sv \
	$(FORMAL_SBY_GENERATOR)
	python3 $(FORMAL_SBY_GENERATOR) --top $*_formal --input $< \
		--properties $(RTL_PATH)/formal/$*_formal_props.sv --solver $(FORMAL_SOLVER) \
		--mode cover --depth $(if $(filter ws2812,$*),$(FORMAL_WS2812_DEPTH),$(if $(filter i2c,$*),$(FORMAL_I2C_DEPTH),$(if $(filter clint,$*),$(FORMAL_CLINT_DEPTH),$(if $(filter psram,$*),$(FORMAL_PSRAM_DEPTH),$(FORMAL_DEPTH))))) \
		$(if $(filter i2c,$*),--no-vcd) --output $@

$(FORMAL_SOLVER_WRAPPER): $(ROOT_PATH)/scripts/bitwuzla_smt2.py
	@mkdir -p $(@D)
	cp $< $@
	chmod +x $@

$(FORMAL_DIR)/%/prove.stamp: $(FORMAL_DIR)/%/prove.sby $(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-prove \
		--log $(@D)/prove.log --result $(@D)/result-prove.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(if $(filter ws2812,$*),$(FORMAL_WS2812_TIMEOUT),$(if $(filter i2c,$*),$(FORMAL_I2C_TIMEOUT),$(FORMAL_TIMEOUT)))s $(FORMAL_SBY) \
		-f -d $(@D)/prove $<
	@test "$$(awk '{print $$1}' $(@D)/prove/status)" = PASS
	@touch $@

$(FORMAL_DIR)/%/cover.stamp: $(FORMAL_DIR)/%/cover.sby $(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-cover \
		--log $(@D)/cover.log --result $(@D)/result-cover.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(if $(filter ws2812,$*),$(FORMAL_WS2812_TIMEOUT),$(if $(filter i2c,$*),$(FORMAL_I2C_TIMEOUT),$(FORMAL_TIMEOUT)))s $(FORMAL_SBY) \
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

formal-rib2apb: $(FORMAL_DIR)/rib2apb/.stamp | manifest

formal-sysctrl: $(FORMAL_DIR)/sysctrl/.stamp | manifest

formal-pll-rcu: $(FORMAL_DIR)/pll_rcu/.stamp | manifest

formal-gpio: $(FORMAL_DIR)/gpio/.stamp | manifest

formal-ws2812: $(FORMAL_DIR)/ws2812/.stamp | manifest

formal-uart: $(FORMAL_DIR)/uart/.stamp | manifest

formal-i2c: $(FORMAL_DIR)/i2c/.stamp | manifest

formal-timer: $(FORMAL_DIR)/timer/.stamp | manifest

formal-clint: $(FORMAL_DIR)/clint/.stamp | manifest

formal-dvp: $(FORMAL_DIR)/dvp/.stamp | manifest

formal-psram: $(FORMAL_DIR)/psram/.stamp | manifest

formal-doctor:
	$(MAKE) FORMAL=YES SIMU=IVERILOG SYNTH=YOSYS STA=NONE doctor

formal-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(FORMAL_DIR)

.PHONY: formal formal-bus formal-rib-adapter formal-rib2apb formal-sysctrl formal-pll-rcu formal-gpio formal-ws2812 formal-uart formal-i2c formal-timer formal-clint formal-dvp formal-psram formal-doctor formal-clean