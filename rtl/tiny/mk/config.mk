# Tiny always boots from normalized SAFE24. Dynamic selection is RCU-owned.
override TINY_R2_P7 := YES
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
$(error SOC=TINY PDK=ICS55 requires HAVE_PLL=YES)
endif
ifeq ($(PDK_BEHAV),YES)
$(error SOC=TINY PDK=ICS55 requires the locked technology models, PDK_BEHAV=NO)
endif
override TINY_SAFE24_PLL_OFF := NO
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
ifeq ($(filter $(EXT_CLK_HZ),24000000 48000000 96000000),)
$(error SOC=TINY requires external XIN of 24, 48 or 96 MHz)
endif
ifeq ($(HAVE_PLL),YES)
ifneq ($(EXT_CLK_HZ),24000000)
$(error SOC=TINY with PLL requires EXT_CLK_HZ=24000000)
endif
endif
ifneq ($(AUD_CLK_HZ),24000000)
$(error SOC=TINY RTC and watchdog use normalized REF24)
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
ifeq ($(filter $(LINK_TYPE),ld2_all_sram ld2_tiny_banked),)
$(error SOC=TINY requires LINK_TYPE=ld2_all_sram or ld2_tiny_banked)
endif
ifneq ($(HAVE_CSR),YES)
$(error SOC=TINY requires HAVE_CSR=YES)
endif
ifneq ($(ISA),RV32IM)
$(error SOC=TINY firmware uses ISA=RV32IM)
endif
ifneq ($(WS2812_P3_ACCEPTANCE),NO)
$(error SOC=TINY uses its integrated P6 acceptance, not the Mini WS2812 P3 image)
endif
ifneq ($(filter YES,$(APU_ENABLE_P7) $(NPU_P5_ACCEPTANCE) $(NPU_P6_ACCEPTANCE)),)
$(error SOC=TINY does not include multimedia accelerators)
endif