APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/tiny.c
APP_CFLAGS += -Os
APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/mcu_acceptance.S
APP_SRCS   += $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p6.c
ifeq ($(TINY_P7_ACCEPTANCE),YES)
APP_SRCS := $(ROOT_PATH)/app/apps/ci_smoke/tiny_r2_p7.c
endif