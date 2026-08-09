SHELL := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

ROOT_PATH ?= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
CONFIG    ?=
LOCK_FILE ?= $(ROOT_PATH)/config/dependencies.lock.json

ifneq ($(strip $(CONFIG)),)
CONFIG_PATH := $(if $(filter /%,$(CONFIG)),$(CONFIG),$(ROOT_PATH)/$(CONFIG))
ifeq ($(wildcard $(CONFIG_PATH)),)
$(error Configuration profile not found: $(CONFIG_PATH))
endif
include $(CONFIG_PATH)
PROFILE_NAME := $(basename $(notdir $(CONFIG_PATH)))
else
CONFIG_PATH  :=
PROFILE_NAME := manual
endif

ifneq ($(origin IP),undefined)
$(error IP is no longer configurable; user IP integration is fixed)
endif
ifneq ($(origin CORE),undefined)
$(error CORE has been removed; the management core is fixed to Hazard3)
endif
ifneq ($(origin HAVE_DEBUG),undefined)
$(error HAVE_DEBUG has been removed; the Hazard3 Debug Module is always enabled)
endif

SOC   ?= MINI
SIMU  ?= VCS
SYNTH ?= NONE
STA   ?= NONE

# HW
PDK                      ?= IHP130
HAVE_PLL                 ?= NO
HAVE_SRAM_IF             ?= NO
HAVE_SRAM_MACRO          ?= NO
PDK_BEHAV                ?= NO
HAVE_SVA                 ?= NO
BUILD_RELEASE            ?= NO
JTAG_IDCODE              ?= DEADBEEF
EXT_CLK_HZ               ?= 72000000
CLINT_TIMEBASE_HZ        ?= 1000000
WAVE                     ?= NO
FORMAL                   ?= NO
VCS_USE_LSF              ?= YES
REGRESS_NETSIM_BOOT_ONLY ?= NO

RTL_SIM_TIMEOUT    ?= -1
SIM_FIRMWARE_NAME  ?= $(FIRMWARE_NAME)
SIM_SUCCESS_MARKER ?= SIM_TEST_PASS

RTL_PATH := $(ROOT_PATH)/rtl/mini

RTL_TOP ?= retrosoc_tb

# SW
ISA           ?= RV32IM
HAVE_CSR      ?= NO
FIRMWARE_NAME ?= retrosoc_fw
APP           ?= shell
LINK_TYPE     ?= ld2_sram
COREMARK_MODE ?= quick

BUILD_ROOT         ?= $(ROOT_PATH)/build
CACHE_ROOT         ?= $(ROOT_PATH)/.cache/retrosoc
BUILD_TIMESTAMP    ?= $(shell date '+%Y-%m-%d-%H-%M')
MAX_JOBS           ?= 16
HOST_CC            ?= cc
PYTHON             ?= python3
FLOW_PYTHON        ?= $(PYTHON)
CLANG_FORMAT       ?= clang-format-14
MBAKE              ?= mbake
VERIBLE_FORMAT     ?= verible-verilog-format
VCS_DEFAULT_RUNNER := $(if $(filter YES,$(VCS_USE_LSF)),bsub -Is)
VCS_RUNNER         ?= $(VCS_DEFAULT_RUNNER)
VCS_SHELL_GOALS    := comp sim netcomp netsim postcomp postsim
VCS_SHELL_PYTHON   := $(if $(filter VCS,$(SIMU)),$(if $(filter $(VCS_SHELL_GOALS),$(MAKECMDGOALS)),$(strip $(VCS_RUNNER) $(PYTHON)),$(PYTHON)),$(PYTHON))
JOBS               ?= $(shell count=$$(nproc 2>/dev/null || printf '1'); \
                       if [ "$$count" -gt "$(MAX_JOBS)" ]; then printf '%s' '$(MAX_JOBS)'; \
else printf '%s' "$$count"; fi)
CONFIG_KEY_VARS    := SOC PDK HAVE_PLL HAVE_SRAM_IF HAVE_SRAM_MACRO PDK_BEHAV HAVE_SVA \
                   BUILD_RELEASE JTAG_IDCODE EXT_CLK_HZ CLINT_TIMEBASE_HZ ISA HAVE_CSR APP LINK_TYPE \
                   COREMARK_MODE RTL_TOP FIRMWARE_NAME
VARIANT_ID         := $(strip $(shell $(VCS_SHELL_PYTHON) $(ROOT_PATH)/scripts/config_key.py \
    --lock $(LOCK_FILE) --profile $(PROFILE_NAME) --timestamp $(BUILD_TIMESTAMP) \
    $(foreach var,$(CONFIG_KEY_VARS),--value $(var)=$($(var))) | tail -n 1))
ifeq ($(VARIANT_ID),)
$(error Failed to calculate build variant ID)
endif
LOCK_DIGEST   := $(strip $(shell $(VCS_SHELL_PYTHON) $(ROOT_PATH)/scripts/dependency_lock.py \
    --lock $(LOCK_FILE) --digest | tail -n 1))
CONFIG_DIGEST := $(lastword $(subst -, ,$(VARIANT_ID)))
export BUILD_TIMESTAMP
VARIANT_ROOT   := $(abspath $(BUILD_ROOT))/$(VARIANT_ID)
SW_BUILD_DIR   := $(VARIANT_ROOT)/sw
SIM_TOOL_NAME  := $(shell printf '%s' '$(SIMU)' | tr '[:upper:]' '[:lower:]')
SIM_BUILD_ROOT := $(VARIANT_ROOT)/sim/$(SIM_TOOL_NAME)
SYN_BUILD_ROOT := $(VARIANT_ROOT)/syn/yosys
STA_BUILD_ROOT := $(VARIANT_ROOT)/sta/opensta
META_DIR       := $(VARIANT_ROOT)/meta
ifeq ($(SYNTH),YOSYS)
FLOW_FILELIST_DIR := $(SYN_BUILD_ROOT)/filelists
else
FLOW_FILELIST_DIR := $(SIM_BUILD_ROOT)/filelists
endif

VALID_SOC           := MINI
VALID_SIMU          := VCS VERILATOR IVERILOG
VALID_SYNTH         := NONE YOSYS
VALID_STA           := NONE OPENSTA
VALID_PDK           := ICS55 IHP130 SKY130 GF180
VALID_BOOL          := YES NO
VALID_ISA           := RV32E RV32I RV32IM
VALID_APP           := benchmark bringup ci_smoke coremark debug shell
VALID_LINK_TYPE     := xip ld2_all_sram ld2_sram ld2_psram ld2_sdram
VALID_COREMARK_MODE := quick standard

define validate_value
$(if $(filter $($(1)),$(2)),,$(error Invalid $(1)='$($(1))'; expected one of: $(2)))
endef

$(call validate_value,SOC,$(VALID_SOC))
$(call validate_value,SIMU,$(VALID_SIMU))
$(call validate_value,SYNTH,$(VALID_SYNTH))
$(call validate_value,STA,$(VALID_STA))
$(call validate_value,PDK,$(VALID_PDK))
$(call validate_value,HAVE_PLL,$(VALID_BOOL))
$(call validate_value,HAVE_SRAM_IF,$(VALID_BOOL))
$(call validate_value,HAVE_SRAM_MACRO,$(VALID_BOOL))
$(call validate_value,PDK_BEHAV,$(VALID_BOOL))
$(call validate_value,HAVE_SVA,$(VALID_BOOL))
$(call validate_value,BUILD_RELEASE,$(VALID_BOOL))
$(call validate_value,WAVE,$(VALID_BOOL))
$(call validate_value,FORMAL,$(VALID_BOOL))
$(call validate_value,VCS_USE_LSF,$(VALID_BOOL))
$(call validate_value,REGRESS_NETSIM_BOOT_ONLY,$(VALID_BOOL))
$(call validate_value,ISA,$(VALID_ISA))
$(call validate_value,HAVE_CSR,$(VALID_BOOL))
$(call validate_value,APP,$(VALID_APP))
$(call validate_value,LINK_TYPE,$(VALID_LINK_TYPE))
$(call validate_value,COREMARK_MODE,$(VALID_COREMARK_MODE))

JTAG_IDCODE_VALID := $(shell printf '%s' '$(JTAG_IDCODE)' | grep -E '^[[:xdigit:]]{8}$$')
ifneq ($(JTAG_IDCODE_VALID),$(JTAG_IDCODE))
$(error JTAG_IDCODE='$(JTAG_IDCODE)' must be exactly eight hexadecimal digits)
endif
JTAG_IDCODE_DEC := $(shell value=$$(printf '%u' 0x$(JTAG_IDCODE)); \
	if [ $$value -gt 2147483647 ]; then echo $$((value - 4294967296)); else echo $$value; fi)

EXT_CLK_HZ_VALID := $(shell printf '%s' '$(EXT_CLK_HZ)' | grep -E '^[1-9][[:digit:]]*$$')
ifneq ($(EXT_CLK_HZ_VALID),$(EXT_CLK_HZ))
$(error EXT_CLK_HZ='$(EXT_CLK_HZ)' must be a positive integer)
endif
CLINT_TIMEBASE_HZ_VALID := $(shell printf '%s' '$(CLINT_TIMEBASE_HZ)' | grep -E '^[1-9][[:digit:]]*$$')
ifneq ($(CLINT_TIMEBASE_HZ_VALID),$(CLINT_TIMEBASE_HZ))
$(error CLINT_TIMEBASE_HZ='$(CLINT_TIMEBASE_HZ)' must be a positive integer)
endif
CLINT_TIMEBASE_RATIO_VALID := $(shell if [ '$(EXT_CLK_HZ)' -ge '$(CLINT_TIMEBASE_HZ)' ] && \
	[ $$(( $(EXT_CLK_HZ) % $(CLINT_TIMEBASE_HZ) )) -eq 0 ]; then printf YES; fi)
ifneq ($(CLINT_TIMEBASE_RATIO_VALID),YES)
$(error EXT_CLK_HZ must be an integer multiple of CLINT_TIMEBASE_HZ)
endif

ifneq ($(filter benchmark-report,$(MAKECMDGOALS)),)
ifneq ($(APP),benchmark)
$(error benchmark-report requires APP=benchmark)
endif

ifneq ($(filter coremark-report,$(MAKECMDGOALS)),)
ifneq ($(APP),coremark)
$(error coremark-report requires APP=coremark)
endif
ifneq ($(COREMARK_MODE),quick)
$(error coremark-report requires COREMARK_MODE=quick)
endif
endif
ifeq ($(RTL_SIM_TIMEOUT),-1)
RTL_SIM_TIMEOUT := 20000000
endif
endif

ifeq ($(SYNTH),YOSYS)
ifeq ($(filter $(PDK),IHP130 ICS55 GF180 SKY130),)
$(error Yosys synthesis does not support PDK=$(PDK))
endif
endif

ifeq ($(STA),OPENSTA)
ifeq ($(HAVE_PLL),YES)
$(error STA=OPENSTA requires a qualified PDK PLL timing profile; HAVE_PLL=YES is unsupported)
endif
endif

DEF_LIST ?= +define+PDK_$(PDK)
DEF_LIST += +define+SIMU_$(SIMU)
DEF_LIST += +define+SOC_JTAG_IDCODE=$(JTAG_IDCODE_DEC)
DEF_LIST += +define+SOC_EXT_CLK_HZ=$(EXT_CLK_HZ)
DEF_LIST += +define+SOC_CLINT_TIMEBASE_HZ=$(CLINT_TIMEBASE_HZ)

ifeq ($(HAVE_PLL), YES)
ifneq ($(filter $(PDK),GF180 SKY130),)
$(error HAVE_PLL=YES requires a qualified crystal pad and is unsupported for PDK=$(PDK))
endif
    DEF_LIST += +define+HAVE_PLL
endif

ifeq ($(HAVE_SRAM_IF), YES)
    DEF_LIST += +define+HAVE_SRAM_IF
endif

ifeq ($(HAVE_SRAM_MACRO), YES)
    DEF_LIST += +define+HAVE_SRAM_MACRO
endif

ifeq ($(PDK_BEHAV), YES)
ifeq ($(SYNTH), YOSYS)
$(error PDK_BEHAV=YES is for functional simulation and cannot be synthesized)
endif
    DEF_LIST += +define+PDK_BEHAV
endif

ifeq ($(HAVE_SVA), NO)
    DEF_LIST += +define+SV_ASSRT_DISABLE
endif

ifeq ($(SYNTH), YOSYS)
    DEF_LIST += +define+SYNTHESIS
endif

include rtl/mini/Makefile
include rtl/mini/mk/formal.mk

ifeq ($(SIMU),IVERILOG)
PERF_LOG ?= $(IVERILOG_BEHV_DIR)/sim.log
else
PERF_LOG ?= $(SIM_BUILD_ROOT)/sim.log
endif

ifeq ($(SYNTH), YOSYS)
include syn/yosys/yosys.mk
endif

ifeq ($(STA), OPENSTA)
    include sta/opensta/opensta.mk
endif

.PHONY: help config doctor setup setup-regression setup-mpw setup-clusterip setup-ip setup-pdk setup-app \
	clean-all purge-cache manifest check-warnings metrics check-metrics package \
	regress-smoke regress-pr regress-nightly sim-asm format format-check sw-format sw-format-check mk-format \
	mk-format-check rtl-format rtl-format-check sw-policy-check sw-host-test \
	benchmark-report coremark-report \
	pin-map check-pin-map soc-topology check-soc-topology user-extensions check-user-extensions \
	check-clock-reset-domains tech-cell-test rtl-lint check-rtl-lint \
	formal formal-bus formal-rib-adapter formal-rib2apb formal-gpio formal-ws2812 formal-uart formal-i2c formal-timer formal-clean formal-doctor
.NOTPARALLEL: setup

help:
	@printf '%s\n' \
	  'retroSoC build targets:' \
	  '  firmware | asm             build firmware' \
	  '  comp | sim                 behavioral simulation' \
	  '  sim-asm                    build/run the assembly self-test' \
	  '  debug-sim                  run the Hazard3 Verilator/OpenOCD/GDB acceptance flow' \
	  '  netcomp | netsim           synthesized-netlist simulation' \
	  '  postcomp | postsim         post-layout simulation' \
	  '  synth | sta                synthesis and timing analysis' \
	  '  setup                      install pinned external dependencies' \
	  '  setup-regression           install pinned dependencies for all PR PDK profiles' \
	  '  doctor                     check tools, paths, and selected configuration' \
	  '  config | manifest          print/write the effective configuration' \
	  '  memory-map                 generate the selected address-map artifacts' \
	  '  check-memory-map           validate the canonical address map' \
	  '  pin-map                    generate the selected pin-map artifacts' \
	  '  check-pin-map              validate the canonical SoC pin map' \
	  '  soc-topology               generate the selected internal SoC integration artifacts' \
	  '  check-soc-topology         validate the canonical internal SoC integration map' \
	  '  user-extensions            generate the selected scalar user-extension bindings' \
	  '  check-user-extensions      validate the canonical user-extension map' \
	  '  check-clock-reset-domains  validate the root clock/reset and CDC inventory' \
	  '  rtl-lint | check-rtl-lint  run/check strict Verilator RTL lint warnings' \
	  '  formal | formal-bus | formal-rib-adapter | formal-rib2apb run SBY protocol proofs' \
	  '  formal-sysctrl | formal-pll-rcu | formal-gpio | formal-ws2812 | formal-uart | formal-i2c | formal-timer | formal-clint run peripheral proofs' \
	  '  formal-doctor              check the SBY, Yosys, sv2v, and Bitwuzla formal toolchain' \
	  '  benchmark-report           run the memory/DMA profile and write meta/performance.json' \
	  '  coremark-report            run the quick CoreMark profile and write meta/coremark.json' \
	  '  tech-cell-test             test GF180/SKY130 technology IO and clock wrappers' \
	  '  check-warnings | metrics   analyze flow logs and reports' \
	  '  check-metrics              apply the committed metrics policy' \
	  '  format                     format self-owned C, Makefile, and RTL sources' \
	  '  format-check               check self-owned C, Makefile, and RTL formatting' \
	  '  sw-format                  apply clang-format to self-owned embedded C code' \
	  '  sw-format-check            check embedded C whitespace and line-ending policy' \
	  '  mk-format | mk-format-check apply/check tracked Makefile formatting' \
	  '  rtl-format | rtl-format-check apply/check self-owned RTL formatting' \
	  '  sw-policy-check            check embedded C API and naming policy' \
	  '  sw-host-test               run host tests for deterministic SDK utilities' \
	  '  regress-smoke              run the IHP130 fast regression suite' \
	  '  regress-pr | regress-nightly run supported full regression suites' \
	  '  package                    create checksummed source deliverables' \
	  '  clean | clean-all          clean current flow or all build output' \
	  '  purge-cache                remove dependency and compiler caches' \
	  '' \
	  'Usage: make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG sim'

config:
	@printf '%-18s %s\n' \
	  ROOT_PATH '$(ROOT_PATH)' CONFIG '$(or $(CONFIG_PATH),<defaults>)' \
	  BUILD_TIMESTAMP '$(BUILD_TIMESTAMP)' VARIANT_ID '$(VARIANT_ID)' VARIANT_ROOT '$(VARIANT_ROOT)' \
	  JOBS '$(JOBS)' \
	  SOC '$(SOC)' MGMT_CORE 'HAZARD3' \
	  SIMU '$(SIMU)' SYNTH '$(SYNTH)' STA '$(STA)' FORMAL '$(FORMAL)' \
	  VCS_USE_LSF '$(VCS_USE_LSF)' PDK '$(PDK)' \
	  HAVE_PLL '$(HAVE_PLL)' HAVE_SRAM_IF '$(HAVE_SRAM_IF)' \
	  HAVE_SRAM_MACRO '$(HAVE_SRAM_MACRO)' PDK_BEHAV '$(PDK_BEHAV)' HAVE_SVA '$(HAVE_SVA)' \
	  BUILD_RELEASE '$(BUILD_RELEASE)' \
	  JTAG_IDCODE '$(JTAG_IDCODE)' EXT_CLK_HZ '$(EXT_CLK_HZ)' \
	  CLINT_TIMEBASE_HZ '$(CLINT_TIMEBASE_HZ)' \
	  ISA '$(ISA)' HAVE_CSR '$(HAVE_CSR)' APP '$(APP)' \
	  LINK_TYPE '$(LINK_TYPE)' COREMARK_MODE '$(COREMARK_MODE)'

doctor:
	@python3 $(ROOT_PATH)/scripts/doctor.py \
	  --root $(ROOT_PATH) --simu $(SIMU) --synth $(SYNTH) --sta $(STA) \
	  --pdk $(PDK) --formal $(FORMAL) --lock $(LOCK_FILE)

benchmark-report: firmware

	$(MAKE) RTL_SIM_TIMEOUT=$(RTL_SIM_TIMEOUT) sim
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/parse_performance_log.py --log $(PERF_LOG) \
		--output $(META_DIR)/performance.json

coremark-report: firmware

	$(MAKE) RTL_SIM_TIMEOUT=$(RTL_SIM_TIMEOUT) sim
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/parse_coremark_log.py --log $(PERF_LOG) \
		--output $(META_DIR)/coremark.json

setup: setup-mpw setup-clusterip setup-ip setup-pdk setup-app

setup-regression:
	$(MAKE) CONFIG=configs/ci/ihp130.mk setup
	$(MAKE) CONFIG=configs/ci/gf180.mk setup
	$(MAKE) CONFIG=configs/ci/ics55.mk setup
	$(MAKE) CONFIG=configs/ci/sky130.mk setup

setup-mpw:
	python3 $(ROOT_PATH)/setup.py
	python3 $(ROOT_PATH)/scripts/prepare_mpw.py \
	  --lock-file $(CACHE_ROOT)/locks/mpw-prepare.lock
	@mkdir -p $(dir $(MPW_STAMP))
	@touch $(MPW_STAMP)

setup-clusterip:
	python3 $(ROOT_PATH)/rtl/managed/clusterip/setup.py

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
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/manifest.py create --root $(ROOT_PATH) \
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

format: sw-format mk-format rtl-format

format-check: sw-format-check mk-format-check rtl-format-check

mk-format:
	python3 $(ROOT_PATH)/scripts/check_format.py --root $(ROOT_PATH) --kind make --apply \
	  --mbake $(MBAKE)

mk-format-check:
	python3 $(ROOT_PATH)/scripts/check_format.py --root $(ROOT_PATH) --kind make \
	  --mbake $(MBAKE)

rtl-format:
	python3 $(ROOT_PATH)/scripts/check_format.py --root $(ROOT_PATH) --kind rtl --apply \
	  --verible-verilog-format $(VERIBLE_FORMAT)

rtl-format-check:
	python3 $(ROOT_PATH)/scripts/check_format.py --root $(ROOT_PATH) --kind rtl \
	  --verible-verilog-format $(VERIBLE_FORMAT)

sw-policy-check:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) --policy-check

sw-host-test:
	python3 $(ROOT_PATH)/scripts/run_c_tests.py --root $(ROOT_PATH) --cc $(HOST_CC)

package: $(MPW_VARIANT_STAMP) $(FILELIST_STAMP) manifest
	python3 $(ROOT_PATH)/scripts/package.py --root $(ROOT_PATH) --lock $(LOCK_FILE) \
	  --variant-root $(VARIANT_ROOT) --output-dir $(ROOT_PATH)/dist/$(VARIANT_ID)

regress-smoke:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite smoke --pdk IHP130

regress-pr:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk IHP130 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk GF180 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk SKY130 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk ICS55 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)

regress-nightly:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite nightly

sim-asm: asm
	$(MAKE) SIM_FIRMWARE_NAME=$(ASM_FIRMWARE_NAME) sim