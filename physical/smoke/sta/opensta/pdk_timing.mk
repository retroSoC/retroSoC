# PDK-specific Liberty inputs for the reproducible core-STA baseline.

ifeq ($(PDK),IHP130)
OPENSTA_LIBERTY   := $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_slow_1p08V_125C.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/lib/sg13g2_io_slow_1p08V_3p0V_125C.lib
ifeq ($(HAVE_SRAM_MACRO),YES)
OPENSTA_SRAM_LIBS := $(wildcard $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/lib/*_slow_1p08V_125C.lib)
endif
else ifeq ($(PDK),GF180)
OPENSTA_LIBERTY   := $(ROOT_PATH)/.cache/retrosoc/pdk/gf180/gf180mcu_fd_sc_mcu7t5v0__ss_125C_4v50.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/.cache/retrosoc/pdk/gf180/gf180mcu_fd_io_retrosoc__ss_125C_4v50.lib
else ifeq ($(PDK),SKY130)
OPENSTA_LIBERTY   := $(ROOT_PATH)/.cache/retrosoc/pdk/sky130/sky130_fd_sc_hd__ss_100C_1v40.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/physical/smoke/sta/opensta/sky130_io_blackbox.liberty
else ifeq ($(PDK),ICS55)
OPENSTA_LIBERTY   := $(ROOT_PATH)/.cache/retrosoc/pdk/ics55/ics55_h7cr_ss.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/physical/pdk/icsprout55-pdk/IP/IO/ICsprout_55LLULP1233_IO_251013/liberty/ICSIOA_N55_3P3_ss_1p08_2p97_125c.lib
else
$(error OpenSTA core-STA does not support PDK=$(PDK))
endif

OPENSTA_SRAM_LIBS ?=