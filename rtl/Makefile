RTL_SIM_PLLEN :=
RTL_SIM_PLLCFG :=
SIM_TOOL :=

CROSS=riscv32-unknown-elf-
CFLAGS := -mabi=ilp32 \
          -march=rv32im \
          -Wl,-Bstatic,-T,retrosoc_sections.lds,--strip-debug \
          -ffreestanding \
          -nostdlib

VNOVAS    := /nfs/tools/synopsys/verdi/V-2023.12-SP1-1/share/PLI/VCS/LINUX64
VEXTRA    := -P ${VNOVAS}/novas.tab\
                ${VNOVAS}/pli.a


VPOST_PATH  := -v /nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic.v
SDF_FILE   := "/nfs/share/temp/flow_110/bes_data/sta/sdf/retrosoc_asic_CTS_MIN_CMIN_SDF_Mar_10_00/retrosoc_asic_CTS_MIN.sdf.gz"


VSIM_INC  := +incdir+./ip \
             +incdir+./ip/cust/spfs \
             +incdir+./ip/cust/spfs_model

## vcs option
VSIM_OPTIONS := -full64  +v2k -sverilog -timescale=1ns/10ps \
                ${VEXTRA} \
                -kdb \
                -debug_access+all \
                -debug_region=cell+lib \
                +error+500 \
                +vcs+flush+all \
                +lint=TFIPC-L \
                +define+no_warning \
                +define+S50 \
                +define+SVA_OFF \
                -xprop=xprop_config \
                -work DEFAULT \
                +define+RANDOMIZE_REG_INIT \
                ${VSIM_INC} \

VTIME_OPTION := +notimingcheck \
                +nospecify \

VPOST_SIM_OPTION := -sdf min:retrosoc_tb.u_retrosoc_asic:${SDF_FILE} \
                   +delay_mode_path \
                   +sdfverbose \
                   +neg_tchk \
                   -negdelay \
                   +optconfigfile+./disable_timing_checklist \
                   -diag=sdf:verbose \
                   +warn=OPD:10,IWNF:10,SDFCOM_UHICD:10,SDFCOM_ANICD:10,SDFCOM_NICD:10,DRTZ:10,SDFCOM_UHICD:10,SDFCOM_NTCDTL:10 \

# RTL code
WAVE := NONE
RTL_SOC := ./retrosoc_asic.v \
           ./retrosoc_asic_tiny.v \
           ./retrosoc.v \
           ./retrosoc_tiny.v \
           ./picorv32.v

RTL_IP := ./ip/spram_model.v \
      ./ip/spimemio.v \
      ./ip/simpleuart.v \
      ./ip/counter_timer.v \
      ./ip/spi_slave.v \
      ./ip/ravenna_spi.v \
      ./ip/spiflash.v \
      ./ip/rs232.v \
      ./ip/kdb_model.v \
      ./ip/psram_model.v \
      ./ip/rcu.v \
      ./ip/cust/spfs_model/N25Qxxx.v \
      ./ip/cust/register.v \
      ./ip/cust/lfsr.v \
      ./ip/cust/fifo.v \
      ./ip/cust/cdc_sync.v \
      ./ip/cust/clk_int_div.v \
      ./ip/cust/edge_det.v \
      ./ip/cust/rst_sync.v \
      ./ip/cust/archinfo.v \
      ./ip/cust/rng.v \
      ./ip/cust/uart.v \
      ./ip/cust/pwm.v \
      ./ip/cust/ps2.v \
      ./ip/cust/i2c.v \
      ./ip/cust/psram_core.v \
      ./ip/cust/psram.v \
      ./ip/cust/spfs/spi_clgen.v \
      ./ip/cust/spfs/spi_shift.v \
      ./ip/cust/spfs/spi_top.v \
      ./ip/cust/spfs/spi_flash.v \
      ./ip/cust/apb_spi_master/spi_master_apb_if.v \
      ./ip/cust/apb_spi_master/spi_master_clkgen.v \
      ./ip/cust/apb_spi_master/spi_master_controller.v \
      ./ip/cust/apb_spi_master/spi_master_fifo.v \
      ./ip/cust/apb_spi_master/spi_master_rx.v \
      ./ip/cust/apb_spi_master/spi_master_tx.v \
      ./ip/cust/apb_spi_master/apb_spi_master.v \
      ./ip/cust/axil2apb/flop.v \
      ./ip/cust/axil2apb/address_decoder.v \
      ./ip/cust/axil2apb/read_data_mux.v \
      ./ip/cust/axil2apb/apb_master.v \
      ./ip/cust/axil2apb/axi_apb_bridge.v \
      ./ip/axil_ip_wrapper.v \
      ./ip/axil_ip_wrapper_tiny.v

RTL_TECH := ../tech/tc_io.v \
            ../tech/tc_clk.v \
            ../tech/tc_pll.v \
            ../tech/tc_sram.v

# RTL_PDK := ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v \
#            ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v \
#            ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v \
#            ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_1024x64_c2_bm_bist.v

RTL_PDK := ../syn/S110/SP013D3WP_V1p7.v \
           ../syn/S110/scc011ums_hd_lvt.v \
           ../syn/S110/scc011ums_hd_rvt.v \
           ../syn/S110/S011HD1P_X256Y4D32_BW.v \
           ../syn/S110/S013PLLFN_V1.4.2.v

RTL_INC := -I./ip \
           -I./ip/cust/spfs \
           -I./ip/cust/spfs_model

# software
FIRMWARE_NAME := retrosoc_fw

SRC_PATH := ../crt/start.s \
            ../crt/tinyuart.c \
            ../crt/tinystring.c \
            ../crt/tinyprintf.c \
            ../crt/tinyflash.c \
            ../crt/tinygpio.c \
            ../crt/tinyhkspi.c \
            ../crt/tinytim.c \
            ../crt/tinyarchinfo.c \
            ../crt/tinyrng.c \
            ../crt/tinyhpuart.c \
            ../crt/tinypwm.c \
            ../crt/tinyps2.c \
            ../crt/tinyi2c.c \
            ../crt/tinylcd.c \
            ../crt/tinypsram.c \
            ../crt/tinybench.c \
            ../crt/tinysh.c \
            ../crt/firmware.c

LDS_PATH := ../crt/sections.lds
# +behv_wave
retrosim: retrosoc_tb.vvp $(FIRMWARE_NAME).elf
	ln -sf $(FIRMWARE_NAME).hex mem_Q128_bottom.vmf
	vvp -l run.log -N $< +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_$(SIM_TOOL) -fst

# +syn_wave
retrosynsim: retrosoc_syn_tb.vvp $(FIRMWARE_NAME).elf
	ln -sf $(FIRMWARE_NAME).hex mem_Q128_bottom.vmf
	vvp -l synrun.log -N $< +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +syn_$(WAVE) +sim_$(SIM_TOOL) -fst


retrosoc_tb.vvp:
	@mkdir -p build
	(iverilog -DFUNCTIONAL $(RTL_INC) -s retrosoc_tb -o $@ retrosoc_tb.v $(RTL_SOC) $(RTL_TECH) $(RTL_PDK) $(RTL_IP) || exit -1) 2>&1 | tee compile.log

retrosoc_syn_tb.vvp:
	@mkdir -p build
	(iverilog -DFUNCTIONAL $(RTL_INC) -s retrosoc_tb -o $@ retrosoc_tb.v ../syn/yosys/out/retrosoc_asic_yosys.v $(RTL_TECH) $(RTL_PDK) $(RTL_IP) || exit -1) 2>&1 | tee syncompile.log



######### tiny version
# +behv_wave
retrosimtiny: retrosoc_tb_tiny.vvp $(FIRMWARE_NAME).elf
	ln -sf $(FIRMWARE_NAME).hex mem_Q128_bottom.vmf
	vvp -l run.log -N $< +behv_$(WAVE) +sim_$(SIM_TOOL) -fst

# +syn_wave
retrosynsimtiny: retrosoc_syn_tb_tiny.vvp $(FIRMWARE_NAME).elf
	ln -sf $(FIRMWARE_NAME).hex mem_Q128_bottom.vmf
	vvp -l synrun.log -N $< +syn_$(WAVE) +sim_$(SIM_TOOL) -fst


retrosoc_tb_tiny.vvp:
	@mkdir -p build
	(iverilog -DFUNCTIONAL $(RTL_INC) -s retrosoc_tb_tiny -o $@ retrosoc_tb_tiny.v $(RTL_SOC) $(RTL_TECH) $(RTL_PDK) $(RTL_IP) || exit -1) 2>&1 | tee compile.log

retrosoc_syn_tb_tiny.vvp:
	@mkdir -p build
	(iverilog -DFUNCTIONAL $(RTL_INC) -s retrosoc_tb_tiny -o $@ retrosoc_tb_tiny.v ../syn/yosys/out/retrosoc_asic_yosys.v $(RTL_TECH) $(RTL_PDK) $(RTL_IP) || exit -1) 2>&1 | tee syncompile.log



../syn/yosys/out/retrosoc_asic_yosys.v:
	$(MAKE) -C ../syn/yosys -f yosys.mk

retrosoc_syn.v:
	yosys ../syn/synth_retrosoc.ys

$(FIRMWARE_NAME).elf:
	$(CROSS)cpp -P -o retrosoc_sections.lds $(LDS_PATH)
	$(CROSS)gcc $(CFLAGS) -I../crt -o $@ $(SRC_PATH)
	$(CROSS)objcopy -O verilog $@ $(FIRMWARE_NAME).hex
	sed -i 's/@30000000/@00000000/g' retrosoc_fw.hex
	$(CROSS)objcopy -O binary  $@ $(FIRMWARE_NAME).bin
	$(CROSS)objdump -d $@ > $(FIRMWARE_NAME).txt


vcomp:
	bsub -Is vcs ${VSIM_OPTIONS} ${VTIME_OPTION} $(RTL_SOC) $(RTL_TECH) $(RTL_PDK) $(RTL_IP) retrosoc_tb.v -top retrosoc_tb -l vcompile.log

vnetcomp:
	bsub -Is vcs ${VSIM_OPTIONS} ${VTIME_OPTION} $(RTL_TECH) $(RTL_PDK) $(RTL_IP) -v ../syn/yosys/out/retrosoc_asic_yosys.v retrosoc_tb.v -top retrosoc_tb -l vnetcompile.log -o net_simv

vsim: vcomp
	bsub -Is ./simv -l vsim.log +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_$(SIM_TOOL)

vnetsim: vnetcomp
	bsub -Is ./net_simv -l vnetsim.log +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +syn_$(WAVE) +sim_$(SIM_TOOL) +bus_conflict_off

vpostcomp:
	bsub -Is vcs ${VSIM_OPTIONS} ${VPOST_SIM_OPTION} ${RTL_PDK} ./ip/rs232.v ./ip/kdb_model.v ./ip/psram_model.v ./ip/cust/spfs_model/N25Qxxx.v retrosoc_tb.v -top retrosoc_tb -l vpostcompile.log ${VPOST_PATH} -o post_simv

vpostsim: vpostcomp
	bsub -Is ./post_simv -l vpostsim.log +$(RTL_SIM_PLLEN) +$(RTL_SIM_PLLCFG) +behv_$(WAVE) +sim_$(SIM_TOOL)

vwave:
	bsub -Is verdi -ssf retrosoc_tb.fsdb -nologo &

vsynwave:
	bsub -Is verdi -ssf retrosoc_syn_tb.fsdb -nologo &



######### tiny version
vcomptiny:
	bsub -Is vcs ${VSIM_OPTIONS} ${VTIME_OPTION} $(RTL_SOC) $(RTL_TECH) $(RTL_PDK) $(RTL_IP) retrosoc_tb_tiny.v -top retrosoc_tb_tiny -l vcompiletiny.log -o simvtiny

vnetcomptiny:
	bsub -Is vcs ${VSIM_OPTIONS} ${VTIME_OPTION} $(RTL_TECH) $(RTL_PDK) $(RTL_IP) -v ../syn/yosys/out/retrosoc_asic_tiny_yosys.v retrosoc_tb_tiny.v -top retrosoc_tb_tiny -l vnetcompiletiny.log -o net_simvtiny

vsimtiny: vcomptiny
	bsub -Is ./simvtiny -l vsimtiny.log +behv_$(WAVE) +sim_$(SIM_TOOL)

vnetsimtiny: vnetcomptiny
	bsub -Is ./net_simvtiny -l vnetsimtiny.log +syn_$(WAVE) +sim_$(SIM_TOOL) +bus_conflict_off

vwavetiny:
	bsub -Is verdi -ssf retrosoc_tb_tiny.fsdb -nologo &

vsynwavetiny:
	bsub -Is verdi -ssf retrosoc_syn_tb_tiny.fsdb -nologo &

clean:
	rm -f *.vvp *.vcd *.fst
	rm -f *.elf *.hex *.bin
	rm -f *.log
	rm -f retrosoc_syn.v

.PHONY: spiflash_tb clean
.PHONY: retrosim retrosynsim retrosoc_syn.v retrosoc_sections.lds
.PHONY: retrosoc_tb.vvp retrosoc_syn_tb.vvp $(FIRMWARE_NAME).elf
