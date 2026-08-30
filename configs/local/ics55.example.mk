# Copy this file to configs/local/ics55.mk. The local copy and every absolute
# macro-model path remain ignored by Git.

include configs/cluster/ics55.mk

HAVE_PLL        := YES
HAVE_SRAM_IF    := YES
HAVE_SRAM_MACRO := YES
SRAM_SIZE_KIB   := 32
AUD_CLK_HZ      := 18432000

# Populate both paths from the local ICS_LIB declared by
# physical/commercial/local/ics55-production.mk. Keep the copied profile and
# any local PLL_TOP simulation adapter ignored by Git.
LOCAL_RTL_FILES := REQUIRED_SRAM_MODEL REQUIRED_PLL_MODEL