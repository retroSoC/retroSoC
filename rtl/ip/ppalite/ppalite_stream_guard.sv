module ppalite_stream_guard (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        clear_i,
    input  logic        flush_i,
    input  logic        active_i,
    input  logic [15:0] width_i,
    input  logic [15:0] height_i,
    input  logic        valid_i,
    output logic        ready_o,
    input  logic [31:0] data_i,
    input  logic [ 3:0] keep_i,
    input  logic [ 3:0] strb_i,
    input  logic        id_i,
    input  logic        dest_i,
    input  logic        user_i,
    input  logic        last_i,
    output logic        slot_valid_o,
    input  logic        slot_pop_i,
    output logic [31:0] slot_data_o,
    output logic        slot_halfword_o,
    output logic        input_done_o,
    output logic        input_done_event_o,
    output logic        framing_event_o,
    output logic [31:0] framing_position_o,
    output logic        excess_o,
    output logic [31:0] excess_position_o,
    output logic [31:0] input_words_o,
    output logic [31:0] stall_cycles_o,
    output logic [ 1:0] level_o,
    output logic [ 7:0] err_o,
    output logic [31:0] err_position_o
);
  logic        s_full;
  logic        s_empty;
  logic        s_done_q;
  logic [15:0] s_x_q;
  logic [15:0] s_y_q;
  logic        s_expected_last;
  logic [ 3:0] s_expected_keep;
  logic        s_framing_err;
  logic        s_excess_err;
  logic        s_accept;
  logic [32:0] s_slot_data;

  assign s_expected_last = ({1'b0, s_x_q} + 17'd2 >= {1'b0, width_i});
  assign s_expected_keep = (s_expected_last && width_i[0]) ? 4'h3 : 4'hf;
  assign s_framing_err = (keep_i != strb_i) || (keep_i != s_expected_keep) ||
      (last_i != s_expected_last) || (user_i != (input_words_o == 32'd0)) || id_i || dest_i;
  assign s_excess_err = valid_i && s_done_q;
  assign framing_event_o = valid_i && !s_done_q && s_framing_err;
  assign framing_position_o = {s_y_q, s_x_q};
  assign excess_o = s_excess_err;
  assign excess_position_o = {s_y_q, s_x_q};
  assign ready_o = active_i && !s_done_q && !s_full && (err_o == 8'd0) && !s_framing_err;
  assign s_accept = valid_i && ready_o && !s_framing_err;
  assign input_done_o = s_done_q;
  assign input_done_event_o = valid_i && !s_done_q && !s_full && (err_o == 8'd0) &&
      !s_framing_err && last_i && ({1'b0, s_y_q} + 17'd1 == {1'b0, height_i});
  assign slot_halfword_o = s_slot_data[32];
  assign slot_data_o = s_slot_data[31:0];

  logic        s_done_d;
  logic [15:0] s_x_d;
  logic [15:0] s_y_d;
  logic [31:0] s_input_words_d;
  logic [31:0] s_stall_cycles_d;
  logic [ 7:0] s_err_d;
  logic [31:0] s_err_position_d;

  always_comb begin
    s_done_d         = s_done_q;
    s_x_d            = s_x_q;
    s_y_d            = s_y_q;
    s_input_words_d  = input_words_o;
    s_stall_cycles_d = stall_cycles_o;
    s_err_d          = err_o;
    s_err_position_d = err_position_o;
    if (!rst_n_i || clear_i) begin
      s_done_d         = 1'b0;
      s_x_d            = 16'd0;
      s_y_d            = 16'd0;
      s_input_words_d  = 32'd0;
      s_stall_cycles_d = 32'd0;
      s_err_d          = 8'd0;
      s_err_position_d = 32'd0;
    end else begin
      if (s_excess_err && (err_o == 8'd0)) begin
        s_err_d          = 8'd4;
        s_err_position_d = {s_y_q, s_x_q};
      end else if (valid_i && active_i && !s_done_q && s_framing_err && (err_o == 8'd0)) begin
        s_err_d          = 8'd3;
        s_err_position_d = {s_y_q, s_x_q};
      end
      if (s_accept) begin
        s_input_words_d = input_words_o + 32'd1;
        if (last_i) begin
          s_x_d = 16'd0;
          s_y_d = s_y_q + 16'd1;
          if ({1'b0, s_y_q} + 17'd1 == {1'b0, height_i}) s_done_d = 1'b1;
        end else begin
          s_x_d = s_x_q + 16'd2;
        end
      end
      if (valid_i && !ready_o && !s_done_q && (stall_cycles_o != 32'hffff_ffff)) begin
        s_stall_cycles_d = stall_cycles_o + 32'd1;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_done_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_done_d),
      .dat_o  (s_done_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_x_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_x_d),
      .dat_o  (s_x_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_y_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_y_d),
      .dat_o  (s_y_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_input_words_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_input_words_d),
      .dat_o  (input_words_o)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_stall_cycles_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stall_cycles_d),
      .dat_o  (stall_cycles_o)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_err_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (err_o)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_err_position_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_position_d),
      .dat_o  (err_position_o)
  );

  ppalite_fifo #(
      .DataWidth  (33),
      .BufferDepth(2)
  ) u_input_fifo (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .flush_i    (flush_i),
      .push_i     (s_accept),
      .push_data_i({(s_expected_keep == 4'h3), data_i}),
      .pop_i      (slot_pop_i),
      .pop_data_o (s_slot_data),
      .full_o     (s_full),
      .empty_o    (s_empty),
      .count_o    (level_o)
  );
  assign slot_valid_o = !s_empty;
`ifdef FORMAL
  logic s_formal_past_q;
  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_formal_past_q <= 1'b0;
    end else begin
      s_formal_past_q <= 1'b1;
      if (s_formal_past_q && !clear_i && $past(!clear_i && s_excess_err && (err_o == 8'd0))) begin
        assert ((err_o == 8'd4) && (err_position_o == $past({s_y_q, s_x_q})));
      end
    end
  end
`endif
endmodule
