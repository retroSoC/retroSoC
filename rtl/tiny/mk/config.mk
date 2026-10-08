# Both Tiny integrations remain SAFE24; PLL presence is not SYS selection.
ifneq ($(MINI_MODE),NONE)
$(error SOC=TINY requires MINI_MODE=NONE)
endif
ifeq ($(filter $(PDK),IHP130 ICS55),)
$(error SOC=TINY supports only PDK=IHP130 or ICS55)
endif
ifneq ($(HAVE_HP),NO)
$(error SOC=TINY requires HAVE_HP=NO)
endif
ifeq ($(PDK),ICS55)
ifneq ($(HAVE_PLL),YES)
$(error SOC=TINY PDK=ICS55 requires HAVE_PLL=YES with the PLL held off)
endif
ifeq ($(PDK_BEHAV),YES)
$(error SOC=TINY PDK=ICS55 requires the locked technology models, PDK_BEHAV=NO)
endif
override TINY_SAFE24_PLL_OFF := YES
else
ifneq ($(HAVE_PLL),NO)
$(error SOC=TINY PDK=IHP130 requires HAVE_PLL=NO)
endif
override TINY_SAFE24_PLL_OFF := NO
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
