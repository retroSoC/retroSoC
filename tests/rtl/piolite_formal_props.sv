module piolite_formal_props (
    input wire       clk_i,
    input wire       rst_n_i,
    input wire       push_i,
    input wire       pop_i,
    input wire       push_accept_i,
    input wire       pop_accept_i,
    input wire       full_i,
    input wire       empty_i,
    input wire [3:0] count_i
);
  reg past_valid = 1'b0;
  always @(posedge clk_i) begin
    past_valid <= rst_n_i;
    if (rst_n_i) begin
      assert (count_i <= 8);
      assert (full_i == (count_i == 8));
      assert (empty_i == (count_i == 0));
      assert (push_accept_i == (push_i && !full_i));
      assert (pop_accept_i == (pop_i && !empty_i));
      if (past_valid) begin
        if ($past(full_i && push_i && pop_i && !empty_i)) begin
          assert (!$past(push_accept_i));
          assert ($past(pop_accept_i));
        end
        if ($past(empty_i && push_i && pop_i)) begin
          assert ($past(push_accept_i));
          assert (!$past(pop_accept_i));
        end
        case ({
          $past(push_accept_i), $past(pop_accept_i)
        })
          2'b10:   assert (count_i == $past(count_i) + 1);
          2'b01:   assert (count_i == $past(count_i) - 1);
          default: assert (count_i == $past(count_i));
        endcase
      end
      cover (full_i);
      cover (empty_i);
      cover (push_accept_i && pop_accept_i);
    end
  end
endmodule
