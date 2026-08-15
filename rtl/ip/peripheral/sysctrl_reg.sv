// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module sysctrl_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    ribp_if.slave       ribp,
    output logic        write_valid_o,
    output logic [7:0]  write_offset_o,
    output logic [31:0] write_data_o,
    output logic [3:0]  write_strobe_o,
    output logic [7:0]  read_offset_o,
    input  logic        read_data_valid_i,
    input  logic [31:0] read_data_i
    // verilog_format: on
);

  logic        s_req_accept;
  logic        s_read_accept;
  logic        s_ribp_ready_d;
  logic        s_ribp_ready_q;
  logic [31:0] s_ribp_rdata_d;
  logic [31:0] s_ribp_rdata_q;

  assign s_req_accept   = ribp.valid && !s_ribp_ready_q;
  assign s_read_accept  = s_req_accept && !(|ribp.wstrb);
  assign write_valid_o  = s_req_accept && (|ribp.wstrb);
  assign write_offset_o = ribp.addr[7:0];
  assign write_data_o   = ribp.wdata;
  assign write_strobe_o = ribp.wstrb;
  assign read_offset_o  = ribp.addr[7:0];
  assign ribp.ready     = s_ribp_ready_q;
  assign ribp.resp_err  = 1'b0;
  assign ribp.rdata     = s_ribp_rdata_q;
  assign s_ribp_ready_d = s_req_accept;
  assign s_ribp_rdata_d = read_data_valid_i ? read_data_i : s_ribp_rdata_q;

  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_ready_d),
      .dat_o  (s_ribp_ready_q)
  );

  dffer #(
      .DATA_WIDTH(32)
  ) u_ribp_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_read_accept),
      .dat_i  (s_ribp_rdata_d),
      .dat_o  (s_ribp_rdata_q)
  );

endmodule
