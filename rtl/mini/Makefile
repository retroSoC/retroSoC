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

# software
include $(RTL_PATH)/script/software.mk

#====================== filelist ======================
ifeq ($(PDK), IHP130)
    NET_FLIST := -f $(RTL_PATH)/../filelist/pdk_ihp130.fl
else ifeq ($(PDK), S110)
    NET_FLIST := -f $(RTL_PATH)/../filelist/pdk_s110.fl
else ifeq ($(PDK), ICS55)
    NET_FLIST := -f $(RTL_PATH)/../filelist/pdk_ics55.fl
else ifeq ($(PDK), GF180)
    NET_FLIST := -f $(RTL_PATH)/../filelist/pdk_gf180.fl
endif

NET_FLIST  += -f $(RTL_PATH)/filelist/def.fl
NET_FLIST  += -f $(RTL_PATH)/filelist/sys_def.fl

ifeq ($(SIMU), VCS)
    NET_FLIST  += -f $(RTL_PATH)/filelist/inc.fl
else ifeq ($(SIMU), VERILATOR)
	NET_FLIST  += -f $(RTL_PATH)/filelist/inc_verilator.fl
endif

RTL_FLIST  := $(NET_FLIST)
RTL_FLIST  += -f $(RTL_PATH)/filelist/ip.fl
RTL_FLIST  += -f $(RTL_PATH)/filelist/tech.fl

ifeq ($(CORE), PICORV32)
    RTL_FLIST += -f $(RTL_PATH)/filelist/core_picorv32.fl
else ifeq ($(CORE), HAZARD3)
    RTL_FLIST += -f $(RTL_PATH)/filelist/core_hazard3.fl
else ifeq ($(CORE), MDD)
    RTL_FLIST += -f $(RTL_PATH)/mpw/.build/core/core.fl
endif

ifeq ($(IP), MDD)
    RTL_FLIST += -f $(RTL_PATH)/mpw/.build/ip/ip.fl
endif

RTL_FLIST += -f $(RTL_PATH)/filelist/top.fl
#====================== end ======================

ifeq ($(SIMU), VCS)
    include $(RTL_PATH)/script/vcs.mk
else ifeq ($(SIMU), VERILATOR)
    include $(RTL_PATH)/script/verilator.mk
else ifeq ($(SIMU), IVER)
    include $(RTL_PATH)/script/iverilog.mk
endif

.PHONY: clean firmware
