SHELL := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

SOC            ?= MINI
SIMU           ?= VCS
SYNTH          ?= NONE
STA            ?= NONE

# HW
PDK             ?= IHP130
HAVE_PLL        ?= NO
HAVE_SRAM_IF    ?= NO
HAVE_SRAM_MACRO ?= NO
HAVE_SVA        ?= NO
WAVE            ?= NO

RTL_SIM_PLLEN   ?= NONE
RTL_SIM_PLLCFG  ?= NONE
RTL_SIM_CORESEL ?= 0
RTL_SIM_TIMEOUT ?= -1

ROOT_PATH      ?= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
RTL_PATH       := $(ROOT_PATH)/rtl/mini

CORE           ?= HAZARD3
IP             ?= NONE
RTL_TOP        ?= retrosoc_tb

# SW
ISA            ?= RV32IM
HAVE_CSR       ?= NO
FIRMWARE_NAME  ?= retrosoc_fw
PROG_TYPE      ?= FULL
LINK_TYPE      ?= ld2_sram

VALID_SOC       := MINI
VALID_CORE      := PICORV32 HAZARD3 MDD
VALID_IP        := NONE MDD
VALID_SIMU      := VCS VERILATOR IVERILOG
VALID_SYNTH     := NONE YOSYS
VALID_STA       := NONE OPENSTA
VALID_PDK       := ICS55 IHP130 SKY130 GF180
VALID_BOOL      := YES NO
VALID_ISA       := RV32E RV32I RV32IM
VALID_PROG_TYPE := BASE FULL
VALID_LINK_TYPE := xip ld2_sram ld2_psram ld2_sdram

define validate_value
$(if $(filter $($(1)),$(2)),,$(error Invalid $(1)='$($(1))'; expected one of: $(2)))
endef

$(call validate_value,SOC,$(VALID_SOC))
$(call validate_value,CORE,$(VALID_CORE))
$(call validate_value,IP,$(VALID_IP))
$(call validate_value,SIMU,$(VALID_SIMU))
$(call validate_value,SYNTH,$(VALID_SYNTH))
$(call validate_value,STA,$(VALID_STA))
$(call validate_value,PDK,$(VALID_PDK))
$(call validate_value,HAVE_PLL,$(VALID_BOOL))
$(call validate_value,HAVE_SRAM_IF,$(VALID_BOOL))
$(call validate_value,HAVE_SRAM_MACRO,$(VALID_BOOL))
$(call validate_value,HAVE_SVA,$(VALID_BOOL))
$(call validate_value,WAVE,$(VALID_BOOL))
$(call validate_value,ISA,$(VALID_ISA))
$(call validate_value,HAVE_CSR,$(VALID_BOOL))
$(call validate_value,PROG_TYPE,$(VALID_PROG_TYPE))
$(call validate_value,LINK_TYPE,$(VALID_LINK_TYPE))

ifeq ($(SYNTH),YOSYS)
ifeq ($(filter $(PDK),IHP130 ICS55),)
$(error Yosys synthesis supports PDK=IHP130 or PDK=ICS55, not PDK=$(PDK))
endif
endif

ifeq ($(STA),OPENSTA)
ifneq ($(PDK),IHP130)
$(error OpenSTA currently supports PDK=IHP130 only)
endif
endif

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

ifeq ($(SYNTH), YOSYS)
    DEF_LIST += +define+SYNTHESIS
endif

include rtl/mini/Makefile

ifeq ($(SYNTH), YOSYS)
include syn/yosys/yosys.mk
endif

ifeq ($(STA), OPENSTA)
    include sta/opensta/opensta.mk
endif

.PHONY: help config doctor setup setup-mpw setup-core setup-clusterip setup-ip setup-pdk setup-app clean-all
.NOTPARALLEL: setup

help:
	@printf '%s\n' \
	  'retroSoC build targets:' \
	  '  firmware | asm             build firmware' \
	  '  comp | sim                 behavioral simulation' \
	  '  netcomp | netsim           synthesized-netlist simulation' \
	  '  postcomp | postsim         post-layout simulation' \
	  '  synth | sta                synthesis and timing analysis' \
	  '  setup                      install pinned external dependencies' \
	  '  doctor                     check tools, paths, and selected configuration' \
	  '  config                     print selected configuration' \
	  '  clean | clean-all          clean current backend or all generated output' \
	  '' \
	  'Key variables: SOC CORE IP SIMU SYNTH STA PDK ISA PROG_TYPE LINK_TYPE'

config:
	@printf '%-18s %s\n' \
	  ROOT_PATH '$(ROOT_PATH)' SOC '$(SOC)' CORE '$(CORE)' IP '$(IP)' \
	  SIMU '$(SIMU)' SYNTH '$(SYNTH)' STA '$(STA)' PDK '$(PDK)' \
	  HAVE_PLL '$(HAVE_PLL)' HAVE_SRAM_IF '$(HAVE_SRAM_IF)' \
	  HAVE_SRAM_MACRO '$(HAVE_SRAM_MACRO)' HAVE_SVA '$(HAVE_SVA)' \
	  ISA '$(ISA)' HAVE_CSR '$(HAVE_CSR)' PROG_TYPE '$(PROG_TYPE)' \
	  LINK_TYPE '$(LINK_TYPE)'

doctor:
	@python3 $(ROOT_PATH)/scripts/doctor.py \
	  --root $(ROOT_PATH) --simu $(SIMU) --synth $(SYNTH) --sta $(STA) \
	  --pdk $(PDK) --core $(CORE) --ip $(IP)

setup: setup-mpw setup-core setup-clusterip setup-ip setup-pdk setup-app

setup-mpw:
	python3 $(ROOT_PATH)/setup.py
	python3 $(ROOT_PATH)/scripts/prepare_mpw.py
	@mkdir -p $(dir $(MPW_STAMP))
	@touch $(MPW_STAMP)

setup-core: setup-mpw
	python3 $(ROOT_PATH)/rtl/mini/core/setup.py

setup-clusterip:
	python3 $(ROOT_PATH)/rtl/clusterip/setup.py

setup-ip:
	python3 $(ROOT_PATH)/rtl/ip/setup.py

setup-pdk:
	python3 $(ROOT_PATH)/pdk/setup.py

setup-app:
	python3 $(ROOT_PATH)/app/setup.py

clean-all:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH)
