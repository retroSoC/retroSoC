// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_loader_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i, f_past_valid;
  wire [2:0] scenario;
  wire [1:0] request_count;
  wire [6:0] cycle;
  wire [7:0] status;
  wire lock, store_write, load_done, abort_done, fault_valid;
  wire abort_seen, fault_seen, load_seen, store_seen;
  wire [10:0] store_addr;
  wire [ 5:0] fault_code;
  wire [ 3:0] fault_stage;
  wire [ 1:0] fault_resp;
  wire [31:0] fault_addr, fault_detail, actual_crc;

  apu_loader_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (!(status[0] && (|status[7:1])));
      assert (request_count <= 2'd3);
      if (store_write) begin
        assert (status[0]);
        assert (request_count == 2'd3);
        assert (store_addr[10:0] == store_addr);
      end
      if (load_done) assert (status[1] && lock);
      if (abort_seen || fault_seen) assert (!status[1] && !lock && !load_seen);
      if (load_seen) assert (store_seen && status[1] && lock);
      if (scenario == 3'd0) begin
        assert (!fault_valid || (fault_code != 6'd9));
      end else if (scenario == 3'd1) begin
        if (fault_valid) begin
          assert (status[3] && !lock && !store_seen && (request_count == 2'd1));
          assert ((fault_code == 6'd9) && (fault_stage == 4'd1) && (fault_resp == 2'd0));
          assert ((fault_addr == 32'h0000_1014) && (fault_detail == 32'd204));
          assert (actual_crc == 32'd0);
        end
      end else if (scenario == 3'd2) begin
        if (fault_valid) begin
          assert (status[3] && !lock && !store_seen && (request_count == 2'd2));
          assert ((fault_code == 6'd9) && (fault_stage == 4'd1) && (fault_resp == 2'd0));
          assert ((fault_addr == 32'h0000_1054) && (fault_detail == 32'd0));
          assert (actual_crc == 32'd0);
        end
      end else if (scenario == 3'd3) begin
        if (fault_valid) begin
          assert (status[6] && !lock && (fault_code == 6'd10));
          assert ((fault_stage == 4'd1) && (fault_resp == 2'd0) && (fault_addr == 32'h0000_102c));
        end
      end else if (scenario == 3'd4) begin
        if (fault_valid) begin
          assert (status[4] && !lock && (fault_code == 6'd9));
          assert ((fault_stage == 4'd1) && (fault_resp == 2'd0) && (fault_addr == 32'h0000_10c0));
          assert (fault_detail[7:0] == 8'd3);
        end
      end else if (scenario == 3'd6) begin
        if (fault_valid) begin
          assert (!lock && (fault_code == 6'd21) && (fault_stage == 4'd11));
        end
      end
    end
    if (f_past_valid && $past(rst_n_i) && $past(status[0]) && !load_done) begin
      assert (!status[1]);
    end
    cover (rst_n_i &&
           (((scenario == 3'd0) && load_seen && store_seen && status[1] && lock) ||
            ((scenario == 3'd1) && fault_valid && status[3]) ||
            ((scenario == 3'd2) && fault_valid && status[3]) ||
            ((scenario == 3'd3) && fault_valid && status[6]) ||
            ((scenario == 3'd4) && fault_valid && status[4]) ||
            ((scenario == 3'd5) && abort_seen) ||
            ((scenario == 3'd6) && fault_seen)));
  end
endmodule
