RTL_SIM_PLLEN  :=
RTL_SIM_PLLCFG :=
SIM_TOOL       :=
WAVE           := NONE
RTL_TOP        := retrosoc_tb

include software.mk
include vcs.mk

comp:
	@mkdir -p build
	cd build && (${SIM_TOOL} ${SIM_OPTIONS} ${TIME_OPTION} ${RTL_FLIST} ${TB_FLIST} -top ${RTL_TOP} -l compile.log)

sim: comp
	${SIM_BINY} -l sim.log +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_$(SIM_TOOL)

netcomp:
	@mkdir -p net_build
	cd net_build && (${SIM_TOOL} ${SIM_OPTIONS} ${TIME_OPTION} ${RTL_FLIST} -v ../syn/yosys/out/retrosoc_asic_yosys.v ${RTL_TOP}.v -top ${RTL_TOP} -l compile.log)

netsim: netcomp
	${SIM_NETBINY} -l vnetsim.log +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +syn_$(WAVE) +sim_$(SIM_TOOL) +bus_conflict_off

postcomp:
	${SIM_TOOL} ${SIM_OPTIONS} ${VPOST_SIM_OPTION} ${RTL_PDK} ./ip/rs232.v ./ip/kdb_model.v ./ip/psram_model.v ./ip/cust/spfs_model/N25Qxxx.v ${RTL_TOP}.v -top ${RTL_TOP} -l vpostcompile.log ${VPOST_PATH} -o post_simv

postsim: postcomp
	${SIM_POSTBINY} -l vpostsim.log +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_$(SIM_TOOL)

wave:
	${VERDI_TOOL} -ssf ${RTL_TOP}.fsdb -nologo &

clean:
	rm -f build
	rm -f *.elf *.hex *.bin

.PHONY: clean $(FIRMWARE_NAME).elf
