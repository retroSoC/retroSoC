// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module opipsram_formal;

  (* anyseq *) (* gclk *)reg         clk_i;

  wire        rst_n_i;
  wire        f_past_valid;

  wire        awvalid;
  wire        awready;
  wire        awid;
  wire [31:0] awaddr;
  wire [ 7:0] awlen;
  wire [ 2:0] awsize;
  wire [ 1:0] awburst;
  wire        awlock;
  wire [ 3:0] awcache;
  wire [ 2:0] awprot;
  wire [ 3:0] awqos;
  wire [ 3:0] awregion;
  wire        awuser;
  wire        wvalid;
  wire        wready;
  wire [31:0] wdata;
  wire [ 3:0] wstrb;
  wire        wlast;
  wire        wuser;
  wire        bvalid;
  wire        bready;
  wire        bid;
  wire [ 1:0] bresp;
  wire        buser;
  wire        arvalid;
  wire        arready;
  wire        arid;
  wire [31:0] araddr;
  wire [ 7:0] arlen;
  wire [ 2:0] arsize;
  wire [ 1:0] arburst;
  wire        arlock;
  wire [ 3:0] arcache;
  wire [ 2:0] arprot;
  wire [ 3:0] arqos;
  wire [ 3:0] arregion;
  wire        aruser;
  wire        rvalid;
  wire        rready;
  wire        rid;
  wire [31:0] rdata;
  wire [ 1:0] rresp;
  wire        rlast;
  wire        ruser;

  wire        apb_psel;
  wire        apb_penable;
  wire        apb_pwrite;
  wire [31:0] apb_paddr;
  wire [31:0] apb_pwdata;
  wire [ 3:0] apb_pstrb;
  wire [ 2:0] apb_pprot;
  wire        apb_pready;
  wire [31:0] apb_prdata;
  wire        apb_pslverr;

  wire        core_mem_req_valid;
  wire        core_mem_req_ready;
  wire        core_mem_req_write;
  wire [31:0] core_mem_req_addr;
  wire [ 3:0] core_mem_req_len;
  wire [31:0] core_mem_req_wdata;
  wire [ 3:0] core_mem_req_wstrb;
  wire        core_mem_rsp_valid;
  wire        core_mem_rsp_ready;
  wire        core_mem_rsp_error;
  wire [31:0] core_mem_rsp_rdata;
  wire        core_phy_req_valid;
  wire        core_phy_req_ready;
  wire        core_phy_req_profile_hyper;
  wire        core_phy_req_write;
  wire        core_phy_req_indirect_register;
  wire [31:0] core_phy_req_addr;
  wire [ 3:0] core_phy_req_len;
  wire [63:0] core_phy_req_wdata;
  wire [15:0] core_phy_req_opi_cmd;
  wire        core_phy_req_opi_width16;
  wire [31:0] core_phy_req_opi_timing;
  wire [31:0] core_phy_req_hyper_timing;
  wire [31:0] core_phy_req_cs_timing;
  wire [31:0] core_phy_req_clk_config;
  wire [ 7:0] core_phy_req_rx_delay;
  wire [31:0] core_phy_req_timeout;
  wire        core_phy_rsp_valid;
  wire        core_phy_rsp_ready;
  wire        core_phy_rsp_error;
  wire [63:0] core_phy_rsp_rdata;
  wire        core_abort_valid;
  wire        core_abort_ready;
  wire        core_busy;
  wire        core_io_active;
  wire        core_quiesced;
  wire        core_initialized;
  wire        core_ready;
  wire        core_trained;
  wire        core_error;
  wire        core_profile_lock;
  wire        core_profile_hyper;
  wire [31:0] core_last_error_addr;
  wire        core_init_done_event;
  wire        core_indirect_done_event;
  wire        core_train_done_event;
  wire        core_error_event;
  wire        core_timeout_event;

  wire        controller_enable;
  wire        memory_enable;
  wire        auto_init;
  wire        line_buffer;
  wire        protocol_hyper;
  wire [31:0] device_size;
  wire [31:0] opi_read_cmd;
  wire [31:0] opi_write_cmd;
  wire [31:0] opi_reg_read_cmd;
  wire [31:0] opi_reg_write_cmd;
  wire [31:0] opi_timing;
  wire [31:0] hyper_timing;
  wire [31:0] clk_config;
  wire [31:0] cs_timing;
  wire [31:0] powerup_cycles;
  wire [31:0] timeout_cycles;
  wire [ 7:0] rx_delay;
  wire        init_cmd;
  wire        abort_cmd;
  wire        soft_reset_cmd;
  wire        train_cmd;
  wire        indirect_start_cmd;
  wire        indirect_write_cmd;
  wire        indirect_register_cmd;
  wire        reg_irq;
  wire [ 4:0] reg_intr_state;
  wire [ 4:0] reg_intr_enable;
  wire [ 4:0] reg_event_bits;
  wire [ 4:0] reg_intr_next;
  wire        reg_busy;

  wire        phy_cmd_valid;
  wire        phy_cmd_ready;
  wire        phy_cmd_profile_hyper;
  wire        phy_cmd_write;
  wire        phy_cmd_indirect_register;
  wire [ 3:0] phy_cmd_len;
  wire [31:0] phy_cmd_clk_config;
  wire        phy_abort;
  wire        phy_rsp_valid;
  wire        phy_rsp_ready;
  wire        phy_rsp_error;
  wire [63:0] phy_rsp_rdata;
  wire        phy_ck;
  wire        phy_cs_n;
  wire [ 7:0] phy_dq_oe;
  wire        phy_rwds_oe;

  localparam logic [31:0] APERTURE_BASE = 32'h4800_0000;
  localparam logic [31:0] APERTURE_LAST = 32'h4FFF_FFFF;
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;

  logic f_phy_rsp_pending_q;

`ifdef OPIPSRAM_BMC
  logic        f_bad_read_q;
  logic [ 7:0] f_bad_read_len_q;
  logic [ 7:0] f_bad_read_beat_q;
  logic [ 3:0] f_bad_read_age_q;
  logic        f_bad_write_q;
  logic [ 7:0] f_bad_write_len_q;
  logic [ 7:0] f_bad_write_beat_q;
  logic [ 3:0] f_bad_write_age_q;
  logic        f_abort_watch_q;
  logic [ 3:0] f_abort_age_q;
  logic        f_timeout_watch_q;
  logic [ 3:0] f_timeout_age_q;
  logic        f_indirect_watch_q;
  logic        f_indirect_write_q;
  logic        f_indirect_register_q;
  logic        f_fill_watch_q;
  logic        f_phy_cmd_active_q;
  logic        f_phy_rsp_hold_q;
  logic        f_phy_rsp_error_q;
  logic [63:0] f_phy_rsp_rdata_q;

  initial begin
    f_bad_read_q          = 1'b0;
    f_bad_read_len_q      = 8'd0;
    f_bad_read_beat_q     = 8'd0;
    f_bad_read_age_q      = 4'd0;
    f_bad_write_q         = 1'b0;
    f_bad_write_len_q     = 8'd0;
    f_bad_write_beat_q    = 8'd0;
    f_bad_write_age_q     = 4'd0;
    f_abort_watch_q       = 1'b0;
    f_abort_age_q         = 4'd0;
    f_timeout_watch_q     = 1'b0;
    f_timeout_age_q       = 4'd0;
    f_indirect_watch_q    = 1'b0;
    f_indirect_write_q    = 1'b0;
    f_indirect_register_q = 1'b0;
    f_fill_watch_q        = 1'b0;
    f_phy_cmd_active_q    = 1'b0;
    f_phy_rsp_hold_q      = 1'b0;
    f_phy_rsp_error_q     = 1'b0;
    f_phy_rsp_rdata_q     = 64'd0;
  end
`endif

  function automatic logic [32:0] burst_last_addr(input logic [31:0] addr, input logic [7:0] length,
                                                  input logic [2:0] size);
    logic [32:0] bytes;
    begin
      bytes           = ({25'd0, length} + 33'd1) << size;
      burst_last_addr = {1'b0, addr} + bytes - 33'd1;
    end
  endfunction

  function automatic logic legal_burst(input logic [31:0] addr, input logic [7:0] length,
                                       input logic [2:0] size, input logic [1:0] burst,
                                       input logic lock, input logic [31:0] size_limit);
    logic [32:0] last_addr;
    begin
      last_addr = burst_last_addr(addr, length, size);
      legal_burst = (length <= 8'd15) && (burst == AXI_BURST_INCR) && !lock &&
          (size <= 3'd2) &&
          ((addr & ((32'd1 << size) - 32'd1)) == 32'd0) &&
          !last_addr[32] && (addr[31:12] == last_addr[31:12]) &&
          (addr >= APERTURE_BASE) && (last_addr[31:0] <= APERTURE_LAST) &&
          (last_addr <= ({1'b0, APERTURE_BASE} + {1'b0, size_limit} - 33'd1));
    end
  endfunction

  function automatic logic protected_config_address(input logic [11:0] offset);
    unique case (offset)
      12'h00C, 12'h018, 12'h01C, 12'h020, 12'h024, 12'h028, 12'h02C,
      12'h030, 12'h034, 12'h038, 12'h03C, 12'h040, 12'h044, 12'h048,
      12'h050, 12'h054, 12'h058, 12'h05C:
      protected_config_address = 1'b1;
      default: protected_config_address = 1'b0;
    endcase
  endfunction

  wire apb_request = apb_psel && apb_penable && !apb_pready;
  wire [4:0] intr_clear = (apb_request && apb_pwrite && (apb_paddr[11:0] == 12'h080) &&
                           apb_pstrb[0]) ? apb_pwdata[4:0] : 5'd0;
  wire [4:0] intr_test_set =
      (apb_request && apb_pwrite && (apb_paddr[11:0] == 12'h08C) && apb_pstrb[0]) ?
      apb_pwdata[4:0] : 5'd0;
  wire profile_start = !core_busy && controller_enable &&
      (init_cmd || (auto_init && !core_initialized));

  opipsram_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(awvalid && !awready)) begin
        assume (awvalid);
        assume (awid == $past(awid));
        assume (awaddr == $past(awaddr));
        assume (awlen == $past(awlen));
        assume (awsize == $past(awsize));
        assume (awburst == $past(awburst));
        assume (awlock == $past(awlock));
        assume (awcache == $past(awcache));
        assume (awprot == $past(awprot));
        assume (awqos == $past(awqos));
        assume (awregion == $past(awregion));
        assume (awuser == $past(awuser));
      end
`ifdef OPIPSRAM_BMC
      if ($past(awvalid && awready)) begin
        assume (awvalid);
        assume (!arvalid);
        assume (awid == $past(awid));
        assume (awaddr == $past(awaddr));
        assume (awlen == $past(awlen));
        assume (awsize == $past(awsize));
        assume (awburst == $past(awburst));
        assume (awlock == $past(awlock));
        assume (awcache == $past(awcache));
        assume (awprot == $past(awprot));
        assume (awqos == $past(awqos));
        assume (awregion == $past(awregion));
        assume (awuser == $past(awuser));
      end
`endif
      if ($past(wvalid && !wready)) begin
        assume (wvalid);
        assume (wdata == $past(wdata));
        assume (wstrb == $past(wstrb));
        assume (wlast == $past(wlast));
        assume (wuser == $past(wuser));
      end
      if ($past(arvalid && !arready)) begin
        assume (arvalid);
        assume (arid == $past(arid));
        assume (araddr == $past(araddr));
        assume (arlen == $past(arlen));
        assume (arsize == $past(arsize));
        assume (arburst == $past(arburst));
        assume (arlock == $past(arlock));
        assume (arcache == $past(arcache));
        assume (arprot == $past(arprot));
        assume (arqos == $past(arqos));
        assume (arregion == $past(arregion));
        assume (aruser == $past(aruser));
      end
`ifdef OPIPSRAM_BMC
      if ($past(arvalid && arready)) begin
        assume (arvalid);
        assume (!awvalid);
        assume (arid == $past(arid));
        assume (araddr == $past(araddr));
        assume (arlen == $past(arlen));
        assume (arsize == $past(arsize));
        assume (arburst == $past(arburst));
        assume (arlock == $past(arlock));
        assume (arcache == $past(arcache));
        assume (arprot == $past(arprot));
        assume (arqos == $past(arqos));
        assume (arregion == $past(arregion));
        assume (aruser == $past(aruser));
      end
`endif
      if ($past(apb_request)) begin
        assume (apb_psel);
        assume (apb_penable);
        assume (apb_pwrite == $past(apb_pwrite));
        assume (apb_paddr == $past(apb_paddr));
        assume (apb_pwdata == $past(apb_pwdata));
        assume (apb_pstrb == $past(apb_pstrb));
        assume (apb_pprot == $past(apb_pprot));
      end
      if ($past(core_phy_rsp_valid && !core_phy_rsp_ready)) begin
        assume (core_phy_rsp_valid);
        assume (core_phy_rsp_error == $past(core_phy_rsp_error));
        assume (core_phy_rsp_rdata == $past(core_phy_rsp_rdata));
      end
      if ($past(phy_cmd_valid && !phy_cmd_ready)) begin
        assume (phy_cmd_valid);
        assume (phy_cmd_profile_hyper == $past(phy_cmd_profile_hyper));
        assume (phy_cmd_write == $past(phy_cmd_write));
        assume (phy_cmd_indirect_register == $past(phy_cmd_indirect_register));
        assume (phy_cmd_len == $past(phy_cmd_len));
        assume (phy_cmd_clk_config == $past(phy_cmd_clk_config));
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
      if ($past(core_mem_req_valid && !core_mem_req_ready)) begin
        assert (core_mem_req_valid);
        assert (core_mem_req_write == $past(core_mem_req_write));
        assert (core_mem_req_addr == $past(core_mem_req_addr));
        assert (core_mem_req_len == $past(core_mem_req_len));
        assert (core_mem_req_wdata == $past(core_mem_req_wdata));
        assert (core_mem_req_wstrb == $past(core_mem_req_wstrb));
      end
      if ($past(core_phy_req_valid && !core_phy_req_ready)) begin
        assert (core_phy_req_valid);
        assert (core_phy_req_profile_hyper == $past(core_phy_req_profile_hyper));
        assert (core_phy_req_write == $past(core_phy_req_write));
        assert (core_phy_req_indirect_register == $past(core_phy_req_indirect_register));
        assert (core_phy_req_addr == $past(core_phy_req_addr));
        assert (core_phy_req_len == $past(core_phy_req_len));
        assert (core_phy_req_wdata == $past(core_phy_req_wdata));
        assert (core_phy_req_opi_cmd == $past(core_phy_req_opi_cmd));
        assert (core_phy_req_opi_width16 == $past(core_phy_req_opi_width16));
        assert (core_phy_req_opi_timing == $past(core_phy_req_opi_timing));
        assert (core_phy_req_hyper_timing == $past(core_phy_req_hyper_timing));
        assert (core_phy_req_cs_timing == $past(core_phy_req_cs_timing));
        assert (core_phy_req_clk_config == $past(core_phy_req_clk_config));
        assert (core_phy_req_rx_delay == $past(core_phy_req_rx_delay));
        assert (core_phy_req_timeout == $past(core_phy_req_timeout));
      end
    end

    if (!rst_n_i) begin
      assume (!apb_psel);
      assume (!awvalid);
      assume (!wvalid);
      assume (!arvalid);
      assume (!phy_cmd_valid);
      assume (!f_past_valid);
    end else if (f_past_valid && !$past(rst_n_i)) begin
      assume (!awvalid);
      assume (!wvalid);
      assume (!arvalid);
      assume (!phy_cmd_valid);
    end else begin
      assume (!((awvalid && awready) && (arvalid && arready)));
      assume (core_phy_req_ready || !core_phy_req_valid);
      assume (core_abort_ready || !core_abort_valid);
      assume (core_phy_rsp_valid || !core_phy_rsp_ready);
`ifdef OPIPSRAM_BMC
      if (rvalid) assume (rready);
      if (bvalid) assume (bready);
`endif
      if (core_mem_rsp_valid) begin
        assume (rready || !rvalid);
        assume (bready || !bvalid);
      end
      if (phy_cs_n) begin
        assert (!phy_ck);
        assert (phy_dq_oe == 8'd0);
        assert (!phy_rwds_oe);
      end
`ifdef OPIPSRAM_BMC
      if (clk_i && !$past(
              clk_i
          ) && $past(
              core_phy_req_valid && core_phy_req_ready && !core_phy_req_write &&
                (core_phy_req_len == 4'd8) && !core_phy_req_indirect_register
          ))
        assert (core_phy_rsp_ready);
      if (clk_i && !$past(clk_i) && f_indirect_watch_q && core_phy_req_valid) begin
        assert (core_phy_req_write == f_indirect_write_q);
        assert (core_phy_req_indirect_register == f_indirect_register_q);
      end
`endif
    end
  end

`ifdef OPIPSRAM_BMC
  always @(posedge clk_i) begin
    if (!f_past_valid || !$past(rst_n_i)) begin
      f_bad_read_q       <= 1'b0;
      f_bad_read_len_q   <= 8'd0;
      f_bad_read_beat_q  <= 8'd0;
      f_bad_read_age_q   <= 4'd0;
      f_bad_write_q      <= 1'b0;
      f_bad_write_len_q  <= 8'd0;
      f_bad_write_beat_q <= 8'd0;
      f_bad_write_age_q  <= 4'd0;
    end else begin
      if (arvalid && arready) begin
        f_bad_read_q <= (!legal_burst(
            araddr, arlen, arsize, arburst, arlock, device_size
        ) || !core_ready) && (arlen <= 8'd7);
        f_bad_read_len_q <= arlen;
        f_bad_read_beat_q <= 8'd0;
        f_bad_read_age_q <= 4'd0;
      end else if (f_bad_read_q) begin
        assert (!core_mem_req_valid);
        if (rvalid) begin
          assert (rresp == AXI_RESP_SLVERR);
          if (rready) begin
            if (rlast) begin
              f_bad_read_q     <= 1'b0;
              f_bad_read_age_q <= 4'd0;
            end else begin
              f_bad_read_beat_q <= f_bad_read_beat_q + 8'd1;
              f_bad_read_age_q  <= 4'd0;
            end
          end else begin
            assert (f_bad_read_age_q < 4'd8);
            f_bad_read_age_q <= f_bad_read_age_q + 4'd1;
          end
        end else begin
          assert (f_bad_read_age_q < 4'd8);
          f_bad_read_age_q <= f_bad_read_age_q + 4'd1;
        end
      end

      if (awvalid && awready) begin
        f_bad_write_q <= (!legal_burst(
            awaddr, awlen, awsize, awburst, awlock, device_size
        ) || !core_ready) && (awlen <= 8'd7);
        f_bad_write_len_q <= awlen;
        f_bad_write_beat_q <= 8'd0;
        f_bad_write_age_q <= 4'd0;
      end else if (f_bad_write_q) begin
        assert (!core_mem_req_valid);
        if (wready) begin
          f_bad_write_age_q <= 4'd0;
          if (wvalid) begin
            if (f_bad_write_beat_q == f_bad_write_len_q) begin
              f_bad_write_q <= 1'b0;
            end else begin
              f_bad_write_beat_q <= f_bad_write_beat_q + 8'd1;
            end
          end
        end else begin
          assert (f_bad_write_age_q < 4'd8);
          f_bad_write_age_q <= f_bad_write_age_q + 4'd1;
        end
      end
    end
  end

  always @(posedge clk_i) begin
    if (!f_past_valid || !$past(rst_n_i)) begin
      f_abort_watch_q       <= 1'b0;
      f_abort_age_q         <= 4'd0;
      f_timeout_watch_q     <= 1'b0;
      f_timeout_age_q       <= 4'd0;
      f_indirect_watch_q    <= 1'b0;
      f_indirect_write_q    <= 1'b0;
      f_indirect_register_q <= 1'b0;
      f_fill_watch_q        <= 1'b0;
      f_phy_cmd_active_q    <= 1'b0;
      f_phy_rsp_hold_q      <= 1'b0;
      f_phy_rsp_error_q     <= 1'b0;
      f_phy_rsp_rdata_q     <= 64'd0;
    end else begin
      if (phy_rsp_valid && !phy_rsp_ready) begin
        if (f_phy_rsp_hold_q) begin
          assert (phy_rsp_error == f_phy_rsp_error_q);
          assert (phy_rsp_rdata == f_phy_rsp_rdata_q);
        end else begin
          f_phy_rsp_error_q <= phy_rsp_error;
          f_phy_rsp_rdata_q <= phy_rsp_rdata;
        end
        f_phy_rsp_hold_q <= 1'b1;
      end else begin
        f_phy_rsp_hold_q <= 1'b0;
      end

      if (phy_cmd_valid && phy_cmd_ready) f_phy_cmd_active_q <= 1'b1;
      if (phy_rsp_valid && phy_rsp_ready) f_phy_cmd_active_q <= 1'b0;
      if (phy_abort) assume (f_phy_cmd_active_q && !phy_rsp_valid);

      if (core_phy_req_valid) begin
        f_fill_watch_q <= !core_phy_req_write && (core_phy_req_len == 4'd8) &&
                            !core_phy_req_indirect_register;
      end else if (core_phy_rsp_valid && core_phy_rsp_ready) begin
        f_fill_watch_q <= 1'b0;
      end

      if (indirect_start_cmd && !reg_busy) begin
        f_indirect_watch_q    <= 1'b1;
        f_indirect_write_q    <= indirect_write_cmd;
        f_indirect_register_q <= indirect_register_cmd;
      end else if (core_indirect_done_event) begin
        f_indirect_watch_q <= 1'b0;
      end
      if (abort_cmd && (core_io_active || f_fill_watch_q || core_phy_req_valid)) begin
        f_abort_watch_q <= 1'b1;
        f_abort_age_q   <= 4'd0;
      end else if (f_abort_watch_q) begin
        if (!core_busy && !core_io_active) begin
          f_abort_watch_q <= 1'b0;
        end else begin
          assert (f_abort_age_q < 4'd8);
          f_abort_age_q <= f_abort_age_q + 4'd1;
        end
      end

      if (core_timeout_event) begin
        f_timeout_watch_q <= 1'b1;
        f_timeout_age_q   <= 4'd0;
      end else if (f_timeout_watch_q) begin
        if (!core_busy && !core_io_active) begin
          f_timeout_watch_q <= 1'b0;
        end else begin
          assert (f_timeout_age_q < 4'd8);
          f_timeout_age_q <= f_timeout_age_q + 4'd1;
        end
      end
    end
  end
`endif

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(
              core_profile_lock && core_initialized && !soft_reset_cmd
          ) && rst_n_i && !soft_reset_cmd && !init_cmd && !$past(
              init_cmd
          )) begin
        assert (core_profile_lock);
        assert (core_profile_hyper == $past(core_profile_hyper));
      end
      if ($past(core_profile_lock) && !core_profile_lock) begin
        assert ($past(soft_reset_cmd) || soft_reset_cmd || !core_initialized);
      end
      if ($past(
              reg_busy && apb_request && apb_pwrite && protected_config_address(apb_paddr[11:0])
          )) begin
        assert (controller_enable == $past(controller_enable));
        assert (memory_enable == $past(memory_enable));
        assert (protocol_hyper == $past(protocol_hyper));
        assert (device_size == $past(device_size));
        assert (opi_read_cmd == $past(opi_read_cmd));
        assert (opi_write_cmd == $past(opi_write_cmd));
        assert (opi_reg_read_cmd == $past(opi_reg_read_cmd));
        assert (opi_reg_write_cmd == $past(opi_reg_write_cmd));
        assert (opi_timing == $past(opi_timing));
        assert (hyper_timing == $past(hyper_timing));
        assert (clk_config == $past(clk_config));
        assert (cs_timing == $past(cs_timing));
        assert (powerup_cycles == $past(powerup_cycles));
        assert (timeout_cycles == $past(timeout_cycles));
        assert (rx_delay == $past(rx_delay));
      end
      assert (reg_intr_next == ((reg_intr_state & ~intr_clear) | reg_event_bits | intr_test_set));
      for (int unsigned bit_index = 0; bit_index < 5; bit_index++) begin
        if (reg_event_bits[bit_index] || intr_test_set[bit_index])
          assert (reg_intr_next[bit_index]);
        if (intr_clear[bit_index] && !reg_event_bits[bit_index] && !intr_test_set[bit_index])
          assert (!reg_intr_next[bit_index]);
      end
      assert (reg_irq == |(reg_intr_state & reg_intr_enable));
    end
  end

  always @(posedge clk_i) begin
    if (!f_past_valid || !$past(rst_n_i)) begin
      f_phy_rsp_pending_q <= 1'b0;
    end else begin
      if (core_phy_req_valid && core_phy_req_ready) f_phy_rsp_pending_q <= 1'b1;
      if (core_phy_rsp_valid && core_phy_rsp_ready) f_phy_rsp_pending_q <= 1'b0;
      if (core_phy_rsp_valid) assume (f_phy_rsp_pending_q);
      if (core_phy_rsp_ready && f_phy_rsp_pending_q) assume (core_phy_rsp_valid);
    end
  end

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      cover (arvalid && arready && legal_burst(
          araddr, arlen, arsize, arburst, arlock, device_size
      ) && core_ready);
      cover (awvalid && awready && legal_burst(
          awaddr, awlen, awsize, awburst, awlock, device_size
      ) && core_ready);
      cover (core_phy_req_valid && core_phy_req_ready && !core_phy_req_write);
      cover (bvalid && (bresp == AXI_RESP_OKAY));
      cover (rvalid && (rresp == AXI_RESP_SLVERR));
      cover (bvalid && (bresp == AXI_RESP_SLVERR));
      cover (core_profile_lock && core_initialized);
      cover (abort_cmd && core_io_active);
      cover (core_abort_valid && core_abort_ready);
      cover (core_error);
      cover (phy_cmd_valid && phy_cmd_ready);
      cover (phy_cmd_valid && phy_cmd_ready && (phy_cmd_clk_config[15:0] > 16'd1));
      cover (phy_cmd_valid && phy_cmd_ready && phy_cmd_profile_hyper &&
             phy_cmd_write && phy_cmd_indirect_register);
      cover (phy_rsp_valid && phy_cs_n && !phy_ck);
      cover (phy_cs_n && !phy_ck && (phy_dq_oe == 8'd0) && !phy_rwds_oe);
    end
  end

endmodule
