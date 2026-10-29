module piolite_fifo (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        flush_i,
    input  logic        push_i,
    input  logic [31:0] push_data_i,
    input  logic        pop_i,
    output logic [31:0] pop_data_o,
    output logic        push_accept_o,
    output logic        pop_accept_o,
    output logic        full_o,
    output logic        empty_o,
    output logic [ 3:0] count_o
);
  logic s_push_accept;
  logic s_pop_accept;

  // Common FIFO permits full push+pop; PIO-lite admits only pre-edge eligible operations.
  assign s_push_accept = push_i && !full_o;
  assign s_pop_accept  = pop_i && !empty_o;
  assign push_accept_o = s_push_accept;
  assign pop_accept_o  = s_pop_accept;

  fifo #(
      .DATA_WIDTH      (32),
      .BUFFER_DEPTH    (8),
      .LOG_BUFFER_DEPTH(3)
  ) u_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .push_i (s_push_accept),
      .full_o (full_o),
      .dat_i  (push_data_i),
      .pop_i  (s_pop_accept),
      .empty_o(empty_o),
      .dat_o  (pop_data_o),
      .cnt_o  (count_o)
  );
`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (count_o <= 4'd8);
      assert (full_o == (count_o == 4'd8));
      assert (empty_o == (count_o == 4'd0));
      assert (push_accept_o == (push_i && !full_o));
      assert (pop_accept_o == (pop_i && !empty_o));
    end
  end
`endif
endmodule
