SOC            ?= MINI
SIMU           ?= VCS
SYNTH          ?= YOSYS
TIMI           ?= OPENSTA

# HW
PDK             ?= IHP130
HAVE_PLL        ?= YES
HAVE_SRAM_IF    ?= YES
HAVE_SRAM_MACRO ?= YES
HAVE_SVA        ?= NO

RTL_SIM_PLLEN   ?= NONE
RTL_SIM_PLLCFG  ?= NONE
RTL_SIM_CORESEL ?= 0
WAVE            ?= NONE

ROOT_PATH      ?= $(CURDIR)
RTL_PATH       ?= NONE

CORE           ?= PICORV32
IP             ?= NONE
RTL_TOP        ?= retrosoc_tb

# SW
ISA            ?= RV32IM
FIRMWARE_NAME  ?= retrosoc_fw
PROG_TYPE      ?= FULL
LINK_TYPE      ?= ld2_sram

$(info ============== BASE INFO ==================================)
$(info retroSoC:      <https://github.com/retroSoC/retroSoC>)
$(info author:        Yuchi Miao <https://github.com/maksyuki>)
$(info license:       MulanPSL-2.0 license)
$(info ROOT_PATH:     $(CURDIR))
$(info SHELL:         $(SHELL))
$(info MAKE VERSION:  $(MAKE_VERSION))
$(info MAKE APP:      $(MAKE))
$(info MAKE CMDGOAL:  $(MAKECMDGOALS))
$(info MAKE FILELIST: $(MAKEFILE_LIST))
$(info ============== HW CONFIG INFO =============================)
$(info SOC             [TINY, MINI]:                   $(SOC))
$(info CORE            [PICORV32, MDD]:                $(CORE))
$(info IP              [NONE, MDD]:                    $(IP))
$(info SIMU            [VCS, VERILATOR]:               $(SIMU))
$(info SYNTH           [YOSYS, DC]:                    $(SYNTH))
$(info TIMI            [OPENSTA, ISTA]:                $(TIMI))
$(info PDK             [ICS55, IHP130, SKY130, GF180]: $(PDK))
$(info HAVE_PLL        [YES, NO]:                      $(HAVE_PLL))
$(info HAVE_SRAM_IF    [YES, NO]:                      $(HAVE_SRAM_IF))
$(info HAVE_SRAM_MACRO [YES, NO]:                      $(HAVE_SRAM_MACRO))
$(info HAVE_SVA        [YES, NO]:                      $(HAVE_SVA))
$(info RTL_SIM_PLLEN:                                  $(RTL_SIM_PLLEN))
$(info RTL_SIM_PLLCFG:                                 $(RTL_SIM_PLLCFG))
$(info RTL_SIM_CORESEL:                                $(RTL_SIM_CORESEL))
$(info WAVE:                                           $(WAVE))
$(info ============== SW CONFIG INFO =============================)
$(info ISA           [RV32E RV32I RV32IM]:             $(ISA))
$(info FIRMWARE_NAME [retrosoc_fw]:                    $(FIRMWARE_NAME))
$(info PROG_TYPE     [BASE FULL]:                      $(PROG_TYPE))
$(info LINK_TYPE     [xip ld2_sram ld2_psram]:         $(LINK_TYPE))
$(info ===========================================================)

DEF_LIST    ?= +define+PDK_$(PDK)
DEF_LIST    += +define+CORE_$(CORE)
DEF_LIST    += +define+IP_$(IP)
DEF_LIST    += +define+SIMU_$(SIMU)

ifeq ($(HAVE_PLL), YES)
    DEF_LIST += +define+HAVE_PLL
endif

ifeq ($(HAVE_SRAM_IF), YES)
    DEF_LIST += +define+HAVE_SRAM_IF
endif

ifeq ($(HAVE_SRAM_MACRO), YES)
    DEF_LIST += +define+HAVE_SRAM_MACRO
endif

ifeq ($(HAVE_SVA), NO)
    DEF_LIST += +define+SV_ASSRT_DISABLE
endif

ifeq ($(SOC), MINI)
    RTL_PATH = $(ROOT_PATH)/rtl/mini
    $(info DEF_LIST: $(DEF_LIST))
    $(file > $(RTL_PATH)/filelist/def.fl, $(DEF_LIST))
    include rtl/mini/Makefile
endif

ifeq ($(SOC), TINY)
    RTL_PATH = $(ROOT_PATH)/rtl/tiny
    $(info DEF_LIST: $(DEF_LIST))
    $(file > $(RTL_PATH)/filelist/def.fl, $(DEF_LIST))
    include rtl/tiny/Makefile
endif

ifeq ($(SYNTH), YOSYS)
    DEF_LIST += +define+SYNTHESIS #HACK: for some core
    $(info SYNTH DEF_LIST: $(DEF_LIST))
    $(file > $(RTL_PATH)/filelist/def.fl, $(DEF_LIST))
    demo := $(shell python3 $(RTL_PATH)/filelist/comb.py $(RTL_FLIST))
    include syn/yosys/yosys.mk
else ifeq ($(SYNTH), DC)
    include syn/dc.mk
endif