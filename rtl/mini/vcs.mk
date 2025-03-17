NOVAS        := /nfs/tools/synopsys/verdi/V-2023.12-SP1-1/share/PLI/VCS/LINUX64
EXTRA        := -P ${NOVAS}/novas.tab ${NOVAS}/pli.a


SIM_TOOL     := bsub -Is vcs
SIM_BINY     := bsub -Is ./simv
VERDI_TOOL   := bsub -Is verdi

COMP_LOG     := -l compile.log
SIM_LOG      := -l sim.log

RTL_INC  := +incdir+../ip \
            +incdir+../ip/cust/spfs \
            +incdir+../ip/cust/spfs_model


RTL_FLIST := -f ../filelist/soc.fl \
             -f ../filelist/ip.fl \
             -f ../filelist/tech.fl \
             -f ../filelist/pdk_s110.fl

TB_FLIST  := -f ../filelist/tb.fl
            

## vcs option
# -debug_region=cell+lib
SIM_OPTIONS := -full64 +v2k -sverilog -timescale=1ns/10ps \
                ${EXTRA} \
                -kdb \
                -debug_access+all \
                +vcs+loopreport+1000 \
                +error+500 \
                +vcs+flush+all \
                +lint=TFIPC-L \
                +define+no_warning \
                +define+S50 \
                +define+SVA_OFF \
                -xprop=../xprop_config \
                -work DEFAULT \
                +define+RANDOMIZE_REG_INIT \
                ${RTL_INC} \


TIME_OPTION := +notimingcheck \
               +nospecify \

POST_PATH := -v /nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic.v
SDF_FILE  := "/nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic_CTS_MIN.sdf.gz"

POST_SIM_OPTION := -sdf min:retrosoc_tb.u_retrosoc_asic:${SDF_FILE} \
                   +delay_mode_path \
                   +sdfverbose \
                   +neg_tchk \
                   -negdelay \
                   +optconfigfile+./disable_timing_checklist \
                   -diag=sdf:verbose \
                   +warn=OPD:10,IWNF:10,SDFCOM_UHICD:10,SDFCOM_ANICD:10,SDFCOM_NICD:10,DRTZ:10,SDFCOM_UHICD:10,SDFCOM_NTCDTL:10 \