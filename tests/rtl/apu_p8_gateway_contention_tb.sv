// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

// APU-P8 Gateway A (APU/SDIO0/USB2) contention evidence.
//
// Three client BFMs model the frozen docs/ip/apu.md burst profiles on the
// real hp_axi4_mux3 round-robin gateway: the APU private DMA (1-16-beat INCR
// descriptor/codec traffic), the SDIO0 DMA block engine (8-16-beat block
// transfers), and the USB2 DMA engine (4-8-beat transfers). All bursts are
// 4 KiB aligned so they never cross a 4 KiB boundary. A downstream model
// applies bounded random stalls (countdown-bounded, at most MaxStall cycles)
// on AW/AR/W/R/B. All randomness comes from seeded xorshift generators; the
// seed defaults to a fixed value and can be overridden with +SEED=<n>.
//
// The scoreboard proves the frozen Gateway A contract:
// (a) every granted ownership is retained until terminal B or RLAST: no
//     downstream address is accepted while a read or write burst is in
//     flight, R/W/B handshakes only ever reach the owning client, beat
//     counts and RLAST/WLAST placement are exact, and end-to-end data tags
//     are uncorrupted in both directions;
// (b) a continuously eligible source is granted within three arbitration
//     decisions, i.e. at most two foreign address grants may pass while it
//     waits, so no client can starve while downstream traffic completes;
// (c) all three clients run to completion with exactly their planned beat
//     counts on the shared fabric identity (address-region attribution,
//     cross-checked between scoreboard, BFMs, and the downstream model);
// (d) idle is declared only after all three clients, the gateway, and the
//     downstream model stay quiescent for eight consecutive cycles.

// Seeded xorshift client BFM: one outstanding transaction at a time, random
// burst lengths, random 4 KiB-aligned addresses, random inter-burst gaps,
// and random R/W/B backpressure.
module gateway_client_bfm #(
    parameter int unsigned        ClientId    = 0,
    parameter int unsigned        ReadBursts  = 8,
    parameter int unsigned        WriteBursts = 8,
    parameter int unsigned        RdMinBeats  = 1,
    parameter int unsigned        RdMaxBeats  = 16,
    parameter int unsigned        WrMinBeats  = 1,
    parameter int unsigned        WrMaxBeats  = 16,
    parameter logic        [31:0] BaseAddr    = 32'h0001_0000
) (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 start_i,
    input  logic          [31:0] seed_i,
    output logic                 done_o,
           axi4_if.master        axi4
);
  logic        [31:0] s_rand_q = 32'h1;
  int unsigned        planned_read_beats = 0;
  int unsigned        planned_write_beats = 0;
  int unsigned        planned_read_bursts = 0;
  int unsigned        planned_write_bursts = 0;
  int unsigned        reads_done;
  int unsigned        writes_done;

  function automatic logic [31:0] data_pattern(input logic [31:0] addr_i,
                                               input int unsigned beat_i);
    logic [31:0] value;
    begin
      value = (addr_i << 5) ^ (addr_i >> 2) ^ 32'hC350_F00D;
      value = value ^ (32'h0001_0101 * 32'(beat_i));
      return value;
    end
  endfunction

  task automatic rand_next(output logic [31:0] value_o);
    begin
      s_rand_q = s_rand_q ^ (s_rand_q << 13);
      s_rand_q = s_rand_q ^ (s_rand_q >> 17);
      s_rand_q = s_rand_q ^ (s_rand_q << 5);
      value_o  = s_rand_q;
    end
  endtask

  // 4 KiB block 0..7 inside the client region, offset so the burst never
  // crosses a 4 KiB boundary.
  function automatic logic [31:0] burst_addr(input logic [31:0] rand_i, input int unsigned beats_i);
    int unsigned word_offset;
    begin
      word_offset = int'(rand_i[9:0]) % (1024 - beats_i + 1);
      return BaseAddr + 32'(int'(rand_i[15:13]) * 4096) + 32'(word_offset * 4);
    end
  endfunction

  task automatic do_read_burst(input logic [31:0] addr_i, input int unsigned beats_i);
    int unsigned        beat;
    logic        [31:0] rand_l;
    logic        [31:0] expected;
    begin
      planned_read_beats  = planned_read_beats + beats_i;
      planned_read_bursts = planned_read_bursts + 1;
      @(negedge clk_i);
      axi4.araddr  = addr_i;
      axi4.arlen   = 8'(beats_i - 1);
      axi4.arsize  = 3'd2;
      axi4.arburst = 2'b01;
      axi4.arvalid = 1'b1;
      @(posedge clk_i);
      while (!axi4.arready) @(posedge clk_i);
      @(negedge clk_i);
      axi4.arvalid = 1'b0;
      beat         = 0;
      while (beat < beats_i) begin
        rand_next(rand_l);
        axi4.rready = ((rand_l % 5) != 32'd0);
        @(posedge clk_i);
        if (axi4.rvalid && axi4.rready) begin
          expected = data_pattern(addr_i + 32'(beat * 4), beat);
          if ((axi4.rdata !== expected) || (axi4.rresp !== 2'b00) ||
              (axi4.rlast !== (beat == (beats_i - 1)))) begin
            $fatal(1, "APU-P8 Gateway A client %0d read data integrity failed at beat %0d",
                   ClientId, beat);
          end
          beat = beat + 1;
        end
        @(negedge clk_i);
      end
      axi4.rready = 1'b0;
    end
  endtask

  task automatic do_write_burst(input logic [31:0] addr_i, input int unsigned beats_i);
    int unsigned        beat;
    logic        [31:0] rand_l;
    begin
      planned_write_beats  = planned_write_beats + beats_i;
      planned_write_bursts = planned_write_bursts + 1;
      @(negedge clk_i);
      axi4.awaddr  = addr_i;
      axi4.awlen   = 8'(beats_i - 1);
      axi4.awsize  = 3'd2;
      axi4.awburst = 2'b01;
      axi4.awvalid = 1'b1;
      @(posedge clk_i);
      while (!axi4.awready) @(posedge clk_i);
      @(negedge clk_i);
      axi4.awvalid = 1'b0;
      beat         = 0;
      while (beat < beats_i) begin
        rand_next(rand_l);
        if ((rand_l % 4) == 32'd0) @(negedge clk_i);
        axi4.wdata  = data_pattern(addr_i + 32'(beat * 4), beat);
        axi4.wstrb  = 4'hF;
        axi4.wlast  = (beat == (beats_i - 1));
        axi4.wvalid = 1'b1;
        @(posedge clk_i);
        while (!axi4.wready) @(posedge clk_i);
        beat = beat + 1;
        @(negedge clk_i);
        axi4.wvalid = 1'b0;
        axi4.wlast  = 1'b0;
      end
      rand_next(rand_l);
      repeat (rand_l % 4) begin
        axi4.bready = 1'b0;
        @(negedge clk_i);
      end
      axi4.bready = 1'b1;
      @(posedge clk_i);
      while (!axi4.bvalid) @(posedge clk_i);
      if (axi4.bresp !== 2'b00) begin
        $fatal(1, "APU-P8 Gateway A client %0d write response error", ClientId);
      end
      @(negedge clk_i);
      axi4.bready = 1'b0;
    end
  endtask

  initial begin
    axi4.awid     = 1'b0;
    axi4.awaddr   = 32'd0;
    axi4.awlen    = 8'd0;
    axi4.awsize   = 3'd2;
    axi4.awburst  = 2'b01;
    axi4.awlock   = 1'b0;
    axi4.awcache  = 4'd0;
    axi4.awprot   = 3'd0;
    axi4.awqos    = 4'd0;
    axi4.awregion = 4'd0;
    axi4.awuser   = 1'b0;
    axi4.awvalid  = 1'b0;
    axi4.wdata    = 32'd0;
    axi4.wstrb    = 4'h0;
    axi4.wlast    = 1'b0;
    axi4.wuser    = 1'b0;
    axi4.wvalid   = 1'b0;
    axi4.bready   = 1'b0;
    axi4.arid     = 1'b0;
    axi4.araddr   = 32'd0;
    axi4.arlen    = 8'd0;
    axi4.arsize   = 3'd2;
    axi4.arburst  = 2'b01;
    axi4.arlock   = 1'b0;
    axi4.arcache  = 4'd0;
    axi4.arprot   = 3'd0;
    axi4.arqos    = 4'd0;
    axi4.arregion = 4'd0;
    axi4.aruser   = 1'b0;
    axi4.arvalid  = 1'b0;
    axi4.rready   = 1'b0;
    done_o        = 1'b0;
    wait (rst_n_i === 1'b1);
    wait (start_i === 1'b1);
    s_rand_q = seed_i ^ (32'h9E37_79B9 * 32'(ClientId + 1));
    if (s_rand_q == 32'd0) s_rand_q = 32'h1;
    reads_done  = 0;
    writes_done = 0;
    @(negedge clk_i);
    while ((reads_done < ReadBursts) || (writes_done < WriteBursts)) begin
      logic        [31:0] rand_l;
      int unsigned        beats;
      rand_next(rand_l);
      if ((reads_done < ReadBursts) && ((writes_done >= WriteBursts) || rand_l[0])) begin
        rand_next(rand_l);
        beats = RdMinBeats + (int'(rand_l[7:0]) % (RdMaxBeats - RdMinBeats + 1));
        rand_next(rand_l);
        do_read_burst(burst_addr(rand_l, beats), beats);
        reads_done = reads_done + 1;
      end else begin
        rand_next(rand_l);
        beats = WrMinBeats + (int'(rand_l[7:0]) % (WrMaxBeats - WrMinBeats + 1));
        rand_next(rand_l);
        do_write_burst(burst_addr(rand_l, beats), beats);
        writes_done = writes_done + 1;
      end
      rand_next(rand_l);
      repeat (rand_l % 4) @(negedge clk_i);
    end
    done_o = 1'b1;
  end
endmodule

// Shared-fabric downstream model: one transaction per direction, exact
// beat/RLAST/WLAST accounting, per-client traffic counters attributed by
// address region, and countdown-bounded random stalls on every channel.
module gateway_downstream_model #(
    parameter int unsigned MaxStall = 5
) (
    input  logic                clk_i,
    input  logic                rst_n_i,
    input  logic         [31:0] seed_i,
    output logic                idle_o,
           axi4_if.slave        axi4
);
  localparam logic [1:0] WrIdle = 2'd0;
  localparam logic [1:0] WrData = 2'd1;
  localparam logic [1:0] WrResp = 2'd2;
  localparam logic RdIdle = 1'd0;
  localparam logic RdData = 1'd1;

  logic        [ 1:0] s_wr_state_q;
  logic               s_rd_state_q;
  logic        [31:0] s_wr_addr_q;
  logic        [31:0] s_rd_addr_q;
  logic        [ 7:0] s_wr_len_q;
  logic        [ 7:0] s_rd_len_q;
  logic        [ 8:0] s_wr_beat_q;
  logic        [ 8:0] s_rd_beat_q;
  logic        [ 3:0] s_aw_delay_q;
  logic        [ 3:0] s_w_delay_q;
  logic        [ 3:0] s_b_delay_q;
  logic        [ 3:0] s_ar_delay_q;
  logic        [ 3:0] s_r_delay_q;
  logic        [31:0] s_rand_wr_q = 32'h1;
  logic        [31:0] s_rand_rd_q = 32'h1;
  logic        [31:0] s_rand_t;
  int unsigned        read_beats          [0:2];
  int unsigned        write_beats         [0:2];

  function automatic logic [31:0] data_pattern(input logic [31:0] addr_i,
                                               input int unsigned beat_i);
    logic [31:0] value;
    begin
      value = (addr_i << 5) ^ (addr_i >> 2) ^ 32'hC350_F00D;
      value = value ^ (32'h0001_0101 * 32'(beat_i));
      return value;
    end
  endfunction

  assign idle_o       = (s_wr_state_q == WrIdle) && (s_rd_state_q == RdIdle);
  assign axi4.awready = (s_wr_state_q == WrIdle) && (s_aw_delay_q == 4'd0);
  assign axi4.wready  = (s_wr_state_q == WrData) && (s_w_delay_q == 4'd0);
  assign axi4.bid     = 1'b0;
  assign axi4.bresp   = 2'b00;
  assign axi4.buser   = 1'b0;
  assign axi4.bvalid  = (s_wr_state_q == WrResp) && (s_b_delay_q == 4'd0);
  assign axi4.arready = (s_rd_state_q == RdIdle) && (s_ar_delay_q == 4'd0);
  assign axi4.rid     = 1'b0;
  assign axi4.rdata   = data_pattern(s_rd_addr_q + {21'd0, s_rd_beat_q, 2'b00}, int'(s_rd_beat_q));
  assign axi4.rresp   = 2'b00;
  assign axi4.rlast   = (s_rd_beat_q == {1'b0, s_rd_len_q});
  assign axi4.ruser   = 1'b0;
  assign axi4.rvalid  = (s_rd_state_q == RdData) && (s_r_delay_q == 4'd0);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_wr_state_q   <= WrIdle;
      s_wr_addr_q    <= 32'd0;
      s_wr_len_q     <= 8'd0;
      s_wr_beat_q    <= 9'd0;
      s_aw_delay_q   <= 4'd0;
      s_w_delay_q    <= 4'd0;
      s_b_delay_q    <= 4'd0;
      write_beats[0] <= 0;
      write_beats[1] <= 0;
      write_beats[2] <= 0;
    end else begin
      case (s_wr_state_q)
        WrIdle: begin
          if (axi4.awvalid && (s_aw_delay_q != 4'd0)) s_aw_delay_q <= s_aw_delay_q - 4'd1;
          if (axi4.awvalid && axi4.awready) begin
            if ((axi4.awaddr[31:20] != 12'h000) || (axi4.awaddr[19:16] < 4'd1) ||
                (axi4.awaddr[19:16] > 4'd3)) begin
              $fatal(1, "APU-P8 Gateway A delivered an unattributable write address 0x%08h",
                     axi4.awaddr);
            end
            if ((axi4.awburst != 2'b01) || (axi4.awsize != 3'd2)) begin
              $fatal(1, "APU-P8 Gateway A corrupted a write address channel");
            end
            s_wr_addr_q  <= axi4.awaddr;
            s_wr_len_q   <= axi4.awlen;
            s_wr_beat_q  <= 9'd0;
            s_wr_state_q <= WrData;
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 13);
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q >> 17);
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 5);
            s_w_delay_q <= 4'(s_rand_wr_q % 32'(MaxStall + 1));
          end
        end
        WrData: begin
          if (axi4.wvalid && axi4.wready) begin
            if (axi4.wdata !== data_pattern(
                    s_wr_addr_q + {21'd0, s_wr_beat_q, 2'b00}, int'(s_wr_beat_q)
                )) begin
              $fatal(1, "APU-P8 Gateway A corrupted write data beat %0d", s_wr_beat_q);
            end
            if (axi4.wstrb !== 4'hF) $fatal(1, "APU-P8 Gateway A corrupted write strobes");
            if (axi4.wlast !== (s_wr_beat_q == {1'b0, s_wr_len_q})) begin
              $fatal(1, "APU-P8 Gateway A corrupted WLAST placement");
            end
            write_beats[int'(s_wr_addr_q[19:16])-1] <= write_beats[int'(s_wr_addr_q[19:16])-1] + 1;
            s_wr_beat_q                             <= s_wr_beat_q + 9'd1;
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 13);
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q >> 17);
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 5);
            s_w_delay_q <= 4'(s_rand_wr_q % 32'(MaxStall + 1));
            if (axi4.wlast) begin
              s_wr_state_q <= WrResp;
              s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 13);
              s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q >> 17);
              s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 5);
              s_b_delay_q <= 4'(s_rand_wr_q % 32'(MaxStall + 1));
            end
          end else if (axi4.wvalid && (s_w_delay_q != 4'd0)) begin
            s_w_delay_q <= s_w_delay_q - 4'd1;
          end
        end
        WrResp: begin
          if (s_b_delay_q != 4'd0) s_b_delay_q <= s_b_delay_q - 4'd1;
          if (axi4.bvalid && axi4.bready) begin
            s_wr_state_q <= WrIdle;
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 13);
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q >> 17);
            s_rand_wr_q = s_rand_wr_q ^ (s_rand_wr_q << 5);
            s_aw_delay_q <= 4'(s_rand_wr_q % 32'(MaxStall + 1));
          end
        end
        default: s_wr_state_q <= WrIdle;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rd_state_q  <= RdIdle;
      s_rd_addr_q   <= 32'd0;
      s_rd_len_q    <= 8'd0;
      s_rd_beat_q   <= 9'd0;
      s_ar_delay_q  <= 4'd0;
      s_r_delay_q   <= 4'd0;
      read_beats[0] <= 0;
      read_beats[1] <= 0;
      read_beats[2] <= 0;
    end else begin
      case (s_rd_state_q)
        RdIdle: begin
          if (axi4.arvalid && (s_ar_delay_q != 4'd0)) s_ar_delay_q <= s_ar_delay_q - 4'd1;
          if (axi4.arvalid && axi4.arready) begin
            if ((axi4.araddr[31:20] != 12'h000) || (axi4.araddr[19:16] < 4'd1) ||
                (axi4.araddr[19:16] > 4'd3)) begin
              $fatal(1, "APU-P8 Gateway A delivered an unattributable read address 0x%08h",
                     axi4.araddr);
            end
            if ((axi4.arburst != 2'b01) || (axi4.arsize != 3'd2)) begin
              $fatal(1, "APU-P8 Gateway A corrupted a read address channel");
            end
            s_rd_addr_q  <= axi4.araddr;
            s_rd_len_q   <= axi4.arlen;
            s_rd_beat_q  <= 9'd0;
            s_rd_state_q <= RdData;
            s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q << 13);
            s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q >> 17);
            s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q << 5);
            s_r_delay_q <= 4'(s_rand_rd_q % 32'(MaxStall + 1));
          end
        end
        RdData: begin
          if (s_r_delay_q != 4'd0) s_r_delay_q <= s_r_delay_q - 4'd1;
          if (axi4.rvalid && axi4.rready) begin
            read_beats[int'(s_rd_addr_q[19:16])-1] <= read_beats[int'(s_rd_addr_q[19:16])-1] + 1;
            s_rd_beat_q                            <= s_rd_beat_q + 9'd1;
            s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q << 13);
            s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q >> 17);
            s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q << 5);
            s_r_delay_q <= 4'(s_rand_rd_q % 32'(MaxStall + 1));
            if (axi4.rlast) begin
              s_rd_state_q <= RdIdle;
              s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q << 13);
              s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q >> 17);
              s_rand_rd_q = s_rand_rd_q ^ (s_rand_rd_q << 5);
              s_ar_delay_q <= 4'(s_rand_rd_q % 32'(MaxStall + 1));
            end
          end
        end
        default: s_rd_state_q <= RdIdle;
      endcase
    end
  end

  initial begin
    wait (rst_n_i === 1'b1);
    s_rand_wr_q = seed_i ^ 32'hD15E_A000;
    s_rand_rd_q = seed_i ^ 32'hD15E_B000;
    if (s_rand_wr_q == 32'd0) s_rand_wr_q = 32'h1;
    if (s_rand_rd_q == 32'd0) s_rand_rd_q = 32'h1;
  end
endmodule

module apu_p8_gateway_contention_tb;
  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               start_i = 1'b0;
  logic        [31:0] seed = 32'd20260916;
  logic        [ 7:0] epoch_i = 8'd0;
  logic               s_apu_done;
  logic               s_sdio0_done;
  logic               s_usb2_done;
  logic               s_downstream_idle;
  logic               s_quiescent;
  logic               s_rd_active_q;
  logic        [ 1:0] s_rd_owner_q;
  logic        [ 7:0] s_rd_len_q;
  logic        [ 8:0] s_rd_beat_q;
  logic               s_wr_active_q;
  logic               s_wr_data_done_q;
  logic        [ 1:0] s_wr_owner_q;
  logic        [ 7:0] s_wr_len_q;
  logic        [ 8:0] s_wr_beat_q;
  logic        [ 2:0] s_eligible;
  logic        [ 2:0] s_rvalids;
  logic        [ 2:0] s_wreadys;
  logic        [ 2:0] s_bvalids;
  logic               s_accept;
  logic        [ 1:0] s_grant;
  int unsigned        s_wait_q            [0:2];
  int unsigned        s_max_wait_q;
  int unsigned        s_sb_read_beats     [0:2];
  int unsigned        s_sb_write_beats    [0:2];
  int unsigned        s_sb_read_bursts    [0:2];
  int unsigned        s_sb_write_bursts   [0:2];
  int unsigned        total_beats;
  int                 quiet;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) apu (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdio0 (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) usb2 (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;

  gateway_client_bfm #(
      .ClientId   (0),
      .ReadBursts (40),
      .WriteBursts(40),
      .RdMinBeats (1),
      .RdMaxBeats (16),
      .WrMinBeats (1),
      .WrMaxBeats (16),
      .BaseAddr   (32'h0001_0000)
  ) u_apu_bfm (
      .clk_i,
      .rst_n_i,
      .start_i,
      .seed_i(seed ^ 32'h0000_0A90),
      .done_o(s_apu_done),
      .axi4  (apu)
  );
  gateway_client_bfm #(
      .ClientId   (1),
      .ReadBursts (24),
      .WriteBursts(24),
      .RdMinBeats (8),
      .RdMaxBeats (16),
      .WrMinBeats (8),
      .WrMaxBeats (16),
      .BaseAddr   (32'h0002_0000)
  ) u_sdio0_bfm (
      .clk_i,
      .rst_n_i,
      .start_i,
      .seed_i(seed ^ 32'h0000_5D10),
      .done_o(s_sdio0_done),
      .axi4  (sdio0)
  );
  gateway_client_bfm #(
      .ClientId   (2),
      .ReadBursts (32),
      .WriteBursts(32),
      .RdMinBeats (4),
      .RdMaxBeats (8),
      .WrMinBeats (4),
      .WrMaxBeats (8),
      .BaseAddr   (32'h0003_0000)
  ) u_usb2_bfm (
      .clk_i,
      .rst_n_i,
      .start_i,
      .seed_i(seed ^ 32'h0000_0B22),
      .done_o(s_usb2_done),
      .axi4  (usb2)
  );

  gateway_downstream_model #(
      .MaxStall(5)
  ) u_downstream (
      .clk_i,
      .rst_n_i,
      .seed_i(seed ^ 32'h0000_D00D),
      .idle_o(s_downstream_idle),
      .axi4  (axi4)
  );

  hp_axi4_mux3 #(
      .RoundRobin       (1'b1),
      .Client0EpochAware(1'b1)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .epoch_i,
      .icache(apu),
      .dcache(sdio0),
      .mmio  (usb2),
      .axi4  (axi4)
  );

  assign s_eligible = {
    usb2.arvalid || usb2.awvalid, sdio0.arvalid || sdio0.awvalid, apu.arvalid || apu.awvalid
  };
  assign s_rvalids = {usb2.rvalid, sdio0.rvalid, apu.rvalid};
  assign s_wreadys = {usb2.wready, sdio0.wready, apu.wready};
  assign s_bvalids = {usb2.bvalid, sdio0.bvalid, apu.bvalid};
  assign s_accept = (axi4.arvalid && axi4.arready) || (axi4.awvalid && axi4.awready);
  assign s_grant   = (axi4.arvalid && axi4.arready) ? (axi4.araddr[17:16] - 2'd1)
                                                    : (axi4.awaddr[17:16] - 2'd1);
  assign s_quiescent = s_apu_done && s_sdio0_done && s_usb2_done && !apu.arvalid &&
      !apu.awvalid && !apu.wvalid && !sdio0.arvalid && !sdio0.awvalid && !sdio0.wvalid &&
      !usb2.arvalid && !usb2.awvalid && !usb2.wvalid && !axi4.arvalid && !axi4.awvalid &&
      !axi4.wvalid && !axi4.rvalid && !axi4.bvalid && s_downstream_idle &&
      (u_dut.s_state_q == 3'd0) && !s_rd_active_q && !s_wr_active_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rd_active_q        <= 1'b0;
      s_rd_owner_q         <= 2'd0;
      s_rd_len_q           <= 8'd0;
      s_rd_beat_q          <= 9'd0;
      s_wr_active_q        <= 1'b0;
      s_wr_data_done_q     <= 1'b0;
      s_wr_owner_q         <= 2'd0;
      s_wr_len_q           <= 8'd0;
      s_wr_beat_q          <= 9'd0;
      s_wait_q[0]          <= 0;
      s_wait_q[1]          <= 0;
      s_wait_q[2]          <= 0;
      s_max_wait_q         <= 0;
      s_sb_read_beats[0]   <= 0;
      s_sb_read_beats[1]   <= 0;
      s_sb_read_beats[2]   <= 0;
      s_sb_write_beats[0]  <= 0;
      s_sb_write_beats[1]  <= 0;
      s_sb_write_beats[2]  <= 0;
      s_sb_read_bursts[0]  <= 0;
      s_sb_read_bursts[1]  <= 0;
      s_sb_read_bursts[2]  <= 0;
      s_sb_write_bursts[0] <= 0;
      s_sb_write_bursts[1] <= 0;
      s_sb_write_bursts[2] <= 0;
    end else begin
      // (a) Ownership retention: no new address while a burst is in flight.
      if (axi4.arvalid && axi4.arready) begin
        if (s_rd_active_q || s_wr_active_q) begin
          $fatal(1, "APU-P8 Gateway A accepted a read address before terminal B/RLAST");
        end
        s_rd_active_q                             <= 1'b1;
        s_rd_owner_q                              <= axi4.araddr[17:16] - 2'd1;
        s_rd_len_q                                <= axi4.arlen;
        s_rd_beat_q                               <= 9'd0;
        s_sb_read_bursts[axi4.araddr[17:16]-2'd1] <= s_sb_read_bursts[axi4.araddr[17:16]-2'd1] + 1;
      end
      if (axi4.awvalid && axi4.awready) begin
        if (s_rd_active_q || s_wr_active_q) begin
          $fatal(1, "APU-P8 Gateway A accepted a write address before terminal B/RLAST");
        end
        s_wr_active_q <= 1'b1;
        s_wr_data_done_q <= 1'b0;
        s_wr_owner_q <= axi4.awaddr[17:16] - 2'd1;
        s_wr_len_q <= axi4.awlen;
        s_wr_beat_q <= 9'd0;
        s_sb_write_bursts[axi4.awaddr[17:16]-2'd1] <=
            s_sb_write_bursts[axi4.awaddr[17:16]-2'd1] + 1;
      end
      if (axi4.wvalid && axi4.wready) begin
        if (!s_wr_active_q || s_wr_data_done_q) begin
          $fatal(1, "APU-P8 Gateway A delivered an orphaned write beat");
        end
        if (axi4.wlast !== (s_wr_beat_q == {1'b0, s_wr_len_q})) begin
          $fatal(1, "APU-P8 Gateway A moved the write burst terminal");
        end
        s_wr_beat_q                    <= s_wr_beat_q + 9'd1;
        s_sb_write_beats[s_wr_owner_q] <= s_sb_write_beats[s_wr_owner_q] + 1;
        if (axi4.wlast) s_wr_data_done_q <= 1'b1;
      end
      if (axi4.bvalid && axi4.bready) begin
        if (!s_wr_active_q || !s_wr_data_done_q) begin
          $fatal(1, "APU-P8 Gateway A delivered B before the write data terminal");
        end
        s_wr_active_q    <= 1'b0;
        s_wr_data_done_q <= 1'b0;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (!s_rd_active_q) $fatal(1, "APU-P8 Gateway A delivered an orphaned read beat");
        if (axi4.rlast !== (s_rd_beat_q == {1'b0, s_rd_len_q})) begin
          $fatal(1, "APU-P8 Gateway A moved the read burst terminal");
        end
        if (axi4.rresp !== 2'b00) $fatal(1, "APU-P8 Gateway A read error response");
        s_rd_beat_q                   <= s_rd_beat_q + 9'd1;
        s_sb_read_beats[s_rd_owner_q] <= s_sb_read_beats[s_rd_owner_q] + 1;
        if (axi4.rlast) s_rd_active_q <= 1'b0;
      end

      // (a) Client-side routing: R/W/B handshakes only ever reach the owner.
      if (s_rd_active_q) begin
        if ((s_rvalids != 3'b000) && (s_rvalids != (3'b001 << s_rd_owner_q))) begin
          $fatal(1, "APU-P8 Gateway A routed read data to a non-owner client");
        end
      end else if (s_rvalids != 3'b000) begin
        $fatal(1, "APU-P8 Gateway A asserted read data with no active read burst");
      end
      if (s_wr_active_q && !s_wr_data_done_q) begin
        if ((s_wreadys != 3'b000) && (s_wreadys != (3'b001 << s_wr_owner_q))) begin
          $fatal(1, "APU-P8 Gateway A routed write ready to a non-owner client");
        end
      end else if (s_wreadys != 3'b000) begin
        $fatal(1, "APU-P8 Gateway A asserted write ready with no active write data");
      end
      if (s_wr_active_q) begin
        if ((s_bvalids != 3'b000) && (s_bvalids != (3'b001 << s_wr_owner_q))) begin
          $fatal(1, "APU-P8 Gateway A routed a write response to a non-owner client");
        end
      end else if (s_bvalids != 3'b000) begin
        $fatal(1, "APU-P8 Gateway A asserted a write response with no active write burst");
      end

      // (b) No starvation: a continuously eligible source loses at most two
      // arbitration decisions before it is granted (bound of three).
      if (s_accept) begin
        for (int client = 0; client < 3; client++) begin
          if (client == int'(s_grant)) begin
            s_wait_q[client] <= 0;
          end else if (s_eligible[client]) begin
            if (s_wait_q[client] >= 2) begin
              $fatal(1,
                     "APU-P8 Gateway A starvation: client %0d lost three consecutive arbitrations",
                     client);
            end
            s_wait_q[client] <= s_wait_q[client] + 1;
            if ((s_wait_q[client] + 1) > s_max_wait_q) s_max_wait_q <= s_wait_q[client] + 1;
          end
        end
      end
    end
  end

  initial begin
    void'($value$plusargs("SEED=%d", seed));
    if (seed == 32'd0) seed = 32'd20260916;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(negedge clk_i);
    start_i = 1'b1;
    wait (s_apu_done && s_sdio0_done && s_usb2_done);
    start_i = 1'b0;

    // (d) Idle is declared only after all three clients, the gateway, and
    // the downstream model stay quiescent for eight consecutive cycles.
    quiet   = 0;
    while (quiet < 8) begin
      @(posedge clk_i);
      if (s_quiescent) quiet = quiet + 1;
      else quiet = 0;
    end

    // (c) Completion with expected byte counts, cross-checked between the
    // scoreboard, the BFMs, and the downstream model.
    if ((s_sb_read_beats[0] != u_apu_bfm.planned_read_beats) ||
        (s_sb_read_beats[1] != u_sdio0_bfm.planned_read_beats) ||
        (s_sb_read_beats[2] != u_usb2_bfm.planned_read_beats)) begin
      $fatal(1, "APU-P8 Gateway A read beat attribution mismatch");
    end
    if ((s_sb_write_beats[0] != u_apu_bfm.planned_write_beats) ||
        (s_sb_write_beats[1] != u_sdio0_bfm.planned_write_beats) ||
        (s_sb_write_beats[2] != u_usb2_bfm.planned_write_beats)) begin
      $fatal(1, "APU-P8 Gateway A write beat attribution mismatch");
    end
    if ((s_sb_read_bursts[0] != u_apu_bfm.planned_read_bursts) ||
        (s_sb_read_bursts[1] != u_sdio0_bfm.planned_read_bursts) ||
        (s_sb_read_bursts[2] != u_usb2_bfm.planned_read_bursts) ||
        (s_sb_write_bursts[0] != u_apu_bfm.planned_write_bursts) ||
        (s_sb_write_bursts[1] != u_sdio0_bfm.planned_write_bursts) ||
        (s_sb_write_bursts[2] != u_usb2_bfm.planned_write_bursts)) begin
      $fatal(1, "APU-P8 Gateway A burst count attribution mismatch");
    end
    for (int client = 0; client < 3; client++) begin
      if ((s_sb_read_beats[client] != u_downstream.read_beats[client]) ||
          (s_sb_write_beats[client] != u_downstream.write_beats[client])) begin
        $fatal(1, "APU-P8 Gateway A downstream counter mismatch for client %0d", client);
      end
      if ((s_sb_read_beats[client] == 0) || (s_sb_write_beats[client] == 0)) begin
        $fatal(1, "APU-P8 Gateway A client %0d made no forward progress", client);
      end
    end
    total_beats = s_sb_read_beats[0] + s_sb_read_beats[1] + s_sb_read_beats[2] +
        s_sb_write_beats[0] + s_sb_write_beats[1] + s_sb_write_beats[2];
    if (total_beats < 700) begin
      $fatal(1, "APU-P8 Gateway A sustained traffic below expectation: %0d beats", total_beats);
    end
    $display(
        "APU-P8 Gateway A contention passed: PASS seed=%0d read_beats=%0d/%0d/%0d write_beats=%0d/%0d/%0d read_bursts=%0d/%0d/%0d write_bursts=%0d/%0d/%0d total_bytes=%0d max_foreign_grants=%0d starvation_bound_arbitrations=3",
        seed, s_sb_read_beats[0], s_sb_read_beats[1], s_sb_read_beats[2], s_sb_write_beats[0],
        s_sb_write_beats[1], s_sb_write_beats[2], s_sb_read_bursts[0], s_sb_read_bursts[1],
        s_sb_read_bursts[2], s_sb_write_bursts[0], s_sb_write_bursts[1], s_sb_write_bursts[2],
        4 * total_beats, s_max_wait_q);
    $finish;
  end

  initial begin
    repeat (150000) @(posedge clk_i);
    $fatal(
        1,
        "APU-P8 Gateway A contention timed out: done=%b%b%b state=%0d rd_active=%b wr_active=%b waits=%0d/%0d/%0d",
        s_apu_done, s_sdio0_done, s_usb2_done, u_dut.s_state_q, s_rd_active_q, s_wr_active_q,
        s_wait_q[0], s_wait_q[1], s_wait_q[2]);
  end

endmodule
