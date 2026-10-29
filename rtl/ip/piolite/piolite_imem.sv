module piolite_imem (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        clear_valid_i,
    input  logic        write_i,
    input  logic [ 4:0] write_addr_i,
    input  logic [15:0] write_data_i,
    input  logic [ 4:0] sm0_addr_i,
    output logic [15:0] sm0_data_o,
    output logic        sm0_valid_o,
    input  logic [ 4:0] sm1_addr_i,
    output logic [15:0] sm1_data_o,
    output logic        sm1_valid_o,
    input  logic [ 4:0] apb_addr_i,
    output logic [15:0] apb_data_o,
    output logic [31:0] valid_o
);
  logic [15:0] s_payload_q[0:31];
  logic [31:0] s_valid_d;
  logic [31:0] s_valid_q;

  assign sm0_data_o  = s_payload_q[sm0_addr_i];
  assign sm0_valid_o = s_valid_q[sm0_addr_i];
  assign sm1_data_o  = s_payload_q[sm1_addr_i];
  assign sm1_valid_o = s_valid_q[sm1_addr_i];
  assign apb_data_o  = s_valid_q[apb_addr_i] ? s_payload_q[apb_addr_i] : 16'd0;
  assign valid_o     = s_valid_q;

  always_comb begin
    s_valid_d = s_valid_q;
    if (clear_valid_i) s_valid_d = 32'd0;
    else if (write_i) s_valid_d[write_addr_i] = 1'b1;
  end

  dffr #(
      .DATA_WIDTH(32)
  ) u_valid (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_valid_d),
      .dat_o  (s_valid_q)
  );

  // Validity alone hides stale payload; the small inferred payload array is not reset.
  always_ff @(posedge clk_i) begin
    if (write_i && !clear_valid_i) s_payload_q[write_addr_i] <= write_data_i;
  end
endmodule
