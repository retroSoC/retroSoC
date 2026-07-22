LVGL_SDK_DIR := $(ROOT_PATH)/app/lvgl/lvgl-main

APP_SRCS += $(sort $(shell find $(LVGL_SDK_DIR)/src -type f -name '*.c'))
APP_SRCS += $(ROOT_PATH)/app/ports/lvgl/lv_port_disp.c
APP_SRCS += $(ROOT_PATH)/app/ports/lvgl/lv_port_indev.c

APP_INC_DIRS += $(LVGL_SDK_DIR)
APP_INC_DIRS += $(ROOT_PATH)/app/ports/lvgl