// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module gateway_a_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i, f_past_valid;
  wire [5:0] cycle;
  wire [2:0] response, seen;
  wire address_valid, address_ready;
  wire [31:0] address_value;
  wire address_accept, terminal;
  logic [1:0] f_expected_q;

  gateway_a_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      f_expected_q <= 2'd0;
    end else begin
      assert ($onehot0(response));
      if (response != 3'd0) begin
        case (f_expected_q)
          2'd0:    assert (response == 3'b001);
          2'd1:    assert (response == 3'b010);
          default: assert (response == 3'b100);
        endcase
        f_expected_q <= (f_expected_q == 2'd2) ? 2'd0 : f_expected_q + 1'b1;
      end
      if (cycle >= 6'd12) assert (seen == 3'b111);
      assert (terminal == (response != 3'd0));
    end

    if (f_past_valid && $past(rst_n_i) && $past(address_valid && !address_ready)) begin
      assert (address_valid);
      assert (address_value == $past(address_value));
    end

    cover (rst_n_i && (seen == 3'b111));
  end

  logic s_unused_observation;
  assign s_unused_observation = f_past_valid ^ address_accept;
endmodule
