`include "mmap_define.svh"

module mem2apb #(
    parameter APB_SLAVES_NUM = 8
) (
    input  logic                      clk_i,
    input  logic                      rst_n_i,
    // mem if
    input  logic                      mem_valid_i,
    input  logic [              31:0] mem_addr_i,
    input  logic [              31:0] mem_wdata_i,
    input  logic [               3:0] mem_wstrb_i,
    output logic [              31:0] mem_rdata_o,
    output logic                      mem_ready_o,
    // apb if
    output logic [              31:0] apb_paddr_o,
    output logic [               2:0] apb_pprot_o,
    output logic [APB_SLAVES_NUM-1:0] apb_psel_o,
    output logic                      apb_penable_o,
    output logic                      apb_pwrite_o,
    output logic [              31:0] apb_pwdata_o,
    output logic [               3:0] apb_pstrb_o,
    input  logic [APB_SLAVES_NUM-1:0] apb_pready_i,
    input  logic [              31:0] apb_prdata0_i,
    input  logic [              31:0] apb_prdata1_i,
    input  logic [              31:0] apb_prdata2_i,
    input  logic [              31:0] apb_prdata3_i,
    input  logic [              31:0] apb_prdata4_i,
    input  logic [              31:0] apb_prdata5_i,
    input  logic [              31:0] apb_prdata6_i,
    input  logic [              31:0] apb_prdata7_i,
    input  logic [APB_SLAVES_NUM-1:0] apb_pslverr_i
);

  logic [31:0] s_rd_data;
  logic        s_xfer_ready;
  logic s_psel_d, s_psel_q;

  assign apb_paddr_o = mem_addr_i;
  assign apb_pprot_o = 3'd0;
  assign apb_psel_o[0] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h10);
  assign apb_psel_o[1] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h20);
  assign apb_psel_o[2] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h30);
  assign apb_psel_o[3] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h40);
  assign apb_psel_o[4] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h50);
  assign apb_psel_o[5] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h60);
  assign apb_psel_o[6] = mem_valid_i && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h70);
  assign apb_psel_o[7] = mem_valid_i && (mem_addr_i[31:24] == `FLASH_START);
  assign apb_penable_o = s_psel_q;
  assign apb_pwrite_o = |mem_wstrb_i;
  assign apb_pwdata_o = mem_wdata_i;
  assign apb_pstrb_o = mem_wstrb_i;

  // HACK: dont need psel signal
  assign mem_ready_o = mem_valid_i && apb_penable_o && s_xfer_ready;
  assign mem_rdata_o = {32{mem_ready_o}} & s_rd_data;


  assign s_psel_d = |apb_psel_o;
  dffr #(1) u_psel_dffr (
      clk_i,
      rst_n_i,
      s_psel_d,
      s_psel_q
  );

  // verilog_format: off
  assign s_rd_data = ({32{apb_psel_o[0]}} & apb_prdata0_i) |
                     ({32{apb_psel_o[1]}} & apb_prdata1_i) |
                     ({32{apb_psel_o[2]}} & apb_prdata2_i) |
                     ({32{apb_psel_o[3]}} & apb_prdata3_i) |
                     ({32{apb_psel_o[4]}} & apb_prdata4_i) |
                     ({32{apb_psel_o[5]}} & apb_prdata5_i) |
                     ({32{apb_psel_o[6]}} & apb_prdata6_i) |
                     ({32{apb_psel_o[7]}} & apb_prdata7_i);

  assign s_xfer_ready = (apb_psel_o[0] & apb_pready_i[0]) |
                        (apb_psel_o[1] & apb_pready_i[1]) |
                        (apb_psel_o[2] & apb_pready_i[2]) |
                        (apb_psel_o[3] & apb_pready_i[3]) |
                        (apb_psel_o[4] & apb_pready_i[4]) |
                        (apb_psel_o[5] & apb_pready_i[5]) |
                        (apb_psel_o[6] & apb_pready_i[6]) |
                        (apb_psel_o[7] & apb_pready_i[7]);
  // verilog_format: on

endmodule
