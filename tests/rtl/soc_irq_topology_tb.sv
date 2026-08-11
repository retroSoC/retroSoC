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

    for (int bit_index = 0; bit_index < 10; bit_index++) begin
      s_ribp_irq            = '0;
      s_ribp_irq[bit_index] = 1'b1;
      s_apb_irq             = '0;
      expect_irq(32'd1 << bit_index);
    end

    for (int bit_index = 10; bit_index < `SOC_IRQ_RIBP_WIDTH; bit_index++) begin
      s_ribp_irq            = '0;
      s_ribp_irq[bit_index] = 1'b1;
      expect_irq(32'd1 << (bit_index + 7));
    end

    for (int bit_index = 0; bit_index < `SOC_IRQ_APB_WIDTH; bit_index++) begin
      s_ribp_irq           = '0;
      s_apb_irq            = '0;
      s_apb_irq[bit_index] = 1'b1;
      case (bit_index)
        0:       expect_irq(32'd1 << 11);
        1:       expect_irq(32'd1 << 12);
        2:       expect_irq(32'd1 << 13);
        3:       expect_irq(32'd1 << 14);
        4:       expect_irq(32'd1 << 16);
        default: $fatal(1, "unexpected APB IRQ bit %0d", bit_index);
      endcase
    end

    s_apb_irq = '0;
    expect_irq('0);
    if (s_irq[10] !== 1'b0 || s_irq[15] !== 1'b0) begin
      $fatal(1, "removed core IRQ bits are not low: IRQ10=%b IRQ15=%b", s_irq[10], s_irq[15]);
    end
    if (s_irq[31:18] !== '0) begin
      $fatal(1, "unallocated core IRQ bits are not low: %h", s_irq[31:18]);
    end

    $display("SoC topology IRQ routing test passed");
    $finish;
  end
endmodule
