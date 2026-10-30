`timescale 1ns / 1ps
module ppalite_bfm_selftest_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        in_valid;
  logic        in_ready;
  logic [31:0] in_data;
  logic [ 3:0] in_keep;
  logic [ 3:0] in_strb;
  logic        in_id;
  logic        in_dest;
  logic        in_user;
  logic        in_last;
  logic        out_valid;
  logic        out_ready;
  logic [31:0] out_data;
  logic [ 3:0] out_keep;
  logic [ 3:0] out_strb;
  logic        out_last;
  logic        out_id;
  logic        out_dest;
  logic        out_user;
  logic [31:0] input_count;
  logic [31:0] output_count;
  always #5 clk_i = ~clk_i;

  ppalite_stream_bfm u_bfm (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .in_valid_o       (in_valid),
      .in_ready_i       (in_ready),
      .in_data_o        (in_data),
      .in_keep_o        (in_keep),
      .in_strb_o        (in_strb),
      .in_id_o          (in_id),
      .in_dest_o        (in_dest),
      .in_user_o        (in_user),
      .in_last_o        (in_last),
      .out_valid_i      (out_valid),
      .out_ready_o      (out_ready),
      .out_data_i       (out_data),
      .out_keep_i       (out_keep),
      .out_strb_i       (out_strb),
      .out_last_i       (out_last),
      .out_id_i         (out_id),
      .out_dest_i       (out_dest),
      .out_user_i       (out_user),
      .input_accepted_o (input_count),
      .output_accepted_o(output_count)
  );

  initial begin
    in_ready  = 1'b0;
    out_valid = 1'b0;
    out_data  = 32'd0;
    out_keep  = 4'hf;
    out_strb  = 4'hf;
    out_last  = 1'b0;
    out_id    = 1'b0;
    out_dest  = 1'b0;
    out_user  = 1'b0;
    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    if (u_bfm.sidebands_valid(4'hf, 4'hf, 1'b0, 1'b0) !== 1'b1)
      $fatal(1, "PPALITE BFM rejected valid sidebands");
`ifndef VERILATOR
    if (u_bfm.sidebands_valid(4'hf, 4'hf, 1'bx, 1'b0) !== 1'b0)
      $fatal(1, "PPALITE BFM accepted unknown ID");
    if (u_bfm.sidebands_valid(4'hf, 4'hf, 1'b0, 1'bx) !== 1'b0)
      $fatal(1, "PPALITE BFM accepted unknown DEST");
    if (u_bfm.sidebands_valid(4'hf, 4'hx, 1'b0, 1'b0) !== 1'b0)
      $fatal(1, "PPALITE BFM accepted unknown STRB");
    $display("PPALITE_P1_COVER PPL-V07 four-state-sideband-rejection");
`endif
    $display("PPALITE_P1_PASS ppalite_bfm_selftest_tb");
    $finish;
  end
endmodule
