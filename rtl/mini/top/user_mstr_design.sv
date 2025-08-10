module user_mstr_design (
    (* keep *) input  logic        clk_i,
    (* keep *) input  logic        rst_n_i,
    (* keep *) output logic        core_valid_o,
    (* keep *) output logic [31:0] core_addr_o,
    (* keep *) output logic [31:0] core_wdata_o,
    (* keep *) output logic [ 3:0] core_wstrb_o,
    (* keep *) input  logic [31:0] core_rdata_i,
    (* keep *) input  logic        core_ready_i,
    (* keep *) input  logic [31:0] irq_i
);

  // balabala
  assign core_valid_o = '0;
  assign core_addr_o  = '0;
  assign core_wdata_o = '0;
  assign core_wstrb_o = '0;
endmodule
