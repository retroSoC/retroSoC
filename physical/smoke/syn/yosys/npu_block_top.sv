// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Structural synthesis/netlist boundary for the production NPU core and DMA.
module npu_block_top (
    // verilog_format: off -- preserve the lifecycle and AXI boundary columns
    input  logic                            clk_hp_i,
    input  logic                            rst_hp_n_i,
    input  logic                            launch_valid_i,
    output logic                            launch_ready_o,
    input  logic [127:0]                    launch_data_i,
    output logic                            result_valid_o,
    input  logic                            result_ready_i,
    output logic [169:0]                    result_data_o,
    input  logic                            snapshot_req_valid_i,
    output logic                            snapshot_req_ready_o,
    output logic                            snapshot_resp_valid_o,
    input  logic                            snapshot_resp_ready_i,
    output logic [671:0]                    snapshot_resp_data_o,
    input  logic [3:0]                      epoch_req_i,
    output logic [3:0]                      epoch_ack_o,
    input  logic                            quiesce_req_i,
    output logic                            quiesce_ack_o,
    output logic                            busy_o,
    output logic                            draining_o,
    input  logic                            block_new_i,
    output logic                            clock_pause_ack_o,
    input  logic                            flush_i,
    output logic                            flush_busy_o,
    output logic                            pause_active_o,
    output logic                            idle_o,
    input  logic                            abort_i,
    output logic [2:0]                      awid_o,
    output logic [31:0]                     awaddr_o,
    output logic [7:0]                      awlen_o,
    output logic [2:0]                      awsize_o,
    output logic [1:0]                      awburst_o,
    output logic                            awlock_o,
    output logic [3:0]                      awcache_o,
    output logic [2:0]                      awprot_o,
    output logic [3:0]                      awqos_o,
    output logic [3:0]                      awregion_o,
    output logic                            awuser_o,
    output logic                            awvalid_o,
    input  logic                            awready_i,
    output logic [63:0]                     wdata_o,
    output logic [7:0]                      wstrb_o,
    output logic                            wlast_o,
    output logic                            wuser_o,
    output logic                            wvalid_o,
    input  logic                            wready_i,
    input  logic [2:0]                      bid_i,
    input  logic [1:0]                      bresp_i,
    input  logic                            buser_i,
    input  logic                            bvalid_i,
    output logic                            bready_o,
    output logic [2:0]                      arid_o,
    output logic [31:0]                     araddr_o,
    output logic [7:0]                      arlen_o,
    output logic [2:0]                      arsize_o,
    output logic [1:0]                      arburst_o,
    output logic                            arlock_o,
    output logic [3:0]                      arcache_o,
    output logic [2:0]                      arprot_o,
    output logic [3:0]                      arqos_o,
    output logic [3:0]                      arregion_o,
    output logic                            aruser_o,
    output logic                            arvalid_o,
    input  logic                            arready_i,
    input  logic [2:0]                      rid_i,
    input  logic [63:0]                     rdata_i,
    input  logic [1:0]                      rresp_i,
    input  logic                            rlast_i,
    input  logic                            ruser_i,
    input  logic                            rvalid_i,
    output logic                            rready_o
    // verilog_format: on
);
  logic        s_dma_clear;
  logic        s_dma_read_req_valid;
  logic        s_dma_read_req_ready;
  logic [31:0] s_dma_read_addr;
  logic [31:0] s_dma_read_bytes;
  logic        s_dma_read_data_valid;
  logic        s_dma_read_data_ready;
  logic [63:0] s_dma_read_data;
  logic [ 7:0] s_dma_read_keep;
  logic        s_dma_read_last;
  logic        s_dma_write_req_valid;
  logic        s_dma_write_req_ready;
  logic [31:0] s_dma_write_addr;
  logic [31:0] s_dma_write_bytes;
  logic        s_dma_write_data_valid;
  logic        s_dma_write_data_ready;
  logic [63:0] s_dma_write_data;
  logic [ 7:0] s_dma_write_keep;
  logic        s_dma_write_last;
  logic        s_dma_write_done;
  logic        s_dma_busy;
  logic        s_dma_read_busy;
  logic        s_dma_write_busy;
  logic        s_dma_pause_ack;
  logic        s_dma_fault;
  logic [ 3:0] s_dma_fault_code;
  logic [31:0] s_dma_fault_addr;
  logic [ 1:0] s_dma_fault_resp;
  logic [63:0] s_dma_read_bytes_cnt;
  logic [63:0] s_dma_write_bytes_cnt;
  logic [63:0] s_dma_stall_cycles;
  logic        s_dma_read_cmd_err;
  logic        s_dma_write_cmd_err;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );

  assign awid_o         = u_axi4.awid;
  assign awaddr_o       = u_axi4.awaddr;
  assign awlen_o        = u_axi4.awlen;
  assign awsize_o       = u_axi4.awsize;
  assign awburst_o      = u_axi4.awburst;
  assign awlock_o       = u_axi4.awlock;
  assign awcache_o      = u_axi4.awcache;
  assign awprot_o       = u_axi4.awprot;
  assign awqos_o        = u_axi4.awqos;
  assign awregion_o     = u_axi4.awregion;
  assign awuser_o       = u_axi4.awuser;
  assign awvalid_o      = u_axi4.awvalid;
  assign u_axi4.awready = awready_i;
  assign wdata_o        = u_axi4.wdata;
  assign wstrb_o        = u_axi4.wstrb;
  assign wlast_o        = u_axi4.wlast;
  assign wuser_o        = u_axi4.wuser;
  assign wvalid_o       = u_axi4.wvalid;
  assign u_axi4.wready  = wready_i;
  assign u_axi4.bid     = bid_i;
  assign u_axi4.bresp   = bresp_i;
  assign u_axi4.buser   = buser_i;
  assign u_axi4.bvalid  = bvalid_i;
  assign bready_o       = u_axi4.bready;
  assign arid_o         = u_axi4.arid;
  assign araddr_o       = u_axi4.araddr;
  assign arlen_o        = u_axi4.arlen;
  assign arsize_o       = u_axi4.arsize;
  assign arburst_o      = u_axi4.arburst;
  assign arlock_o       = u_axi4.arlock;
  assign arcache_o      = u_axi4.arcache;
  assign arprot_o       = u_axi4.arprot;
  assign arqos_o        = u_axi4.arqos;
  assign arregion_o     = u_axi4.arregion;
  assign aruser_o       = u_axi4.aruser;
  assign arvalid_o      = u_axi4.arvalid;
  assign u_axi4.arready = arready_i;
  assign u_axi4.rid     = rid_i;
  assign u_axi4.rdata   = rdata_i;
  assign u_axi4.rresp   = rresp_i;
  assign u_axi4.rlast   = rlast_i;
  assign u_axi4.ruser   = ruser_i;
  assign u_axi4.rvalid  = rvalid_i;
  assign rready_o       = u_axi4.rready;

  npu_core #(
      .ExecutionReady(1'b1)
  ) u_core (
      .clk_hp_i              (clk_hp_i),
      .rst_hp_n_i            (rst_hp_n_i),
      .launch_valid_i        (launch_valid_i),
      .launch_ready_o        (launch_ready_o),
      .launch_data_i         (launch_data_i),
      .result_valid_o        (result_valid_o),
      .result_ready_i        (result_ready_i),
      .result_data_o         (result_data_o),
      .snapshot_req_valid_i  (snapshot_req_valid_i),
      .snapshot_req_ready_o  (snapshot_req_ready_o),
      .snapshot_resp_valid_o (snapshot_resp_valid_o),
      .snapshot_resp_ready_i (snapshot_resp_ready_i),
      .snapshot_resp_data_o  (snapshot_resp_data_o),
      .epoch_req_i           (epoch_req_i),
      .epoch_ack_o           (epoch_ack_o),
      .quiesce_req_i         (quiesce_req_i),
      .quiesce_ack_o         (quiesce_ack_o),
      .busy_o                (busy_o),
      .draining_o            (draining_o),
      .block_new_i           (block_new_i),
      .clock_pause_ack_o     (clock_pause_ack_o),
      .flush_i               (flush_i),
      .flush_busy_o          (flush_busy_o),
      .pause_active_o        (pause_active_o),
      .idle_o                (idle_o),
      .abort_i               (abort_i),
      .dma_clear_o           (s_dma_clear),
      .dma_read_req_valid_o  (s_dma_read_req_valid),
      .dma_read_req_ready_i  (s_dma_read_req_ready),
      .dma_read_addr_o       (s_dma_read_addr),
      .dma_read_bytes_o      (s_dma_read_bytes),
      .dma_read_data_valid_i (s_dma_read_data_valid),
      .dma_read_data_ready_o (s_dma_read_data_ready),
      .dma_read_data_i       (s_dma_read_data),
      .dma_read_keep_i       (s_dma_read_keep),
      .dma_read_last_i       (s_dma_read_last),
      .dma_write_req_valid_o (s_dma_write_req_valid),
      .dma_write_req_ready_i (s_dma_write_req_ready),
      .dma_write_addr_o      (s_dma_write_addr),
      .dma_write_bytes_o     (s_dma_write_bytes),
      .dma_write_data_valid_o(s_dma_write_data_valid),
      .dma_write_data_ready_i(s_dma_write_data_ready),
      .dma_write_data_o      (s_dma_write_data),
      .dma_write_keep_o      (s_dma_write_keep),
      .dma_write_last_o      (s_dma_write_last),
      .dma_write_done_i      (s_dma_write_done),
      .dma_busy_i            (s_dma_busy),
      .dma_read_busy_i       (s_dma_read_busy),
      .dma_write_busy_i      (s_dma_write_busy),
      .dma_pause_ack_i       (s_dma_pause_ack),
      .dma_fault_i           (s_dma_fault),
      .dma_fault_code_i      (s_dma_fault_code),
      .dma_fault_addr_i      (s_dma_fault_addr),
      .dma_fault_resp_i      (s_dma_fault_resp),
      .dma_read_bytes_i      (s_dma_read_bytes_cnt),
      .dma_write_bytes_i     (s_dma_write_bytes_cnt),
      .dma_stall_cycles_i    (s_dma_stall_cycles),
      .dma_read_cmd_err_i    (s_dma_read_cmd_err),
      .dma_write_cmd_err_i   (s_dma_write_cmd_err)
  );

  npu_dma #(
      .MaxBurstBeats(8)
  ) u_dma (
      .clk_hp_i          (clk_hp_i),
      .rst_hp_n_i        (rst_hp_n_i),
      .clear_i           (flush_i || s_dma_clear),
      .block_new_i       (block_new_i),
      .pause_ack_o       (s_dma_pause_ack),
      .read_req_valid_i  (s_dma_read_req_valid),
      .read_req_ready_o  (s_dma_read_req_ready),
      .read_addr_i       (s_dma_read_addr),
      .read_bytes_i      (s_dma_read_bytes),
      .read_data_valid_o (s_dma_read_data_valid),
      .read_data_ready_i (s_dma_read_data_ready),
      .read_data_o       (s_dma_read_data),
      .read_keep_o       (s_dma_read_keep),
      .read_last_o       (s_dma_read_last),
      .write_req_valid_i (s_dma_write_req_valid),
      .write_req_ready_o (s_dma_write_req_ready),
      .write_addr_i      (s_dma_write_addr),
      .write_bytes_i     (s_dma_write_bytes),
      .write_data_valid_i(s_dma_write_data_valid),
      .write_data_ready_o(s_dma_write_data_ready),
      .write_data_i      (s_dma_write_data),
      .write_keep_i      (s_dma_write_keep),
      .write_last_i      (s_dma_write_last),
      .write_done_o      (s_dma_write_done),
      .busy_o            (s_dma_busy),
      .read_busy_o       (s_dma_read_busy),
      .write_busy_o      (s_dma_write_busy),
      .read_bytes_o      (s_dma_read_bytes_cnt),
      .write_bytes_o     (s_dma_write_bytes_cnt),
      .stall_cycles_o    (s_dma_stall_cycles),
      .fault_o           (s_dma_fault),
      .fault_code_o      (s_dma_fault_code),
      .fault_addr_o      (s_dma_fault_addr),
      .fault_resp_o      (s_dma_fault_resp),
      .read_cmd_err_o    (s_dma_read_cmd_err),
      .write_cmd_err_o   (s_dma_write_cmd_err),
      .axi4              (u_axi4)
  );
endmodule
