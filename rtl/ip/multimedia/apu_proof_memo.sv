// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_proof_memo #(
    parameter int unsigned Depth = 8192
) (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        abort_i,
    input  logic        clear_i,
    input  logic        lookup_i,
    input  logic        insert_i,
    input  logic [12:0] addr_i,
    input  logic [63:0] key_i,
    output logic        ready_o,
    output logic        done_o,
    output logic        read_valid_o,
    output logic [63:0] read_key_o
);
  localparam int unsigned BitmapRows = (Depth + 31) / 32;
  localparam logic [7:0] BitmapLast = 8'(BitmapRows - 1);
  typedef enum logic [2:0] {
    Idle,
    LookupWait,
    InsertBitmapWrite,
    ClearBitmap,
    ClearDrain
  } memo_state_e;

  memo_state_e              s_state_q;
  logic        [12:0]       s_addr_q;
  logic        [63:0]       s_key_q;
  logic        [ 7:0]       s_clear_row_q;
  logic        [ 2:0]       s_read_bank_q;

  logic        [ 7:0]       s_key_cs;
  logic        [ 7:0]       s_key_wren;
  logic        [ 7:0][31:0] s_key_low_rdata;
  logic        [ 7:0][31:0] s_key_high_rdata;
  logic                     s_bitmap_cs;
  logic                     s_bitmap_wren;
  logic        [ 9:0]       s_bitmap_addr;
  logic        [31:0]       s_bitmap_wdata;
  logic        [31:0]       s_bitmap_rdata;

`ifndef SYNTHESIS
  initial begin
    if ((Depth == 0) || (Depth > 8192) || ((Depth & (Depth - 1)) != 0)) begin
      $fatal(1, "apu_proof_memo: depth must be a power of two up to 8192");
    end
  end
`endif

  assign ready_o = s_state_q == Idle;

  always_comb begin
    s_key_cs       = 8'd0;
    s_key_wren     = 8'd0;
    s_bitmap_cs    = 1'b0;
    s_bitmap_wren  = 1'b0;
    s_bitmap_addr  = 10'd0;
    s_bitmap_wdata = 32'd0;

    if ((s_state_q == Idle) && clear_i) begin
      s_bitmap_cs    = 1'b1;
      s_bitmap_wren  = 1'b1;
      s_bitmap_addr  = 10'd0;
      s_bitmap_wdata = 32'd0;
    end else if ((s_state_q == Idle) && lookup_i) begin
      s_key_cs[addr_i[12:10]] = 1'b1;
      s_bitmap_cs             = 1'b1;
      s_bitmap_addr           = {2'd0, addr_i[12:5]};
    end else if ((s_state_q == Idle) && insert_i) begin
      s_key_cs[addr_i[12:10]] = 1'b1;
      s_key_wren[addr_i[12:10]] = 1'b1;
      s_bitmap_cs = 1'b1;
      s_bitmap_addr = {2'd0, addr_i[12:5]};
    end else if (s_state_q == InsertBitmapWrite) begin
      s_bitmap_cs    = 1'b1;
      s_bitmap_wren  = 1'b1;
      s_bitmap_addr  = {2'd0, s_addr_q[12:5]};
      s_bitmap_wdata = s_bitmap_rdata | (32'd1 << s_addr_q[4:0]);
    end else if (s_state_q == ClearBitmap) begin
      s_bitmap_cs    = 1'b1;
      s_bitmap_wren  = 1'b1;
      s_bitmap_addr  = {2'd0, s_clear_row_q};
      s_bitmap_wdata = 32'd0;
    end
  end

`ifdef HAVE_SRAM_MACRO
  for (genvar bank = 0; bank < 8; bank++) begin : gen_key_bank
    tc_sram_1024x32 u_key_low_sram (
        .clk_i (clk_i),
        .cs_i  (s_key_cs[bank]),
        .addr_i((s_state_q == Idle) ? addr_i[9:0] : s_addr_q[9:0]),
        .data_i((s_state_q == Idle) ? key_i[31:0] : s_key_q[31:0]),
        .mask_i(4'hf),
        .wren_i(s_key_wren[bank]),
        .data_o(s_key_low_rdata[bank])
    );
    tc_sram_1024x32 u_key_high_sram (
        .clk_i (clk_i),
        .cs_i  (s_key_cs[bank]),
        .addr_i((s_state_q == Idle) ? addr_i[9:0] : s_addr_q[9:0]),
        .data_i((s_state_q == Idle) ? key_i[63:32] : s_key_q[63:32]),
        .mask_i(4'hf),
        .wren_i(s_key_wren[bank]),
        .data_o(s_key_high_rdata[bank])
    );
  end
  tc_sram_1024x32 u_valid_bitmap_sram (
      .clk_i (clk_i),
      .cs_i  (s_bitmap_cs),
      .addr_i(s_bitmap_addr),
      .data_i(s_bitmap_wdata),
      .mask_i(4'hf),
      .wren_i(s_bitmap_wren),
      .data_o(s_bitmap_rdata)
  );
`else
  logic [63:0] s_key_mem   [0:Depth-1];
  logic [31:0] s_bitmap_mem[0:BitmapRows-1];
  logic [12:0] s_key_access_addr;
  logic [63:0] s_key_access_data;

  assign s_key_access_addr = (s_state_q == Idle) ? addr_i : s_addr_q;
  assign s_key_access_data = (s_state_q == Idle) ? key_i : s_key_q;
  always_ff @(posedge clk_i) begin
    if (|s_key_cs) begin
      if (|s_key_wren) begin
        s_key_mem[s_key_access_addr] <= s_key_access_data;
      end else begin
        s_key_low_rdata[s_key_access_addr[12:10]]  <= s_key_mem[s_key_access_addr][31:0];
        s_key_high_rdata[s_key_access_addr[12:10]] <= s_key_mem[s_key_access_addr][63:32];
      end
    end
    if (s_bitmap_cs) begin
      if (s_bitmap_wren) begin
        s_bitmap_mem[s_bitmap_addr[7:0]] <= s_bitmap_wdata;
      end else begin
        s_bitmap_rdata <= s_bitmap_mem[s_bitmap_addr[7:0]];
      end
    end
  end
`endif

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q     <= Idle;
      s_addr_q      <= 13'd0;
      s_key_q       <= 64'd0;
      s_clear_row_q <= 8'd0;
      s_read_bank_q <= 3'd0;
      done_o        <= 1'b0;
      read_valid_o  <= 1'b0;
      read_key_o    <= 64'd0;
    end else begin
      done_o <= 1'b0;
      if (abort_i) begin
        s_state_q     <= Idle;
        s_clear_row_q <= 8'd0;
      end else begin
        unique case (s_state_q)
          Idle: begin
            if (clear_i) begin
              s_clear_row_q <= 8'd1;
              s_state_q     <= (BitmapRows == 1) ? ClearDrain : ClearBitmap;
            end else if (lookup_i) begin
              s_addr_q      <= addr_i;
              s_key_q       <= key_i;
              s_read_bank_q <= addr_i[12:10];
              s_state_q     <= LookupWait;
            end else if (insert_i) begin
              s_addr_q  <= addr_i;
              s_key_q   <= key_i;
              s_state_q <= InsertBitmapWrite;
            end
          end
          LookupWait: begin
            read_key_o   <= {s_key_high_rdata[s_read_bank_q], s_key_low_rdata[s_read_bank_q]};
            read_valid_o <= s_bitmap_rdata[s_addr_q[4:0]];
            done_o       <= 1'b1;
            s_state_q    <= Idle;
          end
          InsertBitmapWrite: begin
            done_o    <= 1'b1;
            s_state_q <= Idle;
          end
          ClearBitmap: begin
            if (s_clear_row_q == BitmapLast) begin
              s_clear_row_q <= 8'd0;
              s_state_q     <= ClearDrain;
            end else begin
              s_clear_row_q <= s_clear_row_q + 1'b1;
            end
          end
          ClearDrain: begin
            done_o    <= 1'b1;
            s_state_q <= Idle;
          end
          default: s_state_q <= Idle;
        endcase
      end
    end
  end
endmodule
