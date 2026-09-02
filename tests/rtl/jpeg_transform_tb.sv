// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_transform_tb;
  logic          clk;
  logic          rst_n;
  logic          start;
  logic          inverse;
  logic [1535:0] block_in;
  logic          start_ready;
  logic [1535:0] block_out;
  logic          result_valid;
  logic          result_ready;

  jpeg_transform u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .inverse_i     (inverse),
      .block_i       (block_in),
      .start_ready_o (start_ready),
      .block_o       (block_out),
      .result_valid_o(result_valid),
      .result_ready_i(result_ready)
  );

  always #5 clk = ~clk;

  task automatic run_transform(input logic direction_i);
    begin
      @(negedge clk);
      inverse = direction_i;
      start   = 1'b1;
      @(negedge clk);
      start = 1'b0;
      while (!result_valid) @(negedge clk);
    end
  endtask

  function automatic logic signed [15:0] expected_coefficient(input int index_i);
    begin
      case (index_i)
        0:       expected_coefficient = -16'sd4;
        1:       expected_coefficient = -16'sd17;
        3:       expected_coefficient = -16'sd3;
        8:       expected_coefficient = -16'sd146;
        24:      expected_coefficient = -16'sd15;
        40:      expected_coefficient = -16'sd5;
        56:      expected_coefficient = -16'sd1;
        default: expected_coefficient = 16'sd0;
      endcase
    end
  endfunction

  initial begin
    clk          = 1'b0;
    rst_n        = 1'b0;
    start        = 1'b0;
    inverse      = 1'b0;
    block_in     = '0;
    result_ready = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    for (int index = 0; index < 64; index++) begin
      block_in[index*24+:24] = 24'(index - 32);
    end
    run_transform(1'b0);
    for (int index = 0; index < 64; index++) begin
      if ($signed(block_out[index*24+:24]) != expected_coefficient(index)) begin
        $fatal(1, "forward transform mismatch at %0d: %0d", index, $signed(
                                                                       block_out[index*24+:24]));
      end
    end

    block_in     = block_out;
    result_ready = 1'b1;
    @(negedge clk);
    result_ready = 1'b0;
    run_transform(1'b1);
    for (int index = 0; index < 64; index++) begin
      if (($signed(
              block_out[index*24+:24]
          ) < (index - 33)) || ($signed(
              block_out[index*24+:24]
          ) > (index - 31))) begin
        $fatal(1, "inverse transform mismatch at %0d: %0d", index, $signed(
                                                                       block_out[index*24+:24]));
      end
    end
    result_ready = 1'b1;
    @(negedge clk);
    $display("JPEG transform tests passed");
    $finish;
  end
endmodule
