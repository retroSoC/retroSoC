// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


module dvp_camera (
    output logic       pclk_o,
    output logic       href_o,
    output logic       vsync_o,
    output logic [7:0] dat_o
);

  // verilog_format: off
  // QVGA format for ov7725
  localparam real PclkFreq = 24.0;
  localparam int  Tpclk    = 1;
  localparam int  PixelPeriod = 2 * Tpclk;  // for RGB format
  localparam int  HActive   = 320 * PixelPeriod; // unit: pixel periods
  localparam int  HAftbk    = 256 * PixelPeriod; // unit: pixel periods
  localparam int  HTotal    = 576 * PixelPeriod; // unit: pixel periods
  localparam int  VSync     = 4;   // unit: TLINE = HTotal
  localparam int  VBack     = 22;  // unit: TLINE = HTotal
  localparam int  VActive   = 240; // unit: TLINE = HTotal
  localparam int  VFront    = 12;  // unit: TLINE = HTotal
  localparam int  VTotal    = 278; // unit: TLINE = HTotal
  // timing parameters
  localparam real Tpdv = 5.0;
  localparam real Tphh = 5.0;
  localparam real Tphl = 5.0;

  // verilog_format: on
  logic s_pclk_q;
  logic s_model_rst_n;
  logic s_rst_n;
  logic s_href;

  logic [11:0] s_h_cnt_d, s_h_cnt_q;
  logic [11:0] s_v_cnt_d, s_v_cnt_q;
  logic [7:0] s_pix_data_d, s_pix_data_q;


  initial begin
    s_pclk_q      = 1'b0;
    s_model_rst_n = 1'b0;
    #200 s_model_rst_n = 1'b1;
  end

  always #(1000 / PclkFreq / 2) s_pclk_q = ~s_pclk_q;
  assign pclk_o = s_pclk_q;
  assign dat_o  = s_pix_data_q;


  rst_sync #(
      .STAGE(5)
  ) u_pclk_rst_sync (
      .clk_i  (pclk_o),
      .rst_n_i(s_model_rst_n),
      .rst_n_o(s_rst_n)
  );


  assign s_h_cnt_d = s_h_cnt_q == 12'(HTotal) - 12'd1 ? '0 : s_h_cnt_q + 12'd1;
  ndffr #(
      .DATA_WIDTH(12)
  ) u_h_cnt_dffr (
      .clk_i  (pclk_o),
      .rst_n_i(s_rst_n),
      .dat_i  (s_h_cnt_d),
      .dat_o  (s_h_cnt_q)
  );


  always_comb begin
    s_v_cnt_d = s_v_cnt_q;
    if ((s_v_cnt_q == 12'(VTotal) - 12'd1) && (s_h_cnt_q == 12'(HTotal) - 12'd1)) begin
      s_v_cnt_d = '0;
    end else if (s_h_cnt_q == 12'(HTotal) - 12'd1) begin
      s_v_cnt_d = s_v_cnt_q + 12'd1;
    end
  end
  ndffr #(
      .DATA_WIDTH(12)
  ) u_v_cnt_dffr (
      .clk_i  (pclk_o),
      .rst_n_i(s_rst_n),
      .dat_i  (s_v_cnt_d),
      .dat_o  (s_v_cnt_q)
  );


  assign s_pix_data_d = s_href ? s_pix_data_q + 8'd1 : s_pix_data_q;
  ndffr #(
      .DATA_WIDTH(8)
  ) u_pix_data (
      .clk_i  (pclk_o),
      .rst_n_i(s_rst_n),
      .dat_i  (s_pix_data_d),
      .dat_o  (s_pix_data_q)
  );


  assign s_href = (s_h_cnt_q <= (12'(HActive) - 12'd1)) &&
                  ((s_v_cnt_q >= 12'(VSync + VBack)) &&
                   (s_v_cnt_q <= 12'(VSync + VBack + VActive - 12'd1)));
  assign vsync_o = s_v_cnt_q <= 12'(VSync) - 12'd1;
  // tPHL or tPHH
  always @(negedge pclk_o) href_o = #Tphl s_href;

  specify
    specparam tSU = 15.0;
    specparam tHD = 8.0;
    specparam tPDV = Tpdv;
    specparam tPHH = Tphh;
    specparam tPHL = Tphl;

    $setuphold(posedge pclk_o, dat_o, tSU, tHD);
    $setuphold(negedge pclk_o, posedge href_o, tPHH, 0);
    $setuphold(negedge pclk_o, negedge href_o, tPHL, 0);
    $setuphold(negedge pclk_o, dat_o, tPDV, 0);


  endspecify
endmodule
