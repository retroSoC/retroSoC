// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module dma_formal;
  localparam int NumChannels = 4;
  localparam int FifoDepth = 4;
  localparam int FifoCountWidth = $clog2(FifoDepth) + 1;

  // verilog_format: off -- formal observations mirror dma_formal_design ports.
  (* anyseq *) (* gclk *) reg clk_i;
  wire          rst_n_i;
  wire          f_past_valid;
  wire [  3:0]  start_i;
  wire [  3:0]  abort_i;
  wire [  3:0]  start_seen;
  wire          abort_seen;
  wire [127:0]  programmed_bytes;
  wire [  3:0]  busy;
  wire [  3:0]  done;
  wire [  3:0]  aborted;
  wire [  3:0]  error;
  wire [  3:0]  abort_pending;
  wire [127:0]  bytes_done;
  wire [127:0]  remaining;
  wire [127:0]  channel_len;
  wire [ 11:0]  fifo_count;
  wire [  3:0]  fifo_push;
  wire [  3:0]  fifo_pop;
  wire [  3:0]  fifo_flush;
  wire [  3:0]  fifo_full;
  wire [  3:0]  fifo_empty;
  wire          read_owner_valid;
  wire [  1:0]  read_owner;
  wire          write_owner_valid;
  wire [  1:0]  write_owner;
  wire [ 31:0]  write_bytes;
  wire [ 31:0]  write_owner_bytes_done;
  wire [ 31:0]  write_owner_len;
  wire          read_start_valid;
  wire          read_start_ready;
  wire [  1:0]  read_start_channel;
  wire          write_start_valid;
  wire          write_start_ready;
  wire [  1:0]  write_start_channel;
  wire          tx_channel_valid;
  wire [  1:0]  tx_channel;
  wire [ 31:0]  tx_channel_bytes_done;
  wire [ 31:0]  tx_channel_len;
  wire          awvalid;
  wire          awready;
  wire          awid;
  wire [ 31:0]  awaddr;
  wire [  7:0]  awlen;
  wire [  2:0]  awsize;
  wire [  1:0]  awburst;
  wire          awlock;
  wire [  3:0]  awcache;
  wire [  2:0]  awprot;
  wire [  3:0]  awqos;
  wire [  3:0]  awregion;
  wire          awuser;
  wire          wvalid;
  wire          wready;
  wire [ 31:0]  wdata;
  wire [  3:0]  wstrb;
  wire          wlast;
  wire          wuser;
  wire          bvalid;
  wire          bready;
  wire          bid;
  wire [  1:0]  bresp;
  wire          buser;
  wire          arvalid;
  wire          arready;
  wire          arid;
  wire [ 31:0]  araddr;
  wire [  7:0]  arlen;
  wire [  2:0]  arsize;
  wire [  1:0]  arburst;
  wire          arlock;
  wire [  3:0]  arcache;
  wire [  2:0]  arprot;
  wire [  3:0]  arqos;
  wire [  3:0]  arregion;
  wire          aruser;
  wire          rvalid;
  wire          rready;
  wire          rid;
  wire [ 31:0]  rdata;
  wire [  1:0]  rresp;
  wire          rlast;
  wire          ruser;
  wire          tx_valid;
  wire          tx_ready;
  wire [ 31:0]  tx_data;
  wire [  3:0]  tx_keep;
  wire [  3:0]  tx_strb;
  wire          tx_last;
  wire          tx_id;
  wire          tx_dest;
  wire          tx_user;
  wire          rx_valid;
  wire          rx_ready;
  wire [ 31:0]  rx_data;
  wire [  3:0]  rx_keep;
  wire [  3:0]  rx_strb;
  wire          rx_last;
  wire          rx_id;
  wire          rx_dest;
  wire          rx_user;
  wire          dvp_rx_valid;
  wire          dvp_rx_ready;
  wire [ 31:0]  dvp_rx_data;
  wire [  3:0]  dvp_rx_keep;
  wire [  3:0]  dvp_rx_strb;
  wire          dvp_rx_last;
  wire          dvp_rx_id;
  wire          dvp_rx_dest;
  wire          dvp_rx_user;
  // verilog_format: on

  logic f_read_inflight_q;
  logic [1:0] f_read_owner_q;
  logic f_write_inflight_q;
  logic [1:0] f_write_owner_q;
  logic f_rburst_active_q;
  logic [4:0] f_rburst_beats_q;
  logic [4:0] f_rburst_beat_q;
  logic f_wburst_active_q;
  logic [4:0] f_wburst_beats_q;
  logic [4:0] f_wburst_beat_q;
  logic f_abort_watch_q;
  logic [4:0] f_abort_age_q;
  logic [NumChannels-1:0] f_completion_event;

  dma_formal_design u_design (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .f_past_valid          (f_past_valid),
      .start_i               (start_i),
      .abort_i               (abort_i),
      .start_seen            (start_seen),
      .abort_seen            (abort_seen),
      .programmed_bytes      (programmed_bytes),
      .busy                  (busy),
      .done                  (done),
      .aborted               (aborted),
      .error                 (error),
      .abort_pending         (abort_pending),
      .bytes_done            (bytes_done),
      .remaining             (remaining),
      .channel_len           (channel_len),
      .fifo_count            (fifo_count),
      .fifo_push             (fifo_push),
      .fifo_pop              (fifo_pop),
      .fifo_flush            (fifo_flush),
      .fifo_full             (fifo_full),
      .fifo_empty            (fifo_empty),
      .read_owner_valid      (read_owner_valid),
      .read_owner            (read_owner),
      .write_owner_valid     (write_owner_valid),
      .write_owner           (write_owner),
      .write_bytes           (write_bytes),
      .write_owner_bytes_done(write_owner_bytes_done),
      .write_owner_len       (write_owner_len),
      .read_start_valid      (read_start_valid),
      .read_start_ready      (read_start_ready),
      .read_start_channel    (read_start_channel),
      .write_start_valid     (write_start_valid),
      .write_start_ready     (write_start_ready),
      .write_start_channel   (write_start_channel),
      .tx_channel_valid      (tx_channel_valid),
      .tx_channel            (tx_channel),
      .tx_channel_bytes_done (tx_channel_bytes_done),
      .tx_channel_len        (tx_channel_len),
      .awvalid               (awvalid),
      .awready               (awready),
      .awid                  (awid),
      .awaddr                (awaddr),
      .awlen                 (awlen),
      .awsize                (awsize),
      .awburst               (awburst),
      .awlock                (awlock),
      .awcache               (awcache),
      .awprot                (awprot),
      .awqos                 (awqos),
      .awregion              (awregion),
      .awuser                (awuser),
      .wvalid                (wvalid),
      .wready                (wready),
      .wdata                 (wdata),
      .wstrb                 (wstrb),
      .wlast                 (wlast),
      .wuser                 (wuser),
      .bvalid                (bvalid),
      .bready                (bready),
      .bid                   (bid),
      .bresp                 (bresp),
      .buser                 (buser),
      .arvalid               (arvalid),
      .arready               (arready),
      .arid                  (arid),
      .araddr                (araddr),
      .arlen                 (arlen),
      .arsize                (arsize),
      .arburst               (arburst),
      .arlock                (arlock),
      .arcache               (arcache),
      .arprot                (arprot),
      .arqos                 (arqos),
      .arregion              (arregion),
      .aruser                (aruser),
      .rvalid                (rvalid),
      .rready                (rready),
      .rid                   (rid),
      .rdata                 (rdata),
      .rresp                 (rresp),
      .rlast                 (rlast),
      .ruser                 (ruser),
      .tx_valid              (tx_valid),
      .tx_ready              (tx_ready),
      .tx_data               (tx_data),
      .tx_keep               (tx_keep),
      .tx_strb               (tx_strb),
      .tx_last               (tx_last),
      .tx_id                 (tx_id),
      .tx_dest               (tx_dest),
      .tx_user               (tx_user),
      .rx_valid              (rx_valid),
      .rx_ready              (rx_ready),
      .rx_data               (rx_data),
      .rx_keep               (rx_keep),
      .rx_strb               (rx_strb),
      .rx_last               (rx_last),
      .rx_id                 (rx_id),
      .rx_dest               (rx_dest),
      .rx_user               (rx_user),
      .dvp_rx_valid          (dvp_rx_valid),
      .dvp_rx_ready          (dvp_rx_ready),
      .dvp_rx_data           (dvp_rx_data),
      .dvp_rx_keep           (dvp_rx_keep),
      .dvp_rx_strb           (dvp_rx_strb),
      .dvp_rx_last           (dvp_rx_last),
      .dvp_rx_id             (dvp_rx_id),
      .dvp_rx_dest           (dvp_rx_dest),
      .dvp_rx_user           (dvp_rx_user)
  );

  always_comb begin
    f_completion_event = '0;
    if (write_owner_valid && bvalid && bready && (bresp == 2'b00) &&
        !abort_pending[write_owner] && !error[write_owner] &&
        ({1'b0, write_owner_bytes_done} + {1'b0, write_bytes} >=
         {1'b0, write_owner_len})) begin
      f_completion_event[write_owner] = 1'b1;
    end
    if (tx_channel_valid && tx_valid && tx_ready && !abort_pending[tx_channel] &&
        !error[tx_channel] &&
        ({1'b0, tx_channel_bytes_done} + 33'd4 >= {1'b0, tx_channel_len})) begin
      f_completion_event[tx_channel] = 1'b1;
    end
  end

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      assume (start_i == 4'd0);
      assume (abort_i == 4'd0);
    end

    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(rx_valid && !rx_ready)) begin
        assume (rx_valid);
        assume (rx_data == $past(rx_data));
        assume (rx_keep == $past(rx_keep));
        assume (rx_strb == $past(rx_strb));
        assume (rx_last == $past(rx_last));
        assume (rx_id == $past(rx_id));
        assume (rx_dest == $past(rx_dest));
        assume (rx_user == $past(rx_user));
      end
      if ($past(dvp_rx_valid && !dvp_rx_ready)) begin
        assume (dvp_rx_valid);
        assume (dvp_rx_data == $past(dvp_rx_data));
        assume (dvp_rx_keep == $past(dvp_rx_keep));
        assume (dvp_rx_strb == $past(dvp_rx_strb));
        assume (dvp_rx_last == $past(dvp_rx_last));
        assume (dvp_rx_id == $past(dvp_rx_id));
        assume (dvp_rx_dest == $past(dvp_rx_dest));
        assume (dvp_rx_user == $past(dvp_rx_user));
      end
    end

    if (rst_n_i) begin
      assume ((start_i & (start_i - 4'd1)) == 4'd0);
      assume ((start_i & start_seen) == 4'd0);
      assume ((start_i & busy) == 4'd0);
      assume (abort_i[3:2] == 2'd0);
      assume (!abort_i[0]);
      assume (!abort_i[1] || (!abort_seen && busy[1] && tx_valid && !tx_ready));
    end
  end

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(awvalid && !awready)) begin
        assert (awvalid);
        assert (awid == $past(awid));
        assert (awaddr == $past(awaddr));
        assert (awlen == $past(awlen));
        assert (awsize == $past(awsize));
        assert (awburst == $past(awburst));
        assert (awlock == $past(awlock));
        assert (awcache == $past(awcache));
        assert (awprot == $past(awprot));
        assert (awqos == $past(awqos));
        assert (awregion == $past(awregion));
        assert (awuser == $past(awuser));
      end
      if ($past(wvalid && !wready)) begin
        assert (wvalid);
        assert (wdata == $past(wdata));
        assert (wstrb == $past(wstrb));
        assert (wlast == $past(wlast));
        assert (wuser == $past(wuser));
      end
      if ($past(arvalid && !arready)) begin
        assert (arvalid);
        assert (arid == $past(arid));
        assert (araddr == $past(araddr));
        assert (arlen == $past(arlen));
        assert (arsize == $past(arsize));
        assert (arburst == $past(arburst));
        assert (arlock == $past(arlock));
        assert (arcache == $past(arcache));
        assert (arprot == $past(arprot));
        assert (arqos == $past(arqos));
        assert (arregion == $past(arregion));
        assert (aruser == $past(aruser));
      end
      if ($past(tx_valid && !tx_ready)) begin
        assert (tx_valid);
        assert (tx_data == $past(tx_data));
        assert (tx_keep == $past(tx_keep));
        assert (tx_strb == $past(tx_strb));
        assert (tx_last == $past(tx_last));
        assert (tx_id == $past(tx_id));
        assert (tx_dest == $past(tx_dest));
        assert (tx_user == $past(tx_user));
      end
      if ($past(bvalid && !bready)) begin
        assert (bvalid);
        assert (bid == $past(bid));
        assert (bresp == $past(bresp));
        assert (buser == $past(buser));
      end
      if ($past(rvalid && !rready)) begin
        assert (rvalid);
        assert (rid == $past(rid));
        assert (rdata == $past(rdata));
        assert (rresp == $past(rresp));
        assert (rlast == $past(rlast));
        assert (ruser == $past(ruser));
      end
    end
  end

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      f_read_inflight_q  <= 1'b0;
      f_read_owner_q     <= 2'd0;
      f_write_inflight_q <= 1'b0;
      f_write_owner_q    <= 2'd0;
      f_rburst_active_q  <= 1'b0;
      f_rburst_beats_q   <= 5'd0;
      f_rburst_beat_q    <= 5'd0;
      f_wburst_active_q  <= 1'b0;
      f_wburst_beats_q   <= 5'd0;
      f_wburst_beat_q    <= 5'd0;
      f_abort_watch_q    <= 1'b0;
      f_abort_age_q      <= 5'd0;
    end else begin
      if (f_read_inflight_q) begin
        assert (read_owner_valid);
        assert (read_owner == f_read_owner_q);
        if (rvalid && rready && rlast) begin
          f_read_inflight_q <= 1'b0;
        end
      end
      if (arvalid && arready) begin
        assert (!f_read_inflight_q);
        assert (read_owner_valid);
        f_read_inflight_q <= 1'b1;
        f_read_owner_q    <= read_owner;
      end

      if (f_write_inflight_q) begin
        assert (write_owner_valid);
        assert (write_owner == f_write_owner_q);
        if (bvalid && bready) begin
          f_write_inflight_q <= 1'b0;
        end
      end
      if (awvalid && awready) begin
        assert (!f_write_inflight_q);
        assert (write_owner_valid);
        f_write_inflight_q <= 1'b1;
        f_write_owner_q    <= write_owner;
      end

      if (f_rburst_active_q && rvalid && rready) begin
        assert (rlast == ((f_rburst_beat_q + 1'b1) == f_rburst_beats_q));
        if (rlast) begin
          f_rburst_active_q <= 1'b0;
        end else begin
          f_rburst_beat_q <= f_rburst_beat_q + 1'b1;
        end
      end
      if (arvalid && arready) begin
        assert (!f_rburst_active_q);
        f_rburst_active_q <= 1'b1;
        f_rburst_beats_q  <= {1'b0, arlen[3:0]} + 1'b1;
        f_rburst_beat_q   <= 5'd0;
      end

      if (f_wburst_active_q && wvalid && wready) begin
        assert (wlast == ((f_wburst_beat_q + 1'b1) == f_wburst_beats_q));
        if (wlast) begin
          f_wburst_active_q <= 1'b0;
        end else begin
          f_wburst_beat_q <= f_wburst_beat_q + 1'b1;
        end
      end
      if (awvalid && awready) begin
        assert (!f_wburst_active_q);
        f_wburst_active_q <= 1'b1;
        f_wburst_beats_q  <= {1'b0, awlen[3:0]} + 1'b1;
        f_wburst_beat_q   <= 5'd0;
      end

      if (abort_i[1]) begin
        f_abort_watch_q <= 1'b1;
        f_abort_age_q   <= 5'd0;
      end else if (f_abort_watch_q && aborted[1]) begin
        f_abort_watch_q <= 1'b0;
        f_abort_age_q   <= 5'd0;
      end else if (f_abort_watch_q) begin
        assert (f_abort_age_q < 5'd15);
        f_abort_age_q <= f_abort_age_q + 1'b1;
      end
    end
  end

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      if (arvalid) begin
        assert (arid == 1'b0);
        assert (arsize == 3'd2);
        assert (arlen <= 8'd3);
        assert ((arburst == 2'b00) || (arburst == 2'b01));
        assert (araddr[1:0] == 2'b00);
        if (arburst == 2'b00) begin
          assert (arlen == 8'd0);
        end else begin
          assert ({1'b0, araddr[11:0]} + (({5'd0, arlen} + 13'd1) << 2) <= 13'd4096);
        end
      end
      if (awvalid) begin
        assert (awid == 1'b0);
        assert (awsize == 3'd2);
        assert (awlen <= 8'd3);
        assert ((awburst == 2'b00) || (awburst == 2'b01));
        assert (awaddr[1:0] == 2'b00);
        if (awburst == 2'b00) begin
          assert (awlen == 8'd0);
        end else begin
          assert ({1'b0, awaddr[11:0]} + (({5'd0, awlen} + 13'd1) << 2) <= 13'd4096);
        end
      end

      for (int unsigned channel = 0; channel < NumChannels; channel++) begin
        assert (fifo_count[(channel*FifoCountWidth)+:FifoCountWidth] <= FifoCountWidth'(FifoDepth));
        if (!fifo_flush[channel] && fifo_pop[channel]) begin
          assert (!fifo_empty[channel]);
        end
        if (!fifo_flush[channel] && fifo_push[channel] && fifo_full[channel]) begin
          assert (fifo_pop[channel] && !fifo_empty[channel]);
        end
        assert (bytes_done[(channel*32)+:32] <= programmed_bytes[(channel*32)+:32]);
        assert (bytes_done[(channel*32)+:2] == 2'd0);
        assert (bytes_done[(channel*32)+:32] <= channel_len[(channel*32)+:32]);
        assert (remaining[(channel*32)+:32] + bytes_done[(channel*32)+:32] ==
                channel_len[(channel*32)+:32]);
        if (error[channel] || aborted[channel]) begin
          assert (!done[channel]);
        end
        if (abort_pending[channel]) begin
          assert (!(read_start_valid && (read_start_channel == channel[1:0])));
          assert (!(write_start_valid && (write_start_channel == channel[1:0])));
        end
        if (aborted[channel]) begin
          assert (!busy[channel]);
          assert (!(read_owner_valid && (read_owner == channel[1:0])));
          assert (!(write_owner_valid && (write_owner == channel[1:0])));
          assert (!(f_read_inflight_q && (f_read_owner_q == channel[1:0])));
          assert (!(f_write_inflight_q && (f_write_owner_q == channel[1:0])));
          assert (!(tx_valid && tx_channel_valid && (tx_channel == channel[1:0])));
        end
        if (f_past_valid && done[channel] && !$past(done[channel])) begin
          assert ($past(f_completion_event[channel]));
        end
      end

      if (write_owner_valid && wvalid) begin
        assert (!fifo_empty[write_owner]);
      end
      if (tx_channel_valid && tx_valid) begin
        assert (!fifo_empty[tx_channel]);
      end

      for (int unsigned fault_channel = 0; fault_channel < NumChannels; fault_channel++) begin
        if (f_past_valid && ((error[fault_channel] && !$past(
                error[fault_channel]
            )) || (aborted[fault_channel] && !$past(
                aborted[fault_channel]
            )))) begin
          for (int unsigned other_channel = 0; other_channel < NumChannels; other_channel++) begin
            if ((other_channel != fault_channel) && done[other_channel] && !$past(
                    done[other_channel]
                )) begin
              assert ($past(f_completion_event[other_channel]));
            end
          end
        end
      end

      cover (arvalid && !arready);
      cover (awvalid && !awready);
      cover (wvalid && !wready);
      cover (tx_valid && !tx_ready);
      cover (start_seen[0] && done[0] && !error[0] && !aborted[0] &&
             (bytes_done[0+:32] == programmed_bytes[0+:32]));
      cover (abort_seen && aborted[1] && !done[1] && !error[1]);
      cover (abort_seen && aborted[1] && busy[0] && !done[0]);
      cover (start_seen[2] && rx_valid && rx_ready);
      cover (start_seen[3] && error[3] && !done[3]);
      cover (start_seen[3] && error[3] && busy[0] && !done[0]);
    end
  end

endmodule
