`timescale 1ns / 1ps
`include "ppalite_define.svh"

module ppalite_arm_dma_race_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  always #5 clk_i = ~clk_i;

  apb4_if ppa_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if host_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if dma_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  logic        route_idle_i = 1'b1;
  logic        source_ready_i = 1'b1;
  logic        source_quiet_i = 1'b1;
  logic        source_done_i = 1'b0;
  logic        source_stopped_i = 1'b1;
  logic [31:0] source_sequence_i = 32'd0;
  logic [31:0] source_words_i = 32'd0;
  logic [31:0] source_geometry_i = 32'h0002_0004;
  logic [ 7:0] source_err_i = 8'd0;
  logic [ 2:0] capture_state;
  logic capture_arm_request, capture_arm, capture_release, capture_close, processor_idle;
  logic [31:0] job_destination, job_transport_bytes;
  logic transport_ready, transport_idle, transport_admitted, transport_done, stream_isolated;
  logic [ 7:0] transport_err;
  logic        dma_start;
  logic        dma_rst_n_i = 1'b1;
  logic        dma_ready_i = 1'b1;
  logic        dma_start_pending_i;
  logic        dma_busy_i = 1'b0;
  logic        dma_done_i = 1'b0;
  logic [31:0] dma_bytes_done_i = 32'd0;
  logic [31:0] dma_error_status_i = 32'd0;

  assign dma_apb.pready = dma_apb.psel && dma_apb.penable;
  assign dma_apb.prdata = 32'd0;
  assign dma_apb.pslverr = 1'b0;
  assign dma_start_pending_i = dma_apb.psel && dma_apb.penable && dma_apb.pwrite &&
      (dma_apb.paddr[11:0] == 12'h200) && (dma_apb.pwdata == 32'd1);

  apb4_ppalite #(
      .ExternalRoute  (1'b1),
      .CapabilityValue(32'h0000_03ff)
  ) u_ppa (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .clock_hz_i           (32'd24000000),
      .route_idle_i         (route_idle_i),
      .route_i              (1'b1),
      .route_change_i       (1'b0),
      .route_write_o        (),
      .route_value_o        (),
      .processing_format_o  (),
      .job_destination_o    (job_destination),
      .job_transport_bytes_o(job_transport_bytes),
      .capture_state_o      (capture_state),
      .capture_arm_request_o(capture_arm_request),
      .capture_arm_o        (capture_arm),
      .capture_release_o    (capture_release),
      .capture_close_o      (capture_close),
      .processor_idle_o     (processor_idle),
      .source_ready_i       (source_ready_i),
      .source_quiet_i       (source_quiet_i),
      .source_done_i        (source_done_i),
      .source_stopped_i     (source_stopped_i),
      .source_sequence_i    (source_sequence_i),
      .source_words_i       (source_words_i),
      .source_geometry_i    (source_geometry_i),
      .source_err_i         (source_err_i),
      .source_config_err_i  (1'b0),
      .source_stats_err_i   (1'b0),
      .transport_ready_i    (transport_ready),
      .transport_idle_i     (transport_idle),
      .transport_done_i     (transport_done),
      .transport_err_i      (transport_err),
      .in_valid_i           (1'b0),
      .in_ready_o           (),
      .in_data_i            (32'd0),
      .in_keep_i            (4'd0),
      .in_strb_i            (4'd0),
      .in_id_i              (1'b0),
      .in_dest_i            (1'b0),
      .in_user_i            (1'b0),
      .in_last_i            (1'b0),
      .out_valid_o          (),
      .out_ready_i          (1'b1),
      .out_data_o           (),
      .out_keep_o           (),
      .out_strb_o           (),
      .out_last_o           (),
      .out_id_o             (),
      .out_dest_o           (),
      .out_user_o           (),
      .irq_o                (),
      .apb4                 (ppa_apb)
  );

  ppalite_dma_guard u_guard (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .host_apb4            (host_apb),
      .dma_apb4             (dma_apb),
      .route_i              (1'b1),
      .capture_state_i      (capture_state),
      .capture_arm_request_i(capture_arm_request),
      .capture_release_i    (capture_release),
      .capture_close_i      (capture_close),
      .job_destination_i    (job_destination),
      .job_transport_bytes_i(job_transport_bytes),
      .dma_rst_n_i          (dma_rst_n_i),
      .dma_ready_i          (dma_ready_i),
      .dma_start_pending_i  (dma_start_pending_i),
      .dma_busy_i           (dma_busy_i),
      .dma_done_i           (dma_done_i),
      .dma_bytes_done_i     (dma_bytes_done_i),
      .dma_error_status_i   (dma_error_status_i),
      .dma_start_o          (dma_start),
      .transport_ready_o    (transport_ready),
      .transport_idle_o     (transport_idle),
      .transport_admitted_o (transport_admitted),
      .transport_done_o     (transport_done),
      .transport_err_o      (transport_err),
      .stream_isolated_o    (stream_isolated)
  );

  task automatic setup_apb(input logic ppa, input logic write_access, input logic [31:0] address,
                           input logic [31:0] data, input logic [3:0] strobe);
    begin
      if (ppa) begin
        ppa_apb.paddr   = address;
        ppa_apb.pwdata  = data;
        ppa_apb.pstrb   = strobe;
        ppa_apb.pwrite  = write_access;
        ppa_apb.psel    = 1'b1;
        ppa_apb.penable = 1'b0;
        ppa_apb.pprot   = 3'd0;
      end else begin
        host_apb.paddr   = address;
        host_apb.pwdata  = data;
        host_apb.pstrb   = strobe;
        host_apb.pwrite  = write_access;
        host_apb.psel    = 1'b1;
        host_apb.penable = 1'b0;
        host_apb.pprot   = 3'd0;
      end
      @(negedge clk_i);
      if (ppa) ppa_apb.penable = 1'b1;
      else host_apb.penable = 1'b1;
    end
  endtask

  task automatic finish_apb(input logic ppa, input logic expected_error);
    integer timeout;
    begin
      timeout = 0;
      while (!(ppa ? ppa_apb.pready : host_apb.pready) && timeout < 8) begin
        @(negedge clk_i);
        timeout++;
      end
      if (!(ppa ? ppa_apb.pready : host_apb.pready))
        $fatal(1, "SIM_TEST_TIMEOUT ARM race APB ppa=%0d", ppa);
      if ((ppa ? ppa_apb.pslverr : host_apb.pslverr) !== expected_error)
        $fatal(
            1,
            "SIM_TEST_FAIL ARM race APB ppa=%0d error=%b expected=%b",
            ppa,
            (ppa ? ppa_apb.pslverr : host_apb.pslverr),
            expected_error
        );
      @(negedge clk_i);
      if (ppa) begin
        ppa_apb.psel    = 1'b0;
        ppa_apb.penable = 1'b0;
        ppa_apb.pwrite  = 1'b0;
        ppa_apb.pstrb   = 4'd0;
      end else begin
        host_apb.psel    = 1'b0;
        host_apb.penable = 1'b0;
        host_apb.pwrite  = 1'b0;
        host_apb.pstrb   = 4'd0;
      end
    end
  endtask

  task automatic write_reg(input logic ppa, input logic [31:0] address, input logic [31:0] data,
                           input logic expected_error);
    begin
      setup_apb(ppa, 1'b1, address, data, 4'hf);
      finish_apb(ppa, expected_error);
    end
  endtask

  task automatic prepare(input logic [31:0] byte_count);
    begin
      write_reg(1'b0, 32'h0204, 32'h0000_03a2, 1'b0);
      write_reg(1'b0, 32'h0208, 32'd0, 1'b0);
      write_reg(1'b0, 32'h020c, 32'h3000_0000, 1'b0);
      write_reg(1'b0, 32'h0210, byte_count, 1'b0);
      write_reg(1'b0, 32'h0214, 32'd11, 1'b0);
      write_reg(1'b0, 32'h0218, 32'd4, 1'b0);
      write_reg(1'b0, 32'h0248, 32'd0, 1'b0);
      write_reg(1'b0, 32'h024c, 32'd0, 1'b0);
      write_reg(1'b1, 32'h0020, 32'h0000_0012, 1'b0);
      write_reg(1'b1, 32'h0024, 32'h0002_0004, 1'b0);
      write_reg(1'b1, 32'h0028, 32'd0, 1'b0);
      write_reg(1'b1, 32'h0030, 32'h3000_0000, 1'b0);
      write_reg(1'b1, 32'h0034, 32'd32, 1'b0);
    end
  endtask

  task automatic race(input logic [3:0] ppa_strobe, input logic expected_ppa_error,
                      input logic expected_dma_error);
    begin
      @(negedge clk_i);
      ppa_apb.paddr    = 32'h0018;
      ppa_apb.pwdata   = 32'd1;
      ppa_apb.pstrb    = ppa_strobe;
      ppa_apb.pwrite   = 1'b1;
      ppa_apb.psel     = 1'b1;
      ppa_apb.penable  = 1'b0;
      ppa_apb.pprot    = 3'd0;
      host_apb.paddr   = 32'h0200;
      host_apb.pwdata  = 32'd1;
      host_apb.pstrb   = 4'hf;
      host_apb.pwrite  = 1'b1;
      host_apb.psel    = 1'b1;
      host_apb.penable = 1'b0;
      host_apb.pprot   = 3'd0;
      @(negedge clk_i);
      ppa_apb.penable  = 1'b1;
      host_apb.penable = 1'b1;
      fork
        finish_apb(1'b1, expected_ppa_error);
        finish_apb(1'b0, expected_dma_error);
      join
    end
  endtask

  initial begin
    ppa_apb.psel     = 1'b0;
    ppa_apb.penable  = 1'b0;
    ppa_apb.pwrite   = 1'b0;
    ppa_apb.paddr    = 32'd0;
    ppa_apb.pwdata   = 32'd0;
    ppa_apb.pstrb    = 4'd0;
    ppa_apb.pprot    = 3'd0;
    host_apb.psel    = 1'b0;
    host_apb.penable = 1'b0;
    host_apb.pwrite  = 1'b0;
    host_apb.paddr   = 32'd0;
    host_apb.pwdata  = 32'd0;
    host_apb.pstrb   = 4'd0;
    host_apb.pprot   = 3'd0;
    repeat (4) @(negedge clk_i);
    rst_n_i = 1'b1;
    repeat (3) @(negedge clk_i);

    prepare(32'd8);
    if (!transport_ready) $fatal(1, "SIM_TEST_FAIL valid job not prepared");
    race(4'hf, 1'b1, 1'b0);
    if (!transport_admitted || (capture_state != `PPALITE_STATE_IDLE))
      $fatal(1, "SIM_TEST_FAIL START did not win valid ARM race");
    write_reg(1'b0, 32'h0200, 32'd16, 1'b0);
    if (transport_admitted) $fatal(1, "SIM_TEST_FAIL race cleanup");

    race(4'h1, 1'b1, 1'b1);
    if (transport_admitted) $fatal(1, "SIM_TEST_FAIL bad-strobe ARM authorized DMA");
    source_ready_i = 1'b0;
    race(4'hf, 1'b1, 1'b1);
    if (transport_admitted) $fatal(1, "SIM_TEST_FAIL unready source authorized DMA");
    source_ready_i    = 1'b1;
    source_geometry_i = 32'h0002_0008;
    race(4'hf, 1'b1, 1'b1);
    if (transport_admitted) $fatal(1, "SIM_TEST_FAIL geometry mismatch authorized DMA");
    source_geometry_i = 32'h0002_0004;

    write_reg(1'b1, 32'h0018, 32'd1, 1'b0);
    if (capture_state != `PPALITE_STATE_ARMED)
      $fatal(1, "SIM_TEST_FAIL normal ARM did not enter ARMED");
    write_reg(1'b0, 32'h0200, 32'd1, 1'b0);
    if (!transport_admitted) $fatal(1, "SIM_TEST_FAIL normal guarded START");

    $display("SIM_TEST_PASS PPALITE_P3_ARM_DMA_RACE");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT PPALite ARM/DMA race");
  end
endmodule
