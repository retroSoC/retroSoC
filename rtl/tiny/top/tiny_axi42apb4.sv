// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "mmap_define.svh"

// APB setup/access are separate cycles; rejected bursts never assert PSEL.
module tiny_axi42apb4 (
    input logic         clk_i,
    input logic         rst_n_i,
          axi4_if.slave axi4,
    `include "tiny_apb_ports.svh"
);
  typedef enum logic [2:0] {
    Idle,
    WriteData,
    Setup,
    Access,
    ReadResponse,
    WriteResponse,
    ReadError,
    WriteError
  } state_e;
  state_e s_state_d, s_state_q;
  logic [2:0] s_state_bits_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [31:0] s_data_d, s_data_q;
  logic [3:0] s_wstrb_d, s_wstrb_q;
  logic s_id_d, s_id_q;
  logic s_write_d, s_write_q;
  logic [1:0] s_resp_d, s_resp_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic [15:0] s_select, s_ready, s_error;
  logic [15:0][31:0] s_rdata;
  logic s_access, s_enable, s_done, s_err;
  logic [31:0] s_read_data;

  assign s_state_q    = state_e'(s_state_bits_q);
  assign axi4.arready = s_state_q == Idle;
  assign axi4.awready = (s_state_q == Idle) && !axi4.arvalid;
  assign axi4.wready  = (s_state_q == WriteData) || (s_state_q == WriteError);
  assign axi4.bid     = s_id_q;
  assign axi4.bresp   = s_resp_q;
  assign axi4.buser   = '0;
  assign axi4.bvalid  = s_state_q == WriteResponse;
  assign axi4.rid     = s_id_q;
  assign axi4.rdata   = s_data_q;
  assign axi4.rresp   = s_resp_q;
  assign axi4.ruser   = '0;
  assign axi4.rlast   = s_beat_q == s_len_q;
  assign axi4.rvalid  = (s_state_q == ReadResponse) || (s_state_q == ReadError);
  assign s_access     = (s_state_q == Setup) || (s_state_q == Access);
  assign s_enable     = s_state_q == Access;
  assign s_done       = |(s_select & s_ready);
  assign s_err        = |(s_select & s_error);

  always_comb begin
    s_select = '0;
    `include "tiny_apb_decode.svh"
s_read_data = '0;
    for (int unsigned target = 0; target < 16; target++) begin
      if (s_select[target]) s_read_data = s_rdata[target];
    end
  end
  `include "tiny_apb_wiring.svh"

  always_comb begin
    s_state_d = s_state_q;
    s_addr_d  = s_addr_q;
    s_wdata_d = s_wdata_q;
    s_wstrb_d = s_wstrb_q;
    s_id_d    = s_id_q;
    s_write_d = s_write_q;
    s_resp_d  = s_resp_q;
    s_data_d  = s_data_q;
    s_len_d   = s_len_q;
    s_beat_d  = s_beat_q;
    unique case (s_state_q)
      Idle: begin
        s_beat_d = '0;
        s_data_d = '0;
        s_resp_d = 2'b00;
        if (axi4.arvalid) begin
          s_addr_d  = axi4.araddr;
          s_id_d    = axi4.arid;
          s_write_d = 1'b0;
          s_len_d   = axi4.arlen;
          if ((axi4.arlen != 8'd0) || (axi4.arburst[1]) || axi4.arlock ||
              (axi4.arsize > 3'd2) || (axi4.araddr[1:0] != 2'd0)) begin
            s_resp_d  = 2'b10;
            s_state_d = ReadError;
          end else s_state_d = Setup;
        end else if (axi4.awvalid) begin
          s_addr_d  = axi4.awaddr;
          s_id_d    = axi4.awid;
          s_write_d = 1'b1;
          s_len_d   = axi4.awlen;
          if ((axi4.awlen != 8'd0) || (axi4.awburst[1]) || axi4.awlock ||
              (axi4.awsize > 3'd2) || (axi4.awaddr[1:0] != 2'd0)) begin
            s_resp_d  = 2'b10;
            s_state_d = WriteError;
          end else s_state_d = WriteData;
        end
      end
      WriteData:
      if (axi4.wvalid) begin
        s_wdata_d = axi4.wdata;
        s_wstrb_d = axi4.wstrb;
        if (!axi4.wlast) begin
          s_resp_d  = 2'b10;
          s_state_d = WriteResponse;
        end else s_state_d = Setup;
      end
      Setup: begin
        if (s_select == 16'd0) begin
          s_resp_d  = 2'b11;
          s_state_d = s_write_q ? WriteResponse : ReadResponse;
        end else s_state_d = Access;
      end
      Access:
      if (s_done) begin
        s_resp_d  = s_err ? 2'b10 : 2'b00;
        s_data_d  = s_read_data;
        s_state_d = s_write_q ? WriteResponse : ReadResponse;
      end
      ReadResponse, ReadError:
      if (axi4.rready) begin
        if (s_beat_q == s_len_q) s_state_d = Idle;
        else s_beat_d = s_beat_q + 8'd1;
      end
      WriteResponse: if (axi4.bready) s_state_d = Idle;
      WriteError:
      if (axi4.wvalid) begin
        if (s_beat_q == s_len_q) s_state_d = WriteResponse;
        else s_beat_d = s_beat_q + 8'd1;
      end
      default:       s_state_d = Idle;
    endcase
  end
  dffr #(
      .DATA_WIDTH(3)
  ) u_state_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_addr_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_wdata_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_data_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_d),
      .dat_o  (s_data_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_wstrb_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wstrb_d),
      .dat_o  (s_wstrb_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_id_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_id_d),
      .dat_o  (s_id_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_d),
      .dat_o  (s_write_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_resp_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_d),
      .dat_o  (s_resp_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_len_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_beat_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_beat_d),
      .dat_o  (s_beat_q)
  );
endmodule
