// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_sysctrl (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         fault_valid_i,
    input  logic [31:0]  fault_addr_i,
    input  logic [3:0]   fault_wstrb_i,
    input  logic         fault_reserved_i,
    apb4_if.slave        apb4,
    sysctrl_if.dut       sysctrl,
    pll_ctrl_if.sysctrl  pll_ctrl
    // verilog_format: on
);

  logic        s_write_valid;
  logic [ 7:0] s_write_offset;
  logic [31:0] s_write_data;
  logic [ 3:0] s_write_strobe;
  logic [ 7:0] s_read_offset;
  logic        s_read_data_valid;
  logic [31:0] s_read_data;

  sysctrl_reg u_sysctrl_reg (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .apb4             (apb4),
      .write_valid_o    (s_write_valid),
      .write_offset_o   (s_write_offset),
      .write_data_o     (s_write_data),
      .write_strobe_o   (s_write_strobe),
      .read_offset_o    (s_read_offset),
      .read_data_valid_i(s_read_data_valid),
      .read_data_i      (s_read_data)
  );

  sysctrl_core u_sysctrl_core (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .write_valid_i    (s_write_valid),
      .write_offset_i   (s_write_offset),
      .write_data_i     (s_write_data),
      .write_strobe_i   (s_write_strobe),
      .read_offset_i    (s_read_offset),
      .fault_valid_i    (fault_valid_i),
      .fault_addr_i     (fault_addr_i),
      .fault_wstrb_i    (fault_wstrb_i),
      .fault_reserved_i (fault_reserved_i),
      .sysctrl          (sysctrl),
      .pll_ctrl         (pll_ctrl),
      .read_data_valid_o(s_read_data_valid),
      .read_data_o      (s_read_data)
  );

endmodule
