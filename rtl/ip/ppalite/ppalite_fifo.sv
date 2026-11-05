module ppalite_fifo #(
    parameter int DataWidth   = 32,
    parameter int BufferDepth = 8,
    parameter int CountWidth  = $clog2(BufferDepth)
) (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 flush_i,
    input  logic                 push_i,
    input  logic [DataWidth-1:0] push_data_i,
    input  logic                 pop_i,
    output logic [DataWidth-1:0] pop_data_o,
    output logic                 full_o,
    output logic                 empty_o,
    output logic [ CountWidth:0] count_o
);
  logic s_push;
  logic s_pop;

  assign s_push = push_i && !full_o;
  assign s_pop  = pop_i && !empty_o;

  fifo #(
      .DATA_WIDTH      (DataWidth),
      .BUFFER_DEPTH    (BufferDepth),
      .LOG_BUFFER_DEPTH($clog2(BufferDepth))
  ) u_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .push_i (s_push),
      .full_o (full_o),
      .dat_i  (push_data_i),
      .pop_i  (s_pop),
      .empty_o(empty_o),
      .dat_o  (pop_data_o),
      .cnt_o  (count_o)
  );
`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_n_i && !flush_i) begin
      assert (count_o <= BufferDepth);
      assert (full_o == (count_o == BufferDepth));
      assert (empty_o == (count_o == 0));
      assert (s_push == (push_i && !full_o));
      assert (s_pop == (pop_i && !empty_o));
    end
  end
`endif
endmodule
