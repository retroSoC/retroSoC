SOC            ?= MINI
SIMU           ?= VCS
SYNTH          ?= YOSYS
TIMI           ?= OPENSTA

# HW
PDK            ?= IHP130
HAVE_PLL       ?= YES
HAVE_SRAM      ?= YES
HAVE_SVA       ?= NO

RTL_SIM_PLLEN  ?= NONE
RTL_SIM_PLLCFG ?= NONE
WAVE           ?= NONE

ROOT_PATH      ?= $(CURDIR)
RTL_PATH       ?= NONE

CORE           ?= PICORV32
RTL_TOP        ?= retrosoc_tb

# SW
ISA            ?= RV32IM
FIRMWARE_NAME  ?= retrosoc_fw
EXEC_TYPE      ?= ld2_sram

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
$(info SOC       [TINY, MINI]:                  $(SOC))
$(info CORE      [MINIRV PICORV32, KIANV]:      $(CORE))
$(info SIMU      [VCS, VERILATOR]:              $(SIMU))
$(info SYNTH     [YOSYS, DC]:                   $(SYNTH))
$(info TIMI      [OPENSTA, ISTA]:               $(TIMI))
$(info PDK       [S110, IHP130, SKY130, ICS55]: $(PDK))
$(info HAVE_PLL  [YES, NO]:                     $(HAVE_PLL))
$(info HAVE_SRAM [YES, NO]:                     $(HAVE_SRAM))
$(info HAVE_SVA  [YES, NO]:                     $(HAVE_SVA))
$(info RTL_SIM_PLLEN:                           $(RTL_SIM_PLLEN))
$(info RTL_SIM_PLLCFG:                          $(RTL_SIM_PLLCFG))
$(info WAVE:                                    $(WAVE))
$(info ============== SW CONFIG INFO =============================)
$(info ISA [RV32E RV32I RV32IM]:                $(ISA))
$(info FIRMWARE_NAME [retrosoc_fw]:             $(FIRMWARE_NAME))
$(info EXEC_TYPE [xip ld2_sram ld2_prsram]:     $(EXEC_TYPE))
$(info ===========================================================)

DEF_LIST    ?= +define+PDK_$(PDK)
DEF_LIST    += +define+CORE_$(CORE)
ifeq ($(HAVE_PLL), YES)
    DEF_LIST += +define+HAVE_PLL
endif

ifeq ($(HAVE_SRAM), YES)
    DEF_LIST += +define+HAVE_SRAM
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