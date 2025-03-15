RTL_SIM_PLLEN  :=
RTL_SIM_PLLCFG :=
WAVE           := NONE
RTL_TOP        := retrosoc_tb

include software.mk
include vcs.mk

comp:
	@mkdir -p build
	cd build && (${SIM_TOOL} ${SIM_OPTIONS} ${TIME_OPTION} ${RTL_FLIST} ${TB_FLIST} -top ${RTL_TOP} ${COMP_LOG})

sim: comp
	cd build && (${SIM_BINY} +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_vcs ${SIM_LOG})

netcomp:
	@mkdir -p net_build
	cd net_build && (${SIM_TOOL} ${SIM_OPTIONS} ${TIME_OPTION} ${RTL_FLIST} -v ../syn/yosys/out/retrosoc_asic_yosys.v ${RTL_TOP}.v -top ${RTL_TOP} ${COMP_LOG})

netsim: netcomp
	${SIM_BINY} +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +syn_$(WAVE) +sim_vcs +bus_conflict_off ${SIM_LOG}

postcomp:
	@mkdir -p post_build
	cd post_build && (${SIM_TOOL} ${SIM_OPTIONS} ${VPOST_SIM_OPTION} ${RTL_PDK} ./ip/rs232.v ./ip/kdb_model.v ./ip/psram_model.v ./ip/cust/spfs_model/N25Qxxx.v ${RTL_TOP}.v -top ${RTL_TOP} ${COMP_LOG} ${VPOST_PATH})

postsim: postcomp
	${SIM_BINY} +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_vcs ${SIM_LOG}

wave:
	${VERDI_TOOL} -ssf ${RTL_TOP}.fsdb -nologo &

clean:
	rm -f build
	rm -f *.elf *.hex *.bin

.PHONY: clean $(FIRMWARE_NAME).elf
