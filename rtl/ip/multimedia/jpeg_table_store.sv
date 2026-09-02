// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_table_store (
    // verilog_format: off -- preserve portal, engine lookup, and status interface columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic [ 1:0]   portal_context_i,
    input  logic [ 3:0]   portal_kind_i,
    input  logic [ 7:0]   portal_index_i,
    input  logic [31:0]   portal_write_data_i,
    input  logic          portal_write_i,
    input  logic          portal_commit_i,
    input  logic          portal_default_i,
    input  logic          portal_clear_i,
    output logic [31:0]   portal_read_data_o,
    output logic [31:0]   portal_status_o,
    input  logic          lookup_i,
    input  logic [ 1:0]   lookup_context_i,
    input  logic [ 3:0]   lookup_kind_i,
    input  logic [ 7:0]   lookup_index_i,
    output logic [31:0]   lookup_data_o,
    output logic          lookup_valid_o,
    output logic          lookup_err_o
    // verilog_format: on
);
  localparam int unsigned EntriesPerContext = 1328;
  localparam int unsigned NumBanks = 6;

  logic [        13:0]       s_portal_addr;
  logic                      s_portal_addr_valid;
  logic [        13:0]       s_lookup_addr;
  logic                      s_lookup_addr_valid;
  logic [        13:0]       s_selected_addr;
  logic                      s_selected_valid;
  logic [         2:0]       s_selected_bank;
  logic [         9:0]       s_selected_word;
  logic [         2:0]       s_read_bank_d;
  logic [         2:0]       s_read_bank_q;
  logic                      s_lookup_pending_d;
  logic                      s_lookup_pending_q;
  logic                      s_lookup_err_d;
  logic                      s_lookup_err_q;
  logic [         3:0]       s_context_valid_d;
  logic [         3:0]       s_context_valid_q;
  logic [         3:0]       s_context_dirty_d;
  logic [         3:0]       s_context_dirty_q;
  logic [         3:0]       s_context_err_d;
  logic [         3:0]       s_context_err_q;
  logic [NumBanks-1:0]       s_bank_cs;
  logic [NumBanks-1:0]       s_bank_write;
  logic [NumBanks-1:0][31:0] s_bank_read_data;

  function automatic logic [14:0] table_address(
      input logic [1:0] context_i, input logic [3:0] kind_i, input logic [7:0] index_i);
    logic [14:0] s_addr;
    logic        s_valid;
    begin
      s_addr  = 15'(context_i * EntriesPerContext);
      s_valid = 1'b1;
      if (kind_i < 4) begin
        s_addr += 15'(int'(kind_i) * 64) + 15'(index_i);
        s_valid = index_i < 8'd64;
      end else if (kind_i < 8) begin
        s_addr += 15'd256 + 15'((int'(kind_i) - 4) * 12) + 15'(index_i);
        s_valid = index_i < 8'd12;
      end else if (kind_i < 12) begin
        s_addr += 15'd304 + 15'((int'(kind_i) - 8) * 256) + 15'(index_i);
      end else begin
        s_valid = 1'b0;
      end
      return {s_valid, s_addr[13:0]};
    end
  endfunction

  always_comb begin
    {s_portal_addr_valid, s_portal_addr} =
        table_address(portal_context_i, portal_kind_i, portal_index_i);
    {s_lookup_addr_valid, s_lookup_addr} =
        table_address(lookup_context_i, lookup_kind_i, lookup_index_i);
    if (lookup_i) begin
      s_selected_addr  = s_lookup_addr;
      s_selected_valid = s_lookup_addr_valid;
    end else begin
      s_selected_addr  = s_portal_addr;
      s_selected_valid = s_portal_addr_valid;
    end
    s_selected_bank = s_selected_addr[12:10];
    s_selected_word = s_selected_addr[9:0];
  end

  always_comb begin
    s_bank_cs    = '0;
    s_bank_write = '0;
    if (s_selected_valid && (s_selected_bank < 3'(NumBanks))) begin
      s_bank_cs[s_selected_bank]    = 1'b1;
      s_bank_write[s_selected_bank] = portal_write_i && !lookup_i;
    end
  end

  assign portal_read_data_o = (s_read_bank_q < 3'(NumBanks)) ?
                                  s_bank_read_data[s_read_bank_q] : 32'd0;
  assign lookup_data_o = portal_read_data_o;
  assign lookup_valid_o = s_lookup_pending_q;
  assign lookup_err_o = s_lookup_err_q;
  assign portal_status_o = {
    20'd0,
    s_context_err_q[portal_context_i],
    s_context_dirty_q[portal_context_i],
    6'd0,
    s_context_valid_q[portal_context_i],
    3'd0
  };

  always_comb begin
    s_read_bank_d      = s_read_bank_q;
    s_lookup_pending_d = lookup_i && s_lookup_addr_valid && s_context_valid_q[lookup_context_i];
    s_lookup_err_d     = lookup_i && (!s_lookup_addr_valid || !s_context_valid_q[lookup_context_i]);
    if (s_selected_valid && (s_selected_bank < 3'(NumBanks))) begin
      s_read_bank_d = s_selected_bank;
    end
    s_context_valid_d = s_context_valid_q;
    s_context_dirty_d = s_context_dirty_q;
    s_context_err_d   = s_context_err_q;
    if (portal_write_i) begin
      s_context_valid_d[portal_context_i] = 1'b0;
      s_context_dirty_d[portal_context_i] = 1'b1;
      if (!s_portal_addr_valid) begin
        s_context_err_d[portal_context_i] = 1'b1;
      end
    end
    if (portal_commit_i) begin
      s_context_valid_d[portal_context_i] = s_context_dirty_q[portal_context_i] &&
                                            !s_context_err_q[portal_context_i];
      s_context_dirty_d[portal_context_i] = 1'b0;
    end
    if (portal_default_i) begin
      s_context_valid_d[portal_context_i] = 1'b0;
      s_context_dirty_d[portal_context_i] = 1'b0;
      s_context_err_d[portal_context_i]   = 1'b1;
    end
    if (portal_clear_i) begin
      s_context_valid_d[portal_context_i] = 1'b0;
      s_context_dirty_d[portal_context_i] = 1'b0;
      s_context_err_d[portal_context_i]   = 1'b0;
    end
  end

  for (genvar bank = 0; bank < NumBanks; bank++) begin : gen_table_bank
    tc_sram_1024x32 u_table_sram (
        .clk_i (clk_i),
        .cs_i  (s_bank_cs[bank]),
        .addr_i(s_selected_word),
        .data_i(portal_write_data_i),
        .mask_i(4'hf),
        .wren_i(s_bank_write[bank]),
        .data_o(s_bank_read_data[bank])
    );
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_read_bank_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_bank_d),
      .dat_o  (s_read_bank_q)
  );
  dffr u_lookup_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lookup_pending_d),
      .dat_o  (s_lookup_pending_q)
  );
  dffr u_lookup_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lookup_err_d),
      .dat_o  (s_lookup_err_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_context_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_context_valid_d),
      .dat_o  (s_context_valid_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_context_dirty_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_context_dirty_d),
      .dat_o  (s_context_dirty_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_context_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_context_err_d),
      .dat_o  (s_context_err_q)
  );
endmodule
