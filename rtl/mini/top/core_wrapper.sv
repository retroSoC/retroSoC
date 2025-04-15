`include "mmap_define.svh"

module core_wrapper (
    input  logic        clk_i,
    input  logic        rst_n_i,
    output logic        core_valid_o,
    output logic [31:0] core_addr_o,
    output logic [31:0] core_wdata_o,
    output logic [ 3:0] core_wstrb_o,
    input  logic [31:0] core_rdata_i,
    input  logic        core_ready_i,
    input  logic [31:0] irq_i
);

`ifdef CORE_PICORV32
  picorv32 #(
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_MUL     (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1),
      .ENABLE_IRQ     (0),
      .PROGADDR_RESET (`FLASH_START_ADDR)
  ) u_picorv32 (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(core_valid_o),
      .mem_instr(),
      .mem_addr (core_addr_o),
      .mem_wdata(core_wdata_o),
      .mem_wstrb(core_wstrb_o),
      .mem_rdata(core_rdata_i),
      .mem_ready(core_ready_i),
      .irq      (irq_i),
      .trap     ()
  );
`elsif CORE_KIANV
  kianv_harris_mc_edition #(
      .RESET_ADDR(`FLASH_START_ADDR),
      .RV32E     (0)
  ) u_kianv_harris_mc_edition (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(core_valid_o),
      .mem_ready(core_ready_i),
      .mem_wstrb(core_wstrb_o),
      .mem_addr (core_addr_o),
      .mem_wdata(core_wdata_o),
      .mem_rdata(core_rdata_i)
  );
`endif
endmodule
