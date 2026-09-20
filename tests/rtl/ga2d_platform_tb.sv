// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps

// Gateway stub for the SDRAM/QPI/OPI/XPI targets: addresses are accepted but
// never answered, so a transaction accepted here proves end-to-end address
// transport to that gateway while the response path stays covered by the SRAM
// model below and by full-SoC SDRAM runs. The downsizer strips the wide ID at
// this narrow boundary, so the stub records any address handshake with its
// address; the V03 target legs run one directed GA2D transaction at a time
// with no other traffic, which attributes each saw flag to master 8 by
// exclusion. Outstanding transactions are retired by a coordinated flush.
module ga2d_platform_idle_target (
    input  logic                clk_i,
    input  logic                rst_n_i,
    output logic                saw_read_o,
    output logic                saw_write_o,
    output logic         [31:0] last_araddr_o,
    output logic         [31:0] last_awaddr_o,
           axi4_if.slave        axi4
);
  assign axi4.awready = 1'b1;
  assign axi4.wready  = 1'b1;
  assign axi4.bid     = '0;
  assign axi4.bresp   = 2'b00;
  assign axi4.buser   = '0;
  assign axi4.bvalid  = 1'b0;
  assign axi4.arready = 1'b1;
  assign axi4.rid     = '0;
  assign axi4.rdata   = '0;
  assign axi4.rresp   = 2'b00;
  assign axi4.rlast   = 1'b1;
  assign axi4.ruser   = '0;
  assign axi4.rvalid  = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      saw_read_o    <= 1'b0;
      saw_write_o   <= 1'b0;
      last_araddr_o <= '0;
      last_awaddr_o <= '0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        saw_read_o    <= 1'b1;
        last_araddr_o <= axi4.araddr;
      end
      if (axi4.awvalid && axi4.awready) begin
        saw_write_o   <= 1'b1;
        last_awaddr_o <= axi4.awaddr;
      end
    end
  end
endmodule

// Behavioural 32 KiB SRAM model sitting behind the native SRAM gateway. Single
// outstanding read and write, one response-beat cadence, optional AR/response
// holds for the lifecycle scenarios. Bursts are accepted beat-by-beat so the
// V13 contention traffic can use moderate INCR bursts; writes honour WSTRB per
// byte and reads return the stored line, which lets the testbench prove
// byte-exact data and guard-byte conservation under interleaving. Contents
// start at a deterministic address-dependent pattern so untouched bytes are
// recognisable. The seen-ID masks record every accepted global ID so old and
// new master IDs can be checked for aliasing after contention.
module ga2d_platform_sram_target (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 hold_ar_i,
    input  logic                 hold_response_i,
    output logic         [  6:0] last_arid_o,
    output logic                 saw_ga2d_o,
    output logic                 saw_legacy_o,
    output logic                 saw_ga2d_write_o,
    output logic                 saw_jpeg_o,
    output logic                 saw_jpeg_write_o,
    output logic         [127:0] seen_arid_mask_o,
    output logic         [127:0] seen_awid_mask_o,
           axi4_if.slave         axi4
);
  logic        read_pending_q;
  logic [ 6:0] read_id_q;
  logic        read_valid_q;
  logic [ 7:0] read_beats_left_q;
  logic [14:0] read_addr_q;
  logic [ 2:0] read_size_q;
  logic        write_address_pending_q;
  logic [ 6:0] write_id_q;
  logic        write_valid_q;
  logic [14:0] write_addr_q;
  logic [ 2:0] write_size_q;
  logic [ 7:0] mem                     [32768];

  initial begin
    for (int i = 0; i < 32768; i++) begin
      mem[i] = 8'(8'hA6 ^ 8'(i) ^ 8'(i >> 8));
    end
  end

  assign axi4.awready = !write_address_pending_q && !write_valid_q;
  assign axi4.wready = write_address_pending_q && !write_valid_q;
  assign axi4.bid = write_id_q;
  assign axi4.bresp = 2'b00;
  assign axi4.buser = '0;
  assign axi4.bvalid = write_valid_q;
  assign axi4.arready = !hold_ar_i && !read_pending_q;
  assign axi4.rid = read_id_q;
  assign axi4.rdata = {
    mem[{read_addr_q[14:3], 3'b000}+15'd7],
    mem[{read_addr_q[14:3], 3'b000}+15'd6],
    mem[{read_addr_q[14:3], 3'b000}+15'd5],
    mem[{read_addr_q[14:3], 3'b000}+15'd4],
    mem[{read_addr_q[14:3], 3'b000}+15'd3],
    mem[{read_addr_q[14:3], 3'b000}+15'd2],
    mem[{read_addr_q[14:3], 3'b000}+15'd1],
    mem[{read_addr_q[14:3], 3'b000}]
  };
  assign axi4.rresp = 2'b00;
  assign axi4.rlast = (read_beats_left_q == 8'd0);
  assign axi4.ruser = '0;
  assign axi4.rvalid = read_valid_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_pending_q          <= 1'b0;
      read_id_q               <= '0;
      read_valid_q            <= 1'b0;
      read_beats_left_q       <= '0;
      read_addr_q             <= '0;
      read_size_q             <= '0;
      write_address_pending_q <= 1'b0;
      write_id_q              <= '0;
      write_valid_q           <= 1'b0;
      write_addr_q            <= '0;
      write_size_q            <= '0;
      last_arid_o             <= '0;
      saw_ga2d_o              <= 1'b0;
      saw_legacy_o            <= 1'b0;
      saw_ga2d_write_o        <= 1'b0;
      saw_jpeg_o              <= 1'b0;
      saw_jpeg_write_o        <= 1'b0;
      seen_arid_mask_o        <= '0;
      seen_awid_mask_o        <= '0;
    end else begin
      if (axi4.awvalid && axi4.awready) begin
        write_address_pending_q          <= 1'b1;
        write_id_q                       <= axi4.awid;
        write_addr_q                     <= axi4.awaddr[14:0];
        write_size_q                     <= axi4.awsize;
        seen_awid_mask_o[axi4.awid[6:0]] <= 1'b1;
        if (axi4.awid == 7'h40) saw_ga2d_write_o <= 1'b1;
        if (axi4.awid[6:3] == 4'd6) saw_jpeg_write_o <= 1'b1;
      end
      if (axi4.wvalid && axi4.wready) begin
        for (int b = 0; b < 8; b++) begin
          if (axi4.wstrb[b]) begin
            mem[{write_addr_q[14:3], 3'b000}+15'(b)] <= axi4.wdata[b*8+:8];
          end
        end
        if (axi4.wlast) begin
          write_valid_q <= 1'b1;
        end else begin
          write_addr_q <= write_addr_q + (15'd1 << write_size_q);
        end
      end
      if (write_valid_q && axi4.bready) begin
        write_address_pending_q <= 1'b0;
        write_valid_q           <= 1'b0;
      end
      if (axi4.arvalid && axi4.arready) begin
        read_pending_q                   <= 1'b1;
        read_id_q                        <= axi4.arid;
        read_addr_q                      <= axi4.araddr[14:0];
        read_size_q                      <= axi4.arsize;
        read_beats_left_q                <= axi4.arlen;
        last_arid_o                      <= axi4.arid;
        seen_arid_mask_o[axi4.arid[6:0]] <= 1'b1;
        if (axi4.arid == 7'h40) saw_ga2d_o <= 1'b1;
        if (axi4.arid == 7'h08) saw_legacy_o <= 1'b1;
        if (axi4.arid[6:3] == 4'd6) saw_jpeg_o <= 1'b1;
      end
      if (read_pending_q && !hold_response_i) begin
        read_valid_q <= 1'b1;
        if (read_valid_q && axi4.rready) begin
          read_valid_q <= 1'b0;
          if (read_beats_left_q == 8'd0) begin
            read_pending_q <= 1'b0;
          end else begin
            read_beats_left_q <= read_beats_left_q - 1'b1;
            read_addr_q       <= read_addr_q + (15'd1 << read_size_q);
          end
        end
      end
    end
  end
endmodule

// Deterministic 32-bit AXI4 master BFM for the V13 contention window. Each
// iteration writes a moderate INCR burst inside the BFM's private SRAM window
// and reads it back, checking IDs, responses, RLAST, and byte-exact data
// against an address/seed pattern. Inter-transaction gaps come from a seeded
// xorshift LFSR, so traffic is random-ish but fully stable across runs.
// Progress counters prove every competitor retires transactions while GA2D
// jobs run; any protocol or data violation stops the test immediately.
module ga2d_platform_bfm32 #(
    parameter logic        [31:0] BaseAddr    = 32'h3000_2000,
    parameter int unsigned        WindowBytes = 1024,
    parameter logic        [31:0] Seed        = 32'h1
) (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 run_i,
    output logic          [31:0] read_txns_o,
    output logic          [31:0] write_txns_o,
    output logic                 done_o,
           axi4_if.master        axi4
);
  typedef enum logic [2:0] {
    Idle,
    Gap,
    WriteAddr,
    WriteData,
    WriteResp,
    ReadAddr,
    ReadData
  } state_e;

  state_e s_state_d, s_state_q;
  logic [2:0] s_state_bits_q;
  logic [31:0] s_lfsr_d, s_lfsr_q;
  logic [31:0] s_gap_d, s_gap_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [7:0] s_beats_d, s_beats_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic s_id_d, s_id_q;
  logic [31:0] s_read_txns_d, s_read_txns_q;
  logic [31:0] s_write_txns_d, s_write_txns_q;

  assign s_state_q = state_e'(s_state_bits_q);
  assign done_o    = (s_state_q == Idle);

  function automatic logic [31:0] lfsr_next(input logic [31:0] value);
    return {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
  endfunction

  function automatic logic [31:0] pattern(input logic [31:0] addr);
    return addr ^ 32'hA5A5_5A5A ^ (Seed * 32'h0101_0101);
  endfunction

  assign axi4.awid     = s_id_q;
  assign axi4.awaddr   = s_addr_q;
  assign axi4.awlen    = s_beats_q - 8'd1;
  assign axi4.awsize   = 3'd2;
  assign axi4.awburst  = 2'b01;
  assign axi4.awlock   = 1'b0;
  assign axi4.awcache  = '0;
  assign axi4.awprot   = '0;
  assign axi4.awqos    = '0;
  assign axi4.awregion = '0;
  assign axi4.awuser   = '0;
  assign axi4.awvalid  = (s_state_q == WriteAddr);
  assign axi4.wdata    = pattern(s_addr_q + {22'd0, s_beat_q, 2'b00});
  assign axi4.wstrb    = 4'hF;
  assign axi4.wlast    = (s_beat_q == (s_beats_q - 8'd1));
  assign axi4.wuser    = '0;
  assign axi4.wvalid   = (s_state_q == WriteData);
  assign axi4.bready   = 1'b1;
  assign axi4.arid     = s_id_q;
  assign axi4.araddr   = s_addr_q;
  assign axi4.arlen    = s_beats_q - 8'd1;
  assign axi4.arsize   = 3'd2;
  assign axi4.arburst  = 2'b01;
  assign axi4.arlock   = 1'b0;
  assign axi4.arcache  = '0;
  assign axi4.arprot   = '0;
  assign axi4.arqos    = '0;
  assign axi4.arregion = '0;
  assign axi4.aruser   = '0;
  assign axi4.arvalid  = (s_state_q == ReadAddr);
  assign axi4.rready   = 1'b1;
  assign read_txns_o   = s_read_txns_q;
  assign write_txns_o  = s_write_txns_q;

  always_comb begin
    s_state_d      = s_state_q;
    s_lfsr_d       = s_lfsr_q;
    s_gap_d        = s_gap_q;
    s_addr_d       = s_addr_q;
    s_beats_d      = s_beats_q;
    s_beat_d       = s_beat_q;
    s_id_d         = s_id_q;
    s_read_txns_d  = s_read_txns_q;
    s_write_txns_d = s_write_txns_q;
    unique case (s_state_q)
      Idle: begin
        if (run_i) begin
          s_lfsr_d  = lfsr_next(s_lfsr_q);
          s_gap_d   = {29'd0, s_lfsr_q[2:0]};
          s_beats_d = 8'd1 + {6'd0, s_lfsr_q[4:3]};
          if ((s_addr_q + {22'd0, s_beats_d, 2'b00}) > (BaseAddr + 32'(WindowBytes))) begin
            s_addr_d = BaseAddr;
          end
          s_state_d = Gap;
        end
      end
      Gap: begin
        if (s_gap_q == 32'd0) begin
          s_beat_d  = '0;
          s_state_d = WriteAddr;
        end else begin
          s_gap_d = s_gap_q - 1'b1;
        end
      end
      WriteAddr: begin
        if (axi4.awready) begin
          s_state_d = WriteData;
        end
      end
      WriteData: begin
        if (axi4.wready) begin
          if (s_beat_q == (s_beats_q - 8'd1)) begin
            s_state_d = WriteResp;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      WriteResp: begin
        if (axi4.bvalid) begin
          s_write_txns_d = s_write_txns_q + 1'b1;
          s_beat_d       = '0;
          s_state_d      = ReadAddr;
        end
      end
      ReadAddr: begin
        if (axi4.arready) begin
          s_state_d = ReadData;
        end
      end
      default: begin
        if (axi4.rvalid) begin
          if (s_beat_q == (s_beats_q - 8'd1)) begin
            s_read_txns_d = s_read_txns_q + 1'b1;
            s_id_d        = ~s_id_q;
            if ((s_addr_q + {22'd0, s_beats_q, 2'b00}) >= (BaseAddr + 32'(WindowBytes))) begin
              s_addr_d = BaseAddr;
            end else begin
              s_addr_d = s_addr_q + {22'd0, s_beats_q, 2'b00};
            end
            s_state_d = Idle;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_bits_q <= 3'(Idle);
      s_lfsr_q       <= Seed;
      s_gap_q        <= '0;
      s_addr_q       <= BaseAddr;
      s_beats_q      <= 8'd1;
      s_beat_q       <= '0;
      s_id_q         <= 1'b0;
      s_read_txns_q  <= '0;
      s_write_txns_q <= '0;
    end else begin
      s_state_bits_q <= 3'(s_state_d);
      s_lfsr_q       <= s_lfsr_d;
      s_gap_q        <= s_gap_d;
      s_addr_q       <= s_addr_d;
      s_beats_q      <= s_beats_d;
      s_beat_q       <= s_beat_d;
      s_id_q         <= s_id_d;
      s_read_txns_q  <= s_read_txns_d;
      s_write_txns_q <= s_write_txns_d;
      if ((s_state_q == WriteResp) && axi4.bvalid) begin
        if ((axi4.bid != s_id_q) || (axi4.bresp != 2'b00)) begin
          $fatal(1, "BFM %0d write response was lost or corrupted under contention", Seed);
        end
      end
      if ((s_state_q == ReadData) && axi4.rvalid) begin
        if ((axi4.rid != s_id_q) || (axi4.rresp != 2'b00) ||
            (axi4.rlast != (s_beat_q == (s_beats_q - 8'd1)))) begin
          $fatal(1, "BFM %0d read response framing was corrupted under contention", Seed);
        end
        if (axi4.rdata != pattern(s_addr_q + {22'd0, s_beat_q, 2'b00})) begin
          $fatal(1, "BFM %0d read-back data mismatch under contention", Seed);
        end
      end
    end
  end
endmodule

module ga2d_platform_tb;
  logic                clk_lp_i = 1'b0;
  logic                clk_io_i = 1'b0;
  logic                clk_hp_i = 1'b0;
  logic                clk_mem_i = 1'b0;
  logic                rst_lp_n_i = 1'b0;
  logic                rst_io_n_i = 1'b0;
  logic                rst_hp_n_i = 1'b0;
  logic                rst_mem_n_i = 1'b0;
  logic                block_new_i = 1'b0;
  logic                recovery_i = 1'b0;
  logic                flush_i = 1'b0;
  logic        [  8:0] resource_block_i = '0;
  logic        [  1:0] mem_pad_mode_i = 2'd1;
  logic                ga2d_core_safe_idle_i = 1'b1;
  logic                ext_h_block_i = 1'b0;
  logic                sram_hold_ar_i = 1'b0;
  logic                sram_hold_response_i = 1'b0;
  logic        [  6:0] sram_last_arid;
  logic                sram_saw_ga2d;
  logic                sram_saw_legacy;
  logic                sram_saw_ga2d_write;
  logic                sram_saw_jpeg;
  logic                sram_saw_jpeg_write;
  logic                idle_o;
  logic                flush_busy_o;
  logic                ext_h_idle_o;
  logic        [  7:0] apu_bridge_epoch_o;
  logic                ga2d_source_stop_o;
  logic                ga2d_source_safe_idle_o;
  logic                ga2d_bridge_clear_busy_o;
  logic        [  7:0] ga2d_bridge_epoch_o;
  logic                ga2d_data_ready_o;
  logic        [  8:0] resource_idle_o;
  logic        [  8:0] resource_block_ack_o;
  logic        [  7:0] outstanding_read_o;
  logic        [  7:0] outstanding_write_o;
  logic                fault_valid_o;
  logic        [  3:0] fault_master_o;
  logic        [  2:0] fault_target_o;
  logic        [ 31:0] fault_addr_o;
  logic                fault_write_o;
  logic        [  3:0] fault_reason_o;
  logic        [  7:0] epoch_before;
  // V13 contention machinery: competitor run control, per-BFM progress
  // counters, and SRAM seen-ID masks for the old/new global-ID alias check.
  logic                contention_run = 1'b0;
  logic        [ 31:0] dma_read_txns;
  logic        [ 31:0] dma_write_txns;
  logic        [ 31:0] apu_read_txns;
  logic        [ 31:0] apu_write_txns;
  logic        [ 31:0] sdio0_read_txns;
  logic        [ 31:0] sdio0_write_txns;
  logic        [ 31:0] sdio1_read_txns;
  logic        [ 31:0] sdio1_write_txns;
  logic        [ 31:0] usb2_read_txns;
  logic        [ 31:0] usb2_write_txns;
  logic                dma_bfm_done;
  logic                apu_bfm_done;
  logic                sdio0_bfm_done;
  logic                sdio1_bfm_done;
  logic                usb2_bfm_done;
  logic        [127:0] sram_seen_arid_mask;
  logic        [127:0] sram_seen_awid_mask;
  logic        [127:0] expected_read_mask;
  logic        [127:0] expected_write_mask;
  // V03 multi-target legs: per-gateway observation of the directed GA2D legs.
  logic                sdram_saw_read;
  logic                sdram_saw_write;
  logic        [ 31:0] sdram_last_araddr;
  logic        [ 31:0] sdram_last_awaddr;
  logic                qpi_saw_read;
  logic                qpi_saw_write;
  logic        [ 31:0] qpi_last_araddr;
  logic        [ 31:0] qpi_last_awaddr;
  logic                opi_saw_read;
  logic                opi_saw_write;
  logic        [ 31:0] opi_last_araddr;
  logic        [ 31:0] opi_last_awaddr;
  logic                xpi_saw_read;
  logic        [ 31:0] xpi_last_araddr;
  // V08 HP clock/lifecycle switching: variable, gateable HP clock.
  int unsigned         hp_half_period = 11;
  logic                hp_clk_enable = 1'b1;
  int                  wait_left;
  int unsigned         cycle_count = 0;
  int unsigned         contention_cycle_start;
  int unsigned         contention_cycle_used;
  // First-fault attribution capture at the data-plane fault boundary.
  typedef struct packed {
    logic [3:0]  master;
    logic [2:0]  target;
    logic [31:0] addr;
    logic        write;
    logic [3:0]  reason;
  } fault_record_t;
  fault_record_t        fault_log            [16];
  int                   fault_log_count = 0;
  logic          [31:0] apb_data;
  // V13 competitor progress snapshots (0=DMA, 1=APU, 2=SDIO0, 3=SDIO1, 4=USB2).
  int unsigned          competitor_snap_start[ 5];
  int unsigned          competitor_snap_mid  [ 5];

  always @(posedge clk_hp_i) begin
    if (rst_hp_n_i && fault_valid_o && (fault_log_count < 16)) begin
      fault_log[fault_log_count].master <= fault_master_o;
      fault_log[fault_log_count].target <= fault_target_o;
      fault_log[fault_log_count].addr   <= fault_addr_o;
      fault_log[fault_log_count].write  <= fault_write_o;
      fault_log[fault_log_count].reason <= fault_reason_o;
      fault_log_count                   <= fault_log_count + 1;
    end
  end

  always @(posedge clk_io_i) begin
    cycle_count <= cycle_count + 1;
  end

  `define GA2D_TB_AWAIT(cond, msg) \
  begin \
    wait_left = 4000; \
    while (!(cond) && (wait_left != 0)) begin \
      @(posedge clk_io_i); \
      wait_left = wait_left - 1; \
    end \
    if (!(cond)) $fatal(1, msg); \
  end

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) hp_icache_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) hp_dcache_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdio0_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdio1_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) spisd_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) usb2_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) apu_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) jpeg_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) ga2d_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) lp_data_axi4 (
      .aclk   (clk_lp_i),
      .aresetn(rst_lp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) ext_h_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) sram_gateway_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdram_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) qpi_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) opi_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) xpi_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  apb4_if fabric_monitor_apb4 (
      .pclk   (clk_hp_i),
      .presetn(rst_hp_n_i)
  );

  always #5 clk_lp_i = ~clk_lp_i;
  always #7 clk_io_i = ~clk_io_i;
  // The HP clock half period is a variable and the clock can be held so the
  // V08 lifecycle scenarios can switch the HP rate mid-test and stop/restart
  // the clock across a coordinated flush. The hold keeps the current level,
  // so no runt pulse is produced.
  always begin
    #(hp_half_period);
    if (hp_clk_enable) clk_hp_i = ~clk_hp_i;
  end
  always #13 clk_mem_i = ~clk_mem_i;

  axi4_master_idle u_hp_icache_idle (.axi4(hp_icache_axi4));
  // V13 competitor map: central DMA (master 2), APU/SDIO0/USB2 (master 3 via
  // the round-robin IO gateway A), and SDIO1 (master 4 via IO gateway B) are
  // driven by deterministic BFMs; the HP dcache tasks below add the CPU-proxy
  // old-ID traffic and the JPEG tasks the master-6 traffic. spisd stays tied
  // off as the quiescent client of IO gateway B (driving it would only repeat
  // the master-4 path SDIO1 already exercises), and ext_h stays tied off
  // because its ACL-gated master is covered by the extension subsystem tests.
  ga2d_platform_bfm32 #(
      .BaseAddr(32'h3000_2000),
      .Seed    (32'h0000_0011)
  ) u_dma_bfm (
      .clk_i       (clk_io_i),
      .rst_n_i     (rst_io_n_i),
      .run_i       (contention_run),
      .read_txns_o (dma_read_txns),
      .write_txns_o(dma_write_txns),
      .done_o      (dma_bfm_done),
      .axi4        (dma_axi4)
  );
  ga2d_platform_bfm32 #(
      .BaseAddr(32'h3000_2400),
      .Seed    (32'h0000_0023)
  ) u_apu_bfm (
      .clk_i       (clk_io_i),
      .rst_n_i     (rst_io_n_i),
      .run_i       (contention_run),
      .read_txns_o (apu_read_txns),
      .write_txns_o(apu_write_txns),
      .done_o      (apu_bfm_done),
      .axi4        (apu_axi4)
  );
  ga2d_platform_bfm32 #(
      .BaseAddr(32'h3000_2800),
      .Seed    (32'h0000_0037)
  ) u_sdio0_bfm (
      .clk_i       (clk_io_i),
      .rst_n_i     (rst_io_n_i),
      .run_i       (contention_run),
      .read_txns_o (sdio0_read_txns),
      .write_txns_o(sdio0_write_txns),
      .done_o      (sdio0_bfm_done),
      .axi4        (sdio0_axi4)
  );
  ga2d_platform_bfm32 #(
      .BaseAddr(32'h3000_2C00),
      .Seed    (32'h0000_0049)
  ) u_sdio1_bfm (
      .clk_i       (clk_io_i),
      .rst_n_i     (rst_io_n_i),
      .run_i       (contention_run),
      .read_txns_o (sdio1_read_txns),
      .write_txns_o(sdio1_write_txns),
      .done_o      (sdio1_bfm_done),
      .axi4        (sdio1_axi4)
  );
  ga2d_platform_bfm32 #(
      .BaseAddr(32'h3000_3000),
      .Seed    (32'h0000_0059)
  ) u_usb2_bfm (
      .clk_i       (clk_io_i),
      .rst_n_i     (rst_io_n_i),
      .run_i       (contention_run),
      .read_txns_o (usb2_read_txns),
      .write_txns_o(usb2_write_txns),
      .done_o      (usb2_bfm_done),
      .axi4        (usb2_axi4)
  );
  axi4_master_idle u_spisd_idle (.axi4(spisd_axi4));
  axi4_master_idle u_ext_h_idle (.axi4(ext_h_axi4));
  ga2d_platform_sram_target u_sram_target (
      .clk_i           (clk_hp_i),
      .rst_n_i         (rst_hp_n_i),
      .hold_ar_i       (sram_hold_ar_i),
      .hold_response_i (sram_hold_response_i),
      .last_arid_o     (sram_last_arid),
      .saw_ga2d_o      (sram_saw_ga2d),
      .saw_legacy_o    (sram_saw_legacy),
      .saw_ga2d_write_o(sram_saw_ga2d_write),
      .saw_jpeg_o      (sram_saw_jpeg),
      .saw_jpeg_write_o(sram_saw_jpeg_write),
      .seen_arid_mask_o(sram_seen_arid_mask),
      .seen_awid_mask_o(sram_seen_awid_mask),
      .axi4            (sram_gateway_axi4)
  );
  ga2d_platform_idle_target u_sdram_target (
      .clk_i        (clk_mem_i),
      .rst_n_i      (rst_mem_n_i),
      .saw_read_o   (sdram_saw_read),
      .saw_write_o  (sdram_saw_write),
      .last_araddr_o(sdram_last_araddr),
      .last_awaddr_o(sdram_last_awaddr),
      .axi4         (sdram_gateway_axi4)
  );
  ga2d_platform_idle_target u_qpi_target (
      .clk_i        (clk_mem_i),
      .rst_n_i      (rst_mem_n_i),
      .saw_read_o   (qpi_saw_read),
      .saw_write_o  (qpi_saw_write),
      .last_araddr_o(qpi_last_araddr),
      .last_awaddr_o(qpi_last_awaddr),
      .axi4         (qpi_gateway_axi4)
  );
  ga2d_platform_idle_target u_opi_target (
      .clk_i        (clk_mem_i),
      .rst_n_i      (rst_mem_n_i),
      .saw_read_o   (opi_saw_read),
      .saw_write_o  (opi_saw_write),
      .last_araddr_o(opi_last_araddr),
      .last_awaddr_o(opi_last_awaddr),
      .axi4         (opi_gateway_axi4)
  );
  ga2d_platform_idle_target u_xpi_target (
      .clk_i        (clk_mem_i),
      .rst_n_i      (rst_mem_n_i),
      .saw_read_o   (xpi_saw_read),
      .saw_write_o  (),
      .last_araddr_o(xpi_last_araddr),
      .last_awaddr_o(),
      .axi4         (xpi_gateway_axi4)
  );

  soc_data_plane u_dut (
      .clk_lp_i                (clk_lp_i),
      .rst_lp_n_i              (rst_lp_n_i),
      .clk_io_i                (clk_io_i),
      .rst_io_n_i              (rst_io_n_i),
      .clk_hp_i                (clk_hp_i),
      .rst_hp_n_i              (rst_hp_n_i),
      .clk_mem_i               (clk_mem_i),
      .rst_mem_n_i             (rst_mem_n_i),
      .block_new_i             (block_new_i),
      .recovery_i              (recovery_i),
      .flush_i                 (flush_i),
      .resource_block_i        (resource_block_i),
      .mem_pad_mode_i          (mem_pad_mode_i),
      .ga2d_core_safe_idle_i   (ga2d_core_safe_idle_i),
      .ext_h_block_i           (ext_h_block_i),
      .ext_h_read_base_i       (32'h3000_0000),
      .ext_h_read_limit_i      (32'h4FFF_FFFF),
      .ext_h_write_base_i      (32'h3000_0000),
      .ext_h_write_limit_i     (32'h4FFF_FFFF),
      .hp_icache_axi4          (hp_icache_axi4),
      .hp_dcache_axi4          (hp_dcache_axi4),
      .dma_axi4                (dma_axi4),
      .sdio0_axi4              (sdio0_axi4),
      .sdio1_axi4              (sdio1_axi4),
      .spisd_axi4              (spisd_axi4),
      .usb2_axi4               (usb2_axi4),
      .apu_axi4                (apu_axi4),
      .jpeg_axi4               (jpeg_axi4),
      .ga2d_axi4               (ga2d_axi4),
      .lp_data_axi4            (lp_data_axi4),
      .ext_h_axi4              (ext_h_axi4),
      .sram_gateway_axi4       (sram_gateway_axi4),
      .sdram_gateway_axi4      (sdram_gateway_axi4),
      .qpi_gateway_axi4        (qpi_gateway_axi4),
      .opi_gateway_axi4        (opi_gateway_axi4),
      .xpi_gateway_axi4        (xpi_gateway_axi4),
      .fabric_monitor_apb4     (fabric_monitor_apb4),
      .idle_o                  (idle_o),
      .flush_busy_o            (flush_busy_o),
      .ext_h_idle_o            (ext_h_idle_o),
      .apu_bridge_epoch_o      (apu_bridge_epoch_o),
      .ga2d_source_stop_o      (ga2d_source_stop_o),
      .ga2d_source_safe_idle_o (ga2d_source_safe_idle_o),
      .ga2d_bridge_clear_busy_o(ga2d_bridge_clear_busy_o),
      .ga2d_bridge_epoch_o     (ga2d_bridge_epoch_o),
      .ga2d_data_ready_o       (ga2d_data_ready_o),
      .resource_idle_o         (resource_idle_o),
      .resource_block_ack_o    (resource_block_ack_o),
      .outstanding_read_o      (outstanding_read_o),
      .outstanding_write_o     (outstanding_write_o),
      .fault_valid_o           (fault_valid_o),
      .fault_ready_i           (1'b1),
      .fault_master_o          (fault_master_o),
      .fault_target_o          (fault_target_o),
      .fault_addr_o            (fault_addr_o),
      .fault_write_o           (fault_write_o),
      .fault_reason_o          (fault_reason_o)
  );

  task automatic issue_ga2d_read(input logic [2:0] id, input logic [31:0] address);
    begin
      @(negedge clk_io_i);
      ga2d_axi4.arid     = id;
      ga2d_axi4.araddr   = address;
      ga2d_axi4.arlen    = '0;
      ga2d_axi4.arsize   = 3'd3;
      ga2d_axi4.arburst  = 2'b01;
      ga2d_axi4.arlock   = 1'b0;
      ga2d_axi4.arcache  = '0;
      ga2d_axi4.arprot   = '0;
      ga2d_axi4.arqos    = 4'hF;
      ga2d_axi4.arregion = '0;
      ga2d_axi4.aruser   = '0;
      ga2d_axi4.arvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.arready);
      @(negedge clk_io_i);
      ga2d_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_ga2d_read(input logic [2:0] id);
    begin
      wait (ga2d_axi4.rvalid);
      if ((ga2d_axi4.rid != id) || (ga2d_axi4.rresp != 2'b00)) begin
        $fatal(1, "GA2D response did not preserve the local source ID");
      end
    end
  endtask

  task automatic issue_ga2d_write(input logic [2:0] id, input logic [31:0] address,
                                  input logic [63:0] data);
    begin
      @(negedge clk_io_i);
      ga2d_axi4.awid     = id;
      ga2d_axi4.awaddr   = address;
      ga2d_axi4.awlen    = '0;
      ga2d_axi4.awsize   = 3'd3;
      ga2d_axi4.awburst  = 2'b01;
      ga2d_axi4.awlock   = 1'b0;
      ga2d_axi4.awcache  = '0;
      ga2d_axi4.awprot   = '0;
      ga2d_axi4.awqos    = 4'hF;
      ga2d_axi4.awregion = '0;
      ga2d_axi4.awuser   = '0;
      ga2d_axi4.awvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.awready);
      @(negedge clk_io_i);
      ga2d_axi4.awvalid = 1'b0;
      ga2d_axi4.wdata   = data;
      ga2d_axi4.wstrb   = '1;
      ga2d_axi4.wlast   = 1'b1;
      ga2d_axi4.wuser   = '0;
      ga2d_axi4.wvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.wready);
      @(negedge clk_io_i);
      ga2d_axi4.wvalid = 1'b0;
    end
  endtask

  task automatic expect_ga2d_write(input logic [2:0] id);
    begin
      wait (ga2d_axi4.bvalid);
      if ((ga2d_axi4.bid != id) || (ga2d_axi4.bresp != 2'b00)) begin
        $fatal(1, "GA2D write response did not preserve the local source ID");
      end
    end
  endtask

  task automatic issue_jpeg_read(input logic [2:0] id, input logic [31:0] address);
    begin
      @(negedge clk_io_i);
      jpeg_axi4.arid     = id;
      jpeg_axi4.araddr   = address;
      jpeg_axi4.arlen    = '0;
      jpeg_axi4.arsize   = 3'd3;
      jpeg_axi4.arburst  = 2'b01;
      jpeg_axi4.arlock   = 1'b0;
      jpeg_axi4.arcache  = '0;
      jpeg_axi4.arprot   = '0;
      jpeg_axi4.arqos    = '0;
      jpeg_axi4.arregion = '0;
      jpeg_axi4.aruser   = '0;
      jpeg_axi4.arvalid  = 1'b1;
      do @(posedge clk_io_i); while (!jpeg_axi4.arready);
      @(negedge clk_io_i);
      jpeg_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_jpeg_read(input logic [2:0] id);
    begin
      wait (jpeg_axi4.rvalid);
      if ((jpeg_axi4.rid != id) || (jpeg_axi4.rresp != 2'b00)) begin
        $fatal(1, "JPEG response did not preserve the local source ID");
      end
    end
  endtask

  task automatic issue_jpeg_write(input logic [2:0] id, input logic [31:0] address,
                                  input logic [63:0] data);
    begin
      @(negedge clk_io_i);
      jpeg_axi4.awid     = id;
      jpeg_axi4.awaddr   = address;
      jpeg_axi4.awlen    = '0;
      jpeg_axi4.awsize   = 3'd3;
      jpeg_axi4.awburst  = 2'b01;
      jpeg_axi4.awlock   = 1'b0;
      jpeg_axi4.awcache  = '0;
      jpeg_axi4.awprot   = '0;
      jpeg_axi4.awqos    = '0;
      jpeg_axi4.awregion = '0;
      jpeg_axi4.awuser   = '0;
      jpeg_axi4.awvalid  = 1'b1;
      do @(posedge clk_io_i); while (!jpeg_axi4.awready);
      @(negedge clk_io_i);
      jpeg_axi4.awvalid = 1'b0;
      jpeg_axi4.wdata   = data;
      jpeg_axi4.wstrb   = '1;
      jpeg_axi4.wlast   = 1'b1;
      jpeg_axi4.wuser   = '0;
      jpeg_axi4.wvalid  = 1'b1;
      do @(posedge clk_io_i); while (!jpeg_axi4.wready);
      @(negedge clk_io_i);
      jpeg_axi4.wvalid = 1'b0;
    end
  endtask

  task automatic expect_jpeg_write(input logic [2:0] id);
    begin
      wait (jpeg_axi4.bvalid);
      if ((jpeg_axi4.bid != id) || (jpeg_axi4.bresp != 2'b00)) begin
        $fatal(1, "JPEG write response did not preserve the local source ID");
      end
    end
  endtask

  task automatic issue_legacy_read(input logic [2:0] id, input logic [31:0] address);
    begin
      @(negedge clk_hp_i);
      hp_dcache_axi4.arid     = id;
      hp_dcache_axi4.araddr   = address;
      hp_dcache_axi4.arlen    = '0;
      hp_dcache_axi4.arsize   = 3'd3;
      hp_dcache_axi4.arburst  = 2'b01;
      hp_dcache_axi4.arlock   = 1'b0;
      hp_dcache_axi4.arcache  = '0;
      hp_dcache_axi4.arprot   = '0;
      hp_dcache_axi4.arqos    = '0;
      hp_dcache_axi4.arregion = '0;
      hp_dcache_axi4.aruser   = '0;
      hp_dcache_axi4.arvalid  = 1'b1;
      do @(posedge clk_hp_i); while (!hp_dcache_axi4.arready);
      @(negedge clk_hp_i);
      hp_dcache_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_legacy_read(input logic [2:0] id);
    begin
      wait (hp_dcache_axi4.rvalid);
      if ((hp_dcache_axi4.rid != id) || (hp_dcache_axi4.rresp != 2'b00)) begin
        $fatal(1, "legacy response did not preserve its source ID");
      end
    end
  endtask

  task automatic issue_lp_read(input logic id, input logic [31:0] address);
    begin
      @(negedge clk_lp_i);
      lp_data_axi4.arid     = id;
      lp_data_axi4.araddr   = address;
      lp_data_axi4.arlen    = '0;
      lp_data_axi4.arsize   = 3'd2;
      lp_data_axi4.arburst  = 2'b01;
      lp_data_axi4.arlock   = 1'b0;
      lp_data_axi4.arcache  = '0;
      lp_data_axi4.arprot   = '0;
      lp_data_axi4.arqos    = '0;
      lp_data_axi4.arregion = '0;
      lp_data_axi4.aruser   = '0;
      lp_data_axi4.arvalid  = 1'b1;
      do @(posedge clk_lp_i); while (!lp_data_axi4.arready);
      @(negedge clk_lp_i);
      lp_data_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_lp_read(input logic id);
    begin
      wait (lp_data_axi4.rvalid);
      if ((lp_data_axi4.rid != id) || (lp_data_axi4.rresp != 2'b00)) begin
        $fatal(1, "LP response did not survive the HP lifecycle flush");
      end
    end
  endtask

  task automatic wait_for_data_ready;
    begin
      wait (ga2d_data_ready_o && !ga2d_source_stop_o);
    end
  endtask

  // Mirror of the SRAM model's deterministic reset contents, so guard bytes
  // and untouched lines can be checked byte-exactly from the testbench side.
  function automatic logic [63:0] sram_init_line(input logic [31:0] address);
    logic [63:0] line;
    logic [14:0] offset;
    begin
      offset = 15'(address);
      for (int b = 0; b < 8; b++) begin
        line[b*8+:8] = 8'(8'hA6 ^ 8'(offset + 15'(b)) ^ 8'((offset + 15'(b)) >> 8));
      end
      return line;
    end
  endfunction

  // GA2D job-pattern base for the contention battery: distinct per job, and
  // per-beat increments keep every 64-bit word unique inside the job.
  function automatic logic [63:0] ga2d_job_base(input int job);
    return 64'hC3C3_3C3C_0000_0000 ^ (64'(job) << 16);
  endfunction

  task automatic issue_ga2d_write_burst(input logic [2:0] id, input logic [31:0] address,
                                        input logic [7:0] beats, input logic [63:0] data_base);
    begin
      @(negedge clk_io_i);
      ga2d_axi4.awid     = id;
      ga2d_axi4.awaddr   = address;
      ga2d_axi4.awlen    = beats - 8'd1;
      ga2d_axi4.awsize   = 3'd3;
      ga2d_axi4.awburst  = 2'b01;
      ga2d_axi4.awlock   = 1'b0;
      ga2d_axi4.awcache  = '0;
      ga2d_axi4.awprot   = '0;
      ga2d_axi4.awqos    = '0;
      ga2d_axi4.awregion = '0;
      ga2d_axi4.awuser   = '0;
      ga2d_axi4.awvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.awready);
      @(negedge clk_io_i);
      ga2d_axi4.awvalid = 1'b0;
      for (int b = 0; b < int'(beats); b++) begin
        ga2d_axi4.wdata  = data_base + 64'(b);
        ga2d_axi4.wstrb  = '1;
        ga2d_axi4.wlast  = (b == (int'(beats) - 1));
        ga2d_axi4.wuser  = '0;
        ga2d_axi4.wvalid = 1'b1;
        do @(posedge clk_io_i); while (!ga2d_axi4.wready);
        @(negedge clk_io_i);
      end
      ga2d_axi4.wvalid = 1'b0;
    end
  endtask

  task automatic issue_ga2d_read_burst(input logic [2:0] id, input logic [31:0] address,
                                       input logic [7:0] beats);
    begin
      @(negedge clk_io_i);
      ga2d_axi4.arid     = id;
      ga2d_axi4.araddr   = address;
      ga2d_axi4.arlen    = beats - 8'd1;
      ga2d_axi4.arsize   = 3'd3;
      ga2d_axi4.arburst  = 2'b01;
      ga2d_axi4.arlock   = 1'b0;
      ga2d_axi4.arcache  = '0;
      ga2d_axi4.arprot   = '0;
      ga2d_axi4.arqos    = '0;
      ga2d_axi4.arregion = '0;
      ga2d_axi4.aruser   = '0;
      ga2d_axi4.arvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.arready);
      @(negedge clk_io_i);
      ga2d_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic check_ga2d_read_burst(input logic [2:0] id, input logic [7:0] beats,
                                       input logic [63:0] data_base);
    begin
      // Sample at negedge: beats may arrive back-to-back through the CDC, so
      // sampling right at the handshake posedge could see the previous beat.
      for (int b = 0; b < int'(beats); b++) begin
        @(negedge clk_io_i);
        while (!ga2d_axi4.rvalid) @(negedge clk_io_i);
        if ((ga2d_axi4.rid != id) || (ga2d_axi4.rresp != 2'b00) ||
            (ga2d_axi4.rlast != (b == (int'(beats) - 1)))) begin
          $fatal(1, "GA2D burst read response framing was corrupted under contention");
        end
        if (ga2d_axi4.rdata != (data_base + 64'(b))) begin
          $fatal(1, "GA2D burst read data was not byte-exact under contention");
        end
      end
    end
  endtask

  task automatic check_ga2d_read_burst_init(input logic [2:0] id, input logic [31:0] address,
                                            input logic [7:0] beats);
    begin
      for (int b = 0; b < int'(beats); b++) begin
        @(negedge clk_io_i);
        while (!ga2d_axi4.rvalid) @(negedge clk_io_i);
        if ((ga2d_axi4.rid != id) || (ga2d_axi4.rresp != 2'b00) ||
            (ga2d_axi4.rlast != (b == (int'(beats) - 1)))) begin
          $fatal(1, "GA2D guard read response framing was corrupted under contention");
        end
        if (ga2d_axi4.rdata != sram_init_line(address + 32'(b) * 32'd8)) begin
          $fatal(1, "GA2D guard bytes were overwritten under contention");
        end
      end
    end
  endtask

  task automatic expect_ga2d_read_data(input logic [2:0] id, input logic [63:0] expected);
    begin
      wait (ga2d_axi4.rvalid);
      if ((ga2d_axi4.rid != id) || (ga2d_axi4.rresp != 2'b00) ||
          (ga2d_axi4.rdata != expected)) begin
        $fatal(1, "GA2D read data did not survive the HP lifecycle switch");
      end
    end
  endtask

  // Fabric-monitor APB access in the HP clock domain, one wait-state access
  // per transfer as implemented by the monitor's registered PREADY.
  task automatic monitor_apb_write(input logic [11:0] offset, input logic [31:0] data);
    begin
      @(negedge clk_hp_i);
      fabric_monitor_apb4.paddr   = 32'(offset);
      fabric_monitor_apb4.pwdata  = data;
      fabric_monitor_apb4.pwrite  = 1'b1;
      fabric_monitor_apb4.pstrb   = 4'hF;
      fabric_monitor_apb4.psel    = 1'b1;
      fabric_monitor_apb4.penable = 1'b0;
      @(negedge clk_hp_i);
      fabric_monitor_apb4.penable = 1'b1;
      @(negedge clk_hp_i);
      while (!fabric_monitor_apb4.pready) @(negedge clk_hp_i);
      if (fabric_monitor_apb4.pslverr) begin
        $fatal(1, "fabric monitor APB write was rejected");
      end
      fabric_monitor_apb4.psel    = 1'b0;
      fabric_monitor_apb4.penable = 1'b0;
      fabric_monitor_apb4.pwrite  = 1'b0;
      fabric_monitor_apb4.pstrb   = '0;
    end
  endtask

  task automatic monitor_apb_read(input logic [11:0] offset, output logic [31:0] data);
    begin
      @(negedge clk_hp_i);
      fabric_monitor_apb4.paddr   = 32'(offset);
      fabric_monitor_apb4.pwrite  = 1'b0;
      fabric_monitor_apb4.psel    = 1'b1;
      fabric_monitor_apb4.penable = 1'b0;
      @(negedge clk_hp_i);
      fabric_monitor_apb4.penable = 1'b1;
      @(negedge clk_hp_i);
      while (!fabric_monitor_apb4.pready) @(negedge clk_hp_i);
      if (fabric_monitor_apb4.pslverr) begin
        $fatal(1, "fabric monitor APB read was rejected");
      end
      data                        = fabric_monitor_apb4.prdata;
      fabric_monitor_apb4.psel    = 1'b0;
      fabric_monitor_apb4.penable = 1'b0;
    end
  endtask

  // One denied GA2D read: the crossbar must route it to the error target, the
  // response must be DECERR, and the first-fault record (both at the
  // data-plane boundary and in the monitor FAULT register) must attribute the
  // fault to master 8 with the expected reason, target, and address. The
  // expected FAULT word always carries bit 12 (master bit 3) set. The monitor
  // latch is cleared afterwards so the next denial is again the first fault.
  task automatic ga2d_denied_read(input logic [2:0] id, input logic [31:0] address,
                                  input logic lock, input logic [3:0] cache, input logic [2:0] prot,
                                  input logic [3:0] reason, input logic [2:0] target,
                                  input logic [31:0] fault_word);
    logic [31:0] apb_data;
    int          faults_before;
    begin
      faults_before = fault_log_count;
      @(negedge clk_io_i);
      ga2d_axi4.arid     = id;
      ga2d_axi4.araddr   = address;
      ga2d_axi4.arlen    = '0;
      ga2d_axi4.arsize   = 3'd3;
      ga2d_axi4.arburst  = 2'b01;
      ga2d_axi4.arlock   = lock;
      ga2d_axi4.arcache  = cache;
      ga2d_axi4.arprot   = prot;
      ga2d_axi4.arqos    = '0;
      ga2d_axi4.arregion = '0;
      ga2d_axi4.aruser   = '0;
      ga2d_axi4.arvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.arready);
      @(negedge clk_io_i);
      ga2d_axi4.arvalid = 1'b0;
      wait (ga2d_axi4.rvalid);
      if ((ga2d_axi4.rid != id) || (ga2d_axi4.rresp != 2'b11) || !ga2d_axi4.rlast) begin
        $fatal(1, "denied GA2D read did not return a final DECERR beat");
      end
      @(posedge clk_io_i);
      `GA2D_TB_AWAIT(fault_log_count == (faults_before + 1),
                     "denied GA2D read produced no fabric fault")
      if ((fault_log[faults_before].master != 4'd8) || fault_log[faults_before].write ||
          (fault_log[faults_before].reason != reason) ||
          (fault_log[faults_before].target != target) ||
          (fault_log[faults_before].addr != address)) begin
        $fatal(1, "denied GA2D read fault was not attributed to master 8");
      end
      monitor_apb_read(12'h014, apb_data);
      if (apb_data != fault_word) begin
        $fatal(1, "fabric monitor FAULT did not carry master 8 with FAULT[12] set");
      end
      monitor_apb_read(12'h018, apb_data);
      if (apb_data != address) begin
        $fatal(1, "fabric monitor FAULT_ADDR did not retain the denied GA2D address");
      end
      monitor_apb_write(12'h00C, 32'h0000_0005);
    end
  endtask

  task automatic ga2d_denied_write(
      input logic [2:0] id, input logic [31:0] address, input logic lock, input logic [3:0] cache,
      input logic [2:0] prot, input logic [3:0] reason, input logic [2:0] target,
      input logic [31:0] fault_word, input logic [63:0] data);
    logic [31:0] apb_data;
    int          faults_before;
    begin
      faults_before = fault_log_count;
      @(negedge clk_io_i);
      ga2d_axi4.awid     = id;
      ga2d_axi4.awaddr   = address;
      ga2d_axi4.awlen    = '0;
      ga2d_axi4.awsize   = 3'd3;
      ga2d_axi4.awburst  = 2'b01;
      ga2d_axi4.awlock   = lock;
      ga2d_axi4.awcache  = cache;
      ga2d_axi4.awprot   = prot;
      ga2d_axi4.awqos    = '0;
      ga2d_axi4.awregion = '0;
      ga2d_axi4.awuser   = '0;
      ga2d_axi4.awvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.awready);
      @(negedge clk_io_i);
      ga2d_axi4.awvalid = 1'b0;
      ga2d_axi4.wdata   = data;
      ga2d_axi4.wstrb   = '1;
      ga2d_axi4.wlast   = 1'b1;
      ga2d_axi4.wuser   = '0;
      ga2d_axi4.wvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.wready);
      @(negedge clk_io_i);
      ga2d_axi4.wvalid = 1'b0;
      wait (ga2d_axi4.bvalid);
      if ((ga2d_axi4.bid != id) || (ga2d_axi4.bresp != 2'b11)) begin
        $fatal(1, "denied GA2D write did not return a DECERR response");
      end
      @(posedge clk_io_i);
      `GA2D_TB_AWAIT(fault_log_count == (faults_before + 1),
                     "denied GA2D write produced no fabric fault")
      if ((fault_log[faults_before].master != 4'd8) || !fault_log[faults_before].write ||
          (fault_log[faults_before].reason != reason) ||
          (fault_log[faults_before].target != target) ||
          (fault_log[faults_before].addr != address)) begin
        $fatal(1, "denied GA2D write fault was not attributed to master 8");
      end
      monitor_apb_read(12'h014, apb_data);
      if (apb_data != fault_word) begin
        $fatal(1, "fabric monitor FAULT did not carry master 8 with FAULT[12] set");
      end
      monitor_apb_read(12'h018, apb_data);
      if (apb_data != address) begin
        $fatal(1, "fabric monitor FAULT_ADDR did not retain the denied GA2D address");
      end
      monitor_apb_write(12'h00C, 32'h0000_0005);
    end
  endtask

  // Coordinated global flush with the same shape as the existing warm-flush
  // case: the bridge epoch must advance, the source must stay closed during
  // the flush, and no late pre-flush response may reach the GA2D source.
  task automatic ga2d_flush_and_recover;
    begin
      epoch_before = ga2d_bridge_epoch_o;
      @(negedge clk_hp_i);
      flush_i = 1'b1;
      repeat (4) @(posedge clk_lp_i);
      repeat (4) @(posedge clk_hp_i);
      if (ga2d_data_ready_o) begin
        $fatal(1, "GA2D data-ready remained asserted during a coordinated flush");
      end
      @(negedge clk_hp_i);
      flush_i = 1'b0;
      wait (ga2d_bridge_epoch_o != epoch_before);
      repeat (4) @(posedge clk_io_i);
      if (ga2d_axi4.rvalid || ga2d_axi4.bvalid) begin
        $fatal(1, "late pre-flush response reached the GA2D source");
      end
      wait_for_data_ready();
      wait (!flush_busy_o);
    end
  endtask

  initial begin
    lp_data_axi4.awid           = '0;
    lp_data_axi4.awaddr         = '0;
    lp_data_axi4.awlen          = '0;
    lp_data_axi4.awsize         = 3'd2;
    lp_data_axi4.awburst        = 2'b01;
    lp_data_axi4.awlock         = 1'b0;
    lp_data_axi4.awcache        = '0;
    lp_data_axi4.awprot         = '0;
    lp_data_axi4.awqos          = '0;
    lp_data_axi4.awregion       = '0;
    lp_data_axi4.awuser         = '0;
    lp_data_axi4.awvalid        = 1'b0;
    lp_data_axi4.wdata          = '0;
    lp_data_axi4.wstrb          = '0;
    lp_data_axi4.wlast          = 1'b1;
    lp_data_axi4.wuser          = '0;
    lp_data_axi4.wvalid         = 1'b0;
    lp_data_axi4.bready         = 1'b1;
    lp_data_axi4.arid           = '0;
    lp_data_axi4.araddr         = '0;
    lp_data_axi4.arlen          = '0;
    lp_data_axi4.arsize         = 3'd2;
    lp_data_axi4.arburst        = 2'b01;
    lp_data_axi4.arlock         = 1'b0;
    lp_data_axi4.arcache        = '0;
    lp_data_axi4.arprot         = '0;
    lp_data_axi4.arqos          = '0;
    lp_data_axi4.arregion       = '0;
    lp_data_axi4.aruser         = '0;
    lp_data_axi4.arvalid        = 1'b0;
    lp_data_axi4.rready         = 1'b1;

    ga2d_axi4.awid              = '0;
    ga2d_axi4.awaddr            = '0;
    ga2d_axi4.awlen             = '0;
    ga2d_axi4.awsize            = 3'd3;
    ga2d_axi4.awburst           = 2'b01;
    ga2d_axi4.awlock            = 1'b0;
    ga2d_axi4.awcache           = '0;
    ga2d_axi4.awprot            = '0;
    ga2d_axi4.awqos             = '0;
    ga2d_axi4.awregion          = '0;
    ga2d_axi4.awuser            = '0;
    ga2d_axi4.awvalid           = 1'b0;
    ga2d_axi4.wdata             = '0;
    ga2d_axi4.wstrb             = '0;
    ga2d_axi4.wlast             = 1'b1;
    ga2d_axi4.wuser             = '0;
    ga2d_axi4.wvalid            = 1'b0;
    ga2d_axi4.bready            = 1'b1;
    ga2d_axi4.arid              = '0;
    ga2d_axi4.araddr            = '0;
    ga2d_axi4.arlen             = '0;
    ga2d_axi4.arsize            = 3'd3;
    ga2d_axi4.arburst           = 2'b01;
    ga2d_axi4.arlock            = 1'b0;
    ga2d_axi4.arcache           = '0;
    ga2d_axi4.arprot            = '0;
    ga2d_axi4.arqos             = '0;
    ga2d_axi4.arregion          = '0;
    ga2d_axi4.aruser            = '0;
    ga2d_axi4.arvalid           = 1'b0;
    ga2d_axi4.rready            = 1'b1;

    jpeg_axi4.awid              = '0;
    jpeg_axi4.awaddr            = '0;
    jpeg_axi4.awlen             = '0;
    jpeg_axi4.awsize            = 3'd3;
    jpeg_axi4.awburst           = 2'b01;
    jpeg_axi4.awlock            = 1'b0;
    jpeg_axi4.awcache           = '0;
    jpeg_axi4.awprot            = '0;
    jpeg_axi4.awqos             = '0;
    jpeg_axi4.awregion          = '0;
    jpeg_axi4.awuser            = '0;
    jpeg_axi4.awvalid           = 1'b0;
    jpeg_axi4.wdata             = '0;
    jpeg_axi4.wstrb             = '0;
    jpeg_axi4.wlast             = 1'b1;
    jpeg_axi4.wuser             = '0;
    jpeg_axi4.wvalid            = 1'b0;
    jpeg_axi4.bready            = 1'b1;
    jpeg_axi4.arid              = '0;
    jpeg_axi4.araddr            = '0;
    jpeg_axi4.arlen             = '0;
    jpeg_axi4.arsize            = 3'd3;
    jpeg_axi4.arburst           = 2'b01;
    jpeg_axi4.arlock            = 1'b0;
    jpeg_axi4.arcache           = '0;
    jpeg_axi4.arprot            = '0;
    jpeg_axi4.arqos             = '0;
    jpeg_axi4.arregion          = '0;
    jpeg_axi4.aruser            = '0;
    jpeg_axi4.arvalid           = 1'b0;
    jpeg_axi4.rready            = 1'b1;

    hp_dcache_axi4.awid         = '0;
    hp_dcache_axi4.awaddr       = '0;
    hp_dcache_axi4.awlen        = '0;
    hp_dcache_axi4.awsize       = 3'd3;
    hp_dcache_axi4.awburst      = 2'b01;
    hp_dcache_axi4.awlock       = 1'b0;
    hp_dcache_axi4.awcache      = '0;
    hp_dcache_axi4.awprot       = '0;
    hp_dcache_axi4.awqos        = '0;
    hp_dcache_axi4.awregion     = '0;
    hp_dcache_axi4.awuser       = '0;
    hp_dcache_axi4.awvalid      = 1'b0;
    hp_dcache_axi4.wdata        = '0;
    hp_dcache_axi4.wstrb        = '0;
    hp_dcache_axi4.wlast        = 1'b1;
    hp_dcache_axi4.wuser        = '0;
    hp_dcache_axi4.wvalid       = 1'b0;
    hp_dcache_axi4.bready       = 1'b1;
    hp_dcache_axi4.arid         = '0;
    hp_dcache_axi4.araddr       = '0;
    hp_dcache_axi4.arlen        = '0;
    hp_dcache_axi4.arsize       = 3'd3;
    hp_dcache_axi4.arburst      = 2'b01;
    hp_dcache_axi4.arlock       = 1'b0;
    hp_dcache_axi4.arcache      = '0;
    hp_dcache_axi4.arprot       = '0;
    hp_dcache_axi4.arqos        = '0;
    hp_dcache_axi4.arregion     = '0;
    hp_dcache_axi4.aruser       = '0;
    hp_dcache_axi4.arvalid      = 1'b0;
    hp_dcache_axi4.rready       = 1'b1;

    fabric_monitor_apb4.paddr   = '0;
    fabric_monitor_apb4.pprot   = '0;
    fabric_monitor_apb4.psel    = 1'b0;
    fabric_monitor_apb4.penable = 1'b0;
    fabric_monitor_apb4.pwrite  = 1'b0;
    fabric_monitor_apb4.pwdata  = '0;
    fabric_monitor_apb4.pstrb   = '0;

    repeat (3) @(posedge clk_io_i);
    rst_lp_n_i  = 1'b1;
    rst_io_n_i  = 1'b1;
    rst_hp_n_i  = 1'b1;
    rst_mem_n_i = 1'b1;
    wait_for_data_ready();

    // A core that has not established a known-safe idle state cannot hand the
    // resource to HP even when the address gate itself is empty.
    @(negedge clk_io_i);
    ga2d_core_safe_idle_i = 1'b0;
    resource_block_i[8]   = 1'b1;
    repeat (5) @(posedge clk_hp_i);
    if (ga2d_source_safe_idle_o || resource_block_ack_o[8] || resource_idle_o[8]) begin
      $fatal(1, "unsafe GA2D core idle state allowed resource-8 handoff");
    end
    @(negedge clk_io_i);
    ga2d_core_safe_idle_i = 1'b1;
    wait (resource_block_ack_o[8]);
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();

    fork
      issue_ga2d_read(3'd0, 32'h3000_0040);
      expect_ga2d_read(3'd0);
      issue_legacy_read(3'd0, 32'h3000_0080);
      expect_legacy_read(3'd0);
    join
    if (!sram_saw_ga2d || !sram_saw_legacy) begin
      $fatal(1, "mixed legacy and GA2D IDs did not reach distinct global IDs");
    end

    fork
      issue_jpeg_read(3'd0, 32'h3000_00A0);
      expect_jpeg_read(3'd0);
      issue_jpeg_write(3'd1, 32'h3000_00E0, 64'h89AB_CDEF_0123_4567);
      expect_jpeg_write(3'd1);
    join
    if (!sram_saw_jpeg || !sram_saw_jpeg_write) begin
      $fatal(1, "JPEG did not cross PCLK-to-HP with master prefix 6");
    end

    fork
      issue_ga2d_write(3'd0, 32'h3000_00C0, 64'h0123_4567_89AB_CDEF);
      expect_ga2d_write(3'd0);
    join
    if (!sram_saw_ga2d_write) begin
      $fatal(1, "GA2D write did not preserve global ID 7'h40");
    end

    wait (!flush_busy_o);
    block_new_i = 1'b1;
    repeat (2) @(posedge clk_hp_i);
    issue_lp_read(1'b0, 32'h3000_0180);
    repeat (2) @(posedge clk_hp_i);
    @(negedge clk_hp_i);
    flush_i = 1'b1;
    repeat (4) @(posedge clk_lp_i);
    repeat (4) @(posedge clk_hp_i);
    @(negedge clk_hp_i);
    flush_i = 1'b0;
    wait (!flush_busy_o);
    block_new_i = 1'b0;
    expect_lp_read(1'b0);
    if (sram_last_arid != 7'h28) begin
      $fatal(1, "HP lifecycle flush discarded the queued LP request");
    end

    wait (ga2d_source_safe_idle_o);
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b1;
    ga2d_axi4.wdata     = 64'hCAFE_BABE_0123_4567;
    ga2d_axi4.wstrb     = '1;
    ga2d_axi4.wlast     = 1'b1;
    ga2d_axi4.wuser     = '0;
    ga2d_axi4.wvalid    = 1'b1;
    repeat (2) @(posedge clk_io_i);
    #1;
    if (ga2d_source_stop_o || ga2d_source_safe_idle_o || resource_block_ack_o[8] ||
        ga2d_axi4.wready) begin
      $fatal(1, "resource block accepted or acknowledged W-before-AW traffic");
    end
    @(negedge clk_io_i);
    ga2d_axi4.awid     = 3'd3;
    ga2d_axi4.awaddr   = 32'h3000_0120;
    ga2d_axi4.awlen    = '0;
    ga2d_axi4.awsize   = 3'd3;
    ga2d_axi4.awburst  = 2'b01;
    ga2d_axi4.awlock   = 1'b0;
    ga2d_axi4.awcache  = '0;
    ga2d_axi4.awprot   = '0;
    ga2d_axi4.awqos    = '0;
    ga2d_axi4.awregion = '0;
    ga2d_axi4.awuser   = '0;
    ga2d_axi4.awvalid  = 1'b1;
    do @(posedge clk_io_i); while (!ga2d_axi4.awready);
    #1;
    if (!ga2d_source_stop_o) begin
      $fatal(1, "resource block did not close after the W-before-AW address handshake");
    end
    if (!ga2d_axi4.wready) begin
      $fatal(1, "W-before-AW write data was not accepted with its address");
    end
    @(negedge clk_io_i);
    ga2d_axi4.awvalid = 1'b0;
    ga2d_axi4.wvalid  = 1'b0;
    if (resource_block_ack_o[8]) begin
      $fatal(1, "resource block acknowledged before the W-before-AW response drained");
    end
    expect_ga2d_write(3'd3);
    wait (resource_block_ack_o[8]);
    if (!ga2d_source_safe_idle_o || !resource_idle_o[8] || ga2d_data_ready_o) begin
      $fatal(1, "W-before-AW resource stop did not reach qualified idle");
    end
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();

    sram_hold_ar_i = 1'b1;
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b1;
    ga2d_axi4.arid      = 3'd1;
    ga2d_axi4.araddr    = 32'h3000_0100;
    ga2d_axi4.arlen     = '0;
    ga2d_axi4.arsize    = 3'd3;
    ga2d_axi4.arburst   = 2'b01;
    ga2d_axi4.arlock    = 1'b0;
    ga2d_axi4.arcache   = '0;
    ga2d_axi4.arprot    = '0;
    ga2d_axi4.arqos     = '0;
    ga2d_axi4.arregion  = '0;
    ga2d_axi4.aruser    = '0;
    ga2d_axi4.arvalid   = 1'b1;
    do @(posedge clk_io_i); while (!ga2d_axi4.arready);
    #1;
    if (!ga2d_source_stop_o) begin
      $fatal(1, "resource stop did not close after the presented address entered transport");
    end
    @(negedge clk_io_i);
    ga2d_axi4.arvalid = 1'b0;
    wait (ga2d_source_stop_o);
    if (ga2d_source_safe_idle_o || resource_block_ack_o[8]) begin
      $fatal(1, "resource block acknowledged before the accepted read drained");
    end
    sram_hold_ar_i = 1'b0;
    fork
      expect_ga2d_read(3'd1);
      wait (resource_block_ack_o[8]);
    join
    if (!ga2d_source_safe_idle_o || !resource_idle_o[8] || ga2d_data_ready_o) begin
      $fatal(1, "GA2D resource stop did not reach qualified idle");
    end
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();

    sram_hold_response_i = 1'b1;
    issue_ga2d_read(3'd2, 32'h3000_0140);
    wait (sram_last_arid == 7'h42);
    epoch_before = ga2d_bridge_epoch_o;
    @(negedge clk_hp_i);
    flush_i              = 1'b1;
    sram_hold_response_i = 1'b0;
    repeat (4) @(posedge clk_io_i);
    if (ga2d_data_ready_o) begin
      $fatal(1, "GA2D data-ready remained asserted during a warm flush");
    end
    repeat (4) @(posedge clk_hp_i);
    @(negedge clk_hp_i);
    flush_i = 1'b0;
    wait (ga2d_bridge_epoch_o != epoch_before);
    repeat (4) @(posedge clk_io_i);
    if (ga2d_axi4.rvalid) begin
      $fatal(1, "late pre-flush response reached the GA2D source");
    end
    wait_for_data_ready();
    wait (!flush_busy_o);

    epoch_before = ga2d_bridge_epoch_o;
    @(negedge clk_hp_i);
    rst_hp_n_i = 1'b0;
    repeat (3) @(posedge clk_hp_i);
    if (ga2d_data_ready_o) begin
      $fatal(1, "GA2D data-ready remained asserted while HP reset was active");
    end
    @(negedge clk_hp_i);
    rst_hp_n_i = 1'b1;
    wait (ga2d_bridge_epoch_o != epoch_before);
    wait_for_data_ready();

    @(negedge clk_io_i);
    rst_io_n_i = 1'b0;
    repeat (3) @(posedge clk_io_i);
    if (ga2d_data_ready_o || !ga2d_source_stop_o) begin
      $fatal(1, "PCLK reset did not close the GA2D source path");
    end
    @(negedge clk_io_i);
    rst_io_n_i = 1'b1;
    wait_for_data_ready();

    // ---------------------------------------------------------------------
    // GA2D-V03 denial paths driven from the master-8 port. The monitor is
    // version 1.1 with nine master banks, so FAULT[12] carries master bit 3;
    // every denial below must latch as the first fault with master 8, and the
    // data-plane fault boundary must agree with the APB readback.
    monitor_apb_read(12'h004, apb_data);
    if (apb_data != 32'h0001_0001) begin
      $fatal(1, "fabric monitor is not the nine-master version 1.1");
    end
    monitor_apb_read(12'h008, apb_data);
    if (apb_data != 32'h0609_0003) begin
      $fatal(1, "fabric monitor does not advertise nine master banks");
    end
    monitor_apb_write(12'h00C, 32'h0000_0001);

    // Nonzero AxCACHE is denied as an access fault on the SRAM target.
    ga2d_denied_read(3'd0, 32'h3000_0600, 1'b0, 4'h2, 3'b000, 4'd3, 3'd0, 32'h0000_1301);
    // Exclusive (AxLOCK) transactions are denied as a protocol fault.
    ga2d_denied_read(3'd0, 32'h3000_0640, 1'b1, 4'h0, 3'b000, 4'd4, 3'd0, 32'h0000_1401);
    // An MMIO-window address is unmapped in the data plane (error target 5).
    ga2d_denied_read(3'd0, 32'h1001_2000, 1'b0, 4'h0, 3'b000, 4'd1, 3'd5, 32'h0000_11A1);
    // Instruction fetches are denied for GA2D (AllowInstruction bit 8 is 0).
    ga2d_denied_read(3'd0, 32'h3000_0680, 1'b0, 4'h0, 3'b100, 4'd3, 3'd0, 32'h0000_1301);
    // Writes exclude XPI: an XPI write is denied as an access fault.
    ga2d_denied_write(3'd0, 32'h5000_0080, 1'b0, 4'h0, 3'b000, 4'd3, 3'd4, 32'h0000_1383,
                      64'hDEAD_BEEF_5A5A_A5A5);
    // OPI is inactive under pad mode 1: denied as an inactive-pad fault.
    ga2d_denied_read(3'd0, 32'h4800_0100, 1'b0, 4'h0, 3'b000, 4'd2, 3'd5, 32'h0000_12A1);
    if (fault_log_count != 6) begin
      $fatal(1, "unexpected extra fabric faults during the denial battery");
    end

    // ---------------------------------------------------------------------
    // GA2D-V03 target coverage from the master-8 port. This TB models SRAM
    // natively (read/write exercised throughout, including byte-exact bursts
    // below) and stubs the SDRAM/QPI/OPI/XPI gateways; each leg drives one
    // directed GA2D transaction at a time, so a gateway saw flag carrying the
    // leg address is master-8 attribution by exclusion. Stubbed response
    // paths are covered by the SRAM model here and by the full-SoC SDRAM
    // ci_smoke/benchmark runs. GA2D's admission credit is one outstanding
    // read and one write, so each leg is retired by a coordinated flush,
    // which also re-proves epoch invalidation per target.
    issue_ga2d_read(3'd0, 32'h3800_0100);
    `GA2D_TB_AWAIT(sdram_saw_read, "GA2D read did not reach the SDRAM gateway")
    if (sdram_last_araddr != 32'h3800_0100) begin
      $fatal(1, "SDRAM gateway saw a corrupted GA2D read address");
    end
    ga2d_flush_and_recover();
    issue_ga2d_write(3'd0, 32'h3800_0180, 64'h0123_4567_89AB_CDEF);
    `GA2D_TB_AWAIT(sdram_saw_write, "GA2D write did not reach the SDRAM gateway")
    if (sdram_last_awaddr != 32'h3800_0180) begin
      $fatal(1, "SDRAM gateway saw a corrupted GA2D write address");
    end
    ga2d_flush_and_recover();
    // QPI is the active PSRAM target under pad mode 1.
    issue_ga2d_read(3'd0, 32'h4000_0100);
    `GA2D_TB_AWAIT(qpi_saw_read, "GA2D read did not reach the QPI gateway")
    if (qpi_last_araddr != 32'h4000_0100) begin
      $fatal(1, "QPI gateway saw a corrupted GA2D read address");
    end
    ga2d_flush_and_recover();
    issue_ga2d_write(3'd0, 32'h4000_0180, 64'h0F1E_2D3C_4B5A_6978);
    `GA2D_TB_AWAIT(qpi_saw_write, "GA2D write did not reach the QPI gateway")
    if (qpi_last_awaddr != 32'h4000_0180) begin
      $fatal(1, "QPI gateway saw a corrupted GA2D write address");
    end
    ga2d_flush_and_recover();
    // XPI read; XPI writes are excluded by policy and were denied above.
    issue_ga2d_read(3'd0, 32'h5000_0100);
    `GA2D_TB_AWAIT(xpi_saw_read, "GA2D read did not reach the XPI gateway")
    if (xpi_last_araddr != 32'h5000_0100) begin
      $fatal(1, "XPI gateway saw a corrupted GA2D read address");
    end
    ga2d_flush_and_recover();
    // OPI becomes the active PSRAM target under pad mode 2.
    @(negedge clk_io_i);
    mem_pad_mode_i = 2'd2;
    repeat (6) @(posedge clk_hp_i);
    issue_ga2d_read(3'd0, 32'h4800_0100);
    `GA2D_TB_AWAIT(opi_saw_read, "GA2D read did not reach the OPI gateway")
    if (opi_last_araddr != 32'h4800_0100) begin
      $fatal(1, "OPI gateway saw a corrupted GA2D read address");
    end
    ga2d_flush_and_recover();
    issue_ga2d_write(3'd0, 32'h4800_0180, 64'h55AA_AA55_0123_4567);
    `GA2D_TB_AWAIT(opi_saw_write, "GA2D write did not reach the OPI gateway")
    if (opi_last_awaddr != 32'h4800_0180) begin
      $fatal(1, "OPI gateway saw a corrupted GA2D write address");
    end
    ga2d_flush_and_recover();
    @(negedge clk_io_i);
    mem_pad_mode_i = 2'd1;
    repeat (6) @(posedge clk_hp_i);
    issue_ga2d_read(3'd0, 32'h3000_0040);
    expect_ga2d_read(3'd0);

    // ---------------------------------------------------------------------
    // GA2D-V13 contention window. The five BFMs (central DMA on master 2,
    // APU/SDIO0/USB2 sharing master 3, SDIO1 on master 4), the JPEG master-6
    // loop, and the legacy HP-dcache loop (CPU proxy with old global ID
    // 7'h08) run against the SRAM target while the GA2D battery executes
    // byte-checked jobs. Memory-refresh contention is not modelled here (no
    // SDRAM model exists in this TB); it is covered by the full-SoC ci_smoke
    // and benchmark runs against the real SDRAM controller.
    contention_run = 1'b1;
    repeat (300) @(posedge clk_io_i);
    competitor_snap_start[0] = dma_read_txns + dma_write_txns;
    competitor_snap_start[1] = apu_read_txns + apu_write_txns;
    competitor_snap_start[2] = sdio0_read_txns + sdio0_write_txns;
    competitor_snap_start[3] = sdio1_read_txns + sdio1_write_txns;
    competitor_snap_start[4] = usb2_read_txns + usb2_write_txns;
    contention_cycle_start   = cycle_count;
    fork
      begin
        repeat (6) begin
          issue_jpeg_read(3'd0, 32'h3000_00A0);
          expect_jpeg_read(3'd0);
          issue_jpeg_write(3'd1, 32'h3000_00E0, 64'h89AB_CDEF_0123_4567);
          expect_jpeg_write(3'd1);
        end
      end
      begin
        repeat (8) begin
          issue_legacy_read(3'd0, 32'h3000_0080);
          expect_legacy_read(3'd0);
        end
      end
      begin
        for (int j = 0; j < 8; j++) begin
          issue_ga2d_write_burst(3'd0, 32'h3000_4000 + 32'(j) * 32'd96, 8'd8, ga2d_job_base(j));
          expect_ga2d_write(3'd0);
          issue_ga2d_read_burst(3'd0, 32'h3000_4000 + 32'(j) * 32'd96, 8'd8);
          check_ga2d_read_burst(3'd0, 8'd8, ga2d_job_base(j));
        end
        for (int j = 0; j < 8; j++) begin
          issue_ga2d_read_burst(3'd1, 32'h3000_4040 + 32'(j) * 32'd96, 8'd4);
          check_ga2d_read_burst_init(3'd1, 32'h3000_4040 + 32'(j) * 32'd96, 8'd4);
        end
        issue_ga2d_read_burst(3'd1, 32'h3000_4300, 8'd4);
        check_ga2d_read_burst_init(3'd1, 32'h3000_4300, 8'd4);
      end
    join
    contention_cycle_used = cycle_count - contention_cycle_start;
    // Forward-progress bound as a fairness assumption, not a wall-clock
    // guarantee: with a progressing target and the fabric's aging promotion
    // (a continuously eligible request wins within 256 HP cycles, about 403
    // clk_io cycles), the battery's 25 GA2D transactions are bounded well
    // under this generous 40000 clk_io cycle limit.
    if (contention_cycle_used > 40000) begin
      $fatal(1, "GA2D jobs made no forward progress under contention");
    end
    competitor_snap_mid[0] = dma_read_txns + dma_write_txns;
    competitor_snap_mid[1] = apu_read_txns + apu_write_txns;
    competitor_snap_mid[2] = sdio0_read_txns + sdio0_write_txns;
    competitor_snap_mid[3] = sdio1_read_txns + sdio1_write_txns;
    competitor_snap_mid[4] = usb2_read_txns + usb2_write_txns;
    for (int c = 0; c < 5; c++) begin
      if (competitor_snap_mid[c] == competitor_snap_start[c]) begin
        $fatal(1, "a competitor was starved while the GA2D battery ran");
      end
    end
    repeat (200) @(posedge clk_io_i);
    contention_run = 1'b0;
    `GA2D_TB_AWAIT(
        dma_bfm_done && apu_bfm_done && sdio0_bfm_done && sdio1_bfm_done && usb2_bfm_done,
        "a competitor BFM wedged after the contention window")
    if (((dma_read_txns + dma_write_txns) == competitor_snap_mid[0]) ||
        ((apu_read_txns + apu_write_txns) == competitor_snap_mid[1]) ||
        ((sdio0_read_txns + sdio0_write_txns) == competitor_snap_mid[2]) ||
        ((sdio1_read_txns + sdio1_write_txns) == competitor_snap_mid[3]) ||
        ((usb2_read_txns + usb2_write_txns) == competitor_snap_mid[4])) begin
      $fatal(1, "a competitor was starved after the GA2D battery finished");
    end
    if ((dma_read_txns < 2) || (dma_write_txns < 2) || (apu_read_txns < 2) ||
        (apu_write_txns < 2) || (sdio0_read_txns < 2) || (sdio0_write_txns < 2) ||
        (sdio1_read_txns < 2) || (sdio1_write_txns < 2) || (usb2_read_txns < 2) ||
        (usb2_write_txns < 2)) begin
      $fatal(1, "a competitor did not retire enough transactions under contention");
    end
    // Old/new global-ID alias check: every ID accepted by the SRAM target
    // must belong to the master that owns it. GA2D's IDs carry the new
    // seventh bit; if that bit were dropped anywhere, GA2D traffic would
    // appear as 7'h00 and alias the (tied-off) HP icache master 0.
    expected_read_mask        = '0;
    expected_read_mask[7'h08] = 1'b1;
    expected_read_mask[7'h10] = 1'b1;
    expected_read_mask[7'h11] = 1'b1;
    expected_read_mask[7'h18] = 1'b1;
    expected_read_mask[7'h19] = 1'b1;
    expected_read_mask[7'h20] = 1'b1;
    expected_read_mask[7'h21] = 1'b1;
    expected_read_mask[7'h28] = 1'b1;
    expected_read_mask[7'h30] = 1'b1;
    for (int b = 0; b < 8; b++) begin
      expected_read_mask[7'h40+b] = 1'b1;
    end
    expected_write_mask        = '0;
    expected_write_mask[7'h10] = 1'b1;
    expected_write_mask[7'h11] = 1'b1;
    expected_write_mask[7'h18] = 1'b1;
    expected_write_mask[7'h19] = 1'b1;
    expected_write_mask[7'h20] = 1'b1;
    expected_write_mask[7'h21] = 1'b1;
    expected_write_mask[7'h31] = 1'b1;
    for (int b = 0; b < 8; b++) begin
      expected_write_mask[7'h40+b] = 1'b1;
    end
    if ((sram_seen_arid_mask & ~expected_read_mask) != 128'd0) begin
      $fatal(1, "an unexpected global read ID reached the SRAM target");
    end
    if ((sram_seen_awid_mask & ~expected_write_mask) != 128'd0) begin
      $fatal(1, "an unexpected global write ID reached the SRAM target");
    end
    if (!sram_seen_arid_mask[7'h40] || !sram_seen_arid_mask[7'h08] ||
        !sram_seen_arid_mask[7'h30]) begin
      $fatal(1, "old and new global read IDs were not interleaved during contention");
    end
    if (sram_seen_arid_mask[7'h00] || sram_seen_awid_mask[7'h00]) begin
      $fatal(1, "GA2D traffic aliased onto the legacy master-0 ID space");
    end
    // Fabric-monitor cross-check: bank 8 at 0x200 must have counted the GA2D
    // battery, and bank 2 the central-DMA competitor.
    monitor_apb_write(12'h00C, 32'h0000_0009);
    monitor_apb_read(12'h200, apb_data);
    if (apb_data == 32'd0) begin
      $fatal(1, "fabric monitor bank 8 recorded no GA2D read accepts");
    end
    monitor_apb_read(12'h204, apb_data);
    if (apb_data == 32'd0) begin
      $fatal(1, "fabric monitor bank 8 recorded no GA2D write accepts");
    end
    monitor_apb_read(12'h140, apb_data);
    if (apb_data == 32'd0) begin
      $fatal(1, "fabric monitor bank 2 recorded no DMA read accepts");
    end
    monitor_apb_read(12'h144, apb_data);
    if (apb_data == 32'd0) begin
      $fatal(1, "fabric monitor bank 2 recorded no DMA write accepts");
    end

    // ---------------------------------------------------------------------
    // GA2D-V08 HP clock/lifecycle switching. First the HP rate changes
    // mid-flight across a coordinated flush with a GA2D read held at the
    // target boundary (presented but not accepted, complementing the
    // accepted-at-target warm flush above): the bridge CDCs are
    // rate-agnostic, so the epoch must still advance, the in-flight read must
    // be invalidated, and traffic must resume at the new rate (and again
    // after switching back). The GA2D core maps exactly this epoch change to
    // EPOCH_LOST (s_epoch_changed in ga2d_core.sv, firmware error code 12).
    sram_hold_ar_i = 1'b1;
    issue_ga2d_read(3'd4, 32'h3000_0500);
    repeat (4) @(posedge clk_hp_i);
    epoch_before   = ga2d_bridge_epoch_o;
    hp_half_period = 17;
    @(negedge clk_hp_i);
    flush_i        = 1'b1;
    sram_hold_ar_i = 1'b0;
    repeat (4) @(posedge clk_lp_i);
    repeat (4) @(posedge clk_hp_i);
    if (ga2d_data_ready_o) begin
      $fatal(1, "GA2D data-ready remained asserted during a rate-switched flush");
    end
    @(negedge clk_hp_i);
    flush_i = 1'b0;
    wait (ga2d_bridge_epoch_o != epoch_before);
    repeat (4) @(posedge clk_io_i);
    if (ga2d_axi4.rvalid) begin
      $fatal(1, "late pre-switch response reached the GA2D source");
    end
    wait_for_data_ready();
    wait (!flush_busy_o);
    issue_ga2d_read(3'd4, 32'h3000_0580);
    expect_ga2d_read(3'd4);
    issue_ga2d_write(3'd4, 32'h3000_05C0, 64'h5A5A_A5A5_0123_4567);
    expect_ga2d_write(3'd4);
    hp_half_period = 11;
    repeat (8) @(posedge clk_hp_i);
    issue_ga2d_read(3'd4, 32'h3000_05C0);
    expect_ga2d_read_data(3'd4, 64'h5A5A_A5A5_0123_4567);

    // A stopped HP clock is a system recovery condition, not a liveness
    // claim. While the clock is held, the PCLK-local bridge epoch must still
    // advance (that is exactly how the GA2D core learns its job is dead and
    // raises EPOCH_LOST), the source must close, and the coordinated flush
    // must NOT complete: the warm-flush controllers stall waiting for the
    // HP-side acknowledgement. Recovery then finishes only through the normal
    // clear/recovery protocol after the clock restarts.
    epoch_before = ga2d_bridge_epoch_o;
    @(negedge clk_hp_i);
    flush_i       = 1'b1;
    hp_clk_enable = 1'b0;
    repeat (32) @(posedge clk_io_i);
    if (ga2d_bridge_epoch_o == epoch_before) begin
      $fatal(1, "PCLK-local bridge epoch did not advance while the HP clock was stopped");
    end
    if (!flush_busy_o) begin
      $fatal(1, "the coordinated flush completed while the HP clock was stopped");
    end
    if (!ga2d_source_stop_o || ga2d_data_ready_o) begin
      $fatal(1, "GA2D source failed to close on the stopped-clock flush");
    end
    hp_clk_enable = 1'b1;
    @(negedge clk_hp_i);
    repeat (6) @(posedge clk_hp_i);
    if (ga2d_data_ready_o) begin
      $fatal(1, "GA2D data-ready returned before the flush protocol completed");
    end
    @(negedge clk_hp_i);
    flush_i = 1'b0;
    wait (!flush_busy_o);
    wait_for_data_ready();
    issue_ga2d_read(3'd5, 32'h3000_0600);
    expect_ga2d_read_data(3'd5, sram_init_line(32'h3000_0600));

    // ---------------------------------------------------------------------
    // V13(d): after contention and the clock/lifecycle switches, the directed
    // routing, admission, and resource-handoff behaviour must be unchanged.
    issue_ga2d_read(3'd6, 32'h3000_0040);
    expect_ga2d_read(3'd6);
    if (sram_last_arid != 7'h46) begin
      $fatal(1, "post-contention GA2D read did not keep global ID 7'h46");
    end
    issue_legacy_read(3'd0, 32'h3000_0080);
    expect_legacy_read(3'd0);
    if (sram_last_arid != 7'h08) begin
      $fatal(1, "post-contention legacy read did not keep global ID 7'h08");
    end
    issue_jpeg_read(3'd0, 32'h3000_00A0);
    expect_jpeg_read(3'd0);
    if (sram_last_arid != 7'h30) begin
      $fatal(1, "post-contention JPEG read did not keep master prefix 6");
    end
    issue_jpeg_write(3'd1, 32'h3000_00E0, 64'h89AB_CDEF_0123_4567);
    expect_jpeg_write(3'd1);
    wait (ga2d_source_safe_idle_o);
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b1;
    wait (resource_block_ack_o[8]);
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();
    if (fault_log_count != 6) begin
      $fatal(1, "contention or clock switching raised a spurious fabric fault");
    end

    $display(
        "GA2D P2 bridge, JPEG master-6 admission, ID7, lifecycle, flush, LP retention, and reset test passed");
    $display("GA2D V03 target/denial, V08 HP clock switch, and V13 contention test passed");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "GA2D platform test timed out");
  end
endmodule

`undef GA2D_TB_AWAIT
