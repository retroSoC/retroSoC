# Tiny's first qualified integration is deliberately a fixed MCU profile.
ifneq ($(MINI_MODE),NONE)
$(error SOC=TINY requires MINI_MODE=NONE)
endif
ifneq ($(PDK),IHP130)
$(error SOC=TINY currently supports only PDK=IHP130)
endif
ifneq ($(HAVE_HP),NO)
$(error SOC=TINY requires HAVE_HP=NO)
endif
ifneq ($(HAVE_PLL),NO)
$(error SOC=TINY requires HAVE_PLL=NO)
endif
ifneq ($(HAVE_SRAM_IF),YES)
$(error SOC=TINY requires HAVE_SRAM_IF=YES)
endif
ifneq ($(HAVE_SRAM_MACRO),YES)
$(error SOC=TINY requires HAVE_SRAM_MACRO=YES)
endif
ifneq ($(SRAM_SIZE_KIB),128)
$(error SOC=TINY first release requires SRAM_SIZE_KIB=128)
endif
ifneq ($(EXT_CLK_HZ),24000000)
$(error SOC=TINY first release requires EXT_CLK_HZ=24000000)
endif
ifneq ($(AUD_CLK_HZ),$(EXT_CLK_HZ))
$(error SOC=TINY uses the system clock for RTC and watchdog)
endif
ifneq ($(CLINT_TIMEBASE_HZ),1000000)
$(error SOC=TINY requires CLINT_TIMEBASE_HZ=1000000)
endif
ifeq ($(filter $(SIMU),IVERILOG VERILATOR),)
$(error SOC=TINY supports SIMU=IVERILOG or VERILATOR)
endif
ifeq ($(filter $(APP),bringup ci_smoke),)
$(error SOC=TINY supports APP=bringup or ci_smoke)
endif
ifneq ($(LINK_TYPE),ld2_all_sram)
$(error SOC=TINY requires LINK_TYPE=ld2_all_sram)
endif
ifneq ($(HAVE_CSR),YES)
$(error SOC=TINY requires HAVE_CSR=YES)
endif
ifneq ($(ISA),RV32IM)
$(error SOC=TINY firmware uses ISA=RV32IM)
endif
ifneq ($(filter YES,$(APU_ENABLE_P7) $(NPU_P5_ACCEPTANCE) $(NPU_P6_ACCEPTANCE)),)
$(error SOC=TINY does not include multimedia accelerators)
endif