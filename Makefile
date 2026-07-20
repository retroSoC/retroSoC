SHELL := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

ROOT_PATH      ?= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
CONFIG         ?=
LOCK_FILE      ?= $(ROOT_PATH)/config/dependencies.lock.json

ifneq ($(strip $(CONFIG)),)
CONFIG_PATH := $(if $(filter /%,$(CONFIG)),$(CONFIG),$(ROOT_PATH)/$(CONFIG))
ifeq ($(wildcard $(CONFIG_PATH)),)
$(error Configuration profile not found: $(CONFIG_PATH))
endif
include $(CONFIG_PATH)
PROFILE_NAME := $(basename $(notdir $(CONFIG_PATH)))
else
CONFIG_PATH :=
PROFILE_NAME := manual
endif

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
SIM_FIRMWARE_NAME ?= $(FIRMWARE_NAME)
SIM_SUCCESS_MARKER ?= retroSoC: A Customized ASIC for Retro Stuff

RTL_PATH       := $(ROOT_PATH)/rtl/mini

CORE           ?= HAZARD3
IP             ?= NONE
RTL_TOP        ?= retrosoc_tb

# SW
ISA            ?= RV32IM
HAVE_CSR       ?= NO
FIRMWARE_NAME  ?= retrosoc_fw
APP            ?= shell
LINK_TYPE      ?= ld2_sram

BUILD_ROOT     ?= $(ROOT_PATH)/build
CACHE_ROOT     ?= $(ROOT_PATH)/.cache/retrosoc
MAX_JOBS       ?= 16
HOST_CC        ?= cc
CLANG_FORMAT   ?= clang-format-14
JOBS           ?= $(shell count=$$(nproc 2>/dev/null || printf '1'); \
                       if [ "$$count" -gt "$(MAX_JOBS)" ]; then printf '%s' '$(MAX_JOBS)'; \
                       else printf '%s' "$$count"; fi)
CONFIG_KEY_VARS := SOC CORE IP PDK HAVE_PLL HAVE_SRAM_IF HAVE_SRAM_MACRO HAVE_SVA \
                   ISA HAVE_CSR APP LINK_TYPE RTL_TOP FIRMWARE_NAME
VARIANT_ID := $(strip $(shell python3 $(ROOT_PATH)/scripts/config_key.py \
    --lock $(LOCK_FILE) --profile $(PROFILE_NAME) \
    $(foreach var,$(CONFIG_KEY_VARS),--value $(var)=$($(var)))))
ifeq ($(VARIANT_ID),)
$(error Failed to calculate build variant ID)
endif
LOCK_DIGEST := $(strip $(shell python3 $(ROOT_PATH)/scripts/dependency_lock.py --lock $(LOCK_FILE) --digest))
VARIANT_ROOT := $(abspath $(BUILD_ROOT))/$(VARIANT_ID)
SW_BUILD_DIR := $(VARIANT_ROOT)/sw
SIM_TOOL_NAME := $(shell printf '%s' '$(SIMU)' | tr '[:upper:]' '[:lower:]')
SIM_BUILD_ROOT := $(VARIANT_ROOT)/sim/$(SIM_TOOL_NAME)
SYN_BUILD_ROOT := $(VARIANT_ROOT)/syn/yosys
STA_BUILD_ROOT := $(VARIANT_ROOT)/sta/opensta
META_DIR := $(VARIANT_ROOT)/meta
ifeq ($(SYNTH),YOSYS)
FLOW_FILELIST_DIR := $(SYN_BUILD_ROOT)/filelists
else
FLOW_FILELIST_DIR := $(SIM_BUILD_ROOT)/filelists
endif

VALID_SOC       := MINI
VALID_CORE      := PICORV32 HAZARD3 MDD
VALID_IP        := NONE MDD
VALID_SIMU      := VCS VERILATOR IVERILOG
VALID_SYNTH     := NONE YOSYS
VALID_STA       := NONE OPENSTA
VALID_PDK       := ICS55 IHP130 SKY130 GF180
VALID_BOOL      := YES NO
VALID_ISA       := RV32E RV32I RV32IM
VALID_APP       := bringup shell
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
$(call validate_value,APP,$(VALID_APP))
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

.PHONY: help config doctor setup setup-mpw setup-core setup-clusterip setup-ip setup-pdk setup-app \
        clean-all purge-cache manifest check-warnings metrics check-metrics package \
        regress-pr regress-nightly sim-asm sw-format sw-format-check sw-policy-check sw-host-test
.NOTPARALLEL: setup

help:
	@printf '%s\n' \
	  'retroSoC build targets:' \
	  '  firmware | asm             build firmware' \
	  '  comp | sim                 behavioral simulation' \
	  '  sim-asm                    build/run the assembly self-test' \
	  '  netcomp | netsim           synthesized-netlist simulation' \
	  '  postcomp | postsim         post-layout simulation' \
	  '  synth | sta                synthesis and timing analysis' \
	  '  setup                      install pinned external dependencies' \
	  '  doctor                     check tools, paths, and selected configuration' \
	  '  config | manifest          print/write the effective configuration' \
	  '  memory-map                 generate the selected address-map artifacts' \
	  '  check-memory-map           validate the canonical address map' \
	  '  check-warnings | metrics   analyze flow logs and reports' \
	  '  check-metrics              apply the committed metrics policy' \
	  '  sw-format                  apply clang-format to self-owned embedded C code' \
	  '  sw-format-check            check embedded C whitespace and line-ending policy' \
	  '  sw-policy-check            check embedded C API and naming policy' \
	  '  sw-host-test               run host tests for deterministic SDK utilities' \
	  '  regress-pr | regress-nightly run supported regression suites' \
	  '  package                    create checksummed source deliverables' \
	  '  clean | clean-all          clean current flow or all build output' \
	  '  purge-cache                remove dependency and compiler caches' \
	  '' \
	  'Usage: make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk SIMU=IVERILOG sim'

config:
	@printf '%-18s %s\n' \
	  ROOT_PATH '$(ROOT_PATH)' CONFIG '$(or $(CONFIG_PATH),<defaults>)' \
	  VARIANT_ID '$(VARIANT_ID)' VARIANT_ROOT '$(VARIANT_ROOT)' \
	  JOBS '$(JOBS)' \
	  SOC '$(SOC)' CORE '$(CORE)' IP '$(IP)' \
	  SIMU '$(SIMU)' SYNTH '$(SYNTH)' STA '$(STA)' PDK '$(PDK)' \
	  HAVE_PLL '$(HAVE_PLL)' HAVE_SRAM_IF '$(HAVE_SRAM_IF)' \
	  HAVE_SRAM_MACRO '$(HAVE_SRAM_MACRO)' HAVE_SVA '$(HAVE_SVA)' \
	  ISA '$(ISA)' HAVE_CSR '$(HAVE_CSR)' APP '$(APP)' \
	  LINK_TYPE '$(LINK_TYPE)'

doctor:
	@python3 $(ROOT_PATH)/scripts/doctor.py \
	  --root $(ROOT_PATH) --simu $(SIMU) --synth $(SYNTH) --sta $(STA) \
	  --pdk $(PDK) --core $(CORE) --ip $(IP) --lock $(LOCK_FILE)

setup: setup-mpw setup-core setup-clusterip setup-ip setup-pdk setup-app

setup-mpw:
	python3 $(ROOT_PATH)/setup.py
	python3 $(ROOT_PATH)/scripts/prepare_mpw.py \
	  --lock-file $(CACHE_ROOT)/locks/mpw-prepare.lock
	@mkdir -p $(dir $(MPW_STAMP))
	@touch $(MPW_STAMP)

setup-core: setup-mpw
	python3 $(ROOT_PATH)/rtl/mini/core/setup.py

setup-clusterip:
	python3 $(ROOT_PATH)/rtl/clusterip/setup.py

setup-ip:
	python3 $(ROOT_PATH)/rtl/ip/setup.py

setup-pdk:
	python3 $(ROOT_PATH)/pdk/setup.py --pdk $(PDK)

setup-app:
	python3 $(ROOT_PATH)/app/setup.py

clean-all:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(abspath $(BUILD_ROOT))

purge-cache:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(abspath $(CACHE_ROOT))

manifest:
	python3 $(ROOT_PATH)/scripts/manifest.py create --root $(ROOT_PATH) \
	  --lock $(LOCK_FILE) --output $(META_DIR)/manifest.json --profile $(PROFILE_NAME) \
	  $(foreach var,$(CONFIG_KEY_VARS),--config $(var)=$($(var))) \
	  --config SIMU=$(SIMU) --config SYNTH=$(SYNTH) --config STA=$(STA)

check-warnings:
	python3 $(ROOT_PATH)/scripts/analyze_warnings.py check --root $(ROOT_PATH) \
	  --profile $(PROFILE_NAME) --variant-root $(VARIANT_ROOT) --output $(META_DIR)/warnings.json

metrics:
	python3 $(ROOT_PATH)/scripts/metrics.py collect --variant-root $(VARIANT_ROOT) \
	  --output $(META_DIR)/metrics.json

check-metrics: metrics
	python3 $(ROOT_PATH)/scripts/metrics.py check --metrics $(META_DIR)/metrics.json \
	  --policy $(ROOT_PATH)/quality/metrics/policy.json \
	  --baseline $(ROOT_PATH)/quality/metrics/baseline.json

sw-format:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) \
	  --apply-format --clang-format $(CLANG_FORMAT)

sw-format-check:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) --format-check \
	  --clang-format-check --clang-format $(CLANG_FORMAT)

sw-policy-check:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) --policy-check

sw-host-test:
	python3 $(ROOT_PATH)/scripts/run_c_tests.py --root $(ROOT_PATH) --cc $(HOST_CC)

package: $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) manifest
	python3 $(ROOT_PATH)/scripts/package.py --root $(ROOT_PATH) --lock $(LOCK_FILE) \
	  --variant-root $(VARIANT_ROOT) --output-dir $(ROOT_PATH)/dist/$(VARIANT_ID)

regress-pr:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr

regress-nightly:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite nightly

sim-asm: asm
	$(MAKE) SIM_FIRMWARE_NAME=$(ASM_FIRMWARE_NAME) \
	  SIM_SUCCESS_MARKER='Mem wr/rd test success' sim
