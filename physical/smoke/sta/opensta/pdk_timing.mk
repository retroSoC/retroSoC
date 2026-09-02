# PDK-specific Liberty inputs for the reproducible core-STA baseline.

ifeq ($(PDK),IHP130)
OPENSTA_LIBERTY       := $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_slow_1p08V_125C.lib
OPENSTA_LINK_LIBS     := $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/lib/sg13g2_io_slow_1p08V_3p0V_125C.lib
IHP130_USB2_SRAM_LIBS := \
    $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_4096x16_c3_bm_bist_slow_1p08V_125C.lib \
    $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/lib/RM_IHPSG13_1P_4096x8_c3_bm_bist_slow_1p08V_125C.lib
ifeq ($(HAVE_SRAM_MACRO),YES)
OPENSTA_SRAM_LIBS := $(wildcard $(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/lib/*_slow_1p08V_125C.lib)
else
OPENSTA_SRAM_LIBS := $(IHP130_USB2_SRAM_LIBS)
endif
else ifeq ($(PDK),GF180)
OPENSTA_LIBERTY   := $(ROOT_PATH)/.cache/retrosoc/pdk/gf180/gf180mcu_fd_sc_mcu7t5v0__ss_125C_4v50.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/.cache/retrosoc/pdk/gf180/gf180mcu_fd_io_retrosoc__ss_125C_4v50.lib
ifeq ($(HAVE_SRAM_MACRO),YES)
OPENSTA_SRAM_LIBS := $(ROOT_PATH)/physical/pdk/gf180mcu-pdk/macros/gf180mcu_fd_ip_sram/latest/cells/gf180mcu_fd_ip_sram__sram512x8m8wm1/gf180mcu_fd_ip_sram__sram512x8m8wm1__ss_125C_4v50.lib
endif
else ifeq ($(PDK),SKY130)
OPENSTA_LIBERTY   := $(ROOT_PATH)/.cache/retrosoc/pdk/sky130/sky130_fd_sc_hd__ss_100C_1v40.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/physical/smoke/sta/opensta/sky130_io_blackbox.liberty
ifeq ($(HAVE_SRAM_MACRO),YES)
OPENSTA_SRAM_LIBS := $(ROOT_PATH)/.cache/retrosoc/pdk/sky130/openram/sky130_sram_4kbyte_1rw_32x1024_8_SS_1p4V_100C.lib
endif
else ifeq ($(PDK),ICS55)
OPENSTA_LIBERTY   := $(ROOT_PATH)/.cache/retrosoc/pdk/ics55/ics55_h7cr_ss.lib
OPENSTA_LINK_LIBS := $(ROOT_PATH)/physical/pdk/icsprout55-pdk/IP/IO/ICsprout_55LLULP1233_IO_251013/liberty/ICSIOA_N55_3P3_ss_1p08_2p97_125c.lib
else
$(error OpenSTA core-STA does not support PDK=$(PDK))
endif

OPENSTA_SRAM_LIBS ?=