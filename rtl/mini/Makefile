$(info RTL_PATH: $(RTL_PATH))

include $(RTL_PATH)/script/software.mk

ifeq ($(SIMU), VCS)
    include $(RTL_PATH)/script/vcs.mk
else ifeq ($(SIMU), IVER)
    include $(RTL_PATH)/script/iverilog.mk
else ifeq ($(SIMU), VERI)
    include $(RTL_PATH)/script/verilator.mk
endif

gen_mpw_code:
ifeq ($(IP), MDD)
	@echo "[mpw] generating user ip ..."
	python3 $(RTL_PATH)/mpw/ip.py
else
	@echo "[mpw] skipping user ip generation"
endif

comp:
	@mkdir -p $(RTL_PATH)/.build
	cd $(RTL_PATH)/.build && ($(SIM_TOOL) $(SIM_OPTIONS) $(TIME_OPTION) $(RTL_FLIST) $(TB_FLIST) -top $(RTL_TOP) $(COMP_LOG))

sim: comp
	cd $(RTL_PATH)/.build && ($(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_vcs $(SIM_LOG))

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

.PHONY: clean firmware
