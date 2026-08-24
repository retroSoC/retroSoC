// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module sysctrl_formal;

  localparam [7:0] SYSCTRL_IPSEL_OFFSET = 8'h04;
  localparam [7:0] SYSCTRL_PLL_CFG_OFFSET = 8'h08;
  localparam [7:0] SYSCTRL_PLL_CMD_OFFSET = 8'h0c;
  localparam [7:0] SYSCTRL_FAULT_STATUS_OFFSET = 8'h10;
  localparam [7:0] SYSCTRL_USER_CORE_RESET_OFFSET = 8'h20;
  localparam [7:0] SYSCTRL_TEST_STATUS_OFFSET = 8'h84;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire [ 7:0] ip_sel;
  wire [ 4:0] core_sel;
  wire [31:0] user_reset;
  wire [31:0] user_reset_mask;
  wire [ 5:0] user_core_count;
  wire        user_bus_enable;
  wire        user_config_error;
  wire [ 2:0] pll_cfg;
  wire        pll_req_valid;
  wire        pll_req_ready;
  wire        pll_busy;
  wire        pll_error;
  wire [ 1:0] pll_error_reason;
  wire        pll_rsp_valid;
  wire        fault_valid;
  wire [31:0] fault_addr;
  wire [ 3:0] fault_wstrb;
  wire        fault_reserved;
  wire        fault_pending;
  wire        fault_write;
  wire [ 2:0] fault_reason;
  wire [31:0] fault_addr_q;
  wire [31:0] fault_count;
  wire        test_done;
  wire        test_pass;
  wire [ 7:0] test_code;

  sysctrl_formal_design u_design (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .f_past_valid     (f_past_valid),
      .rib_valid        (rib_valid),
      .rib_addr         (rib_addr),
      .rib_wdata        (rib_wdata),
      .rib_wstrb        (rib_wstrb),
      .rib_ready        (rib_ready),
      .ip_sel           (ip_sel),
      .core_sel         (core_sel),
      .user_reset       (user_reset),
      .user_reset_mask  (user_reset_mask),
      .user_core_count  (user_core_count),
      .user_bus_enable  (user_bus_enable),
      .user_config_error(user_config_error),
      .pll_cfg          (pll_cfg),
      .pll_req_valid    (pll_req_valid),
      .pll_req_ready    (pll_req_ready),
      .pll_busy         (pll_busy),
      .pll_error        (pll_error),
      .pll_error_reason (pll_error_reason),
      .pll_rsp_valid    (pll_rsp_valid),
      .fault_valid      (fault_valid),
      .fault_addr       (fault_addr),
      .fault_wstrb      (fault_wstrb),
      .fault_reserved   (fault_reserved),
      .fault_pending    (fault_pending),
      .fault_write      (fault_write),
      .fault_reason     (fault_reason),
      .fault_addr_q     (fault_addr_q),
      .fault_count      (fault_count),
      .test_done        (test_done),
      .test_pass        (test_pass),
      .test_code        (test_code)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end
    if (rst_n_i && pll_rsp_valid) begin
      assume (pll_busy);
    end

    if (rst_n_i && f_past_valid) begin
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] &&
                rib_addr[7:0] == 8'h00 && rib_wdata[4:0] < user_core_count &&
                user_reset == user_reset_mask && !user_bus_enable
          )) begin
        assert (core_sel == $past(rib_wdata[4:0]));
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] &&
                rib_addr[7:0] == 8'h00 && rib_wdata[4:0] >= user_core_count
          )) begin
        assert (core_sel == $past(core_sel));
        assert (user_config_error);
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] &&
                rib_addr[7:0] == SYSCTRL_USER_CORE_RESET_OFFSET &&
                (rib_wdata & user_reset_mask) == user_reset_mask
          )) begin
        assert (user_reset == user_reset_mask);
        assert (!user_bus_enable);
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && |rib_wstrb &&
                rib_addr[7:0] == SYSCTRL_IPSEL_OFFSET
          )) begin
        assert (ip_sel == $past(rib_wdata[7:0]));
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] &&
                rib_addr[7:0] == SYSCTRL_PLL_CFG_OFFSET
          )) begin
        assert (pll_cfg == $past(rib_wdata[2:0]));
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] && rib_wdata[0] &&
                rib_addr[7:0] == SYSCTRL_PLL_CMD_OFFSET && !pll_busy && !pll_req_valid
          )) begin
        assert (pll_busy);
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] && rib_wdata[0] &&
                rib_addr[7:0] == SYSCTRL_PLL_CMD_OFFSET && pll_busy
          )) begin
        assert (pll_error);
        if (!$past(pll_rsp_valid)) begin
          assert (pll_error_reason == 2'd3);
        end
      end
      if ($past(rst_n_i && fault_valid)) begin
        assert (fault_pending);
        if (!$past(fault_pending)) begin
          assert (fault_write == (|$past(fault_wstrb)));
          assert (fault_reason == ($past(fault_reserved) ? 3'd2 : 3'd1));
          assert (fault_addr_q == $past(fault_addr));
        end
        if (!$past(&fault_count)) begin
          assert (fault_count == $past(fault_count) + 32'd1);
        end
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb[0] && rib_wdata[0] &&
                rib_addr[7:0] == SYSCTRL_FAULT_STATUS_OFFSET && !fault_valid
          )) begin
        assert (!fault_pending);
      end
      if ($past(
              rst_n_i && rib_valid && !rib_ready && rib_wstrb == 4'hF && rib_wdata[31] &&
                rib_addr[7:0] == SYSCTRL_TEST_STATUS_OFFSET && !test_done
          )) begin
        assert (test_done);
        assert (test_pass == $past(rib_wdata[0]));
        assert (test_code == $past(rib_wdata[15:8]));
      end
      if ($past(
              rst_n_i && !test_done &&
                !(rib_valid && !rib_ready && rib_wstrb == 4'hF && rib_wdata[31] &&
                    rib_addr[7:0] == SYSCTRL_TEST_STATUS_OFFSET)
          )) begin
        assert (!test_done);
      end
      if ($past(rst_n_i && test_done)) begin
        assert (test_done);
        assert (test_pass == $past(test_pass));
        assert (test_code == $past(test_code));
      end
    end

    if (rst_n_i) begin
      cover (pll_busy && pll_req_valid);
      cover (pll_error && pll_error_reason == 2'd3);
      cover (fault_pending && fault_reason == 2'd2);
    end
  end

endmodule
