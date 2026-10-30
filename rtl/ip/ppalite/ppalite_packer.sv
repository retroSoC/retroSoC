module ppalite_packer (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        flush_i,
    input  logic        gray8_i,
    input  logic [31:0] row_bytes_i,
    input  logic        valid_i,
    output logic        ready_o,
    input  logic        sel_i,
    input  logic        line_sel_i,
    input  logic        line_end_i,
    input  logic [15:0] sample_i,
    output logic        valid_o,
    input  logic        ready_i,
    output logic [31:0] data_o,
    output logic [ 3:0] keep_o,
    output logic [ 3:0] strb_o,
    output logic        last_o,
    output logic        id_o,
    output logic        dest_o,
    output logic        user_o,
    output logic [ 3:0] level_o,
    output logic        idle_o
);
  logic [31:0] s_pack_d;
  logic [31:0] s_pack_q;
  logic [ 2:0] s_count_d;
  logic [ 2:0] s_count_q;
  logic [31:0] s_row_count_d;
  logic [31:0] s_row_count_q;
  logic        s_sof_q;
  logic        s_push;
  logic [31:0] s_push_data;
  logic        s_push_last;
  logic        s_full;
  logic        s_empty;
  logic        s_pop;
  logic [33:0] s_pop_data;

  always_comb begin
    s_pack_d      = s_pack_q;
    s_count_d     = s_count_q;
    s_row_count_d = s_row_count_q;
    s_push        = 1'b0;
    s_push_data   = 32'd0;
    s_push_last   = 1'b0;
    if (valid_i) begin
      if (sel_i) begin
        if (gray8_i) begin
          s_pack_d[s_count_q*8+:8] = sample_i[7:0];
          s_count_d                = s_count_q + 3'd1;
          s_row_count_d            = s_row_count_q + 32'd1;
        end else begin
          s_pack_d[s_count_q*8+:16] = sample_i;
          s_count_d                 = s_count_q + 3'd2;
          s_row_count_d             = s_row_count_q + 32'd2;
        end
      end
      if (line_end_i) begin
        if (line_sel_i) begin
          s_push      = 1'b1;
          s_push_data = s_pack_d;
          s_push_last = 1'b1;
        end
        s_pack_d      = 32'd0;
        s_count_d     = 3'd0;
        s_row_count_d = 32'd0;
      end else if ((s_count_d == 3'd4) && (s_row_count_d != row_bytes_i)) begin
        s_push      = 1'b1;
        s_push_data = s_pack_d;
        s_pack_d    = 32'd0;
        s_count_d   = 3'd0;
      end
    end
    ready_o = !s_full;
  end

  assign s_pop   = valid_o && ready_i;
  assign valid_o = !s_empty;
  assign data_o  = s_pop_data[31:0];
  assign last_o  = s_pop_data[32];
  assign user_o  = s_pop_data[33];
  assign keep_o  = 4'hf;
  assign strb_o  = 4'hf;
  assign id_o    = 1'b0;
  assign dest_o  = 1'b0;
  assign idle_o  = s_empty && (s_count_q == 3'd0);

  dffr #(
      .DATA_WIDTH(32)
  ) u_pack_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (flush_i ? 32'd0 : s_pack_d),
      .dat_o  (s_pack_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_count_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (flush_i ? 3'd0 : s_count_d),
      .dat_o  (s_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_row_count_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (flush_i ? 32'd0 : s_row_count_d),
      .dat_o  (s_row_count_q)
  );
  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_sof_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (flush_i ? 1'b1 : (s_sof_q && !(valid_i && ready_o && s_push))),
      .dat_o  (s_sof_q)
  );

  ppalite_fifo #(
      .DataWidth  (34),
      .BufferDepth(8)
  ) u_output_fifo (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .flush_i    (flush_i),
      .push_i     (valid_i && ready_o && s_push),
      .push_data_i({s_sof_q, s_push_last, s_push_data}),
      .pop_i      (s_pop),
      .pop_data_o (s_pop_data),
      .full_o     (s_full),
      .empty_o    (s_empty),
      .count_o    (level_o)
  );
endmodule
