GENERATED_FL_DIR := $(RTL_PATH)/.generated_fl
MPW_STAMP        := $(RTL_PATH)/mpw/.build/.prepared

$(MPW_STAMP):
	@test -d $(RTL_PATH)/mpw/.git || { \
		echo "missing $(RTL_PATH)/mpw; run 'make setup-mpw' first" >&2; \
		exit 1; \
	}
	python3 $(ROOT_PATH)/scripts/prepare_mpw.py
	@mkdir -p $(@D)
	@touch $@

gen_mpw_code: $(MPW_STAMP)
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
	python3 $(RTL_PATH)/script/generate_filelist.py \
		--output-dir $(GENERATED_FL_DIR) \
		$(foreach define,$(DEF_LIST),--define $(define))

# software
include $(RTL_PATH)/mk/software.mk

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
    include $(RTL_PATH)/mk/vcs.mk
else ifeq ($(SIMU), VERILATOR)
    include $(RTL_PATH)/mk/verilator.mk
else ifeq ($(SIMU), IVERILOG)
    include $(RTL_PATH)/mk/iverilog.mk
endif

.PHONY: gen_mpw_code generate_filelist firmware
