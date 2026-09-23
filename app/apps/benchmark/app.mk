APP_SRCS   += $(ROOT_PATH)/app/apps/benchmark/main.c
APP_CFLAGS += -ffunction-sections -fdata-sections -Wl,--gc-sections
# Optional split-run defines for long GA2D campaigns (default: full payload set).
APP_CFLAGS += $(BENCHMARK_EXTRA_CFLAGS)
# The GA2D Phase 6 matrix runs full-frame jobs up to 800x480 on the 24 MHz
# PRODUCT clocks; the Verilator model advances ~3K PCLK cycles per wall second,
# so the complete report needs roughly seven hours.
SOC_SIM_TIME       ?= 25200
VERILATOR_SIM_ARGS ?= --fast-flash