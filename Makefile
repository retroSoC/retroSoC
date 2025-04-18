SOC ?= MINI

ifeq ($(SOC), MINI)
    include rtl/mini/Makefile
endif