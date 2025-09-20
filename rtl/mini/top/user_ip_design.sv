
module user_ip_design #(
    parameter int ID = 8'd255
) (
    // verilog_format: off
    input logic      clk_i,
    input logic      rst_n_i,
    user_gpio_if.dut gpio,
    apb4_if.slave    apb
    // verilog_format: on
);

  // ========== USER CUSTOM AREA ==========
  // NOTE: define constants by using 'localparam'
  localparam USER_IP_APB_ID = 8'h00;
  localparam USER_IP_APB_XX = 8'h04;
  // wire
  logic s_apb_wr_hdshk, s_apb_rd_hdshk;

  assign s_apb_wr_hdshk = apb.psel && apb.penable && apb.pwrite;
  assign s_apb_rd_hdshk = apb.psel && apb.penable && (~apb.pwrite);
  assign apb.pready     = 1'b1;
  assign apb.pslverr    = 1'b0;

  always_comb begin
    apb.rdata = '0;
    if (s_apb_rd_hdshk) begin
      unique case (apb4.addr[7:0])
        USER_IP_APB_ID: apb4.rdata = {24'd0, ID};
        default:        apb4.rdata = '0;
      endcase
    end
  end

  assign gpio.gpio_out = '0;
  assign gpio.gpio_oen = '0;

  // INSTANCE USER CUSTOM DESIGN HERE!!!!

endmodule
