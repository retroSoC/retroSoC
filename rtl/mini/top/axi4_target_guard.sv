// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

module axi4_target_guard #(
    parameter int unsigned AddrWidth  = 32,
    parameter int unsigned DataWidth  = 64,
    parameter int unsigned IdWidth    = 6,
    parameter int unsigned UserWidth  = 1,
    parameter int unsigned ReadDepth  = 4,
    parameter int unsigned WriteDepth = 2
) (
    // verilog_format: off -- preserve the timeout/isolation boundary columns
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 clear_i,
    input  logic          [31:0] timeout_i,
    output logic                 clear_busy_o,
    output logic                 abort_o,
    input  logic                 abort_done_i,
    output logic                 timeout_valid_o,
    output logic                 isolated_o,
    output logic                 timeout_write_o,
    output logic [IdWidth-1:0]   timeout_id_o,
    output logic [AddrWidth-1:0] timeout_addr_o,
           axi4_if.slave         source,
           axi4_if.master        sink
    // verilog_format: on
);
  localparam int unsigned StrbWidth = DataWidth / 8;
  localparam int unsigned AddrChannelWidth =
      IdWidth + AddrWidth + 8 + 3 + 2 + 1 + 4 + 3 + 4 + 4 + UserWidth;

  typedef enum logic [2:0] {
    ReadIdle,
    ReadSend,
    ReadForward,
    ReadAbort,
    ReadSynthetic
  } read_state_e;

  typedef enum logic [2:0] {
    WriteIdle,
    WriteSend,
    WriteStream,
    WriteResponse,
    WriteAbort,
    WriteDrop,
    WriteSynthetic
  } write_state_e;

  logic [AddrChannelWidth-1:0] s_ar_push_data;
  logic [AddrChannelWidth-1:0] s_ar_head_data;
  logic [AddrChannelWidth-1:0] s_aw_push_data;
  logic [AddrChannelWidth-1:0] s_aw_head_data;
  logic                        s_ar_full;
  logic                        s_ar_empty;
  logic                        s_ar_push;
  logic                        s_ar_pop;
  logic                        s_aw_full;
  logic                        s_aw_empty;
  logic                        s_aw_push;
  logic                        s_aw_pop;
  logic [ $clog2(ReadDepth):0] unused_ar_count;
  logic [$clog2(WriteDepth):0] unused_aw_count;

  logic [         IdWidth-1:0] s_ar_id;
  logic [       AddrWidth-1:0] s_ar_addr;
  logic [                 7:0] s_ar_len;
  logic [                 2:0] s_ar_size;
  logic [                 1:0] s_ar_burst;
  logic                        s_ar_lock;
  logic [                 3:0] s_ar_cache;
  logic [                 2:0] s_ar_prot;
  logic [                 3:0] s_ar_qos;
  logic [                 3:0] s_ar_region;
  logic [       UserWidth-1:0] s_ar_user;

  logic [         IdWidth-1:0] s_aw_id;
  logic [       AddrWidth-1:0] s_aw_addr;
  logic [                 7:0] s_aw_len;
  logic [                 2:0] s_aw_size;
  logic [                 1:0] s_aw_burst;
  logic                        s_aw_lock;
  logic [                 3:0] s_aw_cache;
  logic [                 2:0] s_aw_prot;
  logic [                 3:0] s_aw_qos;
  logic [                 3:0] s_aw_region;
  logic [       UserWidth-1:0] s_aw_user;

  read_state_e s_read_state_d, s_read_state_q;
  write_state_e s_write_state_d, s_write_state_q;
  logic [IdWidth-1:0] s_read_id_d, s_read_id_q;
  logic [AddrWidth-1:0] s_read_addr_d, s_read_addr_q;
  logic [8:0] s_read_remaining_d, s_read_remaining_q;
  logic [31:0] s_read_timeout_d, s_read_timeout_q;
  logic [IdWidth-1:0] s_write_id_d, s_write_id_q;
  logic [AddrWidth-1:0] s_write_addr_d, s_write_addr_q;
  logic [31:0] s_write_timeout_d, s_write_timeout_q;
  logic s_write_last_seen_d, s_write_last_seen_q;
  logic s_isolated_d, s_isolated_q;
  logic s_timeout_read;
  logic s_timeout_write;
  logic s_read_progress;
  logic s_write_progress;
  logic s_read_timeout_enable;
  logic s_write_timeout_enable;

  assign s_ar_push_data = {
    source.arid,
    source.araddr,
    source.arlen,
    source.arsize,
    source.arburst,
    source.arlock,
    source.arcache,
    source.arprot,
    source.arqos,
    source.arregion,
    source.aruser
  };
  assign {
    s_ar_id,
    s_ar_addr,
    s_ar_len,
    s_ar_size,
    s_ar_burst,
    s_ar_lock,
    s_ar_cache,
    s_ar_prot,
    s_ar_qos,
    s_ar_region,
    s_ar_user
  } = s_ar_head_data;
  assign s_aw_push_data = {
    source.awid,
    source.awaddr,
    source.awlen,
    source.awsize,
    source.awburst,
    source.awlock,
    source.awcache,
    source.awprot,
    source.awqos,
    source.awregion,
    source.awuser
  };
  assign {
    s_aw_id,
    s_aw_addr,
    s_aw_len,
    s_aw_size,
    s_aw_burst,
    s_aw_lock,
    s_aw_cache,
    s_aw_prot,
    s_aw_qos,
    s_aw_region,
    s_aw_user
  } = s_aw_head_data;

  assign source.arready = !s_ar_full && !clear_i;
  assign source.awready = !s_aw_full && !clear_i;
  assign s_ar_push = source.arvalid && source.arready;
  assign s_aw_push = source.awvalid && source.awready;

  fifo #(
      .DATA_WIDTH  (AddrChannelWidth),
      .BUFFER_DEPTH(ReadDepth)
  ) u_ar_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (s_ar_push),
      .full_o (s_ar_full),
      .dat_i  (s_ar_push_data),
      .pop_i  (s_ar_pop),
      .empty_o(s_ar_empty),
      .dat_o  (s_ar_head_data),
      .cnt_o  (unused_ar_count)
  );
  fifo #(
      .DATA_WIDTH  (AddrChannelWidth),
      .BUFFER_DEPTH(WriteDepth)
  ) u_aw_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (s_aw_push),
      .full_o (s_aw_full),
      .dat_i  (s_aw_push_data),
      .pop_i  (s_aw_pop),
      .empty_o(s_aw_empty),
      .dat_o  (s_aw_head_data),
      .cnt_o  (unused_aw_count)
  );

  assign sink.arid = s_ar_id;
  assign sink.araddr = s_ar_addr;
  assign sink.arlen = s_ar_len;
  assign sink.arsize = s_ar_size;
  assign sink.arburst = s_ar_burst;
  assign sink.arlock = s_ar_lock;
  assign sink.arcache = s_ar_cache;
  assign sink.arprot = s_ar_prot;
  assign sink.arqos = s_ar_qos;
  assign sink.arregion = s_ar_region;
  assign sink.aruser = s_ar_user;
  assign sink.arvalid = (s_read_state_q == ReadSend) && !s_isolated_q;
  assign s_ar_pop = ((s_read_state_q == ReadSend) &&
                     (sink.arready || s_timeout_read || s_isolated_q)) ||
                    ((s_read_state_q == ReadIdle) && s_isolated_q && !s_ar_empty);

  assign source.rid = (s_read_state_q == ReadSynthetic) ? s_read_id_q : sink.rid;
  assign source.rdata = (s_read_state_q == ReadSynthetic) ? '0 : sink.rdata;
  assign source.rresp = (s_read_state_q == ReadSynthetic) ? `AXI4_RESP_SLAVE_ERROR : sink.rresp;
  assign source.rlast = (s_read_state_q == ReadSynthetic) ?
                        (s_read_remaining_q == 9'd1) : sink.rlast;
  assign source.ruser = (s_read_state_q == ReadSynthetic) ? '0 : sink.ruser;
  assign source.rvalid = (s_read_state_q == ReadSynthetic) ||
                         ((s_read_state_q == ReadForward) && sink.rvalid);
  assign sink.rready = (s_read_state_q == ReadForward) ? source.rready :
                       ((s_read_state_q == ReadAbort) ||
                        (s_read_state_q == ReadSynthetic));

  assign s_read_progress = (sink.arvalid && sink.arready) ||
                           ((s_read_state_q == ReadForward) && sink.rvalid && sink.rready);
  assign s_read_timeout_enable = (timeout_i != 32'd0) &&
                                 (((s_read_state_q == ReadSend) && !sink.arready) ||
                                  ((s_read_state_q == ReadForward) && source.rready &&
                                   !sink.rvalid));
  assign s_timeout_read = s_read_timeout_enable && (s_read_timeout_q == timeout_i - 1'b1);

  always_comb begin
    s_read_state_d     = s_read_state_q;
    s_read_id_d        = s_read_id_q;
    s_read_addr_d      = s_read_addr_q;
    s_read_remaining_d = s_read_remaining_q;
    s_read_timeout_d   = s_read_timeout_q;
    if (s_read_state_q == ReadIdle) begin
      s_read_timeout_d = '0;
      if (!s_ar_empty && s_isolated_q) begin
        s_read_id_d        = s_ar_id;
        s_read_addr_d      = s_ar_addr;
        s_read_remaining_d = {1'b0, s_ar_len} + 1'b1;
        s_read_state_d     = ReadSynthetic;
      end else if (!s_ar_empty) begin
        s_read_state_d = ReadSend;
      end
    end else if (s_isolated_q && (s_read_state_q == ReadSend)) begin
      s_read_id_d        = s_ar_id;
      s_read_addr_d      = s_ar_addr;
      s_read_remaining_d = {1'b0, s_ar_len} + 1'b1;
      s_read_state_d     = ReadSynthetic;
    end else if (s_isolated_q && (s_read_state_q == ReadForward)) begin
      s_read_state_d = ReadAbort;
    end else if (s_timeout_read) begin
      s_read_timeout_d = '0;
      if (s_read_state_q == ReadSend) begin
        s_read_id_d        = s_ar_id;
        s_read_addr_d      = s_ar_addr;
        s_read_remaining_d = {1'b0, s_ar_len} + 1'b1;
        s_read_state_d     = ReadSynthetic;
      end else begin
        s_read_id_d    = s_read_id_q;
        s_read_addr_d  = s_read_addr_q;
        s_read_state_d = ReadAbort;
      end
    end else begin
      s_read_timeout_d = s_read_progress ? 32'd0 :
          s_read_timeout_enable ? s_read_timeout_q + 1'b1 : s_read_timeout_q;
      unique case (s_read_state_q)
        ReadSend: begin
          if (sink.arvalid && sink.arready) begin
            s_read_id_d        = s_ar_id;
            s_read_addr_d      = s_ar_addr;
            s_read_remaining_d = {1'b0, s_ar_len} + 1'b1;
            s_read_state_d     = ReadForward;
          end
        end
        ReadForward: begin
          if (sink.rvalid && sink.rready) begin
            if (s_read_remaining_q != 9'd0) s_read_remaining_d = s_read_remaining_q - 1'b1;
            if (sink.rlast || (s_read_remaining_q == 9'd1)) s_read_state_d = ReadIdle;
          end
        end
        ReadAbort: if (abort_done_i) s_read_state_d = ReadSynthetic;
        ReadSynthetic: begin
          if (source.rvalid && source.rready) begin
            if (s_read_remaining_q == 9'd1) begin
              s_read_remaining_d = '0;
              s_read_state_d     = ReadIdle;
            end else begin
              s_read_remaining_d = s_read_remaining_q - 1'b1;
            end
          end
        end
        default:   s_read_state_d = ReadIdle;
      endcase
    end
    if (clear_i) s_read_state_d = ReadIdle;
  end

  assign sink.awid = s_aw_id;
  assign sink.awaddr = s_aw_addr;
  assign sink.awlen = s_aw_len;
  assign sink.awsize = s_aw_size;
  assign sink.awburst = s_aw_burst;
  assign sink.awlock = s_aw_lock;
  assign sink.awcache = s_aw_cache;
  assign sink.awprot = s_aw_prot;
  assign sink.awqos = s_aw_qos;
  assign sink.awregion = s_aw_region;
  assign sink.awuser = s_aw_user;
  assign sink.awvalid = (s_write_state_q == WriteSend) && !s_isolated_q;
  assign s_aw_pop = ((s_write_state_q == WriteSend) &&
                     (sink.awready || s_timeout_write || s_isolated_q)) ||
                    ((s_write_state_q == WriteIdle) && s_isolated_q && !s_aw_empty);

  assign sink.wdata = source.wdata;
  assign sink.wstrb = source.wstrb;
  assign sink.wlast = source.wlast;
  assign sink.wuser = source.wuser;
  assign sink.wvalid = (s_write_state_q == WriteStream) && source.wvalid;
  assign source.wready = (s_write_state_q == WriteStream) ? sink.wready :
                         (s_write_state_q == WriteDrop);

  assign source.bid = (s_write_state_q == WriteSynthetic) ? s_write_id_q : sink.bid;
  assign source.bresp = (s_write_state_q == WriteSynthetic) ? `AXI4_RESP_SLAVE_ERROR : sink.bresp;
  assign source.buser = (s_write_state_q == WriteSynthetic) ? '0 : sink.buser;
  assign source.bvalid = (s_write_state_q == WriteSynthetic) ||
                         ((s_write_state_q == WriteResponse) && sink.bvalid);
  assign sink.bready = (s_write_state_q == WriteResponse) ? source.bready :
                       ((s_write_state_q == WriteAbort) ||
                        (s_write_state_q == WriteSynthetic));

  assign s_write_progress = (sink.awvalid && sink.awready) ||
                            (sink.wvalid && sink.wready) ||
                            ((s_write_state_q == WriteResponse) && sink.bvalid && sink.bready);
  assign s_write_timeout_enable = (timeout_i != 32'd0) &&
      (((s_write_state_q == WriteSend) && !sink.awready) ||
       ((s_write_state_q == WriteStream) && source.wvalid && !sink.wready) ||
       ((s_write_state_q == WriteResponse) && source.bready && !sink.bvalid));
  assign s_timeout_write = s_write_timeout_enable && (s_write_timeout_q == timeout_i - 1'b1);

  always_comb begin
    s_write_state_d     = s_write_state_q;
    s_write_id_d        = s_write_id_q;
    s_write_addr_d      = s_write_addr_q;
    s_write_timeout_d   = s_write_timeout_q;
    s_write_last_seen_d = s_write_last_seen_q;
    if (s_write_state_q == WriteIdle) begin
      s_write_timeout_d   = '0;
      s_write_last_seen_d = 1'b0;
      if (!s_aw_empty && s_isolated_q) begin
        s_write_id_d    = s_aw_id;
        s_write_addr_d  = s_aw_addr;
        s_write_state_d = WriteDrop;
      end else if (!s_aw_empty) begin
        s_write_state_d = WriteSend;
      end
    end else if (s_isolated_q && (s_write_state_q == WriteSend)) begin
      s_write_id_d    = s_aw_id;
      s_write_addr_d  = s_aw_addr;
      s_write_state_d = WriteDrop;
    end else if (s_isolated_q && ((s_write_state_q == WriteStream) ||
                                  (s_write_state_q == WriteResponse))) begin
      s_write_state_d = WriteAbort;
    end else if (s_timeout_write) begin
      s_write_timeout_d = '0;
      if (s_write_state_q == WriteSend) begin
        s_write_id_d    = s_aw_id;
        s_write_addr_d  = s_aw_addr;
        s_write_state_d = WriteDrop;
      end else begin
        s_write_state_d = WriteAbort;
      end
    end else begin
      s_write_timeout_d = s_write_progress ? 32'd0 :
          s_write_timeout_enable ? s_write_timeout_q + 1'b1 : s_write_timeout_q;
      unique case (s_write_state_q)
        WriteSend: begin
          if (sink.awvalid && sink.awready) begin
            s_write_id_d    = s_aw_id;
            s_write_addr_d  = s_aw_addr;
            s_write_state_d = WriteStream;
          end
        end
        WriteStream: begin
          if (sink.wvalid && sink.wready && sink.wlast) begin
            s_write_last_seen_d = 1'b1;
            s_write_state_d     = WriteResponse;
          end
        end
        WriteResponse: begin
          if (sink.bvalid && sink.bready) s_write_state_d = WriteIdle;
        end
        WriteAbort: begin
          if (abort_done_i) begin
            s_write_state_d = s_write_last_seen_q ? WriteSynthetic : WriteDrop;
          end
        end
        WriteDrop: begin
          if (source.wvalid && source.wready && source.wlast) begin
            s_write_last_seen_d = 1'b1;
            s_write_state_d     = WriteSynthetic;
          end
        end
        WriteSynthetic: begin
          if (source.bvalid && source.bready) s_write_state_d = WriteIdle;
        end
        default: s_write_state_d = WriteIdle;
      endcase
    end
    if (clear_i) s_write_state_d = WriteIdle;
  end

  always_comb begin
    s_isolated_d = s_isolated_q;
    if ((s_timeout_read && (s_read_state_q == ReadForward)) ||
        (s_timeout_write && ((s_write_state_q == WriteStream) ||
                             (s_write_state_q == WriteResponse)))) begin
      s_isolated_d = 1'b1;
    end
  end

  assign abort_o = (s_read_state_q == ReadAbort) || (s_write_state_q == WriteAbort);
  assign clear_busy_o = clear_i || abort_o;
  assign timeout_valid_o = s_timeout_read || s_timeout_write;
  assign isolated_o = s_isolated_q;
  assign timeout_write_o = s_timeout_write;
  assign timeout_id_o = s_timeout_write ?
                        ((s_write_state_q == WriteSend) ? s_aw_id : s_write_id_q) :
                        ((s_read_state_q == ReadSend) ? s_ar_id : s_read_id_q);
  assign timeout_addr_o = s_timeout_write ?
                          ((s_write_state_q == WriteSend) ? s_aw_addr : s_write_addr_q) :
                          ((s_read_state_q == ReadSend) ? s_ar_addr : s_read_addr_q);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_state_q      <= ReadIdle;
      s_read_id_q         <= '0;
      s_read_addr_q       <= '0;
      s_read_remaining_q  <= '0;
      s_read_timeout_q    <= '0;
      s_write_state_q     <= WriteIdle;
      s_write_id_q        <= '0;
      s_write_addr_q      <= '0;
      s_write_timeout_q   <= '0;
      s_write_last_seen_q <= 1'b0;
      s_isolated_q        <= 1'b0;
    end else begin
      s_read_state_q      <= s_read_state_d;
      s_read_id_q         <= s_read_id_d;
      s_read_addr_q       <= s_read_addr_d;
      s_read_remaining_q  <= s_read_remaining_d;
      s_read_timeout_q    <= s_read_timeout_d;
      s_write_state_q     <= s_write_state_d;
      s_write_id_q        <= s_write_id_d;
      s_write_addr_q      <= s_write_addr_d;
      s_write_timeout_q   <= s_write_timeout_d;
      s_write_last_seen_q <= s_write_last_seen_d;
      s_isolated_q        <= s_isolated_d;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth < 1) || (DataWidth < 8) || ((DataWidth % 8) != 0) ||
        (IdWidth < 1) || (UserWidth < 1) || (ReadDepth < 2) || (WriteDepth < 2) ||
        ((ReadDepth & (ReadDepth - 1)) != 0) ||
        ((WriteDepth & (WriteDepth - 1)) != 0) || (StrbWidth < 1)) begin
      $fatal(1, "axi4_target_guard: invalid interface or queue geometry");
    end
  end
`endif
endmodule
