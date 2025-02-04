
CROSS=riscv32-unknown-elf-
CFLAGS := -mabi=ilp32 \
          -march=rv32im \
          -Wl,-Bstatic,-T,retrosoc_sections.lds,--strip-debug \
          -ffreestanding \
          -nostdlib

WAVE := NONE

RTL_IP := ./ip/spram_model.v \
      ./ip/spimemio.v \
      ./ip/simpleuart.v \
      ./ip/i2c_master_bit_ctrl.v \
      ./ip/i2c_master_byte_ctrl.v \
      ./ip/simple_i2c_master.v \
      ./ip/i2c_slave.v \
      ./ip/simple_spi_master.v \
      ./ip/counter_timer.v \
      ./ip/spi_slave.v \
      ./ip/ravenna_spi.v \
      ./ip/spiflash.v \
      ./ip/rs232.v \
      ./ip/kdb_model.v \
      ./ip/psram_model.v \
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
      ./ip/cust/psram.v \
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
      ./ip/axil_ip_wrapper.v

RTL_TECH := ../tech/tc_io.v \
            ../tech/tc_clk.v \
            ../tech/tc_sram.v

RTL_PDK := ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v \
           ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v \
           ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v \
           ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_1024x64_c2_bm_bist.v

RTL_INC := -I./ip

# software
FIRMWARE_NAME := retrosoc_fw

SRC_PATH := ../crt/start.s \
            ../crt/tinyuart.c \
            ../crt/tinystring.c \
            ../crt/tinyprintf.c \
            ../crt/tinyflash.c \
            ../crt/firmware.c

LDS_PATH := ../crt/sections.lds
# +behv_wave
retrosim: retrosoc_tb.vvp $(FIRMWARE_NAME).hex $(FIRMWARE_NAME).bin $(FIRMWARE_NAME).txt
	vvp -N $< +firmware=$(FIRMWARE_NAME).hex +behv_$(WAVE) -fst

# +syn_wave
retrosynsim: retrosoc_syn_tb.vvp $(FIRMWARE_NAME).hex
	vvp -N $< +firmware=$(FIRMWARE_NAME).hex +syn_$(WAVE) -fst


retrosoc_tb.vvp: retrosoc_tb.v retrosoc_asic.v retrosoc.v picorv32.v $(RTL_TECH) $(RTL_PDK) $(RTL_IP)
	iverilog -DFUNCTIONAL $(RTL_INC) -s retrosoc_tb -o $@ $^

retrosoc_syn_tb.vvp: retrosoc_tb.v ../syn/yosys/out/retrosoc_asic_yosys.v $(RTL_TECH) $(RTL_PDK) $(RTL_IP)
	iverilog -DFUNCTIONAL -s retrosoc_tb -o $@ $^

../syn/yosys/out/retrosoc_asic_yosys.v:
	$(MAKE) -C ../syn/yosys -f yosys.mk

retrosoc_syn.v:
	yosys ../syn/synth_retrosoc.ys

retrosoc_sections.lds: $(LDS_PATH)
	$(CROSS)cpp -P -o $@ $^

$(FIRMWARE_NAME).elf: $(SRC_PATH)
	@mkdir -p build
	$(CROSS)gcc $(CFLAGS) -I../crt -o $@ $^

$(FIRMWARE_NAME).hex: $(FIRMWARE_NAME).elf
	$(CROSS)objcopy -O verilog $^ $@

$(FIRMWARE_NAME).bin: $(FIRMWARE_NAME).elf
	$(CROSS)objcopy -O binary $^ $@

$(FIRMWARE_NAME).txt: $(FIRMWARE_NAME).elf
	$(CROSS)objdump -d $^ > $@

# ---- Testbench for SPI Flash Model ----
spiflash_tb: spiflash_tb.vvp $(FIRMWARE_NAME).hex
	vvp -N $< +firmware=$(FIRMWARE_NAME).hex

spiflash_tb.vvp: spiflash.v spiflash_tb.v
	iverilog -s testbench -o $@ $^

# ---- ASIC Synthesis Tests ----
cmos.log: spimemio.v simpleuart.v retrosoc.v ../picorv32.v
	yosys -l cmos.log -p 'synth -top retrosoc; abc -g cmos2; opt -fast; stat' $^

clean:
	rm -f *.vvp *.vcd *.fst
	rm -f *.elf *.hex *.bin
	rm -f *.log
	rm -f retrosoc_syn.v

.PHONY: spiflash_tb clean
.PHONY: retrosim retrosynsim retrosoc_syn.v