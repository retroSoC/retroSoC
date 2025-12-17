$(info RTL_PATH: $(RTL_PATH))

gen_mpw_code:
ifeq ($(IP), MDD)
	@echo "[mpw] generating user ip ..."
	python3 $(RTL_PATH)/mpw/ip.py
	python3 $(RTL_PATH)/mpw/core.py $(SIMU)
else
	@echo "[mpw] skipping user ip generation"
endif

include $(RTL_PATH)/script/software.mk

ifeq ($(SIMU), VCS)
    include $(RTL_PATH)/script/vcs.mk
else ifeq ($(SIMU), VERILATOR)
    include $(RTL_PATH)/script/verilator.mk
else ifeq ($(SIMU), IVER)
    include $(RTL_PATH)/script/iverilog.mk
endif

.PHONY: clean firmware
