`ifndef NATV_I2S_DEF_SV
`define NATV_I2S_DEF_SV

// verilog_format: off
`define NATV_I2S_CLKDIV  8'h00
`define NATV_I2S_DEVADDR 8'h04
// verilog_format: on

interface nv_i2s_if ();
  logic mclk_o;
  logic sclk_o;
  logic lrck_o;
  logic dacdat_o;
  logic adcdat_i;

  modport dut(output mclk_o, output sclk_o, output lrck_o, output dacdat_o, input adcdat_i);

endinterface

`endif

module nmi_i2s (
    // verilog_format: off
    input logic   clk_i,
    input logic   rst_n_i,
    nmi_if.slave  nmi,
    nv_i2s_if.dut i2s
    // verilog_format: on
);

  i2s_core u_i2s_core (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .i2s    (i2s)
  );
endmodule
