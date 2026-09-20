APP_SRCS += $(ROOT_PATH)/app/apps/ci_smoke/main.c
# GA2D Phase 6 acceptance cases (bounded-wait and DMA contention evidence)
# outgrew the 32 KiB SRAM image at the global -O3; build this test app -Os.
APP_CFLAGS += -Os