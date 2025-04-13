`include "mmap_define.svh"

module bus (
    input         clk_i,
    output        rst_n_i,
    // core if
    input         core_valid_i,
    input  [31:0] core_addr_i,
    input  [31:0] core_wdata_i,
    input  [ 3:0] core_wstrb_i,
    output [31:0] core_rdata_o,
    output        core_ready_o,
    // natv if
    output        natv_valid_o,
    output [31:0] natv_addr_o,
    output [31:0] natv_wdata_o,
    output [ 3:0] natv_wstrb_o,
    input  [31:0] natv_rdata_i,
    input         natv_ready_i,
    // mmap if
    output        mmap_valid_o,
    output [31:0] mmap_addr_o,
    output [31:0] mmap_wdata_o,
    output [ 3:0] mmap_wstrb_o,
    input  [31:0] mmap_rdata_i,
    input         mmap_ready_i,
    // ram if
    output [14:0] ram_addr_o,
    output [31:0] ram_wdata_o,
    output [ 3:0] ram_wstrb_o,
    input  [31:0] ram_rdata_i,
    // psram if
    output        psram_valid_o,
    output [31:0] psram_addr_o,
    output [31:0] psram_wdata_o,
    output [ 3:0] psram_wstrb_o,
    input  [31:0] psram_rdata_i,
    input         psram_ready_i
);

  wire s_natv_sel, s_mmap_sel, s_ram_sel, s_psram_sel;
  wire s_ram_valid, s_ram_ready;

  assign s_natv_sel    = core_addr_i[31:24] == `NATV_IP_START;
  assign natv_valid_o  = core_valid_i && s_natv_sel;
  assign natv_addr_o   = core_addr_i;
  assign natv_wdata_o  = core_wdata_i;
  assign natv_wstrb_o  = core_wstrb_i;

  assign s_mmap_sel    = core_addr_i[31:24] == `FLASH_START || core_addr_i[31:24] == `CUST_IP_START;
  assign mmap_valid_o  = core_valid_i && s_mmap_sel;
  assign mmap_addr_o   = core_addr_i;
  assign mmap_wdata_o  = core_wdata_i;
  assign mmap_wstrb_o  = core_wstrb_i;

  assign s_ram_sel     = core_addr_i[31:24] == `SRAM_START;
  assign s_ram_valid   = core_valid_i && s_ram_sel;
  assign ram_addr_o    = core_addr_i[16:2];
  assign ram_wdata_o   = core_wdata_i;
  assign ram_wstrb_o   = s_ram_valid ? core_wstrb_i : 4'd0;

  assign s_psram_sel   = core_addr_i[31:24] == `PSRAM_START;
  assign psram_valid_o = core_valid_i && s_psram_sel;
  assign psram_addr_o  = core_addr_i;
  assign psram_wdata_o = core_wdata_i;
  assign psram_wstrb_o = core_wstrb_i;

  dffr #(1) u_ram_ready_dffr (
      clk_i,
      rst_n_i,
      s_ram_valid,
      s_ram_ready
  );

  // verilog_format: off
  assign core_ready_o = (natv_valid_o && natv_ready_i) || 
                        (mmap_valid_o && mmap_ready_i) || 
                         s_ram_ready ||
                        (psram_valid_o && psram_ready_i);

  assign core_rdata_o = (natv_valid_o && natv_ready_i) ? natv_rdata_i:
                        (mmap_valid_o && mmap_ready_i) ? mmap_rdata_i :
                         s_ram_ready ? ram_rdata_i :
                        (psram_valid_o && psram_ready_i) ? psram_rdata_i : 32'h0;
  // verilog_format: on
endmodule
