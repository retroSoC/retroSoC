# User IP is optional and is linked only for MDD configurations.
ifeq ($(IP), MDD)
APP_SRCS     += $(ROOT_PATH)/app/network/userip/userip.c
APP_INC_DIRS += $(ROOT_PATH)/app/network/userip
endif