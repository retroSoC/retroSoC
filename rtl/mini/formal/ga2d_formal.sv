`ifdef GA2D_FORMAL_PROPERTIES
// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ga2d_formal;
  // verilog_format: off -- protocol observations remain grouped by AXI channel.
  (* anyseq *) (* gclk *) reg clk_i;
  wire                    rst_n_i;
  wire                    f_past_valid;
  wire [3:0]              scenario;
  wire                    start_i;
  wire                    resource_stop_i;
  wire                    bridge_clear_busy_i;
  wire [7:0]              bridge_epoch_i;
  wire                    busy;
  wire                    draining;
  wire                    done;
  wire                    aborted;
  wire                    error;
  wire                    recovery_required;
  wire                    safe_idle;
  wire [2:0]              irq_event;
  wire                    error_valid;
  wire [6:0]              error_code;
  wire [3:0]              error_stage;
  wire [1:0]              error_axi_response;
  wire [31:0]             error_address;
  wire [63:0]             read_bytes;
  wire [63:0]             write_bytes;
  wire [15:0]             lines_done;
  wire [5:0]              foreground_fifo_count;
  wire [5:0]              background_fifo_count;
  wire [5:0]              output_fifo_count;
  wire                    read_reserved;
  wire                    read_owner;
  wire                    next_read_owner;
  wire                    inplace_background;
  wire [31:0]             bg_captured_pixels;
  wire [32:0]             write_cover_end_pixel;
  wire                    awvalid;
  wire                    awready;
  wire [2:0]              awid;
  wire [31:0]             awaddr;
  wire [7:0]              awlen;
  wire [2:0]              awsize;
  wire [1:0]              awburst;
  wire                    awlock;
  wire [3:0]              awcache;
  wire [2:0]              awprot;
  wire [3:0]              awqos;
  wire [3:0]              awregion;
  wire                    awuser;
  wire                    wvalid;
  wire                    wready;
  wire [63:0]             wdata;
  wire [7:0]              wstrb;
  wire                    wlast;
  wire                    wuser;
  wire                    bvalid;
  wire                    bready;
  wire [2:0]              bid;
  wire [1:0]              bresp;
  wire                    buser;
  wire                    arvalid;
  wire                    arready;
  wire [2:0]              arid;
  wire [31:0]             araddr;
  wire [7:0]              arlen;
  wire [2:0]              arsize;
  wire [1:0]              arburst;
  wire                    arlock;
  wire [3:0]              arcache;
  wire [2:0]              arprot;
  wire [3:0]              arqos;
  wire [3:0]              arregion;
  wire                    aruser;
  wire                    rvalid;
  wire                    rready;
  wire [2:0]              rid;
  wire [63:0]             rdata;
  wire [1:0]              rresp;
  wire                    rlast;
  wire                    ruser;
  wire                    protocol_residual_rvalid;
  // verilog_format: on

  logic        s_read_inflight_q;
  logic        s_write_inflight_q;
  logic [8:0]  s_read_beats_q;
  logic        s_read_owner_inflight_q;
  logic        s_blend_foreground_retired_q;
  logic [8:0]  s_write_beats_q;
  logic        s_stop_seen_q;
  logic [7:0]  s_stop_age_q;

  ga2d_formal_design u_design (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .f_past_valid            (f_past_valid),
      .scenario                (scenario),
      .start_i                 (start_i),
      .resource_stop_i         (resource_stop_i),
      .bridge_clear_busy_i     (bridge_clear_busy_i),
      .bridge_epoch_i          (bridge_epoch_i),
      .busy                    (busy),
      .draining                (draining),
      .done                    (done),
      .aborted                 (aborted),
      .error                   (error),
      .recovery_required       (recovery_required),
      .safe_idle               (safe_idle),
      .irq_event               (irq_event),
      .error_valid             (error_valid),
      .error_code              (error_code),
      .error_stage             (error_stage),
      .error_axi_response      (error_axi_response),
      .error_address           (error_address),
      .read_bytes              (read_bytes),
      .write_bytes             (write_bytes),
      .lines_done              (lines_done),
      .foreground_fifo_count   (foreground_fifo_count),
      .background_fifo_count   (background_fifo_count),
      .output_fifo_count       (output_fifo_count),
      .read_reserved           (read_reserved),
      .read_owner              (read_owner),
      .next_read_owner         (next_read_owner),
      .inplace_background      (inplace_background),
      .bg_captured_pixels      (bg_captured_pixels),
      .write_cover_end_pixel   (write_cover_end_pixel),
      .awvalid                 (awvalid),
      .awready                 (awready),
      .awid                    (awid),
      .awaddr                  (awaddr),
      .awlen                   (awlen),
      .awsize                  (awsize),
      .awburst                 (awburst),
      .awlock                  (awlock),
      .awcache                 (awcache),
      .awprot                  (awprot),
      .awqos                   (awqos),
      .awregion                (awregion),
      .awuser                  (awuser),
      .wvalid                  (wvalid),
      .wready                  (wready),
      .wdata                   (wdata),
      .wstrb                   (wstrb),
      .wlast                   (wlast),
      .wuser                   (wuser),
      .bvalid                  (bvalid),
      .bready                  (bready),
      .bid                     (bid),
      .bresp                   (bresp),
      .buser                   (buser),
      .arvalid                 (arvalid),
      .arready                 (arready),
      .arid                    (arid),
      .araddr                  (araddr),
      .arlen                   (arlen),
      .arsize                  (arsize),
      .arburst                 (arburst),
      .arlock                  (arlock),
      .arcache                 (arcache),
      .arprot                  (arprot),
      .arqos                   (arqos),
      .arregion                (arregion),
      .aruser                  (aruser),
      .rvalid                  (rvalid),
      .rready                  (rready),
      .rid                     (rid),
      .rdata                   (rdata),
      .rresp                   (rresp),
      .rlast                   (rlast),
      .ruser                   (ruser),
      .protocol_residual_rvalid(protocol_residual_rvalid)
  );

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_read_inflight_q            <= 1'b0;
      s_write_inflight_q           <= 1'b0;
      s_read_beats_q               <= '0;
      s_read_owner_inflight_q      <= 1'b0;
      s_blend_foreground_retired_q <= 1'b0;
      s_write_beats_q              <= '0;
      s_stop_seen_q                <= 1'b0;
      s_stop_age_q                 <= '0;
    end else begin
      if (resource_stop_i) begin
        s_stop_seen_q <= 1'b1;
      end

      if (bridge_clear_busy_i) begin
        s_read_inflight_q       <= 1'b0;
        s_write_inflight_q      <= 1'b0;
        s_read_beats_q          <= '0;
        s_read_owner_inflight_q <= 1'b0;
        s_write_beats_q         <= '0;
      end else begin
        if (arvalid && arready) begin
          assert (!s_read_inflight_q);
          s_read_inflight_q       <= 1'b1;
          s_read_beats_q          <= {1'b0, arlen} + 1'b1;
          s_read_owner_inflight_q <= read_owner;
        end
        if (rvalid && rready) begin
          assert (s_read_inflight_q);
          assert (s_read_beats_q != 0);
          assert (rlast == (s_read_beats_q == 9'd1));
          if (rlast) begin
            s_read_inflight_q <= 1'b0;
            s_read_beats_q    <= '0;
            if ((scenario == 4'd9) || (scenario == 4'd10)) begin
              if (!s_read_owner_inflight_q) begin
                s_blend_foreground_retired_q <= 1'b1;
              end else begin
                assert (s_blend_foreground_retired_q);
              end
            end
          end else begin
            s_read_beats_q <= s_read_beats_q - 1'b1;
          end
        end

        if (awvalid && awready) begin
          assert (!s_write_inflight_q);
          s_write_inflight_q <= 1'b1;
          s_write_beats_q    <= {1'b0, awlen} + 1'b1;
        end
        if (wvalid && wready) begin
          assert (s_write_inflight_q);
          assert (s_write_beats_q != 0);
          assert (wlast == (s_write_beats_q == 9'd1));
          if (wlast) begin
            s_write_beats_q <= '0;
          end else begin
            s_write_beats_q <= s_write_beats_q - 1'b1;
          end
        end
        if (bvalid && bready) begin
          assert (s_write_inflight_q);
          assert (s_write_beats_q == 0);
          s_write_inflight_q <= 1'b0;
        end
      end

      if (!s_stop_seen_q) begin
        s_stop_age_q <= '0;
      end else if (s_stop_age_q != 8'hff) begin
        s_stop_age_q <= s_stop_age_q + 1'b1;
      end
    end

    if (rst_n_i && f_past_valid && $past(f_past_valid)) begin
      if ($past(awvalid && !awready) && !$past(bridge_clear_busy_i) && !bridge_clear_busy_i) begin
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
      if ($past(wvalid && !wready) && !$past(bridge_clear_busy_i) && !bridge_clear_busy_i) begin
        assert (wvalid);
        assert (wdata == $past(wdata));
        assert (wstrb == $past(wstrb));
        assert (wlast == $past(wlast));
        assert (wuser == $past(wuser));
      end
      if ($past(arvalid && !arready) && !$past(bridge_clear_busy_i) && !bridge_clear_busy_i) begin
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
        assert (read_owner == $past(read_owner));
      end
      if ($past(
              s_read_inflight_q
          ) && s_read_inflight_q && !$past(
              bridge_clear_busy_i
          ) && !bridge_clear_busy_i) begin
        assert (read_owner == $past(read_owner));
      end
      if ($past(
              ((scenario == 4'd9) || (scenario == 4'd10)) &&
                rvalid && rready && rlast && (rresp == 2'd0) &&
                (rid == 3'd0)
          )) begin
        assert (next_read_owner == !$past(read_owner));
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
      if (resource_stop_i && !$past(awvalid)) begin
        assert (!awvalid);
      end
      if (resource_stop_i && !$past(arvalid)) begin
        assert (!arvalid);
      end
    end

    if (rst_n_i) begin
      if (awvalid) begin
        assert (awid == 3'd0);
        assert (awsize == 3'd3);
        assert (awlen <= 8'd15);
        assert (output_fifo_count >= ({1'b0, awlen} + 9'd1));
        assert (awburst == 2'b01);
        assert (awaddr[2:0] == 3'd0);
        assert (awlock == 1'b0);
        assert (awcache == 4'd0);
        assert (awprot == 3'd0);
        assert (awqos == 4'd0);
        assert (awregion == 4'd0);
        assert (awuser == 1'b0);
        assert ({1'b0, awaddr[11:0]} + (({5'd0, awlen} + 13'd1) << 3) <= 13'd4096);
      end
      if (arvalid) begin
        assert (arid == 3'd0);
        assert (arlen <= 8'd15);
        assert ((arlen == 8'd0) || (arsize == 3'd3));
        assert ((araddr & ((32'd1 << arsize) - 1'b1)) == 32'd0);
        assert (arburst == 2'b01);
        assert (arlock == 1'b0);
        assert (arcache == 4'd0);
        assert (arprot == 3'd0);
        assert (arqos == 4'd0);
        assert (arregion == 4'd0);
        assert (aruser == 1'b0);
        assert ({1'b0, araddr[11:0]} + (({5'd0, arlen} + 13'd1) << arsize) <= 13'd4096);
      end
      if (wvalid) begin
        assert (wstrb != 8'd0);
      end
      assert (foreground_fifo_count <= 6'd32);
      assert (background_fifo_count <= 6'd32);
      assert (output_fifo_count <= 6'd32);
      if (arvalid) begin
        assert (read_reserved);
        if (!read_owner) begin
          assert ({3'd0, foreground_fifo_count} + ({1'b0, arlen} + 9'd1) <= 9'd32);
        end else begin
          assert ({3'd0, background_fifo_count} + ({1'b0, arlen} + 9'd1) <= 9'd32);
        end
      end
      if (s_read_inflight_q && !bridge_clear_busy_i) begin
        assert (read_reserved);
        assert (read_owner == s_read_owner_inflight_q);
        if (!read_owner) begin
          assert ({3'd0, foreground_fifo_count} + s_read_beats_q <= 9'd32);
        end else begin
          assert ({3'd0, background_fifo_count} + s_read_beats_q <= 9'd32);
        end
      end
      if (awvalid && inplace_background) begin
        assert ({1'b0, bg_captured_pixels} >= write_cover_end_pixel);
      end
      if (safe_idle) begin
        assert (!busy);
        assert (!draining);
        assert (!s_read_inflight_q);
        assert (!s_write_inflight_q);
        assert (foreground_fifo_count == 6'd0);
        assert (background_fifo_count == 6'd0);
        assert (output_fifo_count == 6'd0);
        assert (!read_reserved);
      end
      if (error) begin
        assert (!done);
      end
      assume (scenario <= 4'd10);
      if (scenario == 4'd5) begin
        assert (!done);
      end
      if (scenario == 4'd3 && s_stop_seen_q && (s_stop_age_q >= 8'd20)) begin
        assert (safe_idle);
        assert (aborted);
      end
      if ((scenario == 4'd8) && protocol_residual_rvalid) begin
        assert (error);
        assert (recovery_required);
        assert (read_reserved);
        assert (!rready);
        assert (!arvalid);
        assert (!safe_idle);
      end
      if ((scenario == 4'd9) || (scenario == 4'd10)) begin
        assert (!error);
      end

      cover (scenario == 4'd0 && done && safe_idle && (write_bytes == 64'd2));
      cover (scenario == 4'd1 && done && safe_idle &&
             (read_bytes == 64'd2) && (write_bytes == 64'd2));
      cover (scenario == 4'd3 && aborted && safe_idle);
      cover (scenario == 4'd4 && error && recovery_required && safe_idle);
      cover (scenario == 4'd5 && error && error_valid);
      cover (scenario == 4'd2 && awvalid && awready && (awlen == 8'd14));
      cover (scenario == 4'd7 && awvalid && awready && (awlen == 8'd15));
      cover ((scenario == 4'd8) && protocol_residual_rvalid && error &&
             recovery_required && !rready && !arvalid && !safe_idle);
      cover (scenario == 4'd9 && done && safe_idle && (read_bytes == 64'd3));
      cover (scenario == 4'd10 && done && safe_idle && inplace_background &&
             (bg_captured_pixels >= write_cover_end_pixel));
      cover (awvalid && !awready);
      cover (wvalid && !wready);
      cover (arvalid && !arready);
    end
  end
endmodule
`endif
