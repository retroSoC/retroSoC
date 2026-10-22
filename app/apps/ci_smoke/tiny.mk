APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/tiny.c
APP_CFLAGS += -Os
APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/mcu_acceptance.S
APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p6.c
ifeq ($(TINY_P7_ACCEPTANCE),YES)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p7.c
endif
ifeq ($(TINY_P8_ACCEPTANCE),YES)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p8.c
endif
ifeq ($(TINY_P9_ACCEPTANCE),YES)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p9.c
ifeq ($(TINY_P9_WORKLOAD),RECOVERY)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p9_recovery.c
endif
ifeq ($(TINY_P9_WORKLOAD),VGA_YUV422)
APP_CFLAGS += -DRS_TINY_P9_VGA_YUV422
endif
ifeq ($(TINY_P9_QUICK),YES)
APP_CFLAGS += -DRS_TINY_P9_QUICK
endif
endif
ifeq ($(TINY_P10_ACCEPTANCE),YES)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p10.c
endif
ifeq ($(TINY_SPI_P3_ACCEPTANCE),YES)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_spi_p3.c
endif
