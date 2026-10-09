# R2-P3 software experiment only: external SAFE24, no hardware acceleration changes.
include $(dir $(lastword $(MAKEFILE_LIST)))../ci/ics55-tiny.mk
AUD_CLK_HZ     := 24000000
SW_ISA_PROFILE := TINY_PERF
SW_OPT         := O2
SW_LTO         := NO