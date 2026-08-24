// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module timer_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire        rib_resp_err;
  wire        debug_halted;
  wire        active;
  wire        debug_frozen;
  wire [31:0] value;
  wire        start;
  wire        stop;
  wire        load_now;
  wire        timeout_event;
  wire        compare0_event;
  wire        compare1_event;
  wire        one_shot_done;
  wire [ 2:0] intr_state;
  wire [ 2:0] intr_enable;
  wire        irq;

  timer_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end

    if (rst_n_i) begin
      assert (irq == |(intr_state & intr_enable));
      if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
        assert (rib_ready);
      end
      if (f_past_valid && $past(rst_n_i && !active && !load_now)) begin
        assert (value == $past(value));
      end
      if (f_past_valid && $past(rst_n_i && debug_frozen && !load_now && !stop)) begin
        assert (value == $past(value));
      end
      if (f_past_valid && $past(rst_n_i && timeout_event)) begin
        assert (intr_state[0]);
      end
      if (f_past_valid && $past(rst_n_i && compare0_event)) begin
        assert (intr_state[1]);
      end
      if (f_past_valid && $past(rst_n_i && compare1_event)) begin
        assert (intr_state[2]);
      end
      if (f_past_valid && $past(rst_n_i && one_shot_done)) begin
        assert (!active);
      end

      cover (start);
      cover (debug_frozen && debug_halted);
      cover (timeout_event);
      cover (compare0_event && compare1_event);
      cover (irq);
      cover (rib_ready && rib_resp_err);
    end
  end

endmodule
