// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_sequencer_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i, f_past_valid;
  wire [1:0] scenario;
  wire [5:0] cycle;
  wire [31:0] status, retired, result;
  wire trapped, trap_event, abort_done, trap_seen, abort_seen, idle, fault_valid;
  wire [5:0] fault_code;
  wire [3:0] fault_stage;
  wire [1:0] fault_resp;
  wire [7:0] fault_index;
  wire [31:0] fault_addr, fault_detail;

  apu_sequencer_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (status[31:21] == 11'd0);
      assert (status[10:0] <= 11'd6);
      assert (retired <= 32'd16);
      if (trap_event) begin
        assert (trapped && fault_valid);
        assert (fault_code == 6'd11);
        assert (fault_stage == 4'd11);
        assert (fault_resp == 2'd0);
        assert (fault_index == 8'd0);
        assert (fault_addr == ({21'd0, status[10:0]} << 3));
      end
      if (cycle >= 6'd36) begin
        assert (idle);
        if (scenario == 2'd0) begin
          assert (!trapped && (retired == 32'd4) && (result == 32'd5));
        end else if (scenario == 2'd1) begin
          assert (trap_seen && trapped && (retired == 32'd0));
          assert (fault_detail[7:0] == 8'd7);
        end else if (scenario == 2'd2) begin
          assert (abort_seen && !trapped);
        end else begin
          assert (!trapped && (retired == 32'd9));
        end
      end
    end
    if (f_past_valid && $past(rst_n_i) && $past(idle) && (cycle > 6'd2)) begin
      assert ($stable(status));
      assert ($stable(retired));
      assert ($stable(trapped));
    end
    cover (rst_n_i && idle && (scenario == 2'd0) && (retired == 32'd4));
    cover (rst_n_i && trap_seen && (scenario == 2'd1));
    cover (rst_n_i && abort_seen && (scenario == 2'd2));
    cover (rst_n_i && idle && (scenario == 2'd3) && (retired == 32'd9));
  end
endmodule
