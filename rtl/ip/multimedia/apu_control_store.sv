// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_control_store (
    // verilog_format: off -- preserve loader and sequencer access columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        loader_active_i,
    input  logic        loader_read_i,
    input  logic        loader_write_i,
    input  logic [10:0] loader_addr_i,
    input  logic [63:0] loader_data_i,
    output logic [63:0] loader_data_o,
    output logic        loader_valid_o,
    input  logic        image_valid_i,
    input  logic        fetch_i,
    input  logic [10:0] fetch_addr_i,
    output logic [63:0] fetch_data_o,
    output logic        fetch_valid_o
    // verilog_format: on
);
  logic        s_access;
  logic        s_write;
  logic [10:0] s_addr;
  logic [63:0] s_read_data;
  logic s_loader_read_q, s_fetch_q;

  assign s_access = loader_active_i ? (loader_read_i || loader_write_i) :
      (fetch_i && image_valid_i);
  assign s_write = loader_active_i && loader_write_i;
  assign s_addr = loader_active_i ? loader_addr_i : fetch_addr_i;
  assign loader_data_o = s_read_data;
  assign loader_valid_o = s_loader_read_q;
  assign fetch_data_o = s_read_data;
  assign fetch_valid_o = s_fetch_q;

`ifdef HAVE_SRAM_MACRO
  logic             s_read_bank_q;
  logic [1:0][31:0] s_low_data;
  logic [1:0][31:0] s_high_data;

  tc_sram_1024x32 u_control_low_bank0 (
      .clk_i (clk_i),
      .cs_i  (s_access && (s_addr[10] == 1'b0)),
      .addr_i(s_addr[9:0]),
      .data_i(loader_data_i[31:0]),
      .mask_i(4'hf),
      .wren_i(s_write),
      .data_o(s_low_data[0])
  );
  tc_sram_1024x32 u_control_high_bank0 (
      .clk_i (clk_i),
      .cs_i  (s_access && (s_addr[10] == 1'b0)),
      .addr_i(s_addr[9:0]),
      .data_i(loader_data_i[63:32]),
      .mask_i(4'hf),
      .wren_i(s_write),
      .data_o(s_high_data[0])
  );
  tc_sram_1024x32 u_control_low_bank1 (
      .clk_i (clk_i),
      .cs_i  (s_access && (s_addr[10] == 1'b1)),
      .addr_i(s_addr[9:0]),
      .data_i(loader_data_i[31:0]),
      .mask_i(4'hf),
      .wren_i(s_write),
      .data_o(s_low_data[1])
  );
  tc_sram_1024x32 u_control_high_bank1 (
      .clk_i (clk_i),
      .cs_i  (s_access && (s_addr[10] == 1'b1)),
      .addr_i(s_addr[9:0]),
      .data_i(loader_data_i[63:32]),
      .mask_i(4'hf),
      .wren_i(s_write),
      .data_o(s_high_data[1])
  );

  assign s_read_data = {s_high_data[s_read_bank_q], s_low_data[s_read_bank_q]};

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_bank_q <= 1'b0;
    end else if (s_access && !s_write) begin
      s_read_bank_q <= s_addr[10];
    end
  end
`else
  logic [63:0] mem           [0:2047];
  logic [63:0] s_read_data_q;

  assign s_read_data = s_read_data_q;
  always_ff @(posedge clk_i) begin
    if (s_access) begin
      if (s_write) begin
        mem[s_addr] <= loader_data_i;
      end else begin
        s_read_data_q <= mem[s_addr];
      end
    end
  end
`endif

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_loader_read_q <= 1'b0;
      s_fetch_q       <= 1'b0;
    end else begin
      s_loader_read_q <= loader_active_i && loader_read_i;
      s_fetch_q       <= !loader_active_i && fetch_i && image_valid_i;
    end
  end
endmodule
