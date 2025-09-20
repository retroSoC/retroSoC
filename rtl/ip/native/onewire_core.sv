module onewire_core (
    // verilog_format: off
    input logic    clk_i,
    input logic    rst_n_i,
    onewire_if.dut onewire
    // verilog_format: on
);

  assign onewire.dat_o = '0;
endmodule
