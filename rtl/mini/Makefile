$(info RTL_PATH: $(RTL_PATH))

gen_mpw_code:
	python3 $(RTL_PATH)/mpw/setup.py
ifeq ($(IP), MDD)
	@echo "[mpw] generating user ip ..."
	python3 $(RTL_PATH)/mpw/ip.py
	python3 $(RTL_PATH)/mpw/info.py IP
else
	@echo "[mpw] skipping user ip generation"
endif
ifeq ($(CORE), MDD)
	@echo "[mpw] generating core ..."
	python3 $(RTL_PATH)/mpw/core.py $(SIMU)
	python3 $(RTL_PATH)/mpw/info.py CORE
else
	@echo "[mpw] skipping core generation"
endif

generate_filelist:
	python3 $(RTL_PATH)/script/generate_filelist.py

# software
include $(RTL_PATH)/makefile/software.mk

#====================== filelist ======================
ifeq ($(PDK), IHP130)
    NET_FLIST := -f $(RTL_PATH)/.generated_fl/pdk_ihp130.fl
else ifeq ($(PDK), SKY130)
    NET_FLIST := -f $(RTL_PATH)/.generated_fl/pdk_sky130.fl
else ifeq ($(PDK), ICS55)
    NET_FLIST := -f $(RTL_PATH)/.generated_fl/pdk_ics55.fl
else ifeq ($(PDK), GF180)
    NET_FLIST := -f $(RTL_PATH)/.generated_fl/pdk_gf180.fl
endif

NET_FLIST  += -f $(RTL_PATH)/.generated_fl/def.fl
NET_FLIST  += -f $(RTL_PATH)/.generated_fl/sys_def.fl
NET_FLIST  += -f $(RTL_PATH)/.generated_fl/commonip.fl
NET_FLIST  += -f $(RTL_PATH)/.generated_fl/inc.fl

RTL_FLIST  := $(NET_FLIST)
RTL_FLIST  += -f $(RTL_PATH)/.generated_fl/clusterip.fl
RTL_FLIST  += -f $(RTL_PATH)/.generated_fl/ip.fl
RTL_FLIST  += -f $(RTL_PATH)/.generated_fl/tech.fl

ifeq ($(CORE), PICORV32)
    RTL_FLIST += -f $(RTL_PATH)/.generated_fl/core_picorv32.fl
else ifeq ($(CORE), HAZARD3)
    RTL_FLIST += -f $(RTL_PATH)/.generated_fl/core_hazard3.fl
else ifeq ($(CORE), MDD)
    RTL_FLIST += -f $(RTL_PATH)/mpw/.build/core/core.fl
endif

ifeq ($(IP), MDD)
    RTL_FLIST += -f $(RTL_PATH)/mpw/.build/ip/ip.fl
endif

RTL_FLIST += -f $(RTL_PATH)/.generated_fl/top.fl
#====================== end ======================

ifeq ($(SIMU), VCS)
    include $(RTL_PATH)/makefile/vcs.mk
else ifeq ($(SIMU), VERILATOR)
    include $(RTL_PATH)/makefile/verilator.mk
else ifeq ($(SIMU), IVERILOG)
    include $(RTL_PATH)/makefile/iverilog.mk
endif

.PHONY: clean firmware
