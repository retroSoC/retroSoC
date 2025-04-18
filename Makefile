SOC            ?= MINI
SIMU           ?= VCS
SYNC           ?= YOSYS
TIMI           ?= OPENSTA

PDK            ?= S110
HAVE_PLL       ?= YES
HAVE_SRAM      ?= YES
HAVE_SVA       ?= NO

RTL_SIM_PLLEN  ?= NONE
RTL_SIM_PLLCFG ?= NONE
WAVE           ?= NONE

ROOT_PATH      ?= $(CURDIR)
RTL_PATH       ?= NONE

$(info retroSoC:      <https://github.com/retroSoC/retroSoC>)
$(info author:        Yuchi Miao <https://github.com/maksyuki>)
$(info license:       MulanPSL-2.0 license)
$(info ROOT_PATH:     $(CURDIR))
$(info SHELL:         $(SHELL))
$(info MAKE VERSION:  $(MAKE_VERSION))
$(info MAKE APP:      $(MAKE))
$(info MAKE CMDGOAL:  $(MAKECMDGOALS))
$(info MAKE FILELIST: $(MAKEFILE_LIST))
$(info ============== CONFIG INFO ==============)
$(info SOC:            $(SOC)     [MINI, STD])
$(info SIMU:           $(SIMU)      [VCS, VERILATOR])
$(info SYNC:           $(SYNC)    [YOSYS, DC])
$(info TIMI:           $(TIMI)  [OPENSTA, ISTA])
$(info PDK:            $(PDK)     [S110, IHP130, SKY130])
$(info HAVE_PLL:       $(HAVE_PLL)      [YES, NO])
$(info HAVE_SRAM:      $(HAVE_SRAM)      [YES, NO])
$(info HAVE_SVA:       $(HAVE_SVA)       [YES, NO])

$(info RTL_SIM_PLLEN:  $(RTL_SIM_PLLEN))
$(info RTL_SIM_PLLCFG: $(RTL_SIM_PLLCFG))
$(info WAVE:           $(WAVE))

ifeq ($(SOC), MINI)
    RTL_PATH = $(ROOT_PATH)/rtl/mini
    include rtl/mini/Makefile
endif

ifeq ($(SYNC), YOSYS)
    include syn/yosys/yosys.mk
else ifeq ($(SYNC), DC)
    include syn/dc.mk
endif