
CROSS=riscv32-unknown-elf-
CFLAGS=

retrosim: retrosoc_tb.vvp retrosoc_fw.hex
	vvp -N $< +firmware=retrosoc_fw.hex

retrosynsim: retrosoc_syn_tb.vvp retrosoc_fw.hex
	vvp -N $< +firmware=retrosoc_fw.hex

retrosoc.json: retrosoc.v ice40up5k_spram.v spimemio.v simpleuart.v picosoc.v ../picorv32.v
	yosys -ql retrosoc.log -p 'synth_ice40 -dsp -top retrosoc -json retrosoc.json' $^

retrosoc_tb.vvp: retrosoc_tb.v retrosoc.v ice40up5k_spram.v spimemio.v simpleuart.v picosoc.v picorv32.v spiflash.v
	iverilog -s retrosoc_tb -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS

retrosoc_syn_tb.vvp: retrosoc_tb.v retrosoc_syn.v spiflash.v
	iverilog -s retrosoc_tb -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS

retrosoc_syn.v: retrosoc.json
	yosys -p 'read_json retrosoc.json; write_verilog retrosoc_syn.v'

retrosoc.asc: retrosoc.pcf retrosoc.json
	nextpnr-ice40 --freq 13 --up5k --package sg48 --asc retrosoc.asc --pcf retrosoc.pcf --json retrosoc.json

retrosoc.bin: retrosoc.asc
	icetime -d up5k -c 12 -mtr retrosoc.rpt retrosoc.asc
	icepack retrosoc.asc retrosoc.bin

retroprog: retrosoc.bin retrosoc_fw.bin
	iceprog retrosoc.bin
	iceprog -o 1M retrosoc_fw.bin

retroprog_fw: retrosoc_fw.bin
	iceprog -o 1M retrosoc_fw.bin

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

cmos.log: spimemio.v simpleuart.v picosoc.v ../picorv32.v
	yosys -l cmos.log -p 'synth -top picosoc; abc -g cmos2; opt -fast; stat' $^

# ---- Clean ----

clean:
	rm -f testbench.vvp testbench.vcd spiflash_tb.vvp spiflash_tb.vcd
	rm -f hx8kdemo_fw.elf hx8kdemo_fw.hex hx8kdemo_fw.bin cmos.log
	rm -f retrosoc_fw.elf retrosoc_fw.hex retrosoc_fw.bin
	rm -f hx8kdemo.json hx8kdemo.log hx8kdemo.asc hx8kdemo.rpt hx8kdemo.bin
	rm -f hx8kdemo_syn.v hx8kdemo_syn_tb.vvp hx8kdemo_tb.vvp
	rm -f retrosoc.json retrosoc.log retrosoc.asc retrosoc.rpt retrosoc.bin
	rm -f retrosoc_syn.v retrosoc_syn_tb.vvp retrosoc_tb.vvp

.PHONY: spiflash_tb clean
.PHONY: hx8kprog hx8kprog_fw hx8ksim hx8ksynsim
.PHONY: retroprog retroprog_fw retrosim retrosynsim
