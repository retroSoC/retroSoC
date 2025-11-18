APP_PATH += $(shell find $(ROOT_PATH)/app/lvgl/lvgl-main/src -type f -name '*.c')
APP_PATH += $(ROOT_PATH)/app/lvgl/lv_port_disp.c
APP_PATH += $(ROOT_PATH)/crt/libgcc/clzsi2.c
APP_PATH += $(ROOT_PATH)/crt/libgcc/ffssi2.c
APP_PATH += $(ROOT_PATH)/crt/libgcc/udivdi3.c
APP_PATH += $(ROOT_PATH)/crt/libgcc/divdi3.c
APP_PATH += $(ROOT_PATH)/crt/libgcc/umoddi3.c

INC_PATH += -I$(ROOT_PATH)/app/lvgl/lvgl-main/
INC_PATH += -I$(ROOT_PATH)/app/lvgl/