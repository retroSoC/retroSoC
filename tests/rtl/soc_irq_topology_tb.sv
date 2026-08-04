`timescale 1ns / 1ps

`include "soc_irq_config.svh"

module soc_irq_topology_tb;
  logic [`SOC_IRQ_VECTOR_WIDTH-1:0] s_irq;
  logic [  `SOC_IRQ_RIBP_WIDTH-1:0] s_ribp_irq;
  logic [   `SOC_IRQ_APB_WIDTH-1:0] s_apb_irq;

  `include "soc_irq_wiring.svh"

  task automatic expect_irq(input logic [`SOC_IRQ_VECTOR_WIDTH-1:0] expected);
    begin
      #1;
      if (s_irq !== expected) begin
        $fatal(1, "unexpected IRQ vector: got %h, expected %h", s_irq, expected);
      end
    end
  endtask

  initial begin
    s_ribp_irq = '0;
    s_apb_irq  = '0;
    expect_irq('0);

    for (int bit_index = 0; bit_index < `SOC_IRQ_RIBP_WIDTH; bit_index++) begin
      s_ribp_irq            = '0;
      s_ribp_irq[bit_index] = 1'b1;
      s_apb_irq             = '0;
      expect_irq(32'd1 << bit_index);
    end

    for (int bit_index = 0; bit_index < `SOC_IRQ_APB_WIDTH; bit_index++) begin
      s_ribp_irq           = '0;
      s_apb_irq            = '0;
      s_apb_irq[bit_index] = 1'b1;
      expect_irq(32'd1 << (10 + bit_index));
    end

    if (s_irq[31:17] !== '0) begin
      $fatal(1, "unallocated core IRQ bits are not low: %h", s_irq[31:17]);
    end

    $display("SoC topology IRQ routing test passed");
    $finish;
  end
endmodule
