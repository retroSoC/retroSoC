// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


module DVP_CAMERA (
    output logic       pclk,
    output logic       href,
    output logic       vsync,
    output logic [7:0] data
);

  // verilog_format: off
  // QVGA format for ov7725
  localparam real PCLK_FREQ = 24.0;
  localparam int  TPCLK     = 1;
  localparam int  TP        = 2 * TPCLK;  // for RGB format
  localparam int  H_ACTIVE  = 320 * TP; // unit: TP
  localparam int  H_AFTBK   = 256 * TP; // unit: TP
  localparam int  H_TOTAL   = 576 * TP; // unit: TP
  localparam int  V_SYNC    = 4;   // unit: TLINE = H_TOTAL
  localparam int  V_BACK    = 22;  // unit: TLINE = H_TOTAL
  localparam int  V_ACTIVE  = 240; // unit: TLINE = H_TOTAL
  localparam int  V_FRONT   = 12;  // unit: TLINE = H_TOTAL
  localparam int  V_TOTAL   = 278; // unit: TLINE = H_TOTAL
  // timing parameters
  localparam real tpPDV = 5.0;
  localparam real tpPHH = 5.0;
  localparam real tpPHL = 5.0;

  // verilog_format: on
  logic r_pclk;
  logic r_rst_n, s_rst_n;
  logic org_href;

  logic [11:0] s_h_cnt_d, s_h_cnt_q;
  logic [11:0] s_v_cnt_d, s_v_cnt_q;
  logic [7:0] s_pix_data_d, s_pix_data_q;


  initial begin
    r_pclk  = 1'b0;
    r_rst_n = 1'b0;
    #200 r_rst_n = 1'b1;
  end

  always #(1000 / PCLK_FREQ / 2) r_pclk = ~r_pclk;
  assign pclk = r_pclk;
  assign data = s_pix_data_q;


  rst_sync #(
      .STAGE(5)
  ) u_pclk_rst_sync (
      .clk_i  (pclk),
      .rst_n_i(r_rst_n),
      .rst_n_o(s_rst_n)
  );


  assign s_h_cnt_d = s_h_cnt_q == 12'(H_TOTAL) - 12'd1 ? '0 : s_h_cnt_q + 12'd1;
  ndffr #(12) u_h_cnt_dffr (
      pclk,
      s_rst_n,
      s_h_cnt_d,
      s_h_cnt_q
  );


  always_comb begin
    s_v_cnt_d = s_v_cnt_q;
    if ((s_v_cnt_q == 12'(V_TOTAL) - 12'd1) && (s_h_cnt_q == 12'(H_TOTAL) - 12'd1)) begin
      s_v_cnt_d = '0;
    end else if (s_h_cnt_q == 12'(H_TOTAL) - 12'd1) begin
      s_v_cnt_d = s_v_cnt_q + 12'd1;
    end
  end
  ndffr #(12) u_v_cnt_dffr (
      pclk,
      s_rst_n,
      s_v_cnt_d,
      s_v_cnt_q
  );


  assign s_pix_data_d = href ? s_pix_data_q + 8'd1 : s_pix_data_q;
  ndffr #(8) u_pix_data (
      pclk,
      s_rst_n,
      s_pix_data_d,
      s_pix_data_q
  );


  assign org_href = (s_h_cnt_q <= (12'(H_ACTIVE) - 12'd1)) &&
                   ((s_v_cnt_q >= 12'(V_SYNC + V_BACK)) && (s_v_cnt_q <= 12'(V_SYNC + V_BACK + V_ACTIVE - 12'd1)));
  assign vsync    = s_v_cnt_q <= 12'(V_SYNC) - 12'd1;
  // tPHL or tPHH
  always@(negedge pclk) href = #tpPHL org_href;

  specify
    specparam tSU = 15.0;
    specparam tHD = 8.0;
    specparam tPDV = 5.0;
    specparam tPHH = 5.0;
    specparam tPHL = 5.0;

    $setuphold(posedge pclk, data, tSU, tHD);
    $setuphold(negedge pclk, posedge href, tPHH, 0);
    $setuphold(negedge pclk, negedge href, tPHL, 0);
    $setuphold(negedge pclk, data, tPDV, 0);


  endspecify
endmodule
