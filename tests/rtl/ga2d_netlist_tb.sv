`timescale 1ns / 1ps

`include "ga2d_define.svh"

// Pin-level transaction test for the synthesized apb4_ga2d_block_top netlist
// (GA2D Phase 6). The DUT is the yosys IHP130 netlist produced by
// physical/smoke/syn/yosys/ga2d_block.mk; only its top-level ports are
// referenced here. The scoring idioms mirror tests/rtl/ga2d_dma_tb.sv: a
// byte-exact AXI4 target model, exact destination bytes, exact terminal
// counters, DONE/IRQ behavior, and one validation-error case with no AXI
// traffic.
module ga2d_netlist_tb;
  localparam logic [31:0] SramBase = 32'h3000_0000;
  localparam int unsigned MemoryBytes = 32768;
  localparam logic [2:0] IrqDoneMask = 3'b001 << `APB4_GA2D__IRQ_DONE;
  localparam logic [2:0] IrqErrorMask = 3'b001 << `APB4_GA2D__IRQ_ERROR;

  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               resource_quiesce_i = 1'b0;
  logic               resource_reset_i = 1'b0;
  logic               source_stop_i = 1'b0;
  logic               source_safe_idle_i = 1'b1;
  logic               block_ack_i = 1'b0;
  logic               bridge_clear_busy_i = 1'b0;
  logic        [ 7:0] bridge_epoch_i = 8'd0;
  logic               data_ready_i = 1'b1;
  logic        [ 1:0] mem_pad_mode_i = 2'd0;
  logic               idle_o;
  logic               core_safe_idle_o;
  logic               irq_o;
  logic        [31:0] apb4_paddr;
  logic        [ 2:0] apb4_pprot;
  logic               apb4_psel;
  logic               apb4_penable;
  logic               apb4_pwrite;
  logic        [31:0] apb4_pwdata;
  logic        [ 3:0] apb4_pstrb;
  logic               apb4_pready;
  logic        [31:0] apb4_prdata;
  logic               apb4_pslverr;
  logic        [ 3:0] ga2d_axi4_awid;
  logic        [31:0] ga2d_axi4_awaddr;
  logic        [ 7:0] ga2d_axi4_awlen;
  logic        [ 2:0] ga2d_axi4_awsize;
  logic        [ 1:0] ga2d_axi4_awburst;
  logic               ga2d_axi4_awlock;
  logic        [ 3:0] ga2d_axi4_awcache;
  logic        [ 2:0] ga2d_axi4_awprot;
  logic        [ 3:0] ga2d_axi4_awqos;
  logic        [ 3:0] ga2d_axi4_awregion;
  logic        [ 3:0] ga2d_axi4_awuser;
  logic               ga2d_axi4_awvalid;
  logic               ga2d_axi4_awready;
  logic        [63:0] ga2d_axi4_wdata;
  logic        [ 7:0] ga2d_axi4_wstrb;
  logic               ga2d_axi4_wlast;
  logic        [ 3:0] ga2d_axi4_wuser;
  logic               ga2d_axi4_wvalid;
  logic               ga2d_axi4_wready;
  logic        [ 3:0] ga2d_axi4_bid;
  logic        [ 1:0] ga2d_axi4_bresp;
  logic        [ 3:0] ga2d_axi4_buser;
  logic               ga2d_axi4_bvalid;
  logic               ga2d_axi4_bready;
  logic        [ 3:0] ga2d_axi4_arid;
  logic        [31:0] ga2d_axi4_araddr;
  logic        [ 7:0] ga2d_axi4_arlen;
  logic        [ 2:0] ga2d_axi4_arsize;
  logic        [ 1:0] ga2d_axi4_arburst;
  logic               ga2d_axi4_arlock;
  logic        [ 3:0] ga2d_axi4_arcache;
  logic        [ 2:0] ga2d_axi4_arprot;
  logic        [ 3:0] ga2d_axi4_arqos;
  logic        [ 3:0] ga2d_axi4_arregion;
  logic        [ 3:0] ga2d_axi4_aruser;
  logic               ga2d_axi4_arvalid;
  logic               ga2d_axi4_arready;
  logic        [ 3:0] ga2d_axi4_rid;
  logic        [63:0] ga2d_axi4_rdata;
  logic        [ 1:0] ga2d_axi4_rresp;
  logic               ga2d_axi4_rlast;
  logic        [ 3:0] ga2d_axi4_ruser;
  logic               ga2d_axi4_rvalid;
  logic               ga2d_axi4_rready;
  logic        [ 7:0] s_memory                        [0:MemoryBytes-1];
  logic               s_rvalid_q;
  logic        [31:0] s_raddr_q;
  logic        [63:0] s_rdata_q;
  logic        [ 2:0] s_rsize_q;
  logic        [ 8:0] s_rbeats_q;
  logic        [ 1:0] s_r_delay_q;
  logic               s_aw_pending_q;
  logic        [31:0] s_awaddr_q;
  logic        [ 8:0] s_wbeats_q;
  logic               s_bvalid_q;
  logic        [ 1:0] s_b_delay_q;
  logic        [31:0] s_lfsr_q;
  logic        [ 1:0] s_ar_delay_q;
  logic               s_ar_delay_pending_q;
  logic        [ 1:0] s_aw_delay_q;
  logic               s_aw_delay_pending_q;
  logic        [ 1:0] s_w_delay_q;
  logic               s_w_delay_pending_q;
  int unsigned        s_ar_count;
  int unsigned        s_aw_count;
  logic               s_aw_stalled_q;
  logic        [31:0] s_awaddr_stalled_q;
  logic        [ 7:0] s_awlen_stalled_q;
  logic        [ 2:0] s_awsize_stalled_q;
  logic               s_w_stalled_q;
  logic        [63:0] s_wdata_stalled_q;
  logic        [ 7:0] s_wstrb_stalled_q;
  logic               s_ar_stalled_q;
  logic        [31:0] s_araddr_stalled_q;
  logic        [ 7:0] s_arlen_stalled_q;
  logic        [ 2:0] s_arsize_stalled_q;

  always #5 clk_i = ~clk_i;

  function automatic logic [7:0] memory_byte(input logic [31:0] address_i);
    if ((address_i >= SramBase) && (address_i < (SramBase + MemoryBytes))) begin
      return s_memory[address_i-SramBase];
    end
    return 8'd0;
  endfunction

  function automatic logic [63:0] memory_word(input logic [31:0] address_i);
    logic [63:0] data;
    logic [31:0] aligned_address;
    begin
      data            = '0;
      aligned_address = {address_i[31:3], 3'b000};
      for (int unsigned lane = 0; lane < 8; lane++) begin
        data[lane*8+:8] = memory_byte(aligned_address + lane);
      end
      return data;
    end
  endfunction

  function automatic logic [31:0] next_delay_lfsr(input logic [31:0] value_i);
    return {value_i[30:0], value_i[31] ^ value_i[21] ^ value_i[1] ^ value_i[0]};
  endfunction

  // Behavioral 64-bit AXI4 target model: one outstanding burst per direction,
  // byte-exact memory, legal READY/VALID. Each request or response picks a
  // 0..3 cycle delay from the shared LFSR and then stays eligible until its
  // handshake, so progress is bounded.
  assign ga2d_axi4_arready = !s_rvalid_q && s_ar_delay_pending_q && (s_ar_delay_q == 2'd0);
  assign ga2d_axi4_rid = 4'd0;
  assign ga2d_axi4_rdata = s_rdata_q;
  assign ga2d_axi4_rresp = 2'd0;
  assign ga2d_axi4_rlast = (s_rbeats_q == 9'd1);
  assign ga2d_axi4_ruser = 4'd0;
  assign ga2d_axi4_rvalid = s_rvalid_q && (s_r_delay_q == 2'd0);
  assign ga2d_axi4_awready = !s_aw_pending_q && !s_bvalid_q && s_aw_delay_pending_q &&
                             (s_aw_delay_q == 2'd0);
  assign ga2d_axi4_wready = s_aw_pending_q && !s_bvalid_q && s_w_delay_pending_q &&
                            (s_w_delay_q == 2'd0);
  assign ga2d_axi4_bid = 4'd0;
  assign ga2d_axi4_bresp = 2'd0;
  assign ga2d_axi4_buser = 4'd0;
  assign ga2d_axi4_bvalid = s_bvalid_q && (s_b_delay_q == 2'd0);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rvalid_q           <= 1'b0;
      s_raddr_q            <= '0;
      s_rdata_q            <= '0;
      s_rsize_q            <= '0;
      s_rbeats_q           <= '0;
      s_r_delay_q          <= '0;
      s_aw_pending_q       <= 1'b0;
      s_awaddr_q           <= '0;
      s_wbeats_q           <= '0;
      s_bvalid_q           <= 1'b0;
      s_b_delay_q          <= '0;
      s_lfsr_q             <= 32'h1f12_3bb5;
      s_ar_delay_q         <= '0;
      s_ar_delay_pending_q <= 1'b0;
      s_aw_delay_q         <= '0;
      s_aw_delay_pending_q <= 1'b0;
      s_w_delay_q          <= '0;
      s_w_delay_pending_q  <= 1'b0;
      s_ar_count           <= 0;
      s_aw_count           <= 0;
    end else begin
      if (!ga2d_axi4_arvalid || s_rvalid_q) begin
        s_ar_delay_q         <= '0;
        s_ar_delay_pending_q <= 1'b0;
      end else if (!s_ar_delay_pending_q) begin
        s_ar_delay_q         <= s_lfsr_q[1:0];
        s_ar_delay_pending_q <= 1'b1;
        s_lfsr_q             <= next_delay_lfsr(s_lfsr_q);
      end else if (s_ar_delay_q != 2'd0) begin
        s_ar_delay_q <= s_ar_delay_q - 1'b1;
      end
      if (ga2d_axi4_arvalid && ga2d_axi4_arready) begin
        if ((ga2d_axi4_arlen != 8'd0) && (ga2d_axi4_arsize != 3'd3)) begin
          $fatal(1, "GA2D netlist emitted a non-full-width read burst");
        end
        if ((ga2d_axi4_araddr & ((32'd1 << ga2d_axi4_arsize) - 1'b1)) != 32'd0) begin
          $fatal(1, "GA2D netlist emitted an unaligned read transfer");
        end
        if ({1'b0, ga2d_axi4_araddr[11:0]} +
          (({5'd0, ga2d_axi4_arlen} + 13'd1) << ga2d_axi4_arsize) > 13'd4096) begin
          $fatal(1, "GA2D netlist read burst crossed a 4 KiB boundary");
        end
        s_rvalid_q           <= 1'b1;
        s_raddr_q            <= ga2d_axi4_araddr;
        s_rdata_q            <= memory_word(ga2d_axi4_araddr);
        s_rsize_q            <= ga2d_axi4_arsize;
        s_rbeats_q           <= {1'b0, ga2d_axi4_arlen} + 1'b1;
        s_r_delay_q          <= s_lfsr_q[1:0];
        s_lfsr_q             <= next_delay_lfsr(s_lfsr_q);
        s_ar_delay_pending_q <= 1'b0;
        s_ar_count           <= s_ar_count + 1;
      end else if (s_rvalid_q && ga2d_axi4_rvalid && ga2d_axi4_rready) begin
        if (s_rbeats_q == 9'd1) begin
          s_rvalid_q <= 1'b0;
          s_rbeats_q <= '0;
        end else begin
          s_raddr_q  <= s_raddr_q + (32'd1 << s_rsize_q);
          s_rdata_q  <= memory_word(s_raddr_q + (32'd1 << s_rsize_q));
          s_rbeats_q <= s_rbeats_q - 1'b1;
        end
      end
      if (s_rvalid_q && (s_r_delay_q != 2'd0)) begin
        s_r_delay_q <= s_r_delay_q - 1'b1;
      end

      if (!ga2d_axi4_awvalid || s_aw_pending_q || s_bvalid_q) begin
        s_aw_delay_q         <= '0;
        s_aw_delay_pending_q <= 1'b0;
      end else if (!s_aw_delay_pending_q) begin
        s_aw_delay_q         <= s_lfsr_q[1:0];
        s_aw_delay_pending_q <= 1'b1;
        s_lfsr_q             <= next_delay_lfsr(s_lfsr_q);
      end else if (s_aw_delay_q != 2'd0) begin
        s_aw_delay_q <= s_aw_delay_q - 1'b1;
      end
      if (ga2d_axi4_awvalid && ga2d_axi4_awready) begin
        if (ga2d_axi4_awaddr[2:0] != 3'd0) begin
          $fatal(1, "GA2D netlist emitted an unaligned AXI64 write address");
        end
        if ({1'b0, ga2d_axi4_awaddr[11:0]} +
            (({5'd0, ga2d_axi4_awlen} + 13'd1) << 3) > 13'd4096) begin
          $fatal(1, "GA2D netlist write burst crossed a 4 KiB boundary");
        end
        s_aw_pending_q       <= 1'b1;
        s_awaddr_q           <= ga2d_axi4_awaddr;
        s_wbeats_q           <= {1'b0, ga2d_axi4_awlen} + 1'b1;
        s_aw_delay_pending_q <= 1'b0;
        s_aw_count           <= s_aw_count + 1;
      end
      if (!ga2d_axi4_wvalid || !s_aw_pending_q || s_bvalid_q) begin
        s_w_delay_q         <= '0;
        s_w_delay_pending_q <= 1'b0;
      end else if (!s_w_delay_pending_q) begin
        s_w_delay_q         <= s_lfsr_q[1:0];
        s_w_delay_pending_q <= 1'b1;
        s_lfsr_q            <= next_delay_lfsr(s_lfsr_q);
      end else if (s_w_delay_q != 2'd0) begin
        s_w_delay_q <= s_w_delay_q - 1'b1;
      end
      if (ga2d_axi4_wvalid && ga2d_axi4_wready) begin
        if (!s_aw_pending_q) begin
          $fatal(1, "GA2D netlist issued W without an accepted AW");
        end
        if (ga2d_axi4_wlast != (s_wbeats_q == 9'd1)) begin
          $fatal(1, "GA2D netlist emitted an incorrect WLAST sequence");
        end
        for (int unsigned lane = 0; lane < 8; lane++) begin
          if (ga2d_axi4_wstrb[lane]) begin
            if ((s_awaddr_q + lane) < SramBase ||
              (s_awaddr_q + lane) >= (SramBase + MemoryBytes)) begin
              $fatal(1, "GA2D netlist write escaped the SRAM BFM");
            end
            s_memory[(s_awaddr_q+lane)-SramBase] <= ga2d_axi4_wdata[lane*8+:8];
          end
        end
        if (s_wbeats_q == 9'd1) begin
          s_aw_pending_q       <= 1'b0;
          s_wbeats_q           <= '0;
          s_bvalid_q           <= 1'b1;
          s_b_delay_q          <= s_lfsr_q[1:0];
          s_lfsr_q             <= next_delay_lfsr(s_lfsr_q);
          s_w_delay_pending_q  <= 1'b0;
        end else begin
          s_awaddr_q <= s_awaddr_q + 32'd8;
          s_wbeats_q <= s_wbeats_q - 1'b1;
        end
      end
      if (s_bvalid_q && (s_b_delay_q != 2'd0)) begin
        s_b_delay_q <= s_b_delay_q - 1'b1;
      end
      if (s_bvalid_q && ga2d_axi4_bvalid && ga2d_axi4_bready) begin
        s_bvalid_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_aw_stalled_q     <= 1'b0;
      s_awaddr_stalled_q <= '0;
      s_awlen_stalled_q  <= '0;
      s_awsize_stalled_q <= '0;
      s_w_stalled_q      <= 1'b0;
      s_wdata_stalled_q  <= '0;
      s_wstrb_stalled_q  <= '0;
      s_ar_stalled_q     <= 1'b0;
      s_araddr_stalled_q <= '0;
      s_arlen_stalled_q  <= '0;
      s_arsize_stalled_q <= '0;
    end else begin
      if (s_aw_stalled_q) begin
        if (!ga2d_axi4_awvalid || (ga2d_axi4_awaddr != s_awaddr_stalled_q) ||
            (ga2d_axi4_awlen != s_awlen_stalled_q) ||
            (ga2d_axi4_awsize != s_awsize_stalled_q)) begin
          $fatal(1, "GA2D netlist AW payload changed while stalled");
        end
      end
      if (s_w_stalled_q) begin
        if (!ga2d_axi4_wvalid || (ga2d_axi4_wdata != s_wdata_stalled_q) ||
            (ga2d_axi4_wstrb != s_wstrb_stalled_q)) begin
          $fatal(1, "GA2D netlist W payload changed while stalled");
        end
      end
      if (s_ar_stalled_q) begin
        if (!ga2d_axi4_arvalid || (ga2d_axi4_araddr != s_araddr_stalled_q) ||
            (ga2d_axi4_arlen != s_arlen_stalled_q) ||
            (ga2d_axi4_arsize != s_arsize_stalled_q)) begin
          $fatal(1, "GA2D netlist AR payload changed while stalled");
        end
      end
      if (ga2d_axi4_awvalid) begin
        if ((ga2d_axi4_awid != 4'd0) || (ga2d_axi4_awlen > 8'd15) ||
            (ga2d_axi4_awsize != 3'd3) || (ga2d_axi4_awburst != 2'd1) ||
            (ga2d_axi4_awlock != 1'b0) || (ga2d_axi4_awcache != 4'd0) ||
            (ga2d_axi4_awprot != 3'd0) || (ga2d_axi4_awqos != 4'd0) ||
            (ga2d_axi4_awregion != 4'd0)) begin
          $fatal(1, "GA2D netlist AW attributes violate the AXI contract");
        end
      end
      if (ga2d_axi4_arvalid) begin
        if ((ga2d_axi4_arid != 4'd0) || (ga2d_axi4_arlen > 8'd15) ||
            (ga2d_axi4_arburst != 2'd1) || (ga2d_axi4_arlock != 1'b0) ||
            (ga2d_axi4_arcache != 4'd0) || (ga2d_axi4_arprot != 3'd0) ||
            (ga2d_axi4_arqos != 4'd0) || (ga2d_axi4_arregion != 4'd0)) begin
          $fatal(1, "GA2D netlist AR attributes violate the AXI contract");
        end
      end
      if (ga2d_axi4_wvalid && (ga2d_axi4_wstrb == 8'd0)) begin
        $fatal(1, "GA2D netlist emitted a zero-strobe write");
      end
      s_aw_stalled_q     <= ga2d_axi4_awvalid && !ga2d_axi4_awready;
      s_awaddr_stalled_q <= ga2d_axi4_awaddr;
      s_awlen_stalled_q  <= ga2d_axi4_awlen;
      s_awsize_stalled_q <= ga2d_axi4_awsize;
      s_w_stalled_q      <= ga2d_axi4_wvalid && !ga2d_axi4_wready;
      s_wdata_stalled_q  <= ga2d_axi4_wdata;
      s_wstrb_stalled_q  <= ga2d_axi4_wstrb;
      s_ar_stalled_q     <= ga2d_axi4_arvalid && !ga2d_axi4_arready;
      s_araddr_stalled_q <= ga2d_axi4_araddr;
      s_arlen_stalled_q  <= ga2d_axi4_arlen;
      s_arsize_stalled_q <= ga2d_axi4_arsize;
    end
  end

  // Netlist port bundle: the synthesized apb4_ga2d_block_top exposes every
  // multi-bit wrapper bus as bit-blasted <name>_<index>_ ports (440 ports).
  // This mapping re-bundles them into the vectors used by this testbench;
  // it must track physical/smoke/syn/yosys/apb4_ga2d_block_top.sv.
  apb4_ga2d_block_top u_dut (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .resource_quiesce_i(resource_quiesce_i),
      .resource_reset_i(resource_reset_i),
      .source_stop_i(source_stop_i),
      .source_safe_idle_i(source_safe_idle_i),
      .block_ack_i(block_ack_i),
      .bridge_clear_busy_i(bridge_clear_busy_i),
      .bridge_epoch_i_0_(bridge_epoch_i[0]),
      .bridge_epoch_i_1_(bridge_epoch_i[1]),
      .bridge_epoch_i_2_(bridge_epoch_i[2]),
      .bridge_epoch_i_3_(bridge_epoch_i[3]),
      .bridge_epoch_i_4_(bridge_epoch_i[4]),
      .bridge_epoch_i_5_(bridge_epoch_i[5]),
      .bridge_epoch_i_6_(bridge_epoch_i[6]),
      .bridge_epoch_i_7_(bridge_epoch_i[7]),
      .data_ready_i(data_ready_i),
      .mem_pad_mode_i_0_(mem_pad_mode_i[0]),
      .mem_pad_mode_i_1_(mem_pad_mode_i[1]),
      .idle_o(idle_o),
      .core_safe_idle_o(core_safe_idle_o),
      .irq_o(irq_o),
      .apb4_paddr_0_(apb4_paddr[0]),
      .apb4_paddr_1_(apb4_paddr[1]),
      .apb4_paddr_2_(apb4_paddr[2]),
      .apb4_paddr_3_(apb4_paddr[3]),
      .apb4_paddr_4_(apb4_paddr[4]),
      .apb4_paddr_5_(apb4_paddr[5]),
      .apb4_paddr_6_(apb4_paddr[6]),
      .apb4_paddr_7_(apb4_paddr[7]),
      .apb4_paddr_8_(apb4_paddr[8]),
      .apb4_paddr_9_(apb4_paddr[9]),
      .apb4_paddr_10_(apb4_paddr[10]),
      .apb4_paddr_11_(apb4_paddr[11]),
      .apb4_paddr_12_(apb4_paddr[12]),
      .apb4_paddr_13_(apb4_paddr[13]),
      .apb4_paddr_14_(apb4_paddr[14]),
      .apb4_paddr_15_(apb4_paddr[15]),
      .apb4_paddr_16_(apb4_paddr[16]),
      .apb4_paddr_17_(apb4_paddr[17]),
      .apb4_paddr_18_(apb4_paddr[18]),
      .apb4_paddr_19_(apb4_paddr[19]),
      .apb4_paddr_20_(apb4_paddr[20]),
      .apb4_paddr_21_(apb4_paddr[21]),
      .apb4_paddr_22_(apb4_paddr[22]),
      .apb4_paddr_23_(apb4_paddr[23]),
      .apb4_paddr_24_(apb4_paddr[24]),
      .apb4_paddr_25_(apb4_paddr[25]),
      .apb4_paddr_26_(apb4_paddr[26]),
      .apb4_paddr_27_(apb4_paddr[27]),
      .apb4_paddr_28_(apb4_paddr[28]),
      .apb4_paddr_29_(apb4_paddr[29]),
      .apb4_paddr_30_(apb4_paddr[30]),
      .apb4_paddr_31_(apb4_paddr[31]),
      .apb4_pprot_0_(apb4_pprot[0]),
      .apb4_pprot_1_(apb4_pprot[1]),
      .apb4_pprot_2_(apb4_pprot[2]),
      .apb4_psel(apb4_psel),
      .apb4_penable(apb4_penable),
      .apb4_pwrite(apb4_pwrite),
      .apb4_pwdata_0_(apb4_pwdata[0]),
      .apb4_pwdata_1_(apb4_pwdata[1]),
      .apb4_pwdata_2_(apb4_pwdata[2]),
      .apb4_pwdata_3_(apb4_pwdata[3]),
      .apb4_pwdata_4_(apb4_pwdata[4]),
      .apb4_pwdata_5_(apb4_pwdata[5]),
      .apb4_pwdata_6_(apb4_pwdata[6]),
      .apb4_pwdata_7_(apb4_pwdata[7]),
      .apb4_pwdata_8_(apb4_pwdata[8]),
      .apb4_pwdata_9_(apb4_pwdata[9]),
      .apb4_pwdata_10_(apb4_pwdata[10]),
      .apb4_pwdata_11_(apb4_pwdata[11]),
      .apb4_pwdata_12_(apb4_pwdata[12]),
      .apb4_pwdata_13_(apb4_pwdata[13]),
      .apb4_pwdata_14_(apb4_pwdata[14]),
      .apb4_pwdata_15_(apb4_pwdata[15]),
      .apb4_pwdata_16_(apb4_pwdata[16]),
      .apb4_pwdata_17_(apb4_pwdata[17]),
      .apb4_pwdata_18_(apb4_pwdata[18]),
      .apb4_pwdata_19_(apb4_pwdata[19]),
      .apb4_pwdata_20_(apb4_pwdata[20]),
      .apb4_pwdata_21_(apb4_pwdata[21]),
      .apb4_pwdata_22_(apb4_pwdata[22]),
      .apb4_pwdata_23_(apb4_pwdata[23]),
      .apb4_pwdata_24_(apb4_pwdata[24]),
      .apb4_pwdata_25_(apb4_pwdata[25]),
      .apb4_pwdata_26_(apb4_pwdata[26]),
      .apb4_pwdata_27_(apb4_pwdata[27]),
      .apb4_pwdata_28_(apb4_pwdata[28]),
      .apb4_pwdata_29_(apb4_pwdata[29]),
      .apb4_pwdata_30_(apb4_pwdata[30]),
      .apb4_pwdata_31_(apb4_pwdata[31]),
      .apb4_pstrb_0_(apb4_pstrb[0]),
      .apb4_pstrb_1_(apb4_pstrb[1]),
      .apb4_pstrb_2_(apb4_pstrb[2]),
      .apb4_pstrb_3_(apb4_pstrb[3]),
      .apb4_pready(apb4_pready),
      .apb4_prdata_0_(apb4_prdata[0]),
      .apb4_prdata_1_(apb4_prdata[1]),
      .apb4_prdata_2_(apb4_prdata[2]),
      .apb4_prdata_3_(apb4_prdata[3]),
      .apb4_prdata_4_(apb4_prdata[4]),
      .apb4_prdata_5_(apb4_prdata[5]),
      .apb4_prdata_6_(apb4_prdata[6]),
      .apb4_prdata_7_(apb4_prdata[7]),
      .apb4_prdata_8_(apb4_prdata[8]),
      .apb4_prdata_9_(apb4_prdata[9]),
      .apb4_prdata_10_(apb4_prdata[10]),
      .apb4_prdata_11_(apb4_prdata[11]),
      .apb4_prdata_12_(apb4_prdata[12]),
      .apb4_prdata_13_(apb4_prdata[13]),
      .apb4_prdata_14_(apb4_prdata[14]),
      .apb4_prdata_15_(apb4_prdata[15]),
      .apb4_prdata_16_(apb4_prdata[16]),
      .apb4_prdata_17_(apb4_prdata[17]),
      .apb4_prdata_18_(apb4_prdata[18]),
      .apb4_prdata_19_(apb4_prdata[19]),
      .apb4_prdata_20_(apb4_prdata[20]),
      .apb4_prdata_21_(apb4_prdata[21]),
      .apb4_prdata_22_(apb4_prdata[22]),
      .apb4_prdata_23_(apb4_prdata[23]),
      .apb4_prdata_24_(apb4_prdata[24]),
      .apb4_prdata_25_(apb4_prdata[25]),
      .apb4_prdata_26_(apb4_prdata[26]),
      .apb4_prdata_27_(apb4_prdata[27]),
      .apb4_prdata_28_(apb4_prdata[28]),
      .apb4_prdata_29_(apb4_prdata[29]),
      .apb4_prdata_30_(apb4_prdata[30]),
      .apb4_prdata_31_(apb4_prdata[31]),
      .apb4_pslverr(apb4_pslverr),
      .ga2d_axi4_awid_0_(ga2d_axi4_awid[0]),
      .ga2d_axi4_awid_1_(ga2d_axi4_awid[1]),
      .ga2d_axi4_awid_2_(ga2d_axi4_awid[2]),
      .ga2d_axi4_awid_3_(ga2d_axi4_awid[3]),
      .ga2d_axi4_awaddr_0_(ga2d_axi4_awaddr[0]),
      .ga2d_axi4_awaddr_1_(ga2d_axi4_awaddr[1]),
      .ga2d_axi4_awaddr_2_(ga2d_axi4_awaddr[2]),
      .ga2d_axi4_awaddr_3_(ga2d_axi4_awaddr[3]),
      .ga2d_axi4_awaddr_4_(ga2d_axi4_awaddr[4]),
      .ga2d_axi4_awaddr_5_(ga2d_axi4_awaddr[5]),
      .ga2d_axi4_awaddr_6_(ga2d_axi4_awaddr[6]),
      .ga2d_axi4_awaddr_7_(ga2d_axi4_awaddr[7]),
      .ga2d_axi4_awaddr_8_(ga2d_axi4_awaddr[8]),
      .ga2d_axi4_awaddr_9_(ga2d_axi4_awaddr[9]),
      .ga2d_axi4_awaddr_10_(ga2d_axi4_awaddr[10]),
      .ga2d_axi4_awaddr_11_(ga2d_axi4_awaddr[11]),
      .ga2d_axi4_awaddr_12_(ga2d_axi4_awaddr[12]),
      .ga2d_axi4_awaddr_13_(ga2d_axi4_awaddr[13]),
      .ga2d_axi4_awaddr_14_(ga2d_axi4_awaddr[14]),
      .ga2d_axi4_awaddr_15_(ga2d_axi4_awaddr[15]),
      .ga2d_axi4_awaddr_16_(ga2d_axi4_awaddr[16]),
      .ga2d_axi4_awaddr_17_(ga2d_axi4_awaddr[17]),
      .ga2d_axi4_awaddr_18_(ga2d_axi4_awaddr[18]),
      .ga2d_axi4_awaddr_19_(ga2d_axi4_awaddr[19]),
      .ga2d_axi4_awaddr_20_(ga2d_axi4_awaddr[20]),
      .ga2d_axi4_awaddr_21_(ga2d_axi4_awaddr[21]),
      .ga2d_axi4_awaddr_22_(ga2d_axi4_awaddr[22]),
      .ga2d_axi4_awaddr_23_(ga2d_axi4_awaddr[23]),
      .ga2d_axi4_awaddr_24_(ga2d_axi4_awaddr[24]),
      .ga2d_axi4_awaddr_25_(ga2d_axi4_awaddr[25]),
      .ga2d_axi4_awaddr_26_(ga2d_axi4_awaddr[26]),
      .ga2d_axi4_awaddr_27_(ga2d_axi4_awaddr[27]),
      .ga2d_axi4_awaddr_28_(ga2d_axi4_awaddr[28]),
      .ga2d_axi4_awaddr_29_(ga2d_axi4_awaddr[29]),
      .ga2d_axi4_awaddr_30_(ga2d_axi4_awaddr[30]),
      .ga2d_axi4_awaddr_31_(ga2d_axi4_awaddr[31]),
      .ga2d_axi4_awlen_0_(ga2d_axi4_awlen[0]),
      .ga2d_axi4_awlen_1_(ga2d_axi4_awlen[1]),
      .ga2d_axi4_awlen_2_(ga2d_axi4_awlen[2]),
      .ga2d_axi4_awlen_3_(ga2d_axi4_awlen[3]),
      .ga2d_axi4_awlen_4_(ga2d_axi4_awlen[4]),
      .ga2d_axi4_awlen_5_(ga2d_axi4_awlen[5]),
      .ga2d_axi4_awlen_6_(ga2d_axi4_awlen[6]),
      .ga2d_axi4_awlen_7_(ga2d_axi4_awlen[7]),
      .ga2d_axi4_awsize_0_(ga2d_axi4_awsize[0]),
      .ga2d_axi4_awsize_1_(ga2d_axi4_awsize[1]),
      .ga2d_axi4_awsize_2_(ga2d_axi4_awsize[2]),
      .ga2d_axi4_awburst_0_(ga2d_axi4_awburst[0]),
      .ga2d_axi4_awburst_1_(ga2d_axi4_awburst[1]),
      .ga2d_axi4_awlock(ga2d_axi4_awlock),
      .ga2d_axi4_awcache_0_(ga2d_axi4_awcache[0]),
      .ga2d_axi4_awcache_1_(ga2d_axi4_awcache[1]),
      .ga2d_axi4_awcache_2_(ga2d_axi4_awcache[2]),
      .ga2d_axi4_awcache_3_(ga2d_axi4_awcache[3]),
      .ga2d_axi4_awprot_0_(ga2d_axi4_awprot[0]),
      .ga2d_axi4_awprot_1_(ga2d_axi4_awprot[1]),
      .ga2d_axi4_awprot_2_(ga2d_axi4_awprot[2]),
      .ga2d_axi4_awqos_0_(ga2d_axi4_awqos[0]),
      .ga2d_axi4_awqos_1_(ga2d_axi4_awqos[1]),
      .ga2d_axi4_awqos_2_(ga2d_axi4_awqos[2]),
      .ga2d_axi4_awqos_3_(ga2d_axi4_awqos[3]),
      .ga2d_axi4_awregion_0_(ga2d_axi4_awregion[0]),
      .ga2d_axi4_awregion_1_(ga2d_axi4_awregion[1]),
      .ga2d_axi4_awregion_2_(ga2d_axi4_awregion[2]),
      .ga2d_axi4_awregion_3_(ga2d_axi4_awregion[3]),
      .ga2d_axi4_awuser_0_(ga2d_axi4_awuser[0]),
      .ga2d_axi4_awuser_1_(ga2d_axi4_awuser[1]),
      .ga2d_axi4_awuser_2_(ga2d_axi4_awuser[2]),
      .ga2d_axi4_awuser_3_(ga2d_axi4_awuser[3]),
      .ga2d_axi4_awvalid(ga2d_axi4_awvalid),
      .ga2d_axi4_awready(ga2d_axi4_awready),
      .ga2d_axi4_wdata_0_(ga2d_axi4_wdata[0]),
      .ga2d_axi4_wdata_1_(ga2d_axi4_wdata[1]),
      .ga2d_axi4_wdata_2_(ga2d_axi4_wdata[2]),
      .ga2d_axi4_wdata_3_(ga2d_axi4_wdata[3]),
      .ga2d_axi4_wdata_4_(ga2d_axi4_wdata[4]),
      .ga2d_axi4_wdata_5_(ga2d_axi4_wdata[5]),
      .ga2d_axi4_wdata_6_(ga2d_axi4_wdata[6]),
      .ga2d_axi4_wdata_7_(ga2d_axi4_wdata[7]),
      .ga2d_axi4_wdata_8_(ga2d_axi4_wdata[8]),
      .ga2d_axi4_wdata_9_(ga2d_axi4_wdata[9]),
      .ga2d_axi4_wdata_10_(ga2d_axi4_wdata[10]),
      .ga2d_axi4_wdata_11_(ga2d_axi4_wdata[11]),
      .ga2d_axi4_wdata_12_(ga2d_axi4_wdata[12]),
      .ga2d_axi4_wdata_13_(ga2d_axi4_wdata[13]),
      .ga2d_axi4_wdata_14_(ga2d_axi4_wdata[14]),
      .ga2d_axi4_wdata_15_(ga2d_axi4_wdata[15]),
      .ga2d_axi4_wdata_16_(ga2d_axi4_wdata[16]),
      .ga2d_axi4_wdata_17_(ga2d_axi4_wdata[17]),
      .ga2d_axi4_wdata_18_(ga2d_axi4_wdata[18]),
      .ga2d_axi4_wdata_19_(ga2d_axi4_wdata[19]),
      .ga2d_axi4_wdata_20_(ga2d_axi4_wdata[20]),
      .ga2d_axi4_wdata_21_(ga2d_axi4_wdata[21]),
      .ga2d_axi4_wdata_22_(ga2d_axi4_wdata[22]),
      .ga2d_axi4_wdata_23_(ga2d_axi4_wdata[23]),
      .ga2d_axi4_wdata_24_(ga2d_axi4_wdata[24]),
      .ga2d_axi4_wdata_25_(ga2d_axi4_wdata[25]),
      .ga2d_axi4_wdata_26_(ga2d_axi4_wdata[26]),
      .ga2d_axi4_wdata_27_(ga2d_axi4_wdata[27]),
      .ga2d_axi4_wdata_28_(ga2d_axi4_wdata[28]),
      .ga2d_axi4_wdata_29_(ga2d_axi4_wdata[29]),
      .ga2d_axi4_wdata_30_(ga2d_axi4_wdata[30]),
      .ga2d_axi4_wdata_31_(ga2d_axi4_wdata[31]),
      .ga2d_axi4_wdata_32_(ga2d_axi4_wdata[32]),
      .ga2d_axi4_wdata_33_(ga2d_axi4_wdata[33]),
      .ga2d_axi4_wdata_34_(ga2d_axi4_wdata[34]),
      .ga2d_axi4_wdata_35_(ga2d_axi4_wdata[35]),
      .ga2d_axi4_wdata_36_(ga2d_axi4_wdata[36]),
      .ga2d_axi4_wdata_37_(ga2d_axi4_wdata[37]),
      .ga2d_axi4_wdata_38_(ga2d_axi4_wdata[38]),
      .ga2d_axi4_wdata_39_(ga2d_axi4_wdata[39]),
      .ga2d_axi4_wdata_40_(ga2d_axi4_wdata[40]),
      .ga2d_axi4_wdata_41_(ga2d_axi4_wdata[41]),
      .ga2d_axi4_wdata_42_(ga2d_axi4_wdata[42]),
      .ga2d_axi4_wdata_43_(ga2d_axi4_wdata[43]),
      .ga2d_axi4_wdata_44_(ga2d_axi4_wdata[44]),
      .ga2d_axi4_wdata_45_(ga2d_axi4_wdata[45]),
      .ga2d_axi4_wdata_46_(ga2d_axi4_wdata[46]),
      .ga2d_axi4_wdata_47_(ga2d_axi4_wdata[47]),
      .ga2d_axi4_wdata_48_(ga2d_axi4_wdata[48]),
      .ga2d_axi4_wdata_49_(ga2d_axi4_wdata[49]),
      .ga2d_axi4_wdata_50_(ga2d_axi4_wdata[50]),
      .ga2d_axi4_wdata_51_(ga2d_axi4_wdata[51]),
      .ga2d_axi4_wdata_52_(ga2d_axi4_wdata[52]),
      .ga2d_axi4_wdata_53_(ga2d_axi4_wdata[53]),
      .ga2d_axi4_wdata_54_(ga2d_axi4_wdata[54]),
      .ga2d_axi4_wdata_55_(ga2d_axi4_wdata[55]),
      .ga2d_axi4_wdata_56_(ga2d_axi4_wdata[56]),
      .ga2d_axi4_wdata_57_(ga2d_axi4_wdata[57]),
      .ga2d_axi4_wdata_58_(ga2d_axi4_wdata[58]),
      .ga2d_axi4_wdata_59_(ga2d_axi4_wdata[59]),
      .ga2d_axi4_wdata_60_(ga2d_axi4_wdata[60]),
      .ga2d_axi4_wdata_61_(ga2d_axi4_wdata[61]),
      .ga2d_axi4_wdata_62_(ga2d_axi4_wdata[62]),
      .ga2d_axi4_wdata_63_(ga2d_axi4_wdata[63]),
      .ga2d_axi4_wstrb_0_(ga2d_axi4_wstrb[0]),
      .ga2d_axi4_wstrb_1_(ga2d_axi4_wstrb[1]),
      .ga2d_axi4_wstrb_2_(ga2d_axi4_wstrb[2]),
      .ga2d_axi4_wstrb_3_(ga2d_axi4_wstrb[3]),
      .ga2d_axi4_wstrb_4_(ga2d_axi4_wstrb[4]),
      .ga2d_axi4_wstrb_5_(ga2d_axi4_wstrb[5]),
      .ga2d_axi4_wstrb_6_(ga2d_axi4_wstrb[6]),
      .ga2d_axi4_wstrb_7_(ga2d_axi4_wstrb[7]),
      .ga2d_axi4_wlast(ga2d_axi4_wlast),
      .ga2d_axi4_wuser_0_(ga2d_axi4_wuser[0]),
      .ga2d_axi4_wuser_1_(ga2d_axi4_wuser[1]),
      .ga2d_axi4_wuser_2_(ga2d_axi4_wuser[2]),
      .ga2d_axi4_wuser_3_(ga2d_axi4_wuser[3]),
      .ga2d_axi4_wvalid(ga2d_axi4_wvalid),
      .ga2d_axi4_wready(ga2d_axi4_wready),
      .ga2d_axi4_bid_0_(ga2d_axi4_bid[0]),
      .ga2d_axi4_bid_1_(ga2d_axi4_bid[1]),
      .ga2d_axi4_bid_2_(ga2d_axi4_bid[2]),
      .ga2d_axi4_bid_3_(ga2d_axi4_bid[3]),
      .ga2d_axi4_bresp_0_(ga2d_axi4_bresp[0]),
      .ga2d_axi4_bresp_1_(ga2d_axi4_bresp[1]),
      .ga2d_axi4_buser_0_(ga2d_axi4_buser[0]),
      .ga2d_axi4_buser_1_(ga2d_axi4_buser[1]),
      .ga2d_axi4_buser_2_(ga2d_axi4_buser[2]),
      .ga2d_axi4_buser_3_(ga2d_axi4_buser[3]),
      .ga2d_axi4_bvalid(ga2d_axi4_bvalid),
      .ga2d_axi4_bready(ga2d_axi4_bready),
      .ga2d_axi4_arid_0_(ga2d_axi4_arid[0]),
      .ga2d_axi4_arid_1_(ga2d_axi4_arid[1]),
      .ga2d_axi4_arid_2_(ga2d_axi4_arid[2]),
      .ga2d_axi4_arid_3_(ga2d_axi4_arid[3]),
      .ga2d_axi4_araddr_0_(ga2d_axi4_araddr[0]),
      .ga2d_axi4_araddr_1_(ga2d_axi4_araddr[1]),
      .ga2d_axi4_araddr_2_(ga2d_axi4_araddr[2]),
      .ga2d_axi4_araddr_3_(ga2d_axi4_araddr[3]),
      .ga2d_axi4_araddr_4_(ga2d_axi4_araddr[4]),
      .ga2d_axi4_araddr_5_(ga2d_axi4_araddr[5]),
      .ga2d_axi4_araddr_6_(ga2d_axi4_araddr[6]),
      .ga2d_axi4_araddr_7_(ga2d_axi4_araddr[7]),
      .ga2d_axi4_araddr_8_(ga2d_axi4_araddr[8]),
      .ga2d_axi4_araddr_9_(ga2d_axi4_araddr[9]),
      .ga2d_axi4_araddr_10_(ga2d_axi4_araddr[10]),
      .ga2d_axi4_araddr_11_(ga2d_axi4_araddr[11]),
      .ga2d_axi4_araddr_12_(ga2d_axi4_araddr[12]),
      .ga2d_axi4_araddr_13_(ga2d_axi4_araddr[13]),
      .ga2d_axi4_araddr_14_(ga2d_axi4_araddr[14]),
      .ga2d_axi4_araddr_15_(ga2d_axi4_araddr[15]),
      .ga2d_axi4_araddr_16_(ga2d_axi4_araddr[16]),
      .ga2d_axi4_araddr_17_(ga2d_axi4_araddr[17]),
      .ga2d_axi4_araddr_18_(ga2d_axi4_araddr[18]),
      .ga2d_axi4_araddr_19_(ga2d_axi4_araddr[19]),
      .ga2d_axi4_araddr_20_(ga2d_axi4_araddr[20]),
      .ga2d_axi4_araddr_21_(ga2d_axi4_araddr[21]),
      .ga2d_axi4_araddr_22_(ga2d_axi4_araddr[22]),
      .ga2d_axi4_araddr_23_(ga2d_axi4_araddr[23]),
      .ga2d_axi4_araddr_24_(ga2d_axi4_araddr[24]),
      .ga2d_axi4_araddr_25_(ga2d_axi4_araddr[25]),
      .ga2d_axi4_araddr_26_(ga2d_axi4_araddr[26]),
      .ga2d_axi4_araddr_27_(ga2d_axi4_araddr[27]),
      .ga2d_axi4_araddr_28_(ga2d_axi4_araddr[28]),
      .ga2d_axi4_araddr_29_(ga2d_axi4_araddr[29]),
      .ga2d_axi4_araddr_30_(ga2d_axi4_araddr[30]),
      .ga2d_axi4_araddr_31_(ga2d_axi4_araddr[31]),
      .ga2d_axi4_arlen_0_(ga2d_axi4_arlen[0]),
      .ga2d_axi4_arlen_1_(ga2d_axi4_arlen[1]),
      .ga2d_axi4_arlen_2_(ga2d_axi4_arlen[2]),
      .ga2d_axi4_arlen_3_(ga2d_axi4_arlen[3]),
      .ga2d_axi4_arlen_4_(ga2d_axi4_arlen[4]),
      .ga2d_axi4_arlen_5_(ga2d_axi4_arlen[5]),
      .ga2d_axi4_arlen_6_(ga2d_axi4_arlen[6]),
      .ga2d_axi4_arlen_7_(ga2d_axi4_arlen[7]),
      .ga2d_axi4_arsize_0_(ga2d_axi4_arsize[0]),
      .ga2d_axi4_arsize_1_(ga2d_axi4_arsize[1]),
      .ga2d_axi4_arsize_2_(ga2d_axi4_arsize[2]),
      .ga2d_axi4_arburst_0_(ga2d_axi4_arburst[0]),
      .ga2d_axi4_arburst_1_(ga2d_axi4_arburst[1]),
      .ga2d_axi4_arlock(ga2d_axi4_arlock),
      .ga2d_axi4_arcache_0_(ga2d_axi4_arcache[0]),
      .ga2d_axi4_arcache_1_(ga2d_axi4_arcache[1]),
      .ga2d_axi4_arcache_2_(ga2d_axi4_arcache[2]),
      .ga2d_axi4_arcache_3_(ga2d_axi4_arcache[3]),
      .ga2d_axi4_arprot_0_(ga2d_axi4_arprot[0]),
      .ga2d_axi4_arprot_1_(ga2d_axi4_arprot[1]),
      .ga2d_axi4_arprot_2_(ga2d_axi4_arprot[2]),
      .ga2d_axi4_arqos_0_(ga2d_axi4_arqos[0]),
      .ga2d_axi4_arqos_1_(ga2d_axi4_arqos[1]),
      .ga2d_axi4_arqos_2_(ga2d_axi4_arqos[2]),
      .ga2d_axi4_arqos_3_(ga2d_axi4_arqos[3]),
      .ga2d_axi4_arregion_0_(ga2d_axi4_arregion[0]),
      .ga2d_axi4_arregion_1_(ga2d_axi4_arregion[1]),
      .ga2d_axi4_arregion_2_(ga2d_axi4_arregion[2]),
      .ga2d_axi4_arregion_3_(ga2d_axi4_arregion[3]),
      .ga2d_axi4_aruser_0_(ga2d_axi4_aruser[0]),
      .ga2d_axi4_aruser_1_(ga2d_axi4_aruser[1]),
      .ga2d_axi4_aruser_2_(ga2d_axi4_aruser[2]),
      .ga2d_axi4_aruser_3_(ga2d_axi4_aruser[3]),
      .ga2d_axi4_arvalid(ga2d_axi4_arvalid),
      .ga2d_axi4_arready(ga2d_axi4_arready),
      .ga2d_axi4_rid_0_(ga2d_axi4_rid[0]),
      .ga2d_axi4_rid_1_(ga2d_axi4_rid[1]),
      .ga2d_axi4_rid_2_(ga2d_axi4_rid[2]),
      .ga2d_axi4_rid_3_(ga2d_axi4_rid[3]),
      .ga2d_axi4_rdata_0_(ga2d_axi4_rdata[0]),
      .ga2d_axi4_rdata_1_(ga2d_axi4_rdata[1]),
      .ga2d_axi4_rdata_2_(ga2d_axi4_rdata[2]),
      .ga2d_axi4_rdata_3_(ga2d_axi4_rdata[3]),
      .ga2d_axi4_rdata_4_(ga2d_axi4_rdata[4]),
      .ga2d_axi4_rdata_5_(ga2d_axi4_rdata[5]),
      .ga2d_axi4_rdata_6_(ga2d_axi4_rdata[6]),
      .ga2d_axi4_rdata_7_(ga2d_axi4_rdata[7]),
      .ga2d_axi4_rdata_8_(ga2d_axi4_rdata[8]),
      .ga2d_axi4_rdata_9_(ga2d_axi4_rdata[9]),
      .ga2d_axi4_rdata_10_(ga2d_axi4_rdata[10]),
      .ga2d_axi4_rdata_11_(ga2d_axi4_rdata[11]),
      .ga2d_axi4_rdata_12_(ga2d_axi4_rdata[12]),
      .ga2d_axi4_rdata_13_(ga2d_axi4_rdata[13]),
      .ga2d_axi4_rdata_14_(ga2d_axi4_rdata[14]),
      .ga2d_axi4_rdata_15_(ga2d_axi4_rdata[15]),
      .ga2d_axi4_rdata_16_(ga2d_axi4_rdata[16]),
      .ga2d_axi4_rdata_17_(ga2d_axi4_rdata[17]),
      .ga2d_axi4_rdata_18_(ga2d_axi4_rdata[18]),
      .ga2d_axi4_rdata_19_(ga2d_axi4_rdata[19]),
      .ga2d_axi4_rdata_20_(ga2d_axi4_rdata[20]),
      .ga2d_axi4_rdata_21_(ga2d_axi4_rdata[21]),
      .ga2d_axi4_rdata_22_(ga2d_axi4_rdata[22]),
      .ga2d_axi4_rdata_23_(ga2d_axi4_rdata[23]),
      .ga2d_axi4_rdata_24_(ga2d_axi4_rdata[24]),
      .ga2d_axi4_rdata_25_(ga2d_axi4_rdata[25]),
      .ga2d_axi4_rdata_26_(ga2d_axi4_rdata[26]),
      .ga2d_axi4_rdata_27_(ga2d_axi4_rdata[27]),
      .ga2d_axi4_rdata_28_(ga2d_axi4_rdata[28]),
      .ga2d_axi4_rdata_29_(ga2d_axi4_rdata[29]),
      .ga2d_axi4_rdata_30_(ga2d_axi4_rdata[30]),
      .ga2d_axi4_rdata_31_(ga2d_axi4_rdata[31]),
      .ga2d_axi4_rdata_32_(ga2d_axi4_rdata[32]),
      .ga2d_axi4_rdata_33_(ga2d_axi4_rdata[33]),
      .ga2d_axi4_rdata_34_(ga2d_axi4_rdata[34]),
      .ga2d_axi4_rdata_35_(ga2d_axi4_rdata[35]),
      .ga2d_axi4_rdata_36_(ga2d_axi4_rdata[36]),
      .ga2d_axi4_rdata_37_(ga2d_axi4_rdata[37]),
      .ga2d_axi4_rdata_38_(ga2d_axi4_rdata[38]),
      .ga2d_axi4_rdata_39_(ga2d_axi4_rdata[39]),
      .ga2d_axi4_rdata_40_(ga2d_axi4_rdata[40]),
      .ga2d_axi4_rdata_41_(ga2d_axi4_rdata[41]),
      .ga2d_axi4_rdata_42_(ga2d_axi4_rdata[42]),
      .ga2d_axi4_rdata_43_(ga2d_axi4_rdata[43]),
      .ga2d_axi4_rdata_44_(ga2d_axi4_rdata[44]),
      .ga2d_axi4_rdata_45_(ga2d_axi4_rdata[45]),
      .ga2d_axi4_rdata_46_(ga2d_axi4_rdata[46]),
      .ga2d_axi4_rdata_47_(ga2d_axi4_rdata[47]),
      .ga2d_axi4_rdata_48_(ga2d_axi4_rdata[48]),
      .ga2d_axi4_rdata_49_(ga2d_axi4_rdata[49]),
      .ga2d_axi4_rdata_50_(ga2d_axi4_rdata[50]),
      .ga2d_axi4_rdata_51_(ga2d_axi4_rdata[51]),
      .ga2d_axi4_rdata_52_(ga2d_axi4_rdata[52]),
      .ga2d_axi4_rdata_53_(ga2d_axi4_rdata[53]),
      .ga2d_axi4_rdata_54_(ga2d_axi4_rdata[54]),
      .ga2d_axi4_rdata_55_(ga2d_axi4_rdata[55]),
      .ga2d_axi4_rdata_56_(ga2d_axi4_rdata[56]),
      .ga2d_axi4_rdata_57_(ga2d_axi4_rdata[57]),
      .ga2d_axi4_rdata_58_(ga2d_axi4_rdata[58]),
      .ga2d_axi4_rdata_59_(ga2d_axi4_rdata[59]),
      .ga2d_axi4_rdata_60_(ga2d_axi4_rdata[60]),
      .ga2d_axi4_rdata_61_(ga2d_axi4_rdata[61]),
      .ga2d_axi4_rdata_62_(ga2d_axi4_rdata[62]),
      .ga2d_axi4_rdata_63_(ga2d_axi4_rdata[63]),
      .ga2d_axi4_rresp_0_(ga2d_axi4_rresp[0]),
      .ga2d_axi4_rresp_1_(ga2d_axi4_rresp[1]),
      .ga2d_axi4_rlast(ga2d_axi4_rlast),
      .ga2d_axi4_ruser_0_(ga2d_axi4_ruser[0]),
      .ga2d_axi4_ruser_1_(ga2d_axi4_ruser[1]),
      .ga2d_axi4_ruser_2_(ga2d_axi4_ruser[2]),
      .ga2d_axi4_ruser_3_(ga2d_axi4_ruser[3]),
      .ga2d_axi4_rvalid(ga2d_axi4_rvalid),
      .ga2d_axi4_rready(ga2d_axi4_rready)
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i,
                           input logic expected_error_i);
    begin
      @(negedge clk_i);
      apb4_paddr   = {20'd0, offset_i};
      apb4_pwrite  = 1'b1;
      apb4_pwdata  = value_i;
      apb4_pstrb   = 4'hf;
      apb4_psel    = 1'b1;
      apb4_penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4_pready || (apb4_pslverr != expected_error_i)) begin
        $fatal(1, "GA2D netlist APB write response mismatch at %h", offset_i);
      end
      @(negedge clk_i);
      apb4_psel    = 1'b0;
      apb4_penable = 1'b0;
      apb4_pwrite  = 1'b0;
      apb4_pstrb   = '0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4_paddr   = {20'd0, offset_i};
      apb4_pwrite  = 1'b0;
      apb4_pstrb   = '0;
      apb4_psel    = 1'b1;
      apb4_penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4_pready || apb4_pslverr) begin
        $fatal(1, "GA2D netlist APB read response mismatch at %h", offset_i);
      end
      value_o = apb4_prdata;
      @(negedge clk_i);
      apb4_psel    = 1'b0;
      apb4_penable = 1'b0;
    end
  endtask

  task automatic wait_for_terminal(input logic expected_done_i, input logic expected_error_i,
                                   input logic expected_abort_i);
    logic [31:0] status;
    logic        terminal_seen;
    begin
      terminal_seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 2000) && !terminal_seen; attempt++) begin
        apb_read(`APB4_GA2D__STATUS, status);
        if (!status[`APB4_GA2D__STATUS_BUSY] &&
            (status[`APB4_GA2D__STATUS_DONE] ||
             status[`APB4_GA2D__STATUS_ERROR] ||
             status[`APB4_GA2D__STATUS_ABORTED])) begin
          if ((status[`APB4_GA2D__STATUS_DONE] != expected_done_i) ||
              (status[`APB4_GA2D__STATUS_ERROR] != expected_error_i) ||
              (status[`APB4_GA2D__STATUS_ABORTED] != expected_abort_i)) begin
            $fatal(1, "GA2D netlist terminal status mismatch: %h", status);
          end
          terminal_seen = 1'b1;
        end
      end
      if (!terminal_seen) begin
        $fatal(1, "GA2D netlist terminal state timed out");
      end
    end
  endtask

  task automatic clear_memory(input logic [7:0] value_i);
    begin
      for (int unsigned index = 0; index < MemoryBytes; index++) begin
        s_memory[index] = value_i;
      end
    end
  endtask

  task automatic configure_fill(input logic [2:0] format_i, input logic [15:0] width_i,
                                input logic [15:0] height_i, input logic [31:0] destination_i,
                                input logic [31:0] pitch_i, input logic [31:0] color_i);
    begin
      apb_write(`APB4_GA2D__JOB_CONFIG, 32'd0, 1'b0);
      apb_write(`APB4_GA2D__COLOR, color_i, 1'b0);
      apb_write(`APB4_GA2D__SIZE, {height_i, width_i}, 1'b0);
      apb_write(`APB4_GA2D__DST_ADDRESS, destination_i, 1'b0);
      apb_write(`APB4_GA2D__DST_PITCH, pitch_i, 1'b0);
      apb_write(`APB4_GA2D__DST_FORMAT, {29'd0, format_i}, 1'b0);
    end
  endtask

  task automatic configure_copy(
      input logic [2:0] format_i, input logic [15:0] width_i, input logic [15:0] height_i,
      input logic [31:0] foreground_i, input logic [31:0] foreground_pitch_i,
      input logic [31:0] destination_i, input logic [31:0] destination_pitch_i);
    begin
      apb_write(`APB4_GA2D__JOB_CONFIG, 32'd1, 1'b0);
      apb_write(`APB4_GA2D__SIZE, {height_i, width_i}, 1'b0);
      apb_write(`APB4_GA2D__FG_ADDRESS, foreground_i, 1'b0);
      apb_write(`APB4_GA2D__FG_PITCH, foreground_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__FG_FORMAT, {29'd0, format_i}, 1'b0);
      apb_write(`APB4_GA2D__DST_ADDRESS, destination_i, 1'b0);
      apb_write(`APB4_GA2D__DST_PITCH, destination_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__DST_FORMAT, {29'd0, format_i}, 1'b0);
    end
  endtask

  task automatic configure_blend(
      input logic [2:0] foreground_format_i, input logic [2:0] background_format_i,
      input logic [2:0] destination_format_i, input logic [15:0] width_i,
      input logic [15:0] height_i, input logic [31:0] foreground_i,
      input logic [31:0] foreground_pitch_i, input logic [31:0] background_i,
      input logic [31:0] background_pitch_i, input logic [31:0] destination_i,
      input logic [31:0] destination_pitch_i, input logic [7:0] alpha_i,
      input logic [31:0] color_i);
    begin
      apb_write(`APB4_GA2D__JOB_CONFIG, `APB4_GA2D__OP_BLEND, 1'b0);
      apb_write(`APB4_GA2D__GLOBAL_ALPHA, {24'd0, alpha_i}, 1'b0);
      apb_write(`APB4_GA2D__COLOR, color_i, 1'b0);
      apb_write(`APB4_GA2D__SIZE, {height_i, width_i}, 1'b0);
      apb_write(`APB4_GA2D__FG_ADDRESS, foreground_i, 1'b0);
      apb_write(`APB4_GA2D__FG_PITCH, foreground_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__FG_FORMAT, {29'd0, foreground_format_i}, 1'b0);
      apb_write(`APB4_GA2D__BG_ADDRESS, background_i, 1'b0);
      apb_write(`APB4_GA2D__BG_PITCH, background_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__BG_FORMAT, {29'd0, background_format_i}, 1'b0);
      apb_write(`APB4_GA2D__DST_ADDRESS, destination_i, 1'b0);
      apb_write(`APB4_GA2D__DST_PITCH, destination_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__DST_FORMAT, {29'd0, destination_format_i}, 1'b0);
    end
  endtask

  task automatic start_job;
    begin
      apb_write(`APB4_GA2D__COMMAND, 32'h0000_0001, 1'b0);
    end
  endtask

  task automatic read_snapshot64(input logic [11:0] low_offset_i, input logic [11:0] high_offset_i,
                                 output logic [63:0] value_o);
    logic [31:0] low;
    logic [31:0] high;
    begin
      apb_read(low_offset_i, low);
      apb_read(high_offset_i, high);
      value_o = {high, low};
    end
  endtask

  task automatic check_terminal_counters(input logic [63:0] expected_read_bytes_i,
                                         input logic [63:0] expected_write_bytes_i,
                                         input logic [15:0] expected_lines_i);
    logic [63:0] read_bytes;
    logic [63:0] write_bytes;
    logic [31:0] lines;
    begin
      apb_write(`APB4_GA2D__PERF_SNAPSHOT, 32'h0000_0001, 1'b0);
      read_snapshot64(`APB4_GA2D__SNAP_READ_BYTES_LO, `APB4_GA2D__SNAP_READ_BYTES_HI, read_bytes);
      read_snapshot64(`APB4_GA2D__SNAP_WRITE_BYTES_LO, `APB4_GA2D__SNAP_WRITE_BYTES_HI,
                      write_bytes);
      apb_read(`APB4_GA2D__SNAP_LINES_DONE, lines);
      if ((read_bytes != expected_read_bytes_i) ||
          (write_bytes != expected_write_bytes_i) ||
          (lines[15:0] != expected_lines_i)) begin
        $fatal(1, "GA2D netlist terminal accounting mismatch: read=%h write=%h lines=%h",
               read_bytes, write_bytes, lines);
      end
    end
  endtask

  task automatic check_done_event;
    logic [31:0] irq_state;
    begin
      repeat (2) @(posedge clk_i);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (!irq_state[`APB4_GA2D__IRQ_DONE]) begin
        $fatal(1, "GA2D netlist completion did not latch IRQ_STATE.DONE");
      end
      if (!irq_o) begin
        $fatal(1, "GA2D netlist completion did not assert the enabled raw IRQ");
      end
      apb_write(`APB4_GA2D__IRQ_STATE, {29'd0, IrqDoneMask}, 1'b0);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (irq_state[`APB4_GA2D__IRQ_DONE] || irq_o) begin
        $fatal(1, "GA2D netlist completion IRQ_STATE.DONE W1C did not clear");
      end
    end
  endtask

  task automatic check_error_event;
    logic [31:0] irq_state;
    begin
      repeat (2) @(posedge clk_i);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (!irq_state[`APB4_GA2D__IRQ_ERROR]) begin
        $fatal(1, "GA2D netlist error did not latch IRQ_STATE.ERROR");
      end
      apb_write(`APB4_GA2D__IRQ_STATE, {29'd0, IrqErrorMask}, 1'b0);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (irq_state[`APB4_GA2D__IRQ_ERROR]) begin
        $fatal(1, "GA2D netlist error IRQ_STATE.ERROR W1C did not clear");
      end
    end
  endtask

  task automatic clear_first_error;
    logic [31:0] error_status;
    begin
      apb_write(`APB4_GA2D__ERROR_STATUS, 32'h0000_0001, 1'b0);
      apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
      if (error_status[`APB4_GA2D__ERROR_STATUS_VALID]) begin
        $fatal(1, "GA2D netlist ERROR_STATUS W1C did not clear the first-error record");
      end
    end
  endtask

  // Golden pixel math, mirroring the p5_reference_* functions of
  // tests/rtl/ga2d_dma_tb.sv exactly.
  function automatic logic [31:0] reference_unpack(input logic [31:0] pixel_i,
                                                   input logic [2:0] format_i);
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;
    logic [7:0] alpha;
    begin
      red   = '0;
      green = '0;
      blue  = '0;
      alpha = 8'hff;
      case (format_i)
        `APB4_GA2D__FORMAT_RGB565: begin
          red   = {pixel_i[15:11], pixel_i[15:13]};
          green = {pixel_i[10:5], pixel_i[10:9]};
          blue  = {pixel_i[4:0], pixel_i[4:2]};
        end
        `APB4_GA2D__FORMAT_RGB888: begin
          red   = pixel_i[7:0];
          green = pixel_i[15:8];
          blue  = pixel_i[23:16];
        end
        `APB4_GA2D__FORMAT_XRGB8888: begin
          red   = pixel_i[23:16];
          green = pixel_i[15:8];
          blue  = pixel_i[7:0];
        end
        `APB4_GA2D__FORMAT_ARGB8888: begin
          red   = pixel_i[23:16];
          green = pixel_i[15:8];
          blue  = pixel_i[7:0];
          alpha = pixel_i[31:24];
        end
        default: begin
        end
      endcase
      return {alpha, red, green, blue};
    end
  endfunction

  function automatic logic [31:0] reference_pack(input logic [31:0] rgba_i,
                                                 input logic [2:0] format_i);
    begin
      case (format_i)
        `APB4_GA2D__FORMAT_RGB565:   return {16'd0, rgba_i[23:19], rgba_i[15:10], rgba_i[7:3]};
        `APB4_GA2D__FORMAT_RGB888:   return {8'd0, rgba_i[7:0], rgba_i[15:8], rgba_i[23:16]};
        `APB4_GA2D__FORMAT_XRGB8888: return {8'hff, rgba_i[23:0]};
        `APB4_GA2D__FORMAT_ARGB8888: return rgba_i;
        default:                     return '0;
      endcase
    end
  endfunction

  function automatic logic [7:0] reference_blend_channel(
      input logic [7:0] foreground_i, input logic [7:0] background_i, input logic [7:0] alpha_i);
    logic [16:0] numerator;
    begin
      numerator = ({9'd0, foreground_i} * {9'd0, alpha_i}) +
                  ({9'd0, background_i} * ({9'd0, 8'hff} - {9'd0, alpha_i})) + 17'd127;
      return numerator / 17'd255;
    end
  endfunction

  function automatic logic [31:0] reference_blend(
      input logic [31:0] foreground_i, input logic [31:0] background_i,
      input logic [7:0] global_alpha_i, input logic [2:0] foreground_format_i,
      input logic [2:0] background_format_i, input logic [2:0] destination_format_i);
    logic [31:0] foreground_rgba;
    logic [31:0] background_rgba;
    logic [ 7:0] alpha;
    logic [15:0] alpha_product;
    logic [31:0] result_rgba;
    begin
      foreground_rgba = reference_unpack(foreground_i, foreground_format_i);
      background_rgba = reference_unpack(background_i, background_format_i);
      alpha_product   = {8'd0, foreground_rgba[31:24]} * {8'd0, global_alpha_i};
      alpha           = (alpha_product + 16'd127) / 16'd255;
      result_rgba[31:24] = 8'hff;
      result_rgba[23:16] =
          reference_blend_channel(foreground_rgba[23:16], background_rgba[23:16], alpha);
      result_rgba[15:8] =
          reference_blend_channel(foreground_rgba[15:8], background_rgba[15:8], alpha);
      result_rgba[7:0] =
          reference_blend_channel(foreground_rgba[7:0], background_rgba[7:0], alpha);
      return reference_pack(result_rgba, destination_format_i);
    end
  endfunction

  task automatic run_fill_case;
    logic [31:0] destination;
    logic [31:0] row;
    begin
      destination = SramBase + 32'h200;
      clear_memory(8'hd3);
      configure_fill(`APB4_GA2D__FORMAT_XRGB8888, 16'd3, 16'd2, destination, 32'd16,
                     32'h8012_3456);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      check_done_event();
      check_terminal_counters(64'd0, 64'd24, 16'd2);
      for (int unsigned line = 0; line < 2; line++) begin
        row = destination + (line * 32'd16);
        if (memory_byte(row - 1'b1) != 8'hd3) begin
          $fatal(1, "GA2D netlist FILL changed the leading guard");
        end
        for (int unsigned pixel = 0; pixel < 3; pixel++) begin
          if ({memory_byte(row + pixel * 4 + 3), memory_byte(row + pixel * 4 + 2),
               memory_byte(row + pixel * 4 + 1), memory_byte(row + pixel * 4)} !=
              32'hff12_3456) begin
            $fatal(1, "GA2D netlist FILL pixel mismatch: line=%0d pixel=%0d", line, pixel);
          end
        end
        for (int unsigned padding = 12; padding < 16; padding++) begin
          if (memory_byte(row + padding) != 8'hd3) begin
            $fatal(1, "GA2D netlist FILL changed row padding");
          end
        end
      end
    end
  endtask

  task automatic run_copy_case;
    logic [31:0] foreground;
    logic [31:0] destination;
    logic [31:0] source_row;
    logic [31:0] destination_row;
    begin
      foreground  = SramBase + 32'h400;
      destination = SramBase + 32'h600;
      clear_memory(8'hc7);
      for (int unsigned line = 0; line < 2; line++) begin
        source_row = foreground + (line * 32'd8);
        for (int unsigned byte_index = 0; byte_index < 6; byte_index++) begin
          s_memory[(source_row + byte_index) - SramBase] = (8'h31 * line) + byte_index + 8'd2;
        end
      end
      configure_copy(`APB4_GA2D__FORMAT_RGB565, 16'd3, 16'd2, foreground, 32'd8, destination,
                     32'd8);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      check_done_event();
      check_terminal_counters(64'd12, 64'd12, 16'd2);
      for (int unsigned line = 0; line < 2; line++) begin
        source_row      = foreground + (line * 32'd8);
        destination_row = destination + (line * 32'd8);
        if (memory_byte(destination_row - 1'b1) != 8'hc7) begin
          $fatal(1, "GA2D netlist COPY changed the leading guard");
        end
        for (int unsigned byte_index = 0; byte_index < 6; byte_index++) begin
          if (memory_byte(
                  destination_row + byte_index
              ) != memory_byte(
                  source_row + byte_index
              )) begin
            $fatal(1, "GA2D netlist COPY byte mismatch: line=%0d byte=%0d", line, byte_index);
          end
        end
        for (int unsigned padding = 6; padding < 8; padding++) begin
          if (memory_byte(destination_row + padding) != 8'hc7) begin
            $fatal(1, "GA2D netlist COPY changed row padding");
          end
        end
      end
    end
  endtask

  task automatic run_blend_case(input logic [7:0] global_alpha_i);
    logic [31:0] foreground;
    logic [31:0] background;
    logic [31:0] destination;
    logic [31:0] fg_pixel;
    logic [31:0] bg_pixel;
    logic [31:0] expected;
    logic [ 7:0] alpha_table[0:5];
    logic [31:0] row;
    begin
      foreground  = SramBase + 32'h800;
      background  = SramBase + 32'ha00;
      destination = SramBase + 32'hc00;
      alpha_table[0] = 8'h00;
      alpha_table[1] = 8'h01;
      alpha_table[2] = 8'h7f;
      alpha_table[3] = 8'h80;
      alpha_table[4] = 8'hfe;
      alpha_table[5] = 8'hff;
      clear_memory(8'hd3);
      for (int unsigned index = 0; index < 6; index++) begin
        fg_pixel = {alpha_table[index], 8'h10 + (index * 8'h13), 8'h20 + (index * 8'h07),
                    8'h30 + (index * 8'h0b)};
        bg_pixel = {16'd0, 16'h1234 + (index * 16'h0317)};
        for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
          s_memory[(foreground + (index / 3) * 32'd16 + (index % 3) * 4 + byte_index) -
                   SramBase] = fg_pixel[byte_index*8+:8];
        end
        for (int unsigned byte_index = 0; byte_index < 2; byte_index++) begin
          s_memory[(background + (index / 3) * 32'd8 + (index % 3) * 2 + byte_index) -
                   SramBase] = bg_pixel[byte_index*8+:8];
        end
      end
      configure_blend(`APB4_GA2D__FORMAT_ARGB8888, `APB4_GA2D__FORMAT_RGB565,
                      `APB4_GA2D__FORMAT_RGB565, 16'd3, 16'd2, foreground, 32'd16, background,
                      32'd8, destination, 32'd8, global_alpha_i, 32'd0);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      check_done_event();
      check_terminal_counters(64'd36, 64'd12, 16'd2);
      for (int unsigned index = 0; index < 6; index++) begin
        fg_pixel = {alpha_table[index], 8'h10 + (index * 8'h13), 8'h20 + (index * 8'h07),
                    8'h30 + (index * 8'h0b)};
        bg_pixel = {16'd0, 16'h1234 + (index * 16'h0317)};
        expected = reference_blend(fg_pixel, bg_pixel, global_alpha_i,
                                   `APB4_GA2D__FORMAT_ARGB8888, `APB4_GA2D__FORMAT_RGB565,
                                   `APB4_GA2D__FORMAT_RGB565);
        row = destination + ((index / 3) * 32'd8);
        if ({memory_byte(row + (index % 3) * 2 + 1), memory_byte(row + (index % 3) * 2)} !=
            expected[15:0]) begin
          $fatal(1, "GA2D netlist BLEND pixel mismatch: pixel=%0d global_alpha=%h expected=%h",
                 index, global_alpha_i, expected[15:0]);
        end
      end
      for (int unsigned line = 0; line < 2; line++) begin
        row = destination + (line * 32'd8);
        if (memory_byte(row - 1'b1) != 8'hd3) begin
          $fatal(1, "GA2D netlist BLEND changed the leading guard");
        end
        for (int unsigned padding = 6; padding < 8; padding++) begin
          if (memory_byte(row + padding) != 8'hd3) begin
            $fatal(1, "GA2D netlist BLEND changed row padding");
          end
        end
      end
    end
  endtask

  task automatic run_validation_error_case;
    int unsigned ar_count_before;
    int unsigned aw_count_before;
    logic [31:0] error_status;
    logic [31:0] error_address;
    begin
      ar_count_before = s_ar_count;
      aw_count_before = s_aw_count;
      configure_fill(`APB4_GA2D__FORMAT_XRGB8888, 16'd0, 16'd1, SramBase + 32'he00, 32'd16,
                     32'h8012_3456);
      start_job();
      wait_for_terminal(1'b0, 1'b1, 1'b0);
      apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
      if (!error_status[`APB4_GA2D__ERROR_STATUS_VALID] ||
          (error_status[`APB4_GA2D__ERROR_STATUS_CODE+:7] != `APB4_GA2D__ERROR_INVALID_SIZE) ||
          (error_status[`APB4_GA2D__ERROR_STATUS_STAGE+:4] !=
           `APB4_GA2D__ERROR_STAGE_VALIDATE)) begin
        $fatal(1, "GA2D netlist validation error status mismatch: %h", error_status);
      end
      apb_read(`APB4_GA2D__ERROR_ADDRESS, error_address);
      if (error_address != 32'd0) begin
        $fatal(1, "GA2D netlist validation error address mismatch: %h", error_address);
      end
      if ((s_ar_count != ar_count_before) || (s_aw_count != aw_count_before)) begin
        $fatal(1, "GA2D netlist validation failure issued AXI traffic");
      end
      check_error_event();
      clear_first_error();
    end
  endtask

  initial begin
    apb4_paddr        = '0;
    apb4_pprot        = '0;
    apb4_psel         = 1'b0;
    apb4_penable      = 1'b0;
    apb4_pwrite       = 1'b0;
    apb4_pwdata       = '0;
    apb4_pstrb        = '0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    apb_write(`APB4_GA2D__IRQ_ENABLE, {29'd0, IrqDoneMask}, 1'b0);

    run_fill_case();
    run_copy_case();
    run_blend_case(8'hff);
    run_blend_case(8'ha5);
    run_validation_error_case();

    $display(
        "GA2D P6 netlist block test passed with exact FILL COPY BLEND and validation-error coverage");
    $finish;
  end

  initial begin
    repeat (400000) @(posedge clk_i);
    $fatal(1, "GA2D P6 netlist block test timed out");
  end
endmodule
