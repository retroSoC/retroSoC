APP_SRCS   += $(ROOT_PATH)/app/apps/benchmark/main.c
APP_CFLAGS += -ffunction-sections -fdata-sections -Wl,--gc-sections
SOC_SIM_TIME ?= 600
VERILATOR_SIM_ARGS ?= --fast-flash