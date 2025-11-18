# user custom area
ifeq ($(IP), MDD)
    APP_PATH += $(ROOT_PATH)/app/userip/userip.c
    INC_PATH += -I$(ROOT_PATH)/app/userip
    # add more user custom files into 'APP_PATH'
endif