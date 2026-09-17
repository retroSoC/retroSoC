// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU private storage: sixteen tc_sram_1024x32 banks (64 KiB) with per-word
// validity metadata and half-ownership arbitration. Frozen partition map from
// npu_pkg: raw gather banks 0-3 (two 8192-byte halves), packed A banks 4-7
// (two 8192-byte halves), packed W banks 8-11 (two 8192-byte halves), output
// staging banks 12-13 (two 4096-byte halves), descriptor/parameter banks
// 14-15 (one 8192-byte region).
//
// Contract refinements relative to the phase-1 port sketch (same semantics):
// - Half-local byte addresses are widened so they span a whole half: raw and
//   packed A/W addresses are [12:0] (8192-byte halves), the output-staging
//   address is [11:0] (4096-byte halves) and parameter addresses are [12:0].
// - A parameter write port (param_write_*) completes the read-only parameter
//   region; without it no parameter content could ever become valid.
//
// Access semantics:
// - Every port accepts one access per cycle while its *_valid_i is asserted.
//   All reads are synchronous with one-cycle latency; the returning bank is
//   selected by a selector registered at request time, so read data is never
//   valid in the request cycle.
// - 64-bit A/W accesses drive the two banks of one half simultaneously with
//   addr[12:3] as the row; addr[2:0] must be zero (misaligned 64-bit access
//   is an error). 32-bit ports ignore addr[1:0] (word select). Out-of-range
//   addresses are impossible by construction: each address exactly spans its
//   region, so no range error exists.
// - Each accepted write sets the per-32-bit-word valid bit of every word it
//   touches (any byte strobe asserted). clear_i clears all valid bits and the
//   sticky error: functional invalidation only, physical SRAM contents are
//   never bulk-reset. Reads of invalid words raise the sticky error; error
//   read data is don't-care.
// - Port groups touch disjoint banks except raw_write vs raw_read (raw banks)
//   and pack_write vs a_read/w_read (A/W banks). Concurrent same-half access
//   is a scheduler programming error: the sticky error is raised and the read
//   port wins the bank, dropping the write. Different-half concurrent access
//   (read the active half, write the inactive half) is legal. The parameter
//   write and read ports arbitrate the same way (read wins) without flagging.
// - access_err_port_o encodes the first failing port, sticky until clear_i:
//   3'd0 raw_write conflict, 3'd1 raw_read, 3'd2 pack_write, 3'd3 a_read,
//   3'd4 w_read, 3'd5 out_req, 3'd6 param_read; 3'd7 means no error latched.
module npu_local_sram (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        clear_i,
    // raw gather: gather/DMA write port + packer read port (banks 0-3)
    input  logic        raw_write_valid_i,
    input  logic        raw_write_half_i,
    input  logic [12:0] raw_write_addr_i,
    input  logic [31:0] raw_write_data_i,
    input  logic [ 3:0] raw_write_strb_i,
    input  logic        raw_read_valid_i,
    input  logic        raw_read_half_i,
    input  logic [12:0] raw_read_addr_i,
    output logic [31:0] raw_read_data_o,
    // packed A/W: packer 64-bit write port + compute 64-bit read ports
    input  logic        pack_write_valid_i,
    input  logic        pack_write_sel_w_i,
    input  logic        pack_write_half_i,
    input  logic [12:0] pack_write_addr_i,
    input  logic [63:0] pack_write_data_i,
    input  logic [ 7:0] pack_write_strb_i,
    input  logic        a_read_valid_i,
    input  logic        a_read_half_i,
    input  logic [12:0] a_read_addr_i,
    output logic [63:0] a_read_data_o,
    input  logic        w_read_valid_i,
    input  logic        w_read_half_i,
    input  logic [12:0] w_read_addr_i,
    output logic [63:0] w_read_data_o,
    // output staging: single port (banks 12-13, halves of 4096 bytes)
    input  logic        out_req_valid_i,
    input  logic        out_req_write_i,
    input  logic        out_req_half_i,
    input  logic [11:0] out_req_addr_i,
    input  logic [31:0] out_req_data_i,
    input  logic [ 3:0] out_req_strb_i,
    output logic [31:0] out_read_data_o,
    // parameter region: scheduler write port + compute read port (banks 14-15)
    input  logic        param_write_valid_i,
    input  logic [12:0] param_write_addr_i,
    input  logic [31:0] param_write_data_i,
    input  logic [ 3:0] param_write_strb_i,
    input  logic        param_read_valid_i,
    input  logic [12:0] param_read_addr_i,
    output logic [31:0] param_read_data_o,
    // validity/ownership errors
    output logic        access_err_sticky_o,
    output logic [ 2:0] access_err_port_o
);
  localparam int unsigned BankCount = npu_pkg::BankCount;
  localparam int unsigned BankWords = 2 ** npu_pkg::BankAddrWidth;
  localparam logic [2:0] ErrPortRawWrite = 3'd0;
  localparam logic [2:0] ErrPortRawRead = 3'd1;
  localparam logic [2:0] ErrPortPackWrite = 3'd2;
  localparam logic [2:0] ErrPortARead = 3'd3;
  localparam logic [2:0] ErrPortWRead = 3'd4;
  localparam logic [2:0] ErrPortOutReq = 3'd5;
  localparam logic [2:0] ErrPortParamRead = 3'd6;
  localparam logic [2:0] ErrPortNone = 3'd7;

  logic [BankCount-1:0]                s_bank_cs;
  logic [BankCount-1:0]                s_bank_wren;
  logic [BankCount-1:0][          9:0] s_bank_addr;
  logic [BankCount-1:0][         31:0] s_bank_wdata;
  logic [BankCount-1:0][          3:0] s_bank_wmask;
  logic [BankCount-1:0][         31:0] s_bank_rdata;
  logic [BankCount-1:0][BankWords-1:0] s_valid_q;

  logic [          1:0]                s_raw_write_bank;
  logic [          9:0]                s_raw_write_row;
  logic [          1:0]                s_raw_read_bank;
  logic [          9:0]                s_raw_read_row;
  logic                                s_raw_conflict;
  logic                                s_raw_write_en;
  logic [          9:0]                s_pack_write_row;
  logic [          9:0]                s_a_read_row;
  logic [          9:0]                s_w_read_row;
  logic [          3:0]                s_pack_a_bank_lo;
  logic [          3:0]                s_pack_w_bank_lo;
  logic [          3:0]                s_a_read_bank_lo;
  logic [          3:0]                s_w_read_bank_lo;
  logic                                s_pack_write_misaligned;
  logic                                s_a_read_misaligned;
  logic                                s_w_read_misaligned;
  logic                                s_a_conflict;
  logic                                s_w_conflict;
  logic                                s_pack_a_en;
  logic                                s_pack_w_en;
  logic [          3:0]                s_out_bank;
  logic [          3:0]                s_param_read_bank;
  logic [          3:0]                s_param_write_bank;

  logic [          1:0]                s_raw_read_bank_q;
  logic                                s_a_read_half_q;
  logic                                s_w_read_half_q;
  logic                                s_out_read_half_q;
  logic                                s_param_read_bank_q;
  logic [          3:0]                s_a_read_bank_lo_q;
  logic [          3:0]                s_w_read_bank_lo_q;

  logic                                s_err_raw_write;
  logic                                s_err_raw_read;
  logic                                s_err_pack_write;
  logic                                s_err_a_read;
  logic                                s_err_w_read;
  logic                                s_err_out;
  logic                                s_err_param;
  logic                                s_access_err;
  logic [          2:0]                s_access_err_port;
  logic                                s_access_err_sticky_q;
  logic [          2:0]                s_access_err_port_q;
  logic                                s_unused;

  assign s_raw_write_bank = {raw_write_half_i, raw_write_addr_i[12]};
  assign s_raw_write_row = raw_write_addr_i[11:2];
  assign s_raw_read_bank = {raw_read_half_i, raw_read_addr_i[12]};
  assign s_raw_read_row = raw_read_addr_i[11:2];
  assign s_raw_conflict = raw_write_valid_i && raw_read_valid_i &&
      (raw_write_half_i == raw_read_half_i);
  assign s_raw_write_en = raw_write_valid_i && !s_raw_conflict;

  assign s_pack_write_row = pack_write_addr_i[12:3];
  assign s_a_read_row = a_read_addr_i[12:3];
  assign s_w_read_row = w_read_addr_i[12:3];
  assign s_pack_a_bank_lo = 4'(npu_pkg::PackABankFirst) + {pack_write_half_i, 1'b0};
  assign s_pack_w_bank_lo = 4'(npu_pkg::PackWBankFirst) + {pack_write_half_i, 1'b0};
  assign s_a_read_bank_lo = 4'(npu_pkg::PackABankFirst) + {a_read_half_i, 1'b0};
  assign s_w_read_bank_lo = 4'(npu_pkg::PackWBankFirst) + {w_read_half_i, 1'b0};
  assign s_pack_write_misaligned = pack_write_addr_i[2:0] != 3'd0;
  assign s_a_read_misaligned = a_read_addr_i[2:0] != 3'd0;
  assign s_w_read_misaligned = w_read_addr_i[2:0] != 3'd0;
  assign s_a_conflict = pack_write_valid_i && !pack_write_sel_w_i && a_read_valid_i &&
      (pack_write_half_i == a_read_half_i);
  assign s_w_conflict = pack_write_valid_i && pack_write_sel_w_i && w_read_valid_i &&
      (pack_write_half_i == w_read_half_i);
  assign s_pack_a_en = pack_write_valid_i && !pack_write_sel_w_i && !s_a_conflict &&
      !s_pack_write_misaligned;
  assign s_pack_w_en = pack_write_valid_i && pack_write_sel_w_i && !s_w_conflict &&
      !s_pack_write_misaligned;

  assign s_out_bank = 4'(npu_pkg::OutBankFirst) + {3'd0, out_req_half_i};
  assign s_param_read_bank = 4'(npu_pkg::ParamBankFirst) + {3'd0, param_read_addr_i[12]};
  assign s_param_write_bank = 4'(npu_pkg::ParamBankFirst) + {3'd0, param_write_addr_i[12]};

  // Raw gather banks 0-3: the read port wins any bank-level clash; a same-half
  // concurrent write/read pair is a programming error that drops the write.
  for (genvar bank = 0; bank < 4; bank++) begin : gen_raw_bank
    localparam logic [1:0] BankIndex = 2'(bank);
    logic s_raw_read_sel;
    logic s_raw_write_sel;

    assign s_raw_read_sel = raw_read_valid_i && (s_raw_read_bank == BankIndex);
    assign s_raw_write_sel = s_raw_write_en && (s_raw_write_bank == BankIndex);
    assign s_bank_cs[npu_pkg::RawBankFirst+bank] = s_raw_read_sel || s_raw_write_sel;
    assign s_bank_wren[npu_pkg::RawBankFirst+bank] = s_raw_write_sel && !s_raw_read_sel;
    assign s_bank_addr[npu_pkg::RawBankFirst+bank] =
        s_raw_read_sel ? s_raw_read_row : s_raw_write_row;
    assign s_bank_wdata[npu_pkg::RawBankFirst+bank] = raw_write_data_i;
    assign s_bank_wmask[npu_pkg::RawBankFirst+bank] = raw_write_strb_i;
  end

  // Packed A banks 4-7 and packed W banks 8-11: two banks per half, low word
  // in the even bank, high word in the odd bank; compute reads win conflicts.
  for (genvar half = 0; half < 2; half++) begin : gen_pack_a_bank
    localparam int unsigned BankLow = npu_pkg::PackABankFirst + 2 * half;
    localparam logic HalfValue = 1'(half);
    logic s_a_read_sel;
    logic s_pack_a_sel;

    assign s_a_read_sel            = a_read_valid_i && (a_read_half_i == HalfValue);
    assign s_pack_a_sel            = s_pack_a_en && (pack_write_half_i == HalfValue);
    assign s_bank_cs[BankLow]      = s_a_read_sel || s_pack_a_sel;
    assign s_bank_wren[BankLow]    = s_pack_a_sel && !s_a_read_sel;
    assign s_bank_addr[BankLow]    = s_a_read_sel ? s_a_read_row : s_pack_write_row;
    assign s_bank_wdata[BankLow]   = pack_write_data_i[31:0];
    assign s_bank_wmask[BankLow]   = pack_write_strb_i[3:0];
    assign s_bank_cs[BankLow+1]    = s_a_read_sel || s_pack_a_sel;
    assign s_bank_wren[BankLow+1]  = s_pack_a_sel && !s_a_read_sel;
    assign s_bank_addr[BankLow+1]  = s_a_read_sel ? s_a_read_row : s_pack_write_row;
    assign s_bank_wdata[BankLow+1] = pack_write_data_i[63:32];
    assign s_bank_wmask[BankLow+1] = pack_write_strb_i[7:4];
  end

  for (genvar half = 0; half < 2; half++) begin : gen_pack_w_bank
    localparam int unsigned BankLow = npu_pkg::PackWBankFirst + 2 * half;
    localparam logic HalfValue = 1'(half);
    logic s_w_read_sel;
    logic s_pack_w_sel;

    assign s_w_read_sel            = w_read_valid_i && (w_read_half_i == HalfValue);
    assign s_pack_w_sel            = s_pack_w_en && (pack_write_half_i == HalfValue);
    assign s_bank_cs[BankLow]      = s_w_read_sel || s_pack_w_sel;
    assign s_bank_wren[BankLow]    = s_pack_w_sel && !s_w_read_sel;
    assign s_bank_addr[BankLow]    = s_w_read_sel ? s_w_read_row : s_pack_write_row;
    assign s_bank_wdata[BankLow]   = pack_write_data_i[31:0];
    assign s_bank_wmask[BankLow]   = pack_write_strb_i[3:0];
    assign s_bank_cs[BankLow+1]    = s_w_read_sel || s_pack_w_sel;
    assign s_bank_wren[BankLow+1]  = s_pack_w_sel && !s_w_read_sel;
    assign s_bank_addr[BankLow+1]  = s_w_read_sel ? s_w_read_row : s_pack_write_row;
    assign s_bank_wdata[BankLow+1] = pack_write_data_i[63:32];
    assign s_bank_wmask[BankLow+1] = pack_write_strb_i[7:4];
  end

  // Output staging banks 12-13: one request port, one bank per half.
  for (genvar half = 0; half < 2; half++) begin : gen_out_bank
    localparam int unsigned BankIndex = npu_pkg::OutBankFirst + half;
    localparam logic HalfValue = 1'(half);
    logic s_out_sel;

    assign s_out_sel               = out_req_valid_i && (out_req_half_i == HalfValue);
    assign s_bank_cs[BankIndex]    = s_out_sel;
    assign s_bank_wren[BankIndex]  = s_out_sel && out_req_write_i;
    assign s_bank_addr[BankIndex]  = out_req_addr_i[11:2];
    assign s_bank_wdata[BankIndex] = out_req_data_i;
    assign s_bank_wmask[BankIndex] = out_req_strb_i;
  end

  // Parameter banks 14-15: independent write and read ports; the read port
  // wins a same-bank clash without flagging an error.
  for (genvar bank = 0; bank < 2; bank++) begin : gen_param_bank
    localparam int unsigned BankIndex = npu_pkg::ParamBankFirst + bank;
    localparam logic BankValue = 1'(bank);
    logic s_param_read_sel;
    logic s_param_write_sel;

    assign s_param_read_sel = param_read_valid_i && (param_read_addr_i[12] == BankValue);
    assign s_param_write_sel = param_write_valid_i && (param_write_addr_i[12] == BankValue);
    assign s_bank_cs[BankIndex] = s_param_read_sel || s_param_write_sel;
    assign s_bank_wren[BankIndex] = s_param_write_sel && !s_param_read_sel;
    assign s_bank_addr[BankIndex] =
        s_param_read_sel ? param_read_addr_i[11:2] : param_write_addr_i[11:2];
    assign s_bank_wdata[BankIndex] = param_write_data_i;
    assign s_bank_wmask[BankIndex] = param_write_strb_i;
  end

`ifdef HAVE_SRAM_MACRO
  for (genvar bank = 0; bank < BankCount; bank++) begin : gen_local_bank
    tc_sram_1024x32 u_local_sram (
        .clk_i (clk_i),
        .cs_i  (s_bank_cs[bank]),
        .addr_i(s_bank_addr[bank]),
        .data_i(s_bank_wdata[bank]),
        .mask_i(s_bank_wmask[bank]),
        .wren_i(s_bank_wren[bank]),
        .data_o(s_bank_rdata[bank])
    );
  end
`else
  // Inferred behavioral banks for portable unit simulations (compile with
  // +define+PDK_BEHAV), mirroring the tc_sram_1024x32 wrapper: synchronous
  // read, byte write masks, no reset.
  for (genvar bank = 0; bank < BankCount; bank++) begin : gen_local_bank
    logic [31:0] s_storage_q[0:BankWords-1];
    logic [31:0] s_data_q;

    assign s_bank_rdata[bank] = s_data_q;
    always_ff @(posedge clk_i) begin
      if (s_bank_cs[bank]) begin
        if (!s_bank_wren[bank]) begin
          s_data_q <= s_storage_q[s_bank_addr[bank]];
        end else begin
          if (s_bank_wmask[bank][0]) begin
            s_storage_q[s_bank_addr[bank]][7:0] <= s_bank_wdata[bank][7:0];
          end
          if (s_bank_wmask[bank][1]) begin
            s_storage_q[s_bank_addr[bank]][15:8] <= s_bank_wdata[bank][15:8];
          end
          if (s_bank_wmask[bank][2]) begin
            s_storage_q[s_bank_addr[bank]][23:16] <= s_bank_wdata[bank][23:16];
          end
          if (s_bank_wmask[bank][3]) begin
            s_storage_q[s_bank_addr[bank]][31:24] <= s_bank_wdata[bank][31:24];
          end
          s_data_q <= 32'bx;
        end
      end
    end
  end
`endif

  // Per-word validity metadata: set by accepted writes, functionally cleared
  // by clear_i (or reset); physical SRAM contents are never bulk-reset.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_valid_q <= '0;
    end else if (clear_i) begin
      s_valid_q <= '0;
    end else begin
      if (s_raw_write_en && (raw_write_strb_i != 4'd0)) begin
        s_valid_q[s_raw_write_bank][s_raw_write_row] <= 1'b1;
      end
      if (s_pack_a_en) begin
        if (pack_write_strb_i[3:0] != 4'd0) begin
          s_valid_q[s_pack_a_bank_lo][s_pack_write_row] <= 1'b1;
        end
        if (pack_write_strb_i[7:4] != 4'd0) begin
          s_valid_q[s_pack_a_bank_lo+4'd1][s_pack_write_row] <= 1'b1;
        end
      end
      if (s_pack_w_en) begin
        if (pack_write_strb_i[3:0] != 4'd0) begin
          s_valid_q[s_pack_w_bank_lo][s_pack_write_row] <= 1'b1;
        end
        if (pack_write_strb_i[7:4] != 4'd0) begin
          s_valid_q[s_pack_w_bank_lo+4'd1][s_pack_write_row] <= 1'b1;
        end
      end
      if (out_req_valid_i && out_req_write_i && (out_req_strb_i != 4'd0)) begin
        s_valid_q[s_out_bank][out_req_addr_i[11:2]] <= 1'b1;
      end
      if (param_write_valid_i && (param_write_strb_i != 4'd0) &&
          !(param_read_valid_i && (param_read_addr_i[12] == param_write_addr_i[12]))) begin
        s_valid_q[s_param_write_bank][param_write_addr_i[11:2]] <= 1'b1;
      end
    end
  end

  // Registered read-return selectors (one-cycle synchronous read latency).
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_raw_read_bank_q   <= 2'd0;
      s_a_read_half_q     <= 1'b0;
      s_w_read_half_q     <= 1'b0;
      s_out_read_half_q   <= 1'b0;
      s_param_read_bank_q <= 1'b0;
    end else begin
      if (raw_read_valid_i) begin
        s_raw_read_bank_q <= s_raw_read_bank;
      end
      if (a_read_valid_i) begin
        s_a_read_half_q <= a_read_half_i;
      end
      if (w_read_valid_i) begin
        s_w_read_half_q <= w_read_half_i;
      end
      if (out_req_valid_i && !out_req_write_i) begin
        s_out_read_half_q <= out_req_half_i;
      end
      if (param_read_valid_i) begin
        s_param_read_bank_q <= param_read_addr_i[12];
      end
    end
  end

  assign s_a_read_bank_lo_q = 4'(npu_pkg::PackABankFirst) + {s_a_read_half_q, 1'b0};
  assign s_w_read_bank_lo_q = 4'(npu_pkg::PackWBankFirst) + {s_w_read_half_q, 1'b0};
  assign raw_read_data_o = s_bank_rdata[{2'b00, s_raw_read_bank_q}];
  assign a_read_data_o = {s_bank_rdata[s_a_read_bank_lo_q+4'd1], s_bank_rdata[s_a_read_bank_lo_q]};
  assign w_read_data_o = {s_bank_rdata[s_w_read_bank_lo_q+4'd1], s_bank_rdata[s_w_read_bank_lo_q]};
  assign out_read_data_o = s_bank_rdata[4'(npu_pkg::OutBankFirst)+{3'd0, s_out_read_half_q}];
  assign param_read_data_o = s_bank_rdata[4'(npu_pkg::ParamBankFirst)+{3'd0, s_param_read_bank_q}];

  assign s_err_raw_write = s_raw_conflict;
  assign s_err_raw_read = raw_read_valid_i && !s_valid_q[s_raw_read_bank][s_raw_read_row];
  assign s_err_pack_write = pack_write_valid_i &&
      (s_pack_write_misaligned || s_a_conflict || s_w_conflict);
  assign s_err_a_read = a_read_valid_i &&
      (s_a_read_misaligned || !s_valid_q[s_a_read_bank_lo][s_a_read_row] ||
       !s_valid_q[s_a_read_bank_lo+4'd1][s_a_read_row]);
  assign s_err_w_read = w_read_valid_i &&
      (s_w_read_misaligned || !s_valid_q[s_w_read_bank_lo][s_w_read_row] ||
       !s_valid_q[s_w_read_bank_lo+4'd1][s_w_read_row]);
  assign s_err_out = out_req_valid_i && !out_req_write_i &&
      !s_valid_q[s_out_bank][out_req_addr_i[11:2]];
  assign s_err_param = param_read_valid_i && !s_valid_q[s_param_read_bank][param_read_addr_i[11:2]];

  // First-failing-port priority encode; lowest port code wins within a cycle.
  always_comb begin
    s_access_err = 1'b1;
    if (s_err_raw_write) begin
      s_access_err_port = ErrPortRawWrite;
    end else if (s_err_raw_read) begin
      s_access_err_port = ErrPortRawRead;
    end else if (s_err_pack_write) begin
      s_access_err_port = ErrPortPackWrite;
    end else if (s_err_a_read) begin
      s_access_err_port = ErrPortARead;
    end else if (s_err_w_read) begin
      s_access_err_port = ErrPortWRead;
    end else if (s_err_out) begin
      s_access_err_port = ErrPortOutReq;
    end else if (s_err_param) begin
      s_access_err_port = ErrPortParamRead;
    end else begin
      s_access_err      = 1'b0;
      s_access_err_port = ErrPortNone;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_access_err_sticky_q <= 1'b0;
      s_access_err_port_q   <= ErrPortNone;
    end else if (clear_i) begin
      s_access_err_sticky_q <= 1'b0;
      s_access_err_port_q   <= ErrPortNone;
    end else if (s_access_err && !s_access_err_sticky_q) begin
      s_access_err_sticky_q <= 1'b1;
      s_access_err_port_q   <= s_access_err_port;
    end
  end

  assign access_err_sticky_o = s_access_err_sticky_q;
  assign access_err_port_o = s_access_err_port_q;

  assign s_unused = ^{raw_write_addr_i[1:0], raw_read_addr_i[1:0], out_req_addr_i[1:0],
                      param_write_addr_i[1:0], param_read_addr_i[1:0]} && 1'b0;
endmodule
