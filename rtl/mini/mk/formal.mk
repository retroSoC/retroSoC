FORMAL_DIR                    := $(VARIANT_ROOT)/formal
FORMAL_SBY                    ?= sby
FORMAL_BITWUZLA               ?= $(shell command -v bitwuzla)
FORMAL_SOLVER                 := bitwuzla
FORMAL_SOLVER_DIR             := $(FORMAL_DIR)/bin
FORMAL_SOLVER_WRAPPER         := $(FORMAL_SOLVER_DIR)/bitwuzla
FORMAL_DEPTH                  ?= 20
FORMAL_PLL_RCU_DEPTH          ?= 32
FORMAL_WS2812_DEPTH           ?= 120
FORMAL_I2C_DEPTH              ?= 80
FORMAL_CLINT_DEPTH            ?= 32
FORMAL_PSRAM_DEPTH            ?= 32
FORMAL_OPIPSRAM_DEPTH         ?= 40
FORMAL_OPIPSRAM_BMC_DEPTH     ?= 40
FORMAL_DMA_DEPTH              ?= 24
FORMAL_DMA_COVER_DEPTH        ?= 32
FORMAL_APU_DEPTH              ?= 24
FORMAL_APU_LOADER_DEPTH       ?= 128
FORMAL_APU_LOADER_COVER_DEPTH ?= 128
FORMAL_APU_SEQUENCER_DEPTH    ?= 38
FORMAL_GATEWAY_A_DEPTH        ?= 20
FORMAL_SDIO_DEPTH             ?= 20
FORMAL_SDIO_COVER_DEPTH       ?= 24
FORMAL_TIMEOUT                ?= 60
FORMAL_WS2812_TIMEOUT         ?= 120
FORMAL_I2C_TIMEOUT            ?= 300
FORMAL_OPIPSRAM_TIMEOUT       ?= 300
FORMAL_OPIPSRAM_BMC_TIMEOUT   ?= 600
FORMAL_DMA_TIMEOUT            ?= 120
FORMAL_APU_TIMEOUT            ?= 300
FORMAL_GATEWAY_A_TIMEOUT      ?= 120
FORMAL_SDIO_TIMEOUT           ?= 120
FORMAL_APU_LOADER_TARGETS     := apu_loader_success apu_loader_header_range apu_loader_descriptor_range apu_loader_crc apu_loader_control_flow apu_loader_abort apu_loader_resource_reset
FORMAL_TARGET_TIMEOUT         = $(if $(filter dma,$*),$(FORMAL_DMA_TIMEOUT),$(if $(filter apu apu_sequencer $(FORMAL_APU_LOADER_TARGETS),$*),$(FORMAL_APU_TIMEOUT),$(if $(filter gateway_a,$*),$(FORMAL_GATEWAY_A_TIMEOUT),$(if $(filter sdio,$*),$(FORMAL_SDIO_TIMEOUT),$(if $(filter opipsram,$*),$(FORMAL_OPIPSRAM_TIMEOUT),$(if $(filter ws2812,$*),$(FORMAL_WS2812_TIMEOUT),$(if $(filter i2c,$*),$(FORMAL_I2C_TIMEOUT),$(FORMAL_TIMEOUT))))))))
FORMAL_APU_TARGET_DEPTH       = $(if $(filter $(FORMAL_APU_LOADER_TARGETS),$*),$(FORMAL_APU_LOADER_DEPTH),$(if $(filter apu_sequencer,$*),$(FORMAL_APU_SEQUENCER_DEPTH),$(FORMAL_APU_DEPTH)))
FORMAL_APU_TARGET_COVER_DEPTH = $(if $(filter $(FORMAL_APU_LOADER_TARGETS),$*),$(FORMAL_APU_LOADER_COVER_DEPTH),$(FORMAL_APU_TARGET_DEPTH))
FORMAL_TARGET_TOP             = $(if $(filter $(FORMAL_APU_LOADER_TARGETS),$*),apu_loader,$*)
FORMAL_COMPACT_COVER_TARGETS  := i2c opipsram dma $(FORMAL_APU_LOADER_TARGETS)
FORMAL_TARGETS                := bus rib_adapter rib2apb sysctrl pll_rcu gpio ws2812 uart i2c timer clint dvp i2s psram onchip_ram opipsram dma apu $(FORMAL_APU_LOADER_TARGETS) apu_sequencer gateway_a sdio
FORMAL_FILELIST_GENERATOR     := $(RTL_PATH)/formal/generate_formal_filelist.py
FORMAL_SBY_GENERATOR          := $(RTL_PATH)/formal/generate_sby_config.py
FORMAL_RESULT_GENERATOR       := $(RTL_PATH)/formal/formal_results.py
FORMAL_SOURCE_FILES           := $(RTL_PATH)/formal/bus_formal.sv \
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
                             $(RTL_PATH)/formal/i2s_formal.sv \
                             $(RTL_PATH)/formal/i2s_formal_props.sv \
                             $(RTL_PATH)/formal/psram_formal.sv \
                             $(RTL_PATH)/formal/psram_formal_props.sv \
                             $(RTL_PATH)/formal/onchip_ram_formal.sv \
                             $(RTL_PATH)/formal/onchip_ram_formal_props.sv \
                             $(RTL_PATH)/formal/opipsram_formal.sv \
                             $(RTL_PATH)/formal/opipsram_formal_props.sv \
                             $(RTL_PATH)/formal/dma_formal.sv \
                             $(RTL_PATH)/formal/dma_formal_props.sv \
                             $(RTL_PATH)/formal/apu_formal.sv \
                             $(RTL_PATH)/formal/apu_formal_props.sv \
                             $(RTL_PATH)/formal/apu_loader_formal.sv \
                             $(RTL_PATH)/formal/apu_loader_formal_props.sv \
                             $(RTL_PATH)/formal/apu_sequencer_formal.sv \
                             $(RTL_PATH)/formal/apu_sequencer_formal_props.sv \
                             $(RTL_PATH)/formal/gateway_a_formal.sv \
                             $(RTL_PATH)/formal/gateway_a_formal_props.sv \
                             $(RTL_PATH)/formal/sdio_formal.sv \
                             $(RTL_PATH)/formal/sdio_formal_props.sv \
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
                             $(ROOT_PATH)/rtl/ip/peripheral/clock_ctrl_if.sv \
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
                             $(ROOT_PATH)/rtl/ip/serial/i2s_define.svh \
                             $(ROOT_PATH)/rtl/ip/serial/i2s_pkg.sv \
                             $(ROOT_PATH)/rtl/ip/serial/i2s_reg.sv \
                             $(ROOT_PATH)/rtl/ip/serial/i2c_if.sv \
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
                             $(RTL_PATH)/top/onchip_ram_reg.sv \
                             $(RTL_PATH)/top/onchip_ram.sv \
                             $(ROOT_PATH)/rtl/tech/tc_sram.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/register.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/xchecker.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/gray2bin.sv \
                             $(ROOT_PATH)/rtl/ip/util/async_fifo.sv \
                             $(ROOT_PATH)/rtl/tech/tc_clk.sv \
                             $(ROOT_PATH)/rtl/tech/tc_opipsram_delay.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_define.svh \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_pkg.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_protocol.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_trx.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_axi4.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_core.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_phy.sv \
                             $(ROOT_PATH)/rtl/ip/memory/opipsram_reg.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/dma_pkg.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/dma_req_if.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/dma_axi4_master.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/apu_dma.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/apu_microcode_pkg.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/apu_microcode_loader.sv \
                             $(ROOT_PATH)/rtl/ip/multimedia/apu_codec_sequencer.sv \
                             $(ROOT_PATH)/rtl/ip/peripheral/dma_core.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/clkrst/counter.sv \
                             $(RTL_PATH)/top/rcu.sv \
                             $(RTL_PATH)/top/pll_rcu_controller.sv \
                             $(RTL_PATH)/top/hp_axi4_mux3.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/apb4_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/ribp_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/apb4_pure_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/axi4_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/cdc/cdc_rst_ctrlr.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/cdc/cdc_2phase.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/edge_det.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/spill_register.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/utils/fifo.sv \
                             $(ROOT_PATH)/rtl/managed/clusterip/common/rtl/stream/round_robin_arbiter.sv \
                             $(ROOT_PATH)/scripts/bitwuzla_smt2.py
FORMAL_STAMPS                 := $(addsuffix /.stamp,$(addprefix $(FORMAL_DIR)/,$(FORMAL_TARGETS)))
FORMAL_INTERMEDIATES          := $(foreach target,$(FORMAL_TARGETS), \
	$(FORMAL_DIR)/$(target)/formal.fl $(FORMAL_DIR)/$(target)/design.v \
	$(FORMAL_DIR)/$(target)/prove.sby $(FORMAL_DIR)/$(target)/cover.sby \
	$(FORMAL_DIR)/$(target)/prove.stamp \
	$(FORMAL_DIR)/$(target)/cover.stamp) \
	$(FORMAL_DIR)/opipsram/bmc.sby $(FORMAL_DIR)/opipsram/bmc.stamp \
	$(FORMAL_SOLVER_WRAPPER)
FORMAL_RESULT                 := $(META_DIR)/formal.json

.SECONDARY: $(FORMAL_INTERMEDIATES)

$(FORMAL_DIR)/%/formal.fl: $(FORMAL_FILELIST_GENERATOR) $(FORMAL_SOURCE_FILES) \
	$(MEMORY_MAP_STAMP) $(SOC_TOPOLOGY_STAMP) $(USER_EXTENSIONS_STAMP)
	@mkdir -p $(@D)
	python3 $(FORMAL_FILELIST_GENERATOR) --target $* --output $@ \
		--memory-map-dir $(MEMORY_MAP_DIR) --soc-topology-dir $(SOC_TOPOLOGY_DIR) \
		--user-extensions-dir $(USER_EXTENSIONS_DIR)

$(FORMAL_DIR)/%/design.v: $(FORMAL_DIR)/%/formal.fl $(RTL_PATH)/script/convt_sv2v.py \
	$(RTL_PATH)/script/filelist.py $(FORMAL_SOURCE_FILES)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sv2v \
		--log $(@D)/sv2v.log --result $(@D)/result-sv2v.json \
		-- python3 $(RTL_PATH)/script/convt_sv2v.py -f $< --output $@

$(FORMAL_DIR)/%/prove.sby: $(FORMAL_DIR)/%/design.v \
	$(FORMAL_SBY_GENERATOR)
	python3 $(FORMAL_SBY_GENERATOR) --top $(FORMAL_TARGET_TOP)_formal --input $< \
		--properties $(RTL_PATH)/formal/$(FORMAL_TARGET_TOP)_formal_props.sv --solver $(FORMAL_SOLVER) \
		--mode $(if $(filter dma apu apu_sequencer $(FORMAL_APU_LOADER_TARGETS) gateway_a sdio onchip_ram,$*),bmc,prove) --depth $(if $(filter pll_rcu,$*),$(FORMAL_PLL_RCU_DEPTH),$(if $(filter dma,$*),$(FORMAL_DMA_DEPTH),$(if $(filter apu apu_sequencer $(FORMAL_APU_LOADER_TARGETS),$*),$(FORMAL_APU_TARGET_DEPTH),$(if $(filter gateway_a,$*),$(FORMAL_GATEWAY_A_DEPTH),$(if $(filter sdio,$*),$(FORMAL_SDIO_DEPTH),$(if $(filter opipsram,$*),$(FORMAL_OPIPSRAM_DEPTH),$(if $(filter ws2812,$*),$(FORMAL_WS2812_DEPTH),$(if $(filter i2c,$*),$(FORMAL_I2C_DEPTH),$(if $(filter clint,$*),$(FORMAL_CLINT_DEPTH),$(if $(filter psram,$*),$(FORMAL_PSRAM_DEPTH),$(FORMAL_DEPTH))))))))))) --output $@
	@if [ "$*" = opipsram ]; then sed -i '/^async2sync/i clk2fflogic' $@; fi

$(FORMAL_DIR)/%/cover.sby: $(FORMAL_DIR)/%/design.v \
	$(FORMAL_SBY_GENERATOR)
	python3 $(FORMAL_SBY_GENERATOR) --top $(FORMAL_TARGET_TOP)_formal --input $< \
		--properties $(RTL_PATH)/formal/$(FORMAL_TARGET_TOP)_formal_props.sv --solver $(FORMAL_SOLVER) \
		--mode cover --depth $(if $(filter pll_rcu,$*),$(FORMAL_PLL_RCU_DEPTH),$(if $(filter dma,$*),$(FORMAL_DMA_COVER_DEPTH),$(if $(filter apu apu_sequencer $(FORMAL_APU_LOADER_TARGETS),$*),$(FORMAL_APU_TARGET_COVER_DEPTH),$(if $(filter gateway_a,$*),$(FORMAL_GATEWAY_A_DEPTH),$(if $(filter sdio,$*),$(FORMAL_SDIO_COVER_DEPTH),$(if $(filter opipsram,$*),$(FORMAL_OPIPSRAM_DEPTH),$(if $(filter ws2812,$*),$(FORMAL_WS2812_DEPTH),$(if $(filter i2c,$*),$(FORMAL_I2C_DEPTH),$(if $(filter clint,$*),$(FORMAL_CLINT_DEPTH),$(if $(filter psram,$*),$(FORMAL_PSRAM_DEPTH),$(FORMAL_DEPTH))))))))))) \
		$(if $(filter $(FORMAL_COMPACT_COVER_TARGETS),$*),--no-vcd) --output $@
	@if [ "$*" = opipsram ]; then sed -i '/^async2sync/i clk2fflogic' $@; fi

$(FORMAL_DIR)/opipsram/bmc.sby: $(FORMAL_DIR)/opipsram/design.v \
	$(RTL_PATH)/formal/opipsram_formal_props.sv $(FORMAL_SBY_GENERATOR)
	python3 $(FORMAL_SBY_GENERATOR) --top opipsram_formal \
		--input $(FORMAL_DIR)/opipsram/design.v \
		--properties $(RTL_PATH)/formal/opipsram_formal_props.sv \
		--solver $(FORMAL_SOLVER) --mode bmc --depth $(FORMAL_OPIPSRAM_BMC_DEPTH) \
		--output $@
	@sed -i 's/^read_verilog -formal -sv properties.v$$/read_verilog -formal -sv -DOPIPSRAM_BMC properties.v/' $@
	@sed -i '/^async2sync/i clk2fflogic' $@

$(FORMAL_SOLVER_WRAPPER): $(ROOT_PATH)/scripts/bitwuzla_smt2.py
	@mkdir -p $(@D)
	cp $< $@
	chmod +x $@

$(FORMAL_DIR)/%/prove.stamp: $(FORMAL_DIR)/%/prove.sby $(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-prove \
		--log $(@D)/prove.log --result $(@D)/result-prove.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(FORMAL_TARGET_TIMEOUT)s $(FORMAL_SBY) \
		-f -d $(@D)/prove $<
	@test "$$(awk '{print $$1}' $(@D)/prove/status)" = PASS
	@touch $@

$(FORMAL_DIR)/%/cover.stamp: $(FORMAL_DIR)/%/cover.sby $(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-cover \
		--log $(@D)/cover.log --result $(@D)/result-cover.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(FORMAL_TARGET_TIMEOUT)s $(FORMAL_SBY) \
		-f -d $(@D)/cover $<
	@test "$$(awk '{print $$1}' $(@D)/cover/status)" = PASS
	@touch $@

$(FORMAL_DIR)/opipsram/bmc.stamp: $(FORMAL_DIR)/opipsram/bmc.sby \
	$(FORMAL_SOLVER_WRAPPER)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool formal-sby-bmc \
		--log $(@D)/bmc.log --result $(@D)/result-bmc.json \
		--env RETROSOC_BITWUZLA=$(FORMAL_BITWUZLA) \
		--env PATH=$(FORMAL_SOLVER_DIR):$(PATH) \
		-- timeout --foreground --kill-after=5s $(FORMAL_OPIPSRAM_BMC_TIMEOUT)s $(FORMAL_SBY) \
		-f -d $(@D)/bmc $<
	@test "$$(awk '{print $$1}' $(@D)/bmc/status)" = PASS
	@touch $@

$(FORMAL_DIR)/opipsram/.stamp: $(FORMAL_DIR)/opipsram/prove.stamp \
	$(FORMAL_DIR)/opipsram/cover.stamp $(FORMAL_DIR)/opipsram/bmc.stamp
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

formal-i2s: $(FORMAL_DIR)/i2s/.stamp | manifest

formal-psram: $(FORMAL_DIR)/psram/.stamp | manifest

formal-onchip-ram: $(FORMAL_DIR)/onchip_ram/.stamp | manifest

formal-opipsram: $(FORMAL_DIR)/opipsram/.stamp | manifest

formal-dma: $(FORMAL_DIR)/dma/.stamp | manifest

formal-apu: $(FORMAL_DIR)/apu/.stamp | manifest

formal-apu-loader: $(addsuffix /.stamp,$(addprefix $(FORMAL_DIR)/,$(FORMAL_APU_LOADER_TARGETS))) | manifest

formal-apu-sequencer: $(FORMAL_DIR)/apu_sequencer/.stamp | manifest

formal-gateway-a: $(FORMAL_DIR)/gateway_a/.stamp | manifest

formal-sdio: $(FORMAL_DIR)/sdio/.stamp | manifest

formal-doctor:
	$(MAKE) FORMAL=YES SIMU=IVERILOG SYNTH=YOSYS STA=NONE doctor

formal-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(FORMAL_DIR)

.PHONY: formal formal-bus formal-rib-adapter formal-rib2apb formal-sysctrl formal-pll-rcu formal-gpio formal-ws2812 formal-uart formal-i2c formal-timer formal-clint formal-dvp formal-i2s formal-psram formal-onchip-ram formal-opipsram formal-dma formal-apu formal-apu-loader formal-apu-sequencer formal-gateway-a formal-sdio formal-doctor formal-clean
