`timescale 1ns / 1ps

module gpio_pad_caps_tb #(
    parameter bit ExpectedInputCmos = 1'b0,
    parameter bit ExpectedPullUp    = 1'b0,
    parameter bit ExpectedPullDown  = 1'b0
);

  initial begin
    if ((gpio_pad_caps_pkg::HasInputCmos !== ExpectedInputCmos) ||
        (gpio_pad_caps_pkg::HasPullUp !== ExpectedPullUp) ||
        (gpio_pad_caps_pkg::HasPullDown !== ExpectedPullDown)) begin
      $fatal(1, "GPIO pad capability matrix mismatch");
    end
    $display("GPIO pad capability matrix test passed");
    $finish;
  end

endmodule
