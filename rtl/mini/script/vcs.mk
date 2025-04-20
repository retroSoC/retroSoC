NOVAS        := /nfs/tools/synopsys/verdi/V-2023.12-SP1-1/share/PLI/VCS/LINUX64
EXTRA        := -P $(NOVAS)/novas.tab $(NOVAS)/pli.a


SIM_TOOL     := bsub -Is vcs
SIM_BINY     := bsub -Is ./simv
VERDI_TOOL   := bsub -Is verdi

COMP_LOG     := -l compile.log
SIM_LOG      := -l sim.log

RTL_INC  := +incdir+../core/kianV \
            +incdir+../ip/native \
            +incdir+../../clusterip/common/rtl \
            +incdir+../../clusterip/common/rtl/cdc \
            +incdir+../../clusterip/common/rtl/clkrst \
            +incdir+../../clusterip/common/rtl/interface \
            +incdir+../../clusterip/common/rtl/tech \
            +incdir+../../clusterip/common/rtl/utils \
            +incdir+../../clusterip/archinfo/rtl \
            +incdir+../../clusterip/rng/rtl \
            +incdir+../../clusterip/uart/rtl \
            +incdir+../../clusterip/pwm/rtl \
            +incdir+../../clusterip/ps2/rtl \
            +incdir+../../clusterip/i2c/rtl \
            +incdir+../ip/3rd_party/spfs \
            +incdir+../ip/3rd_party/spfs_model

DEF_LIST    ?= +define+PDK_$(PDK)
DEF_LIST    += +define+CORE_$(CORE)

ifeq ($(HAVE_PLL), YES)
    DEF_LIST += +define+HAVE_PLL
endif

ifeq ($(HAVE_SRAM), YES)
    DEF_LIST += +define+HAVE_SRAM
endif

ifeq ($(HAVE_SVA), NO)
    DEF_LIST += +define+SV_ASSRT_DISABLE
endif

ifeq ($(PDK), IHP130)
    RTL_FLIST := -f ../filelist/pdk_ihp130.fl
else ifeq ($(PDK), S110)
    RTL_FLIST := -f ../filelist/pdk_s110.fl
endif

ifeq ($(CORE), PICORV32)
    RTL_FLIST += -f ../filelist/core_picorv32.fl
else ifeq ($(CORE), KIANV)
    RTL_FLIST += -f ../filelist/core_kianv.fl
endif

RTL_FLIST += -f ../filelist/top.fl \
             -f ../filelist/ip.fl \
             -f ../filelist/tech.fl

TB_FLIST  := -f ../filelist/tb.fl

## vcs option
# -debug_region=cell+lib
SIM_OPTIONS := -full64 +v2k -sverilog -timescale=1ns/10ps \
                $(EXTRA) \
                -kdb \
                -debug_access+all \
                +vcs+loopreport+10000 \
                +error+500 \
                +vcs+flush+all \
                +lint=TFIPC-L \
                $(DEF_LIST) \
                -xprop=../xprop_config \
                -work DEFAULT \
                $(RTL_INC)


TIME_OPTION := +notimingcheck +nospecify

POST_PATH := -v /nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic.v
SDF_FILE  := "/nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic_CTS_MIN.sdf.gz"

POST_SIM_OPTION := -sdf min:retrosoc_tb.u_retrosoc_asic:$(SDF_FILE) \
                   +delay_mode_path \
                   +sdfverbose \
                   +neg_tchk \
                   -negdelay \
                   +optconfigfile+./disable_timing_checklist \
                   -diag=sdf:verbose \
                   +warn=OPD:10,IWNF:10,SDFCOM_UHICD:10,SDFCOM_ANICD:10,SDFCOM_NICD:10,DRTZ:10,SDFCOM_UHICD:10,SDFCOM_NTCDTL:10