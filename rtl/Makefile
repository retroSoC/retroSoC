
CROSS=riscv32-unknown-elf-
CFLAGS=

WAVE := NONE

RTL :=
# +behv_wave
retrosim: retrosoc_tb.vvp retrosoc_fw.hex retrosoc_fw.bin
	vvp -N $< +firmware=retrosoc_fw.hex +behv_$(WAVE)

# +syn_wave
retrosynsim: retrosoc_syn_tb.vvp retrosoc_fw.hex
	vvp -N $< +firmware=retrosoc_fw.hex +syn_$(WAVE)

retrosoc_tb.vvp: retrosoc_tb.v retrosoc_asic.v ./ip/spram_model.v ./ip/spimemio.v ./ip/simpleuart.v retrosoc.v picorv32.v ./ip/spiflash.v ../tech/tc_io.v ../tech/tc_clk.v ../tech/tc_sram.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_1024x16_c2_bm_bist.v
	iverilog -s retrosoc_tb -o $@ $^

retrosoc_syn_tb.vvp: retrosoc_tb.v ../syn/yosys/out/retrosoc_yosys.v spiflash.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v ../syn/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/RM_IHPSG13_1P_1024x16_c2_bm_bist.v
	iverilog -s retrosoc_tb -o $@ $^

../syn/yosys/out/retrosoc_yosys.v:
	$(MAKE) -C ../syn/yosys -f yosys.mk

retrosoc_syn.v:
	yosys ../syn/synth_retrosoc.ys

retrosoc_sections.lds: sections.lds
	$(CROSS)cpp -P -DRETROSOC -o $@ $^

retrosoc_fw.elf: retrosoc_sections.lds start.s firmware.c
	$(CROSS)gcc $(CFLAGS) -DRETROSOC -mabi=ilp32 -march=rv32ic -Wl,-Bstatic,-T,retrosoc_sections.lds,--strip-debug -ffreestanding -nostdlib -o retrosoc_fw.elf start.s firmware.c

retrosoc_fw.hex: retrosoc_fw.elf
	$(CROSS)objcopy -O verilog retrosoc_fw.elf retrosoc_fw.hex

retrosoc_fw.bin: retrosoc_fw.elf
	$(CROSS)objcopy -O binary retrosoc_fw.elf retrosoc_fw.bin

# ---- Testbench for SPI Flash Model ----
spiflash_tb: spiflash_tb.vvp retrosoc_fw.hex
	vvp -N $< +firmware=retrosoc_fw.hex

spiflash_tb.vvp: spiflash.v spiflash_tb.v
	iverilog -s testbench -o $@ $^

# ---- ASIC Synthesis Tests ----
cmos.log: spimemio.v simpleuart.v retrosoc.v ../picorv32.v
	yosys -l cmos.log -p 'synth -top retrosoc; abc -g cmos2; opt -fast; stat' $^

# ---- Clean ----
clean:
	rm -f *.vvp *.vcd 
	rm -f *.elf *.hex *.bin
	rm -f *.log
	rm -f retrosoc_syn.v

.PHONY: spiflash_tb clean
.PHONY: retrosim retrosynsim retrosoc_syn.v