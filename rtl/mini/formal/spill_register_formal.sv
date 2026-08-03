// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module spill_register_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        flush_i,
    output logic        valid_i,
    output logic        ready_o,
    output logic [31:0] data_i,
    output logic        valid_o,
    output logic        ready_i,
    output logic [31:0] data_o
);

  (* anyseq *)logic        f_flush;
  (* anyseq *)logic        f_valid;
  (* anyseq *)logic [31:0] f_data;
  (* anyseq *)logic        f_ready;

  assign flush_i = f_flush;
  assign valid_i = f_valid;
  assign data_i  = f_data;
  assign ready_i = f_ready;

  spill_register #(
      .DATA_WIDTH(32),
      .BYPASS    (1'b0)
  ) u_spill_register (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .valid_i(valid_i),
      .ready_o(ready_o),
      .data_i (data_i),
      .valid_o(valid_o),
      .ready_i(ready_i),
      .data_o (data_o)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
