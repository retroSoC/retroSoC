APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/tiny.c
APP_CFLAGS += -Os
APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/mcu_acceptance.S
APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p6.c
ifeq ($(TINY_PIOLITE_P4_ACCEPTANCE),YES)
PIOLITE_P4_PROGRAM_NAMES := logic_capture pulse_generate pulse_capture uart_tx uart_rx spi_master spi_master_mode1 spi_master_mode2 spi_master_mode3 ir_tx ir_rx led_scan gamepad
PIOLITE_P4_GENERATED_DIR := $(VARIANT_ROOT)/generated/piolite
PIOLITE_P4_GENERATED_C   := $(addprefix $(PIOLITE_P4_GENERATED_DIR)/,$(addsuffix .c,$(PIOLITE_P4_PROGRAM_NAMES)))
APP_SRCS                 := $(ROOT_PATH)/app/apps/bringup/tiny_piolite_p4.c \
                            $(ROOT_PATH)/app/apps/bringup/piolite_p4_examples.c \
                            $(ROOT_PATH)/app/apps/bringup/piolite_p4_scenarios.c
APP_CFLAGS               += -DRS_PIOLITE_P4_SCENARIO_$(TINY_PIOLITE_P4_SCENARIO)
TINY_SIM_ARGS            += +piolite_p4_loopback +piolite_p4_scenario_$(TINY_PIOLITE_P4_SCENARIO)
APP_INC_DIRS             += $(PIOLITE_P4_GENERATED_DIR) $(ROOT_PATH)/app/apps/bringup
$(SW_BUILD_DIR)/firmware: $(PIOLITE_P4_GENERATED_C)
$(PIOLITE_P4_GENERATED_DIR)/%.c: $(ROOT_PATH)/app/asm/piolite/%.piolite \
	$(ROOT_PATH)/scripts/piolite_asm.py $(ROOT_PATH)/scripts/piolite_isa.py
	@mkdir -p $(@D)
	$(PYTHON) $(ROOT_PATH)/scripts/piolite_asm.py $< $@
endif