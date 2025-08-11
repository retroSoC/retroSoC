module user_ip_design (
    input  logic        clk_i,
    input  logic        rst_n_i,
    output logic [15:0] gpio_out_o,
    input  logic [15:0] gpio_in_i,
    output logic [15:0] gpio_oeb_o,
    input  logic [31:0] apb_paddr_i,
    input  logic [ 2:0] apb_pprot_i,
    input  logic        apb_psel_i,
    input  logic        apb_penable_i,
    input  logic        apb_pwrite_i,
    input  logic [31:0] apb_pwdata_i,
    input  logic [ 3:0] apb_pstrb_i,
    output logic        apb_pready_o,
    output logic [31:0] apb_prdata_o
);

  assign gpio_out_o   = '0;
  assign gpio_oeb_o   = '0;
  assign apb_pready_o = '0;
  assign apb_prdata_o = '0;

endmodule
