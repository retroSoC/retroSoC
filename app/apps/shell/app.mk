APP_SRCS += $(ROOT_PATH)/app/apps/shell/main.c
APP_SRCS += $(ROOT_PATH)/crt/src/service/shell.c
APP_SRCS += $(ROOT_PATH)/crt/src/hal/i2s.c
APP_SRCS += $(ROOT_PATH)/app/board/src/at24cxx.c
APP_SRCS += $(ROOT_PATH)/app/board/src/pcf8563b.c
APP_SRCS += $(ROOT_PATH)/app/board/src/es8388.c
APP_SRCS += $(ROOT_PATH)/app/board/src/w25q128jvxim.c
APP_SRCS += $(ROOT_PATH)/app/media/src/wav_audio.c
APP_SRCS += $(ROOT_PATH)/app/media/src/video_player.c
APP_SRCS += $(ROOT_PATH)/app/media/src/donut.c

APP_INC_DIRS += $(ROOT_PATH)/app/board/include
APP_INC_DIRS += $(ROOT_PATH)/app/media/include

include $(ROOT_PATH)/app/middleware/fatfs/fatfs.mk
include $(ROOT_PATH)/app/benchmark/coremark/coremark.mk
include $(ROOT_PATH)/app/network/userip/userip.mk