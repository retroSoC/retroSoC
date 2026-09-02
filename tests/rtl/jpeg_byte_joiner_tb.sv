`timescale 1ns / 1ps

module jpeg_byte_joiner_tb;
  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic [63:0] input_data;
  logic [ 7:0] input_keep;
  logic        input_valid;
  logic        input_ready;
  logic        input_last;
  logic        error_flag;
  int          output_beats;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) output_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  jpeg_byte_joiner u_dut (
      .clk_i        (clk),
      .rst_n_i      (rst_n),
      .input_data_i (input_data),
      .input_keep_i (input_keep),
      .input_valid_i(input_valid),
      .input_ready_o(input_ready),
      .input_last_i (input_last),
      .output_axis  (output_axis),
      .error_o      (error_flag)
  );

  task automatic send_beat(input logic [63:0] data_i, input logic [7:0] keep_i, input logic last_i);
    begin
      @(negedge clk);
      input_data  = data_i;
      input_keep  = keep_i;
      input_last  = last_i;
      input_valid = 1'b1;
      @(posedge clk);
      while (!input_ready) @(posedge clk);
      @(negedge clk);
      input_valid = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && output_axis.tvalid && output_axis.tready) begin
      if (output_beats == 0) begin
        if (output_axis.tdata != 64'ha2a1a00504030201 || output_axis.tkeep != 8'hff ||
            output_axis.tlast) begin
          $fatal(1, "joined full beat mismatch");
        end
      end else if (output_beats == 1) begin
        if (output_axis.tdata[15:0] != 16'hd9ff || output_axis.tkeep != 8'h03 ||
            !output_axis.tlast) begin
          $fatal(1, "joined final beat mismatch");
        end
      end else begin
        $fatal(1, "unexpected joined output beat");
      end
      output_beats <= output_beats + 1;
    end
  end

  initial begin
    input_data         = '0;
    input_keep         = '0;
    input_valid        = 1'b0;
    input_last         = 1'b0;
    output_axis.tready = 1'b0;
    output_beats       = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    send_beat(64'h0000000504030201, 8'h1f, 1'b0);
    send_beat(64'h0000000000a2a1a0, 8'h07, 1'b0);
    repeat (2) @(negedge clk);
    if (!output_axis.tvalid || output_axis.tdata != 64'ha2a1a00504030201) begin
      $fatal(1, "full output was not held under backpressure: valid=%0d data=%h keep=%h",
             output_axis.tvalid, output_axis.tdata, output_axis.tkeep);
    end
    output_axis.tready = 1'b1;
    send_beat(64'h000000000000d9ff, 8'h03, 1'b1);
    while (output_beats < 2) @(negedge clk);
    if (error_flag) $fatal(1, "unexpected byte joiner error");
    $display("JPEG byte joiner tests passed");
    $finish;
  end
endmodule
