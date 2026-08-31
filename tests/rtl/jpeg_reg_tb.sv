`timescale 1ns / 1ps

module jpeg_reg_tb;
  logic       clk = 1'b0;
  logic       rst_n = 1'b0;
  logic       busy;
  logic       job_done;
  logic       error_event;
  logic       start_pulse;
  logic       table_write;
  logic [7:0] table_index;
  logic       irq;

  apb4_if apb4 (
      .pclk   (clk),
      .presetn(rst_n)
  );

  always #5 clk = ~clk;

  jpeg_reg u_dut (
      .clk_i              (clk),
      .rst_n_i            (rst_n),
      .apb4               (apb4),
      .busy_i             (busy),
      .ring_active_i      (1'b0),
      .encode_i           (1'b1),
      .quiesce_i          (1'b0),
      .job_done_i         (job_done),
      .ring_event_i       (1'b0),
      .header_ready_i     (1'b0),
      .abort_done_i       (1'b0),
      .error_event_i      (error_event),
      .error_code_i       (5'd9),
      .error_stage_i      (4'd7),
      .error_axi_resp_i   (2'd2),
      .error_addr_i       (32'h38001234),
      .error_detail_i     (32'h55aa55aa),
      .cycles_i           (64'h123456789abcdef0),
      .pixels_i           (32'd99),
      .input_bytes_i      (32'd100),
      .output_bytes_i     (32'd50),
      .read_stall_i       (32'd4),
      .write_stall_i      (32'd5),
      .result_size_i      (32'd50),
      .result_image_size_i(32'h00100020),
      .result_format_i    (32'd3),
      .result_markers_i   (32'd7),
      .ring_head_i        (32'd2),
      .ring_status_i      (32'd1),
      .table_data_i       (32'h11223344),
      .table_status_i     (32'd1),
      .start_o            (start_pulse),
      .abort_o            (),
      .soft_reset_o       (),
      .ring_kick_o        (),
      .job_config_o       (),
      .image_size_o       (),
      .input_format_o     (),
      .output_format_o    (),
      .encode_config_o    (),
      .restart_interval_o (),
      .bitstream_addr_o   (),
      .bitstream_size_o   (),
      .plane0_addr_o      (),
      .plane0_stride_o    (),
      .plane1_addr_o      (),
      .plane1_stride_o    (),
      .plane2_addr_o      (),
      .plane2_stride_o    (),
      .metadata_addr_o    (),
      .metadata_length_o  (),
      .ring_base_o        (),
      .ring_size_o        (),
      .ring_tail_o        (),
      .ring_control_o     (),
      .irq_coalesce_o     (),
      .table_context_o    (),
      .table_kind_o       (),
      .table_index_o      (table_index),
      .table_write_data_o (),
      .table_write_o      (table_write),
      .table_commit_o     (),
      .table_default_o    (),
      .table_clear_o      (),
      .perf_enable_o      (),
      .perf_clear_o       (),
      .irq_o              (irq)
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] data_i,
                           input logic [3:0] strobe_i, input logic expected_err_i);
    begin
      @(negedge clk);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwdata  = data_i;
      apb4.pstrb   = strobe_i;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk);
      apb4.penable = 1'b1;
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_err_i)) begin
        $fatal(1, "APB write response mismatch at %h", offset_i);
      end
      @(negedge clk);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] data_o,
                          input logic expected_err_i);
    begin
      @(negedge clk);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk);
      apb4.penable = 1'b1;
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_err_i)) begin
        $fatal(1, "APB read response mismatch at %h", offset_i);
      end
      data_o = apb4.prdata;
      @(negedge clk);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] value;

    apb4.paddr   = '0;
    apb4.pprot   = '0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    busy         = 1'b0;
    job_done     = 1'b0;
    error_event  = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    apb_read(12'h000, value, 1'b0);
    if (value != 32'h4a504547) $fatal(1, "JPEG IP ID mismatch");
    apb_write(12'h084, 32'h04380780, 4'hf, 1'b0);
    apb_write(12'h084, 32'h00000021, 4'h1, 1'b0);
    apb_read(12'h084, value, 1'b0);
    if (value != 32'h04380721) $fatal(1, "byte-strobe update mismatch");
    apb_write(12'h01c, 32'h1, 4'hf, 1'b0);
    @(negedge clk);
    job_done = 1'b1;
    @(negedge clk);
    job_done = 1'b0;
    apb_read(12'h018, value, 1'b0);
    if (value != 32'h1 || !irq) $fatal(1, "completion IRQ mismatch");
    apb_write(12'h018, 32'h1, 4'h1, 1'b0);
    if (irq) $fatal(1, "IRQ W1C failed");

    @(negedge clk);
    error_event = 1'b1;
    @(negedge clk);
    error_event = 1'b0;
    apb_read(12'h024, value, 1'b0);
    if (value[0] != 1'b1 || value[5:1] != 5'd9 || value[9:6] != 4'd7) begin
      $fatal(1, "first-error status mismatch");
    end
    apb_read(12'h028, value, 1'b0);
    if (value != 32'h38001234) $fatal(1, "first-error address mismatch");

    apb_write(12'h208, 32'd7, 4'hf, 1'b0);
    apb_write(12'h20c, 32'h11223344, 4'hf, 1'b0);
    if (table_index != 8'd8) $fatal(1, "table portal did not auto-increment");
    apb_write(12'h200, 32'd4, 4'hf, 1'b1);
    apb_read(12'h010, value, 1'b1);
    busy = 1'b1;
    apb_write(12'h084, 32'd1, 4'hf, 1'b1);
    apb_write(12'h010, 32'h1, 4'hf, 1'b1);
    busy = 1'b0;
    apb_write(12'h010, 32'h1, 4'hf, 1'b0);
    $display("JPEG APB register tests passed");
    $finish;
  end
endmodule
