// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module spill_register_formal;
  (* anyseq *) (* gclk *)reg  clk_i;
  wire rst_n_i;
  wire f_past_valid;
  wire flush_i, valid_i, ready_o, valid_o, ready_i;
  wire [31:0] data_i, data_o;
  reg  [1:0] count;

  wire       push = valid_i && ready_o;
  wire       pop = valid_o && ready_i;

  spill_register_formal_design u_design (.*);

  initial begin
    count = 2'd0;
  end

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      count <= 2'd0;
    end else begin
      assume (!(flush_i && valid_i));
      if (f_past_valid && $past(rst_n_i && valid_i && !ready_o)) begin
        assume (valid_i);
        assume (data_i == $past(data_i));
      end

      assert (count <= 2'd2);
      assert (valid_o == (count != 2'd0));
      assert (ready_o == (count != 2'd2));
      if (f_past_valid && $past(rst_n_i && valid_o && !ready_i && !flush_i)) begin
        assert (valid_o);
        assert (data_o == $past(data_o));
      end

      if (flush_i) begin
        count <= 2'd0;
      end else begin
        case ({
          push, pop
        })
          2'b10: begin
            count <= count + 1'b1;
          end
          2'b01: begin
            count <= count - 1'b1;
          end
          2'b11:   count <= count;
          default: count <= count;
        endcase
      end

      cover (count == 2'd2 && !ready_i);
      cover (f_past_valid && $past(count == 2'd2 && ready_i) && count == 2'd1);
      cover (flush_i && count != 2'd0);
    end
  end
endmodule
