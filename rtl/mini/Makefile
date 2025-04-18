SIMU           ?= VCS
SYNC           ?= YOSYS
PDK            ?= S110
HAVE_PLL       ?= YES
HAVE_SRAM      ?= YES
HAVE_SVA       ?= NO

RTL_TOP        ?= retrosoc_tb
CORE           ?= PICORV32

RTL_SIM_PLLEN  ?= NONE
RTL_SIM_PLLCFG ?= NONE
WAVE           ?= NONE

include script/software.mk

$(info ====== CONFIG INFO ======)
$(info SIMU:           $(SIMU))
$(info PDK:            $(PDK))
$(info HAVE_PLL:       $(HAVE_PLL))
$(info HAVE_SRAM:      $(HAVE_SRAM))
$(info HAVE_SVA:       $(HAVE_SVA))
$(info RTL_TOP:        $(RTL_TOP))
$(info CORE:           $(CORE))
$(info RTL_SIM_PLLEN:  $(RTL_SIM_PLLEN))
$(info RTL_SIM_PLLCFG: $(RTL_SIM_PLLCFG))
$(info WAVE:           $(WAVE))
$(info =========================)

ifeq ($(SIMU), VCS)
    include script/vcs.mk
else ifeq ($(SIMU), IVER)
    include script/iverilog.mk
else ifeq ($(SIMU), VERI)
    include script/verilator.mk
endif

ifeq ($(SYNC), YOSYS)
    include script/yosys.mk
else ifeq ($(SYNC), DC)
    include script/dc.mk
endif

comp:
	@mkdir -p .build
	cd .build && ($(SIM_TOOL) $(SIM_OPTIONS) $(TIME_OPTION) $(RTL_FLIST) $(TB_FLIST) -top $(RTL_TOP) $(COMP_LOG))

sim: comp
	ln -sf ../retrosoc_fw.hex .build/mem_Q128_bottom.vmf
	cd .build && ($(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_vcs $(SIM_LOG))

wave:
	cd .build && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

netcomp:
	@mkdir -p .net_build
	cd .net_build && ($(SIM_TOOL) $(SIM_OPTIONS) $(TIME_OPTION) $(RTL_FLIST) -v ../syn/yosys/out/retrosoc_asic_yosys.v $(RTL_TOP).v -top $(RTL_TOP) $(COMP_LOG))

netsim: netcomp
	$(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +syn_$(WAVE) +sim_vcs +bus_conflict_off $(SIM_LOG)

netwave:
	cd .net_build && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

postcomp:
	@mkdir -p .post_build
	cd .post_build && ($(SIM_TOOL) $(SIM_OPTIONS) $(VPOST_SIM_OPTION) $(RTL_PDK) ./ip/rs232.v ./ip/kdb_model.v ./ip/psram_model.v ./ip/cust/spfs_model/N25Qxxx.v $(RTL_TOP).v -top $(RTL_TOP) $(COMP_LOG) $(VPOST_PATH))

postsim: postcomp
	$(SIM_BINY) +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_vcs $(SIM_LOG)

postwave:
	cd .post_build && ($(VERDI_TOOL) -ssf $(RTL_TOP).fsdb -nologo &)

clean:
	rm -rf .build .net_build .post_build

.PHONY: clean $(FIRMWARE_NAME).elf
