APP_PATH += $(ROOT_PATH)/app/src/coremark/coremark-main/core_main.c
APP_PATH += $(ROOT_PATH)/app/src/coremark/coremark-main/core_list_join.c
APP_PATH += $(ROOT_PATH)/app/src/coremark/coremark-main/core_matrix.c
APP_PATH += $(ROOT_PATH)/app/src/coremark/coremark-main/core_state.c
APP_PATH += $(ROOT_PATH)/app/src/coremark/coremark-main/core_util.c
APP_PATH += $(ROOT_PATH)/app/src/coremark/core_portme.c

INC_PATH += -I$(ROOT_PATH)/app/src/coremark/coremark-main
INC_PATH += -I$(ROOT_PATH)/app/src/coremark