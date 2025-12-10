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

.PHONY: clean firmware
