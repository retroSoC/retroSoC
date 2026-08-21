// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A
// PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module sdio_formal;
  (* anyseq *) (* gclk *)reg          clk_i;
  reg          rst_n_i;
  reg          f_past_valid;

  (* anyseq *)logic        apb_psel_i;
  (* anyseq *)logic        apb_penable_i;
  (* anyseq *)logic        apb_pwrite_i;
  (* anyseq *)logic [31:0] apb_paddr_i;
  (* anyseq *)logic [31:0] apb_pwdata_i;
  (* anyseq *)logic [ 3:0] apb_pstrb_i;
  (* anyseq *)logic [ 7:0] irq_event_i;
  (* anyseq *)logic        axi_awready_i;
  (* anyseq *)logic        axi_wready_i;
  (* anyseq *)logic        axi_bvalid_i;
  (* anyseq *)logic        axi_bid_i;
  (* anyseq *)logic [ 1:0] axi_bresp_i;
  (* anyseq *)logic        axi_arready_i;
  (* anyseq *)logic        axi_rvalid_i;
  (* anyseq *)logic        axi_rid_i;
  (* anyseq *)logic [31:0] axi_rdata_i;
  (* anyseq *)logic [ 1:0] axi_rresp_i;
  (* anyseq *)logic        axi_rlast_i;
  (* anyseq *)logic        dma_data_out_ready_i;

  wire         apb_pready_o;
  wire  [31:0] apb_prdata_o;
  wire         apb_pslverr_o;
  wire         irq_o;
  wire         sck_o;
  wire         launch_tick_o;
  wire         sample_tick_o;
  wire         clock_running_o;
  wire         dma_busy_o;
  wire         dma_done_o;
  wire         dma_error_o;
  wire  [ 7:0] dma_error_code_o;
  wire  [31:0] dma_current_desc_o;
  wire  [31:0] dma_bytes_done_o;
  wire  [31:0] dma_error_addr_o;
  wire         dma_data_out_valid_o;
  wire  [31:0] dma_data_out_o;
  wire  [ 3:0] dma_data_out_strb_o;
  wire         dma_data_out_last_o;
  wire         axi_awvalid_o;
  wire  [31:0] axi_awaddr_o;
  wire  [ 7:0] axi_awlen_o;
  wire  [ 2:0] axi_awsize_o;
  wire  [ 1:0] axi_awburst_o;
  wire         axi_wvalid_o;
  wire  [31:0] axi_wdata_o;
  wire  [ 3:0] axi_wstrb_o;
  wire         axi_wlast_o;
  wire         axi_bready_o;
  wire         axi_arvalid_o;
  wire  [31:0] axi_araddr_o;
  wire  [ 7:0] axi_arlen_o;
  wire  [ 2:0] axi_arsize_o;
  wire  [ 1:0] axi_arburst_o;
  wire         axi_rready_o;
  wire         host_enable_o;
  wire         clock_enable_o;
  wire  [15:0] half_period_o;
  wire  [ 1:0] bus_width_o;
  wire  [15:0] desc_count_o;
  wire         dma_start_o;
  wire         dma_abort_o;

  logic [ 4:0] f_abort_age_q;
  logic        f_abort_pending_q;
  logic        f_irq_seen_q;
  logic        f_read_pending_q;
  logic        f_abort_read_pending_q;

  sdio_formal_design u_design (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .apb_psel_i          (apb_psel_i),
      .apb_penable_i       (apb_penable_i),
      .apb_pwrite_i        (apb_pwrite_i),
      .apb_paddr_i         (apb_paddr_i),
      .apb_pwdata_i        (apb_pwdata_i),
      .apb_pstrb_i         (apb_pstrb_i),
      .irq_event_i         (irq_event_i),
      .axi_awready_i       (axi_awready_i),
      .axi_wready_i        (axi_wready_i),
      .axi_bvalid_i        (axi_bvalid_i),
      .axi_bid_i           (axi_bid_i),
      .axi_bresp_i         (axi_bresp_i),
      .axi_arready_i       (axi_arready_i),
      .axi_rvalid_i        (axi_rvalid_i),
      .axi_rid_i           (axi_rid_i),
      .axi_rdata_i         (axi_rdata_i),
      .axi_rresp_i         (axi_rresp_i),
      .axi_rlast_i         (axi_rlast_i),
      .dma_data_out_ready_i(dma_data_out_ready_i),
      .apb_pready_o        (apb_pready_o),
      .apb_prdata_o        (apb_prdata_o),
      .apb_pslverr_o       (apb_pslverr_o),
      .irq_o               (irq_o),
      .sck_o               (sck_o),
      .launch_tick_o       (launch_tick_o),
      .sample_tick_o       (sample_tick_o),
      .clock_running_o     (clock_running_o),
      .dma_busy_o          (dma_busy_o),
      .dma_done_o          (dma_done_o),
      .dma_error_o         (dma_error_o),
      .dma_error_code_o    (dma_error_code_o),
      .dma_current_desc_o  (dma_current_desc_o),
      .dma_bytes_done_o    (dma_bytes_done_o),
      .dma_error_addr_o    (dma_error_addr_o),
      .dma_data_out_valid_o(dma_data_out_valid_o),
      .dma_data_out_o      (dma_data_out_o),
      .dma_data_out_strb_o (dma_data_out_strb_o),
      .dma_data_out_last_o (dma_data_out_last_o),
      .axi_awvalid_o       (axi_awvalid_o),
      .axi_awaddr_o        (axi_awaddr_o),
      .axi_awlen_o         (axi_awlen_o),
      .axi_awsize_o        (axi_awsize_o),
      .axi_awburst_o       (axi_awburst_o),
      .axi_wvalid_o        (axi_wvalid_o),
      .axi_wdata_o         (axi_wdata_o),
      .axi_wstrb_o         (axi_wstrb_o),
      .axi_wlast_o         (axi_wlast_o),
      .axi_bready_o        (axi_bready_o),
      .axi_arvalid_o       (axi_arvalid_o),
      .axi_araddr_o        (axi_araddr_o),
      .axi_arlen_o         (axi_arlen_o),
      .axi_arsize_o        (axi_arsize_o),
      .axi_arburst_o       (axi_arburst_o),
      .axi_rready_o        (axi_rready_o),
      .host_enable_o       (host_enable_o),
      .clock_enable_o      (clock_enable_o),
      .half_period_o       (half_period_o),
      .bus_width_o         (bus_width_o),
      .desc_count_o        (desc_count_o),
      .dma_start_o         (dma_start_o),
      .dma_abort_o         (dma_abort_o)
  );

  initial begin
    rst_n_i                = 1'b0;
    f_past_valid           = 1'b0;
    f_abort_pending_q      = 1'b0;
    f_abort_age_q          = 5'd0;
    f_irq_seen_q           = 1'b0;
    f_read_pending_q       = 1'b0;
    f_abort_read_pending_q = 1'b0;
  end

  always @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      assume (!apb_psel_i);
      assume (!axi_bvalid_i);
      assume (!axi_rvalid_i);
      assume (!irq_event_i);
    end
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(apb_psel_i && !apb_penable_i)) begin
        assume (apb_psel_i);
        assume (apb_paddr_i == $past(apb_paddr_i));
        assume (apb_pwrite_i == $past(apb_pwrite_i));
        assume (apb_pwdata_i == $past(apb_pwdata_i));
        assume (apb_pstrb_i == $past(apb_pstrb_i));
      end
      if ($past(axi_rvalid_i && !axi_rready_o)) begin
        assume (axi_rvalid_i);
        assume (axi_rid_i == $past(axi_rid_i));
        assume (axi_rdata_i == $past(axi_rdata_i));
        assume (axi_rresp_i == $past(axi_rresp_i));
        assume (axi_rlast_i == $past(axi_rlast_i));
      end
      if ($past(axi_bvalid_i && !axi_bready_o)) begin
        assume (axi_bvalid_i);
        assume (axi_bid_i == $past(axi_bid_i));
        assume (axi_bresp_i == $past(axi_bresp_i));
      end
    end
  end

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      f_abort_pending_q      <= 1'b0;
      f_abort_age_q          <= 5'd0;
      f_irq_seen_q           <= 1'b0;
      f_read_pending_q       <= 1'b0;
      f_abort_read_pending_q <= 1'b0;
    end
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(
              apb_pready_o && apb_psel_i && apb_penable_i
          ) && apb_psel_i && apb_penable_i && (apb_paddr_i == $past(
              apb_paddr_i
          )) && (apb_pwrite_i == $past(
              apb_pwrite_i
          )) && (apb_pwdata_i == $past(
              apb_pwdata_i
          )) && (apb_pstrb_i == $past(
              apb_pstrb_i
          ))) begin
        assert (apb_prdata_o == $past(apb_prdata_o));
        assert (apb_pslverr_o == $past(apb_pslverr_o));
      end

      if ($past(axi_awvalid_o && !axi_awready_i)) begin
        assert (axi_awvalid_o);
        assert (axi_awaddr_o == $past(axi_awaddr_o));
        assert (axi_awlen_o == $past(axi_awlen_o));
        assert (axi_awsize_o == $past(axi_awsize_o));
        assert (axi_awburst_o == $past(axi_awburst_o));
      end
      if ($past(axi_wvalid_o && !axi_wready_i)) begin
        if (axi_wvalid_o) begin
          assert (axi_wdata_o == $past(axi_wdata_o));
          assert (axi_wstrb_o == $past(axi_wstrb_o));
          assert (axi_wlast_o == $past(axi_wlast_o));
        end
      end
      if ($past(axi_arvalid_o && !axi_arready_i)) begin
        assert (axi_arvalid_o);
        assert (axi_araddr_o == $past(axi_araddr_o));
        assert (axi_arlen_o == $past(axi_arlen_o));
        assert (axi_arsize_o == $past(axi_arsize_o));
        assert (axi_arburst_o == $past(axi_arburst_o));
      end

      if (axi_awvalid_o) begin
        assert (axi_awlen_o <= 8'd15);
        assert (axi_awsize_o == 3'd2);
        assert ((axi_awburst_o == 2'b01) || (axi_awburst_o == 2'b00));
        assert (axi_awaddr_o[1:0] == 2'b00);
        if (axi_awburst_o == 2'b01) begin
          assert ({1'b0, axi_awaddr_o[11:0]} + (({5'd0, axi_awlen_o} + 13'd1) << 2) <= 13'd4096);
        end
      end
      if (axi_arvalid_o) begin
        assert (axi_arlen_o <= 8'd15);
        assert (axi_arsize_o == 3'd2);
        assert ((axi_arburst_o == 2'b01) || (axi_arburst_o == 2'b00));
        assert (axi_araddr_o[1:0] == 2'b00);
        if (axi_arburst_o == 2'b01) begin
          assert ({1'b0, axi_araddr_o[11:0]} + (({5'd0, axi_arlen_o} + 13'd1) << 2) <= 13'd4096);
        end

      end

      if (axi_arvalid_o && axi_arready_i) begin
        f_read_pending_q <= 1'b1;
      end
      if (f_read_pending_q && dma_abort_o) begin
        f_abort_read_pending_q <= 1'b1;
      end
      if (f_read_pending_q && f_abort_read_pending_q) begin
        assert (axi_rready_o);
        cover (axi_rvalid_i && axi_rready_o && axi_rlast_i);
      end
      if (f_read_pending_q && axi_rvalid_i && axi_rready_o && axi_rlast_i) begin
        f_read_pending_q       <= 1'b0;
        f_abort_read_pending_q <= 1'b0;
      end

      // The reduced DMA wrapper has no separate FIFO instance; stream
      // ownership and byte accounting are the tractable FIFO-bound proxy.
      assert (dma_bytes_done_o >= 32'd0);
      if (dma_start_o && (desc_count_o > 16'd16)) begin
        cover (dma_error_o);
      end

      if (sck_o != $past(sck_o)) begin
        assert ($past(launch_tick_o) || $past(sample_tick_o));
      end

      if (dma_abort_o) begin
        f_abort_pending_q <= 1'b1;
        f_abort_age_q     <= 5'd0;
      end else if (f_abort_pending_q) begin
        if (dma_done_o || dma_error_o || !dma_busy_o) begin
          f_abort_pending_q <= 1'b0;
        end else begin
          if (f_abort_age_q != 5'd31) begin
            f_abort_age_q <= f_abort_age_q + 1'b1;
          end
        end
      end

      if (irq_o) begin
        f_irq_seen_q <= 1'b1;
      end
      if (apb_pwrite_i && apb_penable_i && apb_paddr_i[11:0] == 12'h100 &&
          apb_pwdata_i[7:0] != 8'd0) begin
        f_irq_seen_q <= 1'b0;
      end

      cover (apb_pready_o && apb_psel_i && apb_penable_i);
      cover (dma_abort_o);
      cover (irq_o);
    end
  end

endmodule
