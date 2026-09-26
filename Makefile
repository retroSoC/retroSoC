SHELL := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

ROOT_PATH ?= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
CONFIG    ?=
LOCK_FILE ?= $(ROOT_PATH)/dependencies/dependencies.lock.json

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

SOC          ?= MINI
MINI_MODE    ?= PRODUCT
SIMU         ?= VCS
SYNTH        ?= NONE
SYNTH_RECIPE ?= balanced
STA          ?= NONE

# HW
PDK               ?= IHP130
HAVE_PLL          ?= NO
HAVE_SRAM_IF      ?= $(if $(filter ICS55,$(PDK)),NO,YES)
HAVE_SRAM_MACRO   ?= $(if $(filter ICS55,$(PDK)),NO,YES)
SRAM_SIZE_KIB     ?= $(if $(filter ICS55,$(PDK)),128,32)
PDK_BEHAV         ?= NO
HAVE_SVA          ?= NO
APU_ENABLE_P7     ?= NO
HAVE_HP           ?= YES
HP_CONFIG         ?= rv32imafdc_zicbom_max
BUILD_RELEASE     ?= NO
JTAG_IDCODE       ?= DEADBEEF
EXT_CLK_HZ        ?= 72000000
AUD_CLK_HZ        ?= 18432000
CLINT_TIMEBASE_HZ ?= 1000000
MGMT_CPU_CLK_HZ   := $(if $(filter PRODUCT,$(MINI_MODE)),24000000,$(EXT_CLK_HZ))
# Reset-state peripheral clock: the PCLK divider in the clock/reset subsystem
# resets to passthrough on the LP root clock, so PCLK starts at the management
# CPU frequency until software programs a different divider.
PCLK_CLK_HZ              := $(MGMT_CPU_CLK_HZ)
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
ISA                ?= RV32IM
HAVE_CSR           ?= NO
FIRMWARE_NAME      ?= retrosoc_fw
APP                ?= shell
LINK_TYPE          ?= ld2_sram
COREMARK_MODE      ?= quick
NPU_P5_ACCEPTANCE  ?= NO
NPU_P6_ACCEPTANCE  ?= NO
NPU_P6_WORKLOAD    ?= kws
HP_PERF_MIN_RATIO  ?= 2.5
LP_COREMARK_REPORT ?=
HP_COREMARK_REPORT ?=

BUILD_ROOT         ?= $(ROOT_PATH)/build
CACHE_ROOT         ?= $(ROOT_PATH)/.cache/retrosoc
VEXIIRISCV_ROOT    ?= $(ROOT_PATH)/.cache/retrosoc/sources/vexiiriscv
SBT                ?= sbt
BUILD_TIMESTAMP    ?= $(shell date '+%Y-%m-%d-%H-%M')
BUILD_TIMESTAMP    := $(BUILD_TIMESTAMP)
MAX_JOBS           ?= 16
HOST_CC            ?= cc
PYTHON             ?= python3
FLOW_PYTHON        ?= $(PYTHON)
CLANG_FORMAT       ?= clang-format-14
MBAKE              ?= mbake
VERIBLE_FORMAT     ?= verible-verilog-format
VERIBLE_LINT       ?= verible-verilog-lint
VCS_DEFAULT_RUNNER := $(if $(filter YES,$(VCS_USE_LSF)),bsub -Is)
VCS_RUNNER         ?= $(VCS_DEFAULT_RUNNER)
VCS_SHELL_GOALS    := comp sim netcomp netsim postcomp postsim
VCS_SHELL_PYTHON   := $(if $(filter VCS,$(SIMU)),$(if $(filter $(VCS_SHELL_GOALS),$(MAKECMDGOALS)),$(strip $(VCS_RUNNER) $(PYTHON)),$(PYTHON)),$(PYTHON))
JOBS               ?= $(shell count=$$(nproc 2>/dev/null || printf '1'); \
                       if [ "$$count" -gt "$(MAX_JOBS)" ]; then printf '%s' '$(MAX_JOBS)'; \
else printf '%s' "$$count"; fi)
LOCAL_RTL_FILES    ?=
CONFIG_KEY_VARS    := SOC MINI_MODE PDK HAVE_PLL HAVE_SRAM_IF HAVE_SRAM_MACRO SRAM_SIZE_KIB PDK_BEHAV HAVE_SVA APU_ENABLE_P7 \
                   HAVE_HP HP_CONFIG BUILD_RELEASE JTAG_IDCODE EXT_CLK_HZ AUD_CLK_HZ CLINT_TIMEBASE_HZ MGMT_CPU_CLK_HZ \
                   ISA HAVE_CSR APP LINK_TYPE COREMARK_MODE RTL_TOP FIRMWARE_NAME
CONFIG_KEY_VARS    += NPU_P5_ACCEPTANCE NPU_P6_ACCEPTANCE NPU_P6_WORKLOAD
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
VARIANT_ROOT            := $(abspath $(BUILD_ROOT))/$(VARIANT_ID)
SW_BUILD_DIR            := $(VARIANT_ROOT)/sw
SIM_TOOL_NAME           := $(shell printf '%s' '$(SIMU)' | tr '[:upper:]' '[:lower:]')
SIM_BUILD_ROOT          := $(VARIANT_ROOT)/sim/$(SIM_TOOL_NAME)
META_DIR                := $(VARIANT_ROOT)/meta
HP_GENERATED_DIR        := $(VARIANT_ROOT)/generated/vexiiriscv
HP_GENERATED_RTL        := $(HP_GENERATED_DIR)/vexii_riscv_hp_generated.v
HP_GENERATED_MANIFEST   := $(HP_GENERATED_DIR)/manifest.json
HP_GENERATED_STAMP      := $(HP_GENERATED_DIR)/.stamp
APU_P5_DIR              := $(VARIANT_ROOT)/apu/p5
APU_P5_BUNDLE           := $(APU_P5_DIR)/apu-p5.apumc
APU_P5_REFERENCE_DIR    := $(VARIANT_ROOT)/apu/reference
APU_P5_CORPUS_MANIFEST  := $(APU_P5_DIR)/corpus-manifest.json
APU_P5_CORPUS_RTL_DIR   := $(APU_P5_DIR)/corpus-rtl
APU_P7_DIR              := $(VARIANT_ROOT)/apu/kws
APU_P7_MODEL            := $(APU_P7_DIR)/apu-p7.apum
APU_P7_MODEL_MANIFEST   := $(APU_P7_DIR)/apu-p7-manifest.json
APU_P9_COEFFICIENT_DIR  := $(VARIANT_ROOT)/apu/coefficients
APU_P9_APUC             := $(APU_P9_COEFFICIENT_DIR)/apu-p9.apuc
APU_P9_LAYOUT_MANIFEST  := $(APU_P9_COEFFICIENT_DIR)/coefficient-layout.json
APU_P9_EVIDENCE_DIR     := $(VARIANT_ROOT)/apu/p9/evidence
APU_P9_EVIDENCE_LAYOUT  := $(APU_P9_EVIDENCE_DIR)/coefficient-layout.json
APU_P7_KWS_TFLITE       := $(CACHE_ROOT)/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting/trained_models/kws_ref_model.tflite
NPU_P0_DIR              := $(VARIANT_ROOT)/npu/p0
NPU_P5_DIR              := $(VARIANT_ROOT)/npu/p5
NPU_P5_KWS_DIR          := $(NPU_P5_DIR)/deployments/kws
NPU_P5_VWW_DIR          := $(NPU_P5_DIR)/deployments/vww
NPU_P5_KWS_C            := $(NPU_P5_KWS_DIR)/kws_npu.c
NPU_P5_VWW_C            := $(NPU_P5_VWW_DIR)/vww_npu.c
NPU_P5_KWS_STAMP        := $(NPU_P5_KWS_DIR)/.stamp
NPU_P5_VWW_STAMP        := $(NPU_P5_VWW_DIR)/.stamp
NPU_P5_ACCEPTANCE_DIR   := $(NPU_P5_DIR)/acceptance
NPU_P5_ACCEPTANCE_C     := $(NPU_P5_ACCEPTANCE_DIR)/npu_acceptance_data.c
NPU_P5_ACCEPTANCE_STAMP := $(NPU_P5_ACCEPTANCE_DIR)/.stamp
NPU_P5_C_QUALITY_RESULT := $(NPU_P5_DIR)/evidence/result-c-quality.json
NPU_P5_REPORT           := $(NPU_P5_DIR)/evidence/qualification-p5.json
NPU_P6_DIR              := $(VARIANT_ROOT)/npu/p6
NPU_P6_CORPUS_DIR       := $(NPU_P6_DIR)/corpus
NPU_P6_FORMAL_REPORT    := $(NPU_P6_DIR)/evidence/qualification-p6-formal.json
NPU_P6_NETLIST_DIR      := $(NPU_P6_DIR)/netlist
NPU_P6_PERF_DIR         := $(NPU_P6_DIR)/verilator
NPU_P6_PERF_REPORT      := $(NPU_P6_PERF_DIR)/qualification-p6-verilator.json
NPU_P6_PHYS_DIR         := $(NPU_P6_DIR)/physical
NPU_P6_PHYS_REPORT      := $(NPU_P6_PHYS_DIR)/qualification-p6-physical.json
NPU_P6_REGRESS_DIR      := $(NPU_P6_DIR)/regression
NPU_P6_REGRESS_REPORT   := $(NPU_P6_REGRESS_DIR)/qualification-p6-regression.json
NPU_P6_REPORT           := $(NPU_P6_DIR)/evidence/qualification-p6.json
NPU_P6_P0_REPORT        ?=
NPU_P6_P5_REPORT        ?=
NPU_P5_LP_VARIANT_ROOT  ?=
NPU_P5_HP_VARIANT_ROOT  ?=
NPU_P5_LP_CONFIG_DIGEST ?=
NPU_P5_HP_CONFIG_DIGEST ?=
HP_LINUX_BUILD_DIR      := $(VARIANT_ROOT)/hp-linux
HP_LINUX_STAMP          := $(HP_LINUX_BUILD_DIR)/images/.stamp
HP_BOOT_BUNDLE_NAME     ?= retrosoc_hp_linux
HP_BOOT_BUNDLE_BIN      := $(SW_BUILD_DIR)/$(HP_BOOT_BUNDLE_NAME).bin
HP_BOOT_BUNDLE_HEX      := $(SW_BUILD_DIR)/$(HP_BOOT_BUNDLE_NAME).hex
HP_BOOT_BUNDLE_MANIFEST := $(SW_BUILD_DIR)/$(HP_BOOT_BUNDLE_NAME).json
HP_LINUX_SIM_TIME       ?= 7200
HP_SMOKE_SIM_TIME       ?= 300
HP_SMOKE_BUILD_DIR      := $(VARIANT_ROOT)/hp-smoke
HP_SMOKE_STAMP          := $(HP_SMOKE_BUILD_DIR)/images/.stamp
HP_SMOKE_BUNDLE_NAME    ?= retrosoc_hp_smoke
HP_SMOKE_BUNDLE_BIN     := $(SW_BUILD_DIR)/$(HP_SMOKE_BUNDLE_NAME).bin
HP_SMOKE_BUNDLE_HEX     := $(SW_BUILD_DIR)/$(HP_SMOKE_BUNDLE_NAME).hex
HP_SMOKE_MANIFEST       := $(SW_BUILD_DIR)/$(HP_SMOKE_BUNDLE_NAME).json
HP_APU_BUILD_DIR        := $(VARIANT_ROOT)/hp-apu
HP_APU_STAMP            := $(HP_APU_BUILD_DIR)/images/.stamp
HP_APU_BUNDLE_NAME      ?= retrosoc_hp_apu
HP_APU_BUNDLE_BIN       := $(SW_BUILD_DIR)/$(HP_APU_BUNDLE_NAME).bin
HP_APU_BUNDLE_HEX       := $(SW_BUILD_DIR)/$(HP_APU_BUNDLE_NAME).hex
HP_APU_MANIFEST         := $(SW_BUILD_DIR)/$(HP_APU_BUNDLE_NAME).json
HP_BUILDRT_ROOT         := $(ROOT_PATH)/.cache/retrosoc/sources/buildroot-hp
HP_LINUX_ROOT           := $(ROOT_PATH)/.cache/retrosoc/sources/linux-hp
HP_OPENSBI_ROOT         := $(ROOT_PATH)/.cache/retrosoc/sources/opensbi-hp
ifeq ($(SYNTH_RECIPE),balanced)
SYN_BUILD_ROOT   := $(VARIANT_ROOT)/syn/yosys
STA_BUILD_ROOT   := $(VARIANT_ROOT)/sta/opensta
NETLIST_SIM_ROOT := $(SIM_BUILD_ROOT)/netl
METRICS_OUTPUT   := $(META_DIR)/metrics.json
else
SYN_BUILD_ROOT   := $(VARIANT_ROOT)/syn/yosys-$(SYNTH_RECIPE)
STA_BUILD_ROOT   := $(VARIANT_ROOT)/sta/opensta-$(SYNTH_RECIPE)
NETLIST_SIM_ROOT := $(SIM_BUILD_ROOT)/netl-$(SYNTH_RECIPE)
METRICS_OUTPUT   := $(META_DIR)/metrics-$(SYNTH_RECIPE).json
endif
ifeq ($(SYNTH),YOSYS)
FLOW_FILELIST_DIR := $(SYN_BUILD_ROOT)/filelists
else
FLOW_FILELIST_DIR := $(SIM_BUILD_ROOT)/filelists
endif

VALID_SOC           := MINI
VALID_MINI_MODE     := PRODUCT MPW
VALID_SIMU          := VCS VERILATOR IVERILOG
VALID_SYNTH         := NONE YOSYS
VALID_SYNTH_RECIPE  := balanced area speed
VALID_STA           := NONE OPENSTA
VALID_PDK           := ICS55 IHP130 SKY130 GF180
VALID_BOOL          := YES NO
VALID_HP_CONFIG     := rv32imafdc_zicbom_max
VALID_ISA           := RV32E RV32I RV32IM
VALID_APP           := benchmark bringup ci_smoke coremark debug hp_boot shell xpi_flash_loader apu_release
VALID_LINK_TYPE     := xip jtag_sram ld2_all_sram ld2_sram ld2_psram ld2_sdram
VALID_COREMARK_MODE := quick standard
VALID_SRAM_SIZE_KIB := 4 16 32 64 128

define validate_value
$(if $(filter $($(1)),$(2)),,$(error Invalid $(1)='$($(1))'; expected one of: $(2)))
endef

$(call validate_value,SOC,$(VALID_SOC))
$(call validate_value,MINI_MODE,$(VALID_MINI_MODE))
$(call validate_value,SIMU,$(VALID_SIMU))
$(call validate_value,SYNTH,$(VALID_SYNTH))
$(call validate_value,SYNTH_RECIPE,$(VALID_SYNTH_RECIPE))
$(call validate_value,STA,$(VALID_STA))
$(call validate_value,PDK,$(VALID_PDK))
$(call validate_value,HAVE_PLL,$(VALID_BOOL))
$(call validate_value,HAVE_SRAM_IF,$(VALID_BOOL))
$(call validate_value,HAVE_SRAM_MACRO,$(VALID_BOOL))
$(call validate_value,SRAM_SIZE_KIB,$(VALID_SRAM_SIZE_KIB))
$(call validate_value,PDK_BEHAV,$(VALID_BOOL))
$(call validate_value,HAVE_SVA,$(VALID_BOOL))
$(call validate_value,APU_ENABLE_P7,$(VALID_BOOL))
$(call validate_value,HAVE_HP,$(VALID_BOOL))
$(call validate_value,HP_CONFIG,$(VALID_HP_CONFIG))
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
$(call validate_value,NPU_P5_ACCEPTANCE,$(VALID_BOOL))
$(call validate_value,NPU_P6_ACCEPTANCE,$(VALID_BOOL))
$(call validate_value,NPU_P6_WORKLOAD,kws vww)

ifeq ($(NPU_P5_ACCEPTANCE),YES)
ifeq ($(filter $(APP),ci_smoke hp_boot),)
$(error NPU_P5_ACCEPTANCE=YES requires APP=ci_smoke or APP=hp_boot)
endif
endif

ifeq ($(NPU_P6_ACCEPTANCE),YES)
ifneq ($(APP),hp_boot)
$(error NPU_P6_ACCEPTANCE=YES requires APP=hp_boot)
endif
ifeq ($(NPU_P5_ACCEPTANCE),YES)
$(error NPU_P5_ACCEPTANCE and NPU_P6_ACCEPTANCE are mutually exclusive)
endif
endif

ifeq ($(MINI_MODE),PRODUCT)
ifneq ($(HAVE_HP),YES)
$(error MINI_MODE=PRODUCT requires HAVE_HP=YES)
endif
endif

MISSING_LOCAL_RTL_FILES := $(filter-out $(wildcard $(LOCAL_RTL_FILES)),$(LOCAL_RTL_FILES))
ifneq ($(strip $(MISSING_LOCAL_RTL_FILES)),)
$(error LOCAL_RTL_FILES contains missing source(s): $(MISSING_LOCAL_RTL_FILES))
endif

ifeq ($(HAVE_SRAM_MACRO),YES)
ifneq ($(HAVE_SRAM_IF),YES)
$(error HAVE_SRAM_MACRO=YES requires HAVE_SRAM_IF=YES)
endif
endif

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
AUD_CLK_HZ_VALID := $(shell printf '%s' '$(AUD_CLK_HZ)' | grep -E '^[1-9][[:digit:]]*$$')
ifneq ($(AUD_CLK_HZ_VALID),$(AUD_CLK_HZ))
$(error AUD_CLK_HZ='$(AUD_CLK_HZ)' must be a positive integer)
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
DEF_LIST += +define+SOC_AUD_CLK_HZ=$(AUD_CLK_HZ)
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

ifeq ($(HAVE_HP), YES)
    DEF_LIST += +define+HAVE_HP
endif

ifeq ($(APU_ENABLE_P7), YES)
    DEF_LIST += +define+APU_ENABLE_P7
endif

ifeq ($(MINI_MODE), PRODUCT)
    DEF_LIST += +define+MINI_PRODUCT
else
    DEF_LIST += +define+MINI_MPW
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
include physical/smoke/syn/yosys/yosys.mk
include physical/smoke/syn/yosys/ga2d_block.mk
include physical/smoke/syn/yosys/apu_block.mk
endif

ifeq ($(STA), OPENSTA)
    include physical/smoke/sta/opensta/opensta.mk
endif

include physical/librelane/Makefile
include physical/ecc/Makefile

.PHONY: crypto-p0-constants crypto-p0-rtl crypto-p0-baseline crypto-p0-report
crypto-p0-constants: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p0.py constants --variant-root $(VARIANT_ROOT)
crypto-p0-rtl: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p0.py rtl --variant-root $(VARIANT_ROOT) --jobs $(JOBS)
crypto-p0-baseline: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p0.py synth --variant-root $(VARIANT_ROOT)
crypto-p0-report: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p0.py report --variant-root $(VARIANT_ROOT)

.PHONY: crypto-p1-constants crypto-p1-rtl crypto-p1-formal crypto-p1-synth crypto-p1-report
crypto-p1-constants: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py constants --variant-root $(VARIANT_ROOT)
crypto-p1-rtl: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --macro --full-rsa --jobs $(JOBS)
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --macro --case crypto_dma_v2_tb --jobs $(JOBS)
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --macro --case crypto_storage_tb --jobs $(JOBS)
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --macro --case crypto_concurrent_tb --jobs $(JOBS)
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --macro --case crypto_response_fault_tb --jobs $(JOBS)
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --macro --simulator icarus
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --jobs $(JOBS)
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py rtl --variant-root $(VARIANT_ROOT) --case crypto_storage_tb --jobs $(JOBS)
crypto-p1-formal: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py formal --variant-root $(VARIANT_ROOT)
crypto-p1-synth: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py synth --variant-root $(VARIANT_ROOT)
crypto-p1-report: manifest
	$(PYTHON) $(ROOT_PATH)/scripts/crypto_p1.py report --variant-root $(VARIANT_ROOT) \
	  --baseline-root $(CRYPTO_P0_BASELINE_ROOT) --lp-variant-root $(CRYPTO_P1_LP_ROOT) \
	  $(if $(CRYPTO_P1_CI_ROOT),--ci-variant-root $(CRYPTO_P1_CI_ROOT),)

.PHONY: help config doctor setup setup-regression setup-mpw setup-vexiiriscv setup-clusterip setup-ip setup-pdk setup-app setup-apu-reference setup-apu-kws-reference apu-p5-bundle apu-p5-corpus apu-p7-model apu-p9-coefficients apu-p9-evidence apu-p9-memory-ab setup-hp-linux hp-linux hp-bundle hp-linux-sim hp-smoke-bundle hp-smoke-sim hp-apu-bundle hp-apu-sim \
	clean-all purge-cache manifest check-warnings metrics check-metrics package commercial-package \
	regress-smoke regress-rtl regress-pr regress-nightly sim-asm format format-check sw-format sw-format-check mk-format \
	mk-format-check rtl-format rtl-format-check rtl-style-check rtl-migrate-connections rtl-migrate-names sw-policy-check sw-host-test \
	benchmark-report coremark-report \
	hp-performance-check \
	apu-block-filelist apu-block-synth apu-block-sta apu-block-report apu-block-evidence apu-block-clean \
	pin-map check-pin-map soc-topology check-soc-topology user-extensions check-user-extensions \
	check-clock-reset-domains tech-cell-test rtl-lint check-rtl-lint \
	  formal formal-bus formal-rib-adapter formal-rib2apb formal-gpio formal-ws2812 formal-uart formal-i2c formal-timer formal-dvp formal-i2s formal-onchip-ram formal-opipsram formal-dma formal-apu formal-apu-kws formal-apu-p9 formal-gateway-a formal-sdio formal-clean formal-doctor \
	rtl-style-check-all rtl-readiness-check rtl-readiness-check-all vexii-generate
.NOTPARALLEL: setup

help:
	@printf '%s\n' \
	  'retroSoC build targets:' \
	  '  crypto-p0-constants        verify and package the independent CRYC1 baseline' \
	  '  crypto-p0-rtl              run V1 Crypto, RSA-2048 and real DMA evidence' \
	  '  crypto-p0-baseline         run unchanged balanced Crypto block synthesis' \
	  '  crypto-p0-report           check and aggregate CRYPTO-P0 evidence' \
	  '  firmware | asm             build firmware' \
	  '  comp | sim                 behavioral simulation' \
	  '  sim-asm                    build/run the assembly self-test' \
	  '  debug-sim                  run the Hazard3 Verilator/OpenOCD/GDB acceptance flow' \
	  '  netcomp | netsim           synthesized-netlist simulation' \
	  '  postcomp | postsim         post-layout simulation' \
	  '  synth | sta                synthesis and timing analysis' \
	  '  synth-ga2d-block           isolated GA2D block synthesis evidence' \
	  '  netsim-ga2d-block          GA2D synthesized-block transaction test' \
	  '  sta-ga2d-block             GA2D block timing analysis' \
	  '  apu-block-evidence         compare P5/P7 APU block synthesis and STA' \
	  '  librelane-doctor           validate the IHP130 LibreLane Chip flow' \
	  '  librelane-chip             run the single-level IHP130 pad-ring flow' \
	  '  librelane-openroad         open the current Chip run in OpenROAD' \
	  '  librelane-klayout          open the current Chip run in KLayout' \
	  '  librelane-package          package full-chip views and evidence' \
	  '  ecc-setup                   install the pinned ECC CLI and ICS55 inputs' \
	  '  ecc-doctor                  validate the padless ICS55 ECC hardening flow' \
	  '  ecc-core                    run the padless ICS55 ECC hardening flow' \
	  '  ecc-package                 package ECC core views and evidence' \
	  '  setup                      install pinned external dependencies' \
	  '  setup-apu-reference        install pinned host-only APU FLAC references' \
	  '  setup-apu-kws-reference   validate pinned P7 KWS model/corpus inputs' \
	  '  apu-p5-bundle              build the deterministic WAV/FLAC APUMC bundle' \
	  '  apu-p5-corpus              qualify pinned FLAC with BAM/libFLAC and production RTL' \
	  '  apu-p7-model               convert the locked MLPerf Tiny KWS model to APUM' \
	  '  apu-p9-coefficients        build the frozen APUC image and 15-bank manifest' \
	  '  apu-p9-evidence            initialize the six fail-closed P9 evidence reports' \
	  '  apu-p9-memory-ab           compare explicit baseline/candidate synthesis roots' \
	  '  setup-npu-reference        install/verify locked NPU models, corpora, and oracle' \
	  '  npu-p0-qualify             qualify full corpora against the independent oracle' \
	  '  npu-p5-deployments         build deterministic KWS/VWW ABI-1 packages' \
	  '  npu-p5-c-quality           run retained embedded-C/HAL quality evidence' \
	  '  npu-p5-host                run compiler, generated-C, executor, and ABI tests' \
	  '  npu-p5-rtl                 run frozen model inputs through Icarus and Verilator' \
	  '  npu-p5-lp-sim              run LP interrupt bare-metal NPU acceptance' \
	  '  npu-p5-hp-sim              run HP polling/Zicbom bare-metal NPU acceptance' \
	  '  npu-p5-report              validate and assemble retained P5 evidence' \
	  '  npu-p6-corpus              build deterministic 100-case qualification shards' \
	  '  npu-p6-formal              close DMA, context, and control bounded proofs' \
	  '  npu-p6-verilator           run both complete corpora on PRODUCT Verilator' \
	  '  npu-p6-netlist             run isolated NPU physical and gate transactions' \
	  '  npu-p6-physical            run full PRODUCT IHP130 synthesis/STA evidence' \
	  '  npu-p6-regression          run and retain the full PR/nightly matrices' \
	  '  npu-p6-report              assemble fail-closed NPU-V015..V018 evidence' \
	  '  npu-p6-qualify             execute all required P6 qualification gates' \
	  '  setup-regression           install pinned dependencies for all PR PDK profiles' \
	  '  setup-hp-linux             install pinned Buildroot, Linux, and OpenSBI sources' \
	  '  hp-linux                   build the pinned RV32 HP Linux image set' \
	  '  hp-bundle                  package LP firmware and HP Linux images for flash' \
	  '  hp-linux-sim               run the fast-flash HP Linux userspace acceptance test' \
	  '  hp-smoke-sim               run LP release, HP MMIO, and mailbox RTL smoke test' \
	  '  hp-apu-bundle              package the APU release LP firmware and HP payload' \
	  '  hp-apu-sim                 run the LP/HP APU ownership evidence simulation' \
	  '  doctor                     check tools, paths, and selected configuration' \
	  '  config | manifest          print/write the effective configuration' \
	  '  memory-map                 generate the selected address-map artifacts' \
	  '  check-memory-map           validate the canonical address map' \
	  '  pin-map                    generate the selected pin-map artifacts' \
	  '  check-pin-map              validate the canonical SoC pin map' \
	  '  soc-topology               generate the selected internal SoC integration artifacts' \
	  '  check-soc-topology         validate the canonical internal SoC integration map' \
	  '  user-extensions            generate the selected scalar user-extension bindings' \
	  '  vexii-generate             generate the locked HP VexiiRiscv RTL below build/' \
	  '  check-user-extensions      validate the canonical user-extension map' \
	  '  check-clock-reset-domains  validate the root clock/reset and CDC inventory' \
	  '  rtl-lint | check-rtl-lint  run/check strict Verilator RTL lint warnings' \
	  '  formal | formal-bus | formal-rib-adapter | formal-rib2apb run SBY protocol proofs' \
	  'formal-sysctrl | formal-pll-rcu | formal-gpio | formal-ws2812 | formal-uart | formal-i2c | formal-timer | formal-clint | formal-dvp | formal-i2s | formal-onchip-ram | formal-opipsram | formal-dma | formal-ga2d | formal-apu | formal-apu-kws | formal-apu-p9 | formal-gateway-a | formal-sdio run peripheral proofs' \
	  '  formal-doctor              check the SBY, Yosys, sv2v, and Bitwuzla formal toolchain' \
	  '  benchmark-report           run the memory/DMA profile and write meta/performance.json' \
	  '  coremark-report            run the quick CoreMark profile and write meta/coremark.json' \
	  '  hp-performance-check       require measured HP CoreMark/MHz >= 2.5x LP' \
	  '  tech-cell-test             test open-PDK technology IO and clock wrappers' \
	  '  check-warnings | metrics   analyze flow logs and reports' \
	  '  check-metrics              apply the committed metrics policy' \
	  '  format                     format self-owned C, Makefile, and RTL sources' \
	  '  format-check               check self-owned C, Makefile, and RTL formatting' \
	  '  sw-format                  apply clang-format to self-owned embedded C code' \
	  '  sw-format-check            check embedded C whitespace and line-ending policy' \
	  '  mk-format | mk-format-check apply/check tracked Makefile formatting' \
	  '  rtl-format | rtl-format-check apply/check self-owned RTL formatting' \
	  '  rtl-style-check-all        check all self-owned RTL naming and language rules' \
	  '  rtl-readiness-check        validate affected RTL readiness records' \
	  '  rtl-readiness-check-all    validate all RTL readiness records' \
	  '  rtl-migrate-connections  convert provably positional RTL instances to named ports' \
	  '  rtl-migrate-names        shorten local RTL identifier names' \
	  '  rtl-style-check            check changed self-owned RTL naming and connections' \
	  '  sw-policy-check            check embedded C API and naming policy' \
	  '  sw-host-test               run host tests for deterministic SDK utilities' \
	  '  regress-smoke              run the IHP130 fast regression suite' \
	  '  regress-pr | regress-nightly run supported full regression suites' \
	  '  package                    create checksummed source deliverables' \
	  '  commercial-package         create the RTL package consumed in the EDA zone' \
	  '  clean | clean-all          clean current flow or all build output' \
	  '  purge-cache                remove dependency and compiler caches' \
	  '' \
	  'Usage: make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG sim'

config:
	@printf '%-18s %s\n' \
	  ROOT_PATH '$(ROOT_PATH)' CONFIG '$(or $(CONFIG_PATH),<defaults>)' \
	  BUILD_TIMESTAMP '$(BUILD_TIMESTAMP)' VARIANT_ID '$(VARIANT_ID)' VARIANT_ROOT '$(VARIANT_ROOT)' \
	  JOBS '$(JOBS)' \
	  SOC '$(SOC)' MINI_MODE '$(MINI_MODE)' MGMT_CORE 'HAZARD3' \
	  SIMU '$(SIMU)' SYNTH '$(SYNTH)' SYNTH_RECIPE '$(SYNTH_RECIPE)' \
	  STA '$(STA)' FORMAL '$(FORMAL)' \
	  VCS_USE_LSF '$(VCS_USE_LSF)' PDK '$(PDK)' \
	  HAVE_PLL '$(HAVE_PLL)' HAVE_SRAM_IF '$(HAVE_SRAM_IF)' \
	  HAVE_SRAM_MACRO '$(HAVE_SRAM_MACRO)' SRAM_SIZE_KIB '$(SRAM_SIZE_KIB)' \
	  PDK_BEHAV '$(PDK_BEHAV)' HAVE_SVA '$(HAVE_SVA)' APU_ENABLE_P7 '$(APU_ENABLE_P7)' \
	  HAVE_HP '$(HAVE_HP)' HP_CONFIG '$(HP_CONFIG)' BUILD_RELEASE '$(BUILD_RELEASE)' \
	  JTAG_IDCODE '$(JTAG_IDCODE)' EXT_CLK_HZ '$(EXT_CLK_HZ)' AUD_CLK_HZ '$(AUD_CLK_HZ)' \
	  CLINT_TIMEBASE_HZ '$(CLINT_TIMEBASE_HZ)' MGMT_CPU_CLK_HZ '$(MGMT_CPU_CLK_HZ)' \
	  ISA '$(ISA)' HAVE_CSR '$(HAVE_CSR)' APP '$(APP)' \
	  LINK_TYPE '$(LINK_TYPE)' COREMARK_MODE '$(COREMARK_MODE)'

doctor:
	@python3 $(ROOT_PATH)/scripts/doctor.py \
	  --root $(ROOT_PATH) --simu $(SIMU) --synth $(SYNTH) --sta $(STA) \
	  --pdk $(PDK) --have-sram-macro $(HAVE_SRAM_MACRO) \
	  --formal $(FORMAL) --lock $(LOCK_FILE)

benchmark-report: firmware

	$(MAKE) RTL_SIM_TIMEOUT=$(RTL_SIM_TIMEOUT) sim
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/parse_performance_log.py --log $(PERF_LOG) \
		--output $(META_DIR)/performance.json

coremark-report: firmware

	$(MAKE) RTL_SIM_TIMEOUT=$(RTL_SIM_TIMEOUT) sim
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/parse_coremark_log.py --log $(PERF_LOG) \
		--output $(META_DIR)/coremark.json

hp-performance-check:
	@test -n '$(LP_COREMARK_REPORT)' -a -n '$(HP_COREMARK_REPORT)' || { \
		echo 'LP_COREMARK_REPORT and HP_COREMARK_REPORT are required' >&2; exit 1; }
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/check_lp_hp_performance.py \
		--lp $(LP_COREMARK_REPORT) --hp $(HP_COREMARK_REPORT) \
		--minimum-ratio $(HP_PERF_MIN_RATIO) --output $(META_DIR)/lp-hp-performance.json

setup: setup-mpw setup-vexiiriscv setup-clusterip setup-ip setup-pdk setup-app

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

setup-vexiiriscv:
	python3 $(ROOT_PATH)/scripts/setup_vexiiriscv.py

setup-clusterip:
	python3 $(ROOT_PATH)/rtl/managed/clusterip/setup.py

setup-ip:
	python3 $(ROOT_PATH)/rtl/ip/setup.py

setup-pdk:
	python3 $(ROOT_PATH)/physical/pdk/setup.py --pdk $(PDK)

setup-app:
	python3 $(ROOT_PATH)/app/setup.py

setup-apu-reference:
	python3 $(ROOT_PATH)/scripts/setup_apu_reference.py --build-dir $(APU_P5_REFERENCE_DIR)

setup-apu-kws-reference:
	python3 $(ROOT_PATH)/scripts/setup_apu_reference.py --target p7 --build-dir $(APU_P7_DIR)

setup-npu-reference:
	python3 $(ROOT_PATH)/scripts/setup_npu_reference.py --build-dir $(NPU_P0_DIR)

.PHONY: setup-npu-reference npu-p0-qualify
npu-p0-qualify: | manifest
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool npu-p0-qualification \
		--log $(NPU_P0_DIR)/qualification.log --result $(NPU_P0_DIR)/result-qualification.json \
		-- python3 $(ROOT_PATH)/scripts/qualify_npu_p0.py --output-dir $(NPU_P0_DIR) \
		--profile $(PROFILE_NAME) --config-digest $(CONFIG_DIGEST) --jobs $(JOBS)

NPU_P5_COMPILER_INPUTS := $(ROOT_PATH)/scripts/npu_compiler.py \
	$(ROOT_PATH)/scripts/npu_compiler_p0.py $(ROOT_PATH)/scripts/npu_model.py \
	$(ROOT_PATH)/scripts/npu_descriptors.py $(ROOT_PATH)/scripts/npu_reference.py
NPU_KWS_MODEL          := $(CACHE_ROOT)/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting/trained_models/kws_ref_model.tflite
NPU_VWW_MODEL          := $(CACHE_ROOT)/sources/apu-mlperf-tiny/benchmark/training/visual_wake_words/trained_models/vww_96_int8.tflite

$(NPU_P5_KWS_STAMP): $(NPU_P5_COMPILER_INPUTS) | setup-npu-reference
	python3 $(ROOT_PATH)/scripts/npu_compiler.py --model $(NPU_KWS_MODEL) --workload kws \
		--symbol-prefix kws --output-dir $(NPU_P5_KWS_DIR) \
		--expected-sha256 aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae \
		--preprocessing mfcc-49x10-int8
	@touch $@

$(NPU_P5_VWW_STAMP): $(NPU_P5_COMPILER_INPUTS) | setup-npu-reference
	python3 $(ROOT_PATH)/scripts/npu_compiler.py --model $(NPU_VWW_MODEL) --workload vww \
		--symbol-prefix vww --output-dir $(NPU_P5_VWW_DIR) \
		--expected-sha256 597a384c8c2c8a1276f04702f25013b7838f2f814f1ca7c174d295b73e3d6b7b \
		--preprocessing rgb96-u8-xor80
	@touch $@

$(NPU_P5_KWS_C): $(NPU_P5_KWS_STAMP)
$(NPU_P5_VWW_C): $(NPU_P5_VWW_STAMP)

$(NPU_P5_ACCEPTANCE_STAMP): $(NPU_P5_KWS_STAMP) \
	$(ROOT_PATH)/scripts/npu_acceptance_data.py $(ROOT_PATH)/scripts/npu_executor.py
	python3 $(ROOT_PATH)/scripts/npu_acceptance_data.py --output-dir $(NPU_P5_ACCEPTANCE_DIR)
	@touch $@

$(NPU_P5_ACCEPTANCE_C): $(NPU_P5_ACCEPTANCE_STAMP)

npu-p5-deployments: $(NPU_P5_KWS_STAMP) $(NPU_P5_VWW_STAMP) | manifest

npu-p6-corpus: npu-p0-qualify
	python3 $(ROOT_PATH)/scripts/npu_p6_corpus.py --p0-dir $(NPU_P0_DIR) \
		--output-dir $(NPU_P6_CORPUS_DIR) --cases-per-shard 100

npu-p6-formal: formal-npu-p6
	python3 $(ROOT_PATH)/scripts/npu_p6_formal_report.py --formal-dir $(FORMAL_DIR) \
		--output $(NPU_P6_FORMAL_REPORT)

npu-p6-netlist:
	python3 $(ROOT_PATH)/scripts/run_npu_p6_netlist.py \
		--output-dir $(NPU_P6_NETLIST_DIR) --timeout-seconds 7200 --jobs $(JOBS)

npu-p6-verilator: npu-p6-corpus
	python3 $(ROOT_PATH)/scripts/run_npu_p6_verilator.py \
		--corpus-report $(NPU_P6_CORPUS_DIR)/corpus-shards.json \
		--output-dir $(NPU_P6_PERF_DIR) --build-timestamp $(BUILD_TIMESTAMP) \
		--jobs $(JOBS) --timeout-seconds 86400 --sim-time 86400

npu-p6-physical: npu-p6-netlist
	python3 $(ROOT_PATH)/scripts/run_npu_p6_physical.py \
		--isolated-report $(NPU_P6_NETLIST_DIR)/qualification-p6-netlist.json \
		--output-dir $(NPU_P6_PHYS_DIR) --build-timestamp $(BUILD_TIMESTAMP)

npu-p6-regression:
	python3 $(ROOT_PATH)/scripts/run_npu_p6_regression.py \
		--output-dir $(NPU_P6_REGRESS_DIR) --build-timestamp $(BUILD_TIMESTAMP)

npu-p6-report: npu-p6-corpus npu-p6-formal npu-p6-verilator npu-p6-netlist \
	npu-p6-physical npu-p6-regression
	@test -n '$(NPU_P6_P0_REPORT)' -a -n '$(NPU_P6_P5_REPORT)' || { \
		echo 'NPU P6 requires explicit current-revision P0/P5 report paths' >&2; exit 1; }
	python3 $(ROOT_PATH)/scripts/npu_p6_report.py \
		--p0-report $(NPU_P6_P0_REPORT) --p5-report $(NPU_P6_P5_REPORT) \
		--corpus-report $(NPU_P6_CORPUS_DIR)/corpus-shards.json \
		--performance-report $(NPU_P6_PERF_REPORT) \
		--formal-report $(NPU_P6_FORMAL_REPORT) \
		--netlist-report $(NPU_P6_NETLIST_DIR)/qualification-p6-netlist.json \
		--physical-report $(NPU_P6_PHYS_REPORT) \
		--regression-report $(NPU_P6_REGRESS_REPORT) --output $(NPU_P6_REPORT)

npu-p6-qualify: npu-p6-report

npu-p5-rtl: npu-p5-deployments
	python3 $(ROOT_PATH)/scripts/qualify_npu_p5.py \
		--output-dir $(NPU_P5_DIR)/evidence/rtl --timeout-seconds 3600 --jobs 4 \
		--profile $(PROFILE_NAME) --config-digest $(CONFIG_DIGEST) --pdk $(PDK) \
		--lock $(LOCK_FILE)

npu-p5-c-quality:
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool npu-p5-c-quality \
		--log $(NPU_P5_DIR)/evidence/c-quality.log \
		--result $(NPU_P5_C_QUALITY_RESULT) \
		-- $(MAKE) sw-format-check sw-policy-check sw-host-test

npu-p5-host: npu-p5-deployments npu-p5-c-quality
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool npu-p5-host \
		--log $(NPU_P5_DIR)/evidence/host.log \
		--result $(NPU_P5_DIR)/evidence/result-host.json \
		-- python3 -m pytest -q $(ROOT_PATH)/tests/test_npu_compiler.py \
		$(ROOT_PATH)/tests/test_npu_executor.py $(ROOT_PATH)/tests/test_npu_register_parity.py

npu-p5-report:
	@test -n '$(NPU_P5_LP_VARIANT_ROOT)' -a -n '$(NPU_P5_HP_VARIANT_ROOT)' \
		-a -n '$(NPU_P5_LP_CONFIG_DIGEST)' -a -n '$(NPU_P5_HP_CONFIG_DIGEST)' || { \
		echo 'NPU P5 LP/HP variant roots and config digests are required' >&2; exit 1; }
	python3 $(ROOT_PATH)/scripts/npu_p5_report.py \
		--kws $(NPU_P5_KWS_DIR) --vww $(NPU_P5_VWW_DIR) \
		--host-result $(NPU_P5_DIR)/evidence/result-host.json \
		--c-quality-result $(NPU_P5_C_QUALITY_RESULT) \
		--p0-report $(NPU_P0_DIR)/qualification-p0.json \
		--rtl-report $(NPU_P5_DIR)/evidence/rtl/qualification-p5-rtl.json \
		--build-manifest $(META_DIR)/manifest.json --config-digest $(CONFIG_DIGEST) \
		--lp-result $(NPU_P5_LP_VARIANT_ROOT)/sim/verilator/result-sim.json \
		--lp-check $(NPU_P5_LP_VARIANT_ROOT)/sim/verilator/result-npu-p5-lp-sim-check.json \
		--lp-log $(NPU_P5_LP_VARIANT_ROOT)/sim/verilator/sim.log \
		--lp-manifest $(NPU_P5_LP_VARIANT_ROOT)/meta/manifest.json \
		--lp-config-digest $(NPU_P5_LP_CONFIG_DIGEST) \
		--lp-kws $(NPU_P5_LP_VARIANT_ROOT)/npu/p5/deployments/kws \
		--lp-firmware $(NPU_P5_LP_VARIANT_ROOT)/sw/retrosoc_fw.bin \
		--hp-result $(NPU_P5_HP_VARIANT_ROOT)/sim/verilator/result-sim.json \
		--hp-check $(NPU_P5_HP_VARIANT_ROOT)/sim/verilator/result-npu-p5-hp-sim-check.json \
		--hp-log $(NPU_P5_HP_VARIANT_ROOT)/sim/verilator/sim.log \
		--hp-manifest $(NPU_P5_HP_VARIANT_ROOT)/meta/manifest.json \
		--hp-config-digest $(NPU_P5_HP_CONFIG_DIGEST) \
		--hp-kws $(NPU_P5_HP_VARIANT_ROOT)/npu/p5/deployments/kws \
		--hp-firmware $(NPU_P5_HP_VARIANT_ROOT)/sw/retrosoc_hp_smoke.bin \
		--output $(NPU_P5_REPORT)

.PHONY: npu-p5-deployments npu-p5-c-quality npu-p5-host npu-p5-rtl npu-p5-report \
	npu-p5-lp-sim npu-p5-hp-sim npu-p6-corpus npu-p6-formal npu-p6-netlist \
	npu-p6-verilator npu-p6-physical npu-p6-regression npu-p6-report npu-p6-qualify

$(APU_P5_BUNDLE): $(ROOT_PATH)/scripts/build_apu_p5_bundle.py \
	$(ROOT_PATH)/scripts/generate_apu_p5_microcode.py \
	$(ROOT_PATH)/scripts/apu_p5_coefficients.py $(ROOT_PATH)/scripts/apu_mcasm.py \
	$(ROOT_PATH)/scripts/apu_isa.py $(ROOT_PATH)/rtl/ip/multimedia/apu_p5_codecs.apus
	python3 $(ROOT_PATH)/scripts/generate_apu_p5_microcode.py \
		--output $(ROOT_PATH)/rtl/ip/multimedia/apu_p5_codecs.apus --check
	python3 $(ROOT_PATH)/scripts/build_apu_p5_bundle.py --output-dir $(APU_P5_DIR)

apu-p5-bundle: $(APU_P5_BUNDLE)

$(APU_P7_MODEL): $(ROOT_PATH)/scripts/apu_kws_convert.py \
	$(ROOT_PATH)/scripts/apu_kws.py $(APU_P7_KWS_TFLITE)
	python3 $(ROOT_PATH)/scripts/apu_kws_convert.py --target p7 \
		--model $(APU_P7_KWS_TFLITE) --output $@ --manifest $(APU_P7_MODEL_MANIFEST)

apu-p7-model: $(APU_P7_MODEL)

$(APU_P9_APUC) $(APU_P9_LAYOUT_MANIFEST) &: $(APU_P7_MODEL) \
	$(ROOT_PATH)/scripts/generate_apu_kws_rtl_constants.py \
	$(ROOT_PATH)/scripts/apu_kws_coeff.py
	python3 $(ROOT_PATH)/scripts/generate_apu_kws_rtl_constants.py \
		--apum $(APU_P7_MODEL) \
		--output $(APU_P9_COEFFICIENT_DIR)/apu_kws_rom.svh \
		--profile-output $(APU_P9_COEFFICIENT_DIR)/apu_kws_apum_profile.svh \
		--apuc-output $(APU_P9_APUC) --manifest-output $(APU_P9_LAYOUT_MANIFEST)

apu-p9-coefficients: $(APU_P9_APUC) $(APU_P9_LAYOUT_MANIFEST)

$(APU_P9_EVIDENCE_LAYOUT): $(APU_P9_LAYOUT_MANIFEST) $(APU_P9_APUC) \
	$(ROOT_PATH)/scripts/apu_p9_evidence.py
	python3 $(ROOT_PATH)/scripts/apu_p9_evidence.py initialize \
		--layout $(APU_P9_LAYOUT_MANIFEST) --apuc $(APU_P9_APUC) \
		--profile $(CONFIG) \
		--output-dir $(APU_P9_EVIDENCE_DIR)

apu-p9-evidence: $(APU_P9_EVIDENCE_LAYOUT)

apu-p9-memory-ab:
	@test -n '$(APU_P9_BASELINE_ROOT)' -a -n '$(APU_P9_CANDIDATE_ROOT)'
	python3 $(ROOT_PATH)/scripts/apu_p9_memory_ab.py \
		--baseline-root $(APU_P9_BASELINE_ROOT) --candidate-root $(APU_P9_CANDIDATE_ROOT) \
		--output $(APU_P9_EVIDENCE_DIR)/memory-synthesis-ab.json

apu-p5-corpus: setup-apu-reference $(APU_P5_BUNDLE)
	python3 $(ROOT_PATH)/scripts/qualify_apu_p5_corpus.py \
		--flac $(APU_P5_REFERENCE_DIR)/src/flac/flac \
		--corpus $(ROOT_PATH)/.cache/retrosoc/sources/apu-flac-corpus \
		--output $(APU_P5_CORPUS_MANIFEST)
	python3 $(ROOT_PATH)/scripts/run_apu_p5_corpus_rtl.py \
		--manifest $(APU_P5_CORPUS_MANIFEST) --bundle $(APU_P5_BUNDLE) \
		--corpus $(ROOT_PATH)/.cache/retrosoc/sources/apu-flac-corpus \
		--build-dir $(APU_P5_CORPUS_RTL_DIR) --output $(APU_P5_CORPUS_MANIFEST) \
		--jobs $(JOBS) --timeout-seconds 86400

setup-hp-linux:
	python3 $(ROOT_PATH)/scripts/setup_hp_linux.py

$(HP_LINUX_STAMP): $(ROOT_PATH)/scripts/build_hp_linux.py \
	$(ROOT_PATH)/app/ports/linux/configs/retrosoc_hp_defconfig \
	$(ROOT_PATH)/app/ports/linux/busybox/retrosoc_hp.config \
	$(ROOT_PATH)/app/ports/linux/linux/retrosoc_hp.config \
	$(ROOT_PATH)/app/ports/linux/linux/retrosoc_hp.dts \
	$(ROOT_PATH)/app/ports/linux/opensbi/retrosoc_hp/Kconfig \
	$(ROOT_PATH)/app/ports/linux/opensbi/retrosoc_hp/configs/defconfig \
	$(ROOT_PATH)/app/ports/linux/opensbi/retrosoc_hp/objects.mk \
	$(ROOT_PATH)/app/ports/linux/opensbi/retrosoc_hp/platform.c \
	$(ROOT_PATH)/app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp
	@test '$(HAVE_HP)' = YES
	python3 $(ROOT_PATH)/scripts/build_hp_linux.py --root $(ROOT_PATH) \
		--buildroot $(HP_BUILDRT_ROOT) --linux $(HP_LINUX_ROOT) --opensbi $(HP_OPENSBI_ROOT) \
		--output $(HP_LINUX_BUILD_DIR) --jobs $(JOBS)
	@touch $@

hp-linux: $(HP_LINUX_STAMP)

$(HP_BOOT_BUNDLE_BIN): $(FIRMWARE_ELF) $(HP_LINUX_STAMP) \
	$(ROOT_PATH)/scripts/package_hp_boot.py
	python3 $(ROOT_PATH)/scripts/package_hp_boot.py \
		--firmware $(SW_BUILD_DIR)/$(FIRMWARE_NAME).bin \
		--images $(HP_LINUX_BUILD_DIR)/images --output $@ \
		--manifest $(HP_BOOT_BUNDLE_MANIFEST)

$(HP_BOOT_BUNDLE_HEX): $(HP_BOOT_BUNDLE_BIN)
	$(OBJC) -I binary -O verilog $< $@

hp-bundle: $(HP_BOOT_BUNDLE_BIN) $(HP_BOOT_BUNDLE_HEX)

hp-linux-sim: hp-bundle comp
	@test '$(SIMU)' = VERILATOR
	$(MAKE) BUILD_TIMESTAMP=$(BUILD_TIMESTAMP) SIM_FIRMWARE_NAME=$(HP_BOOT_BUNDLE_NAME) \
		SOC_SIM_TIME=$(HP_LINUX_SIM_TIME) VERILATOR_SIM_ARGS=--fast-flash sim
	python3 $(ROOT_PATH)/scripts/check_simulation.py \
		--log $(SIM_BUILD_ROOT)/sim.log \
		--result $(SIM_BUILD_ROOT)/result-hp-linux-sim-check.json \
		--require 'VERILATOR_FAST_FLASH=enabled' \
		--require 'retroSoC HP Linux ready' \
		--require 'HP_LINUX_READY' \
		--require 'SIM_TEST_PASS code=0'

HP_SMOKE_NPU_DEPS :=
HP_SMOKE_NPU_ARGS :=
ifeq ($(NPU_P5_ACCEPTANCE),YES)
HP_SMOKE_NPU_DEPS += $(NPU_P5_KWS_C) $(NPU_P5_ACCEPTANCE_C) \
	$(ROOT_PATH)/app/ports/linux/smoke/npu_acceptance.c $(ROOT_PATH)/crt/src/hal/npu.c
HP_SMOKE_NPU_ARGS += --define=-DRS_NPU_P5_ACCEPTANCE \
	--extra-source $(ROOT_PATH)/app/ports/linux/smoke/npu_acceptance.c \
	--extra-source $(ROOT_PATH)/crt/src/hal/npu.c \
	--extra-source $(NPU_P5_KWS_C) --extra-source $(NPU_P5_ACCEPTANCE_C) \
	--include $(ROOT_PATH)/crt/include --include $(MEMORY_MAP_C_DIR) \
	--include $(USER_EXTENSIONS_DIR)/include --include $(SOC_TOPOLOGY_INCLUDE_DIR) \
	--include $(NPU_P5_KWS_DIR) --include $(NPU_P5_ACCEPTANCE_DIR)
endif
ifeq ($(NPU_P6_ACCEPTANCE),YES)
NPU_P6_MODEL_DIR       := $(if $(filter kws,$(NPU_P6_WORKLOAD)),$(NPU_P5_KWS_DIR),$(NPU_P5_VWW_DIR))
NPU_P6_MODEL_C         := $(if $(filter kws,$(NPU_P6_WORKLOAD)),$(NPU_P5_KWS_C),$(NPU_P5_VWW_C))
NPU_P6_WORKLOAD_DEFINE := $(if $(filter kws,$(NPU_P6_WORKLOAD)),RS_NPU_P6_WORKLOAD_KWS,RS_NPU_P6_WORKLOAD_VWW)
HP_SMOKE_NPU_DEPS      += $(NPU_P6_MODEL_C) \
	$(ROOT_PATH)/app/benchmark/npu/npu_p6_reference.c \
	$(ROOT_PATH)/app/benchmark/npu/npu_p6_reference.h \
	$(ROOT_PATH)/app/benchmark/npu/npu_p6_runner.c \
	$(ROOT_PATH)/app/benchmark/npu/npu_p6_runner.h $(ROOT_PATH)/crt/src/hal/npu.c \
	$(ROOT_PATH)/crt/src/hal/ga2d.c $(ROOT_PATH)/crt/src/hal/ga2d_math.c
HP_SMOKE_NPU_ARGS      += --define=-DRS_NPU_P6_ACCEPTANCE \
	--define=-DRS_NPU_PLAN_TEST --define=-D$(NPU_P6_WORKLOAD_DEFINE) \
	--extra-source $(ROOT_PATH)/app/benchmark/npu/npu_p6_runner.c \
	--extra-source $(ROOT_PATH)/app/benchmark/npu/npu_p6_reference.c \
	--extra-source $(ROOT_PATH)/crt/src/hal/npu.c \
	--extra-source $(ROOT_PATH)/crt/src/hal/ga2d.c \
	--extra-source $(ROOT_PATH)/crt/src/hal/ga2d_math.c --extra-source $(NPU_P6_MODEL_C) \
	--include $(ROOT_PATH)/crt/include --include $(MEMORY_MAP_C_DIR) \
	--include $(USER_EXTENSIONS_DIR)/include --include $(SOC_TOPOLOGY_INCLUDE_DIR) \
	--include $(ROOT_PATH)/app/benchmark/npu --include $(NPU_P6_MODEL_DIR)
endif

$(HP_SMOKE_STAMP): $(ROOT_PATH)/scripts/build_hp_smoke.py \
	$(ROOT_PATH)/app/ports/linux/smoke/start.S \
	$(ROOT_PATH)/app/ports/linux/smoke/linker.ld $(HP_SMOKE_NPU_DEPS) \
	$(MEMORY_MAP_STAMP) $(USER_EXTENSIONS_STAMP) $(SOC_TOPOLOGY_STAMP)
	python3 $(ROOT_PATH)/scripts/build_hp_smoke.py \
		--source $(ROOT_PATH)/app/ports/linux/smoke/start.S \
		--linker $(ROOT_PATH)/app/ports/linux/smoke/linker.ld \
		--output $(HP_SMOKE_BUILD_DIR) --cross $(CROSS) $(HP_SMOKE_NPU_ARGS)
	@touch $@

$(HP_SMOKE_BUNDLE_BIN): $(FIRMWARE_ELF) $(HP_SMOKE_STAMP) \
	$(ROOT_PATH)/scripts/package_hp_boot.py
	python3 $(ROOT_PATH)/scripts/package_hp_boot.py \
		--firmware $(SW_BUILD_DIR)/$(FIRMWARE_NAME).bin \
		--images $(HP_SMOKE_BUILD_DIR)/images --output $@ \
		--manifest $(HP_SMOKE_MANIFEST)

$(HP_SMOKE_BUNDLE_HEX): $(HP_SMOKE_BUNDLE_BIN)
	$(OBJC) -I binary -O verilog $< $@

hp-smoke-bundle: $(HP_SMOKE_BUNDLE_BIN) $(HP_SMOKE_BUNDLE_HEX)

hp-smoke-sim: hp-smoke-bundle comp
	@test '$(SIMU)' = VERILATOR
	$(MAKE) BUILD_TIMESTAMP=$(BUILD_TIMESTAMP) SIM_FIRMWARE_NAME=$(HP_SMOKE_BUNDLE_NAME) \
		SOC_SIM_TIME=$(HP_SMOKE_SIM_TIME) VERILATOR_SIM_ARGS=--fast-flash sim
	python3 $(ROOT_PATH)/scripts/check_simulation.py \
		--log $(SIM_BUILD_ROOT)/sim.log \
		--result $(SIM_BUILD_ROOT)/result-hp-smoke-sim-check.json \
		--require 'SIM_TEST_PASS code=0' \
		--require 'HP_LINUX_READY' \
		--require 'HP_GA2D_PASS' \
		--require 'HP_GA2D_CACHE_CLEAN'
$(HP_APU_STAMP): $(ROOT_PATH)/scripts/build_hp_apu.py \
	$(ROOT_PATH)/app/ports/hp-apu/start.S \
	$(ROOT_PATH)/app/ports/hp-apu/main.c \
	$(ROOT_PATH)/app/ports/hp-apu/linker.ld \
	$(ROOT_PATH)/app/apps/apu_release/apu_release_page.h \
	$(ROOT_PATH)/crt/include/retrosoc/hal/apu_regs.h \
	$(MEMORY_MAP_STAMP) $(USER_EXTENSIONS_STAMP)
	python3 $(ROOT_PATH)/scripts/build_hp_apu.py \
		--source-dir $(ROOT_PATH)/app/ports/hp-apu \
		--output $(HP_APU_BUILD_DIR) --cross $(CROSS) \
		--include $(MEMORY_MAP_C_DIR) \
		--include $(USER_EXTENSIONS_DIR)/include \
		--include $(ROOT_PATH)/crt/include \
		--include $(ROOT_PATH)/app/apps/apu_release
	@touch $@

$(HP_APU_BUNDLE_BIN): $(FIRMWARE_ELF) $(HP_APU_STAMP) \
	$(ROOT_PATH)/scripts/package_hp_boot.py
	python3 $(ROOT_PATH)/scripts/package_hp_boot.py \
		--firmware $(SW_BUILD_DIR)/$(FIRMWARE_NAME).bin \
		--images $(HP_APU_BUILD_DIR)/images --output $@ \
		--manifest $(HP_APU_MANIFEST)

$(HP_APU_BUNDLE_HEX): $(HP_APU_BUNDLE_BIN)
	$(OBJC) -I binary -O verilog $< $@

hp-apu-bundle: $(HP_APU_BUNDLE_BIN) $(HP_APU_BUNDLE_HEX)

hp-apu-sim: hp-apu-bundle comp
	@test '$(SIMU)' = VERILATOR
	$(MAKE) BUILD_TIMESTAMP=$(BUILD_TIMESTAMP) SIM_FIRMWARE_NAME=$(HP_APU_BUNDLE_NAME) \
		VERILATOR_SIM_ARGS=--fast-flash sim
	python3 $(ROOT_PATH)/scripts/check_simulation.py \
		--log $(SIM_BUILD_ROOT)/sim.log \
		--result $(SIM_BUILD_ROOT)/result-hp-apu-sim-check.json \
		--require 'VERILATOR_FAST_FLASH=enabled' \
		--require 'APU_RELEASE_PASS' \
		--require 'SIM_TEST_PASS code=0'

npu-p5-hp-sim: hp-smoke-sim
	@test '$(NPU_P5_ACCEPTANCE)' = YES
	python3 $(ROOT_PATH)/scripts/check_simulation.py \
		--log $(SIM_BUILD_ROOT)/sim.log \
		--result $(SIM_BUILD_ROOT)/result-npu-p5-hp-sim-check.json \
		--require 'HP_NPU_PASS' --require 'SIM_TEST_PASS code=0'

npu-p5-lp-sim: firmware sim
	@test '$(APP)' = ci_smoke -a '$(NPU_P5_ACCEPTANCE)' = YES -a '$(HAVE_CSR)' = YES
	python3 $(ROOT_PATH)/scripts/check_simulation.py \
		--log $(SIM_BUILD_ROOT)/sim.log \
		--result $(SIM_BUILD_ROOT)/result-npu-p5-lp-sim-check.json \
		--require 'NPU_P5_LP model=kws' --require 'SIM_TEST_PASS code=0'

ifeq ($(HAVE_HP),YES)
$(HP_GENERATED_STAMP): $(ROOT_PATH)/scripts/generate_vexiiriscv.py \
	$(ROOT_PATH)/scripts/vexiiriscv/GenerateRetroSocHp.scala $(LOCK_FILE)
	python3 $(ROOT_PATH)/scripts/generate_vexiiriscv.py \
		--root $(ROOT_PATH) --source $(VEXIIRISCV_ROOT) --output $(HP_GENERATED_DIR) \
		--manifest $(HP_GENERATED_MANIFEST) --lock $(LOCK_FILE) --sbt $(SBT)
	@touch $@

vexii-generate: $(HP_GENERATED_STAMP)
else
vexii-generate:
	@printf '%s\n' 'HAVE_HP=NO; no VexiiRiscv RTL is required'
endif

clean-all:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(abspath $(BUILD_ROOT))

purge-cache:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(abspath $(CACHE_ROOT))

manifest:
	$(FLOW_PYTHON) $(ROOT_PATH)/scripts/manifest.py create --root $(ROOT_PATH) \
	  --lock $(LOCK_FILE) --output $(META_DIR)/manifest.json --profile $(PROFILE_NAME) \
	  $(foreach var,$(CONFIG_KEY_VARS),--config $(var)=$($(var))) \
	  --config SIMU=$(SIMU) --config SYNTH=$(SYNTH) --config SYNTH_RECIPE=$(SYNTH_RECIPE) \
	  --config STA=$(STA)

check-warnings:
	python3 $(ROOT_PATH)/scripts/analyze_warnings.py check --root $(ROOT_PATH) \
	  --profile $(PROFILE_NAME) --variant-root $(VARIANT_ROOT) --output $(META_DIR)/warnings.json

metrics:
	python3 $(ROOT_PATH)/scripts/metrics.py collect --variant-root $(VARIANT_ROOT) \
	  --synth-root $(SYN_BUILD_ROOT) --sta-root $(STA_BUILD_ROOT) \
	  --recipe $(SYNTH_RECIPE) --output $(METRICS_OUTPUT)

check-metrics: metrics
	python3 $(ROOT_PATH)/scripts/metrics.py check --metrics $(METRICS_OUTPUT) \
	  --policy $(ROOT_PATH)/quality/metrics/policy.json \
	  --baseline $(ROOT_PATH)/quality/metrics/baseline.json

sw-format:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) \
	  --apply-format --clang-format $(CLANG_FORMAT)

sw-format-check:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) --format-check \
	  --clang-format-check --clang-format $(CLANG_FORMAT)

format: sw-format mk-format rtl-format

format-check: sw-format-check mk-format-check rtl-format-check rtl-style-check

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

rtl-migrate-connections:
	python3 $(ROOT_PATH)/scripts/migrate_rtl_connections.py --root $(ROOT_PATH) --apply

rtl-migrate-names:
	python3 $(ROOT_PATH)/scripts/migrate_rtl_names.py --root $(ROOT_PATH) --apply

rtl-style-check:
	python3 $(ROOT_PATH)/scripts/check_rtl_style.py --root $(ROOT_PATH) \
	  --profile owned --changed-only --enforce-naming --verible-verilog-lint $(VERIBLE_LINT)

rtl-style-check-all:
	python3 $(ROOT_PATH)/scripts/check_rtl_style.py --root $(ROOT_PATH) \
	  --profile owned --enforce-naming --audit $(ROOT_PATH)/rtl/rtl_style_audit.json \
	  --verible-verilog-lint $(VERIBLE_LINT)

rtl-readiness-check:
	python3 $(ROOT_PATH)/scripts/check_rtl_readiness.py --root $(ROOT_PATH)

rtl-readiness-check-all: rtl-readiness-check

sw-policy-check:
	python3 $(ROOT_PATH)/scripts/check_embedded_c.py --root $(ROOT_PATH) --policy-check

sw-host-test:
	python3 $(ROOT_PATH)/scripts/run_c_tests.py --root $(ROOT_PATH) --cc $(HOST_CC)

package: $(MPW_VARIANT_DEP) $(FILELIST_STAMP) manifest
	python3 $(ROOT_PATH)/scripts/package.py --root $(ROOT_PATH) --lock $(LOCK_FILE) \
	  --variant-root $(VARIANT_ROOT) --output-dir $(ROOT_PATH)/dist/$(VARIANT_ID)

commercial-package: $(MPW_VARIANT_DEP) $(FILELIST_STAMP) manifest
	@test '$(PDK)' = ICS55
	@test '$(HAVE_PLL)' = YES
	@test '$(HAVE_SRAM_IF)' = YES
	@test '$(HAVE_SRAM_MACRO)' = YES
	python3 $(ROOT_PATH)/scripts/package.py --root $(ROOT_PATH) --lock $(LOCK_FILE) \
	  --variant-root $(VARIANT_ROOT) --output-dir $(VARIANT_ROOT)/commercial/input

regress-smoke:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite smoke --pdk IHP130

regress-rtl:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite rtl --pdk IHP130

regress-pr:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk IHP130 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk GF180 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk SKY130 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite pr --pdk ICS55 $(if $(filter YES,$(REGRESS_NETSIM_BOOT_ONLY)),--netsim-boot-only)

regress-nightly:
	python3 $(ROOT_PATH)/scripts/regress.py --root $(ROOT_PATH) --suite nightly

sim-asm: asm
	$(MAKE) SIM_FIRMWARE_NAME=$(ASM_FIRMWARE_NAME) sim
