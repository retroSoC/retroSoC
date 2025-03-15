module rcu (
    input            xtal_clk_i,
    input            ext_clk_i,
    input            clk_bypass_i,
    input            ext_rst_n_i,
    input      [2:0] pll_cfg_i,
    output           sys_clk_o,
    output           sys_rst_n_o,
    output reg       sys_clkdiv4_o
);
  wire       s_xtal_clk_buf;
  wire       s_ext_clk_buf;
  wire       s_pll_clk;
  wire       s_pll_clk_buf;
  wire       s_sys_clk;
  wire       s_ext_rst_n_sync;
  wire       s_pll_lock;
  reg        r_pll_bp;
  reg  [3:0] r_pll_N;
  reg  [7:0] r_pll_M;
  reg  [1:0] r_pll_OD;
  reg  [3:0] r_div_cnt;


  tc_clk_buf u_xtal_buf (
      .clk_i(xtal_clk_i),
      .clk_o(s_xtal_clk_buf)
  );
  tc_clk_buf u_ext_clk_buf (
      .clk_i(ext_clk_i),
      .clk_o(s_ext_clk_buf)
  );
  tc_clk_buf u_pll_clk_buf (
      .clk_i(s_pll_clk),
      .clk_o(s_pll_clk_buf)
  );
  tc_clk_mux2 u_sys_mux (
      .clk0_i   (s_pll_clk_buf),
      .clk1_i   (s_ext_clk_buf),
      .clk_sel_i(clk_bypass_i),
      .clk_o    (s_sys_clk)
  );
  tc_clk_buf u_sys_clk_buf (
      .clk_i(s_sys_clk),
      .clk_o(sys_clk_o)
  );

  rst_sync #(
      .STAGE(5)
  ) u_rst_sync (
      .clk_i  (sys_clk_o),
      .rst_n_i(ext_rst_n_i),
      .rst_n_o(s_ext_rst_n_sync)
  );

  assign sys_rst_n_o = clk_bypass_i ? s_ext_rst_n_sync : s_pll_lock;


  // sys_clk_o/4
  always @(posedge sys_clk_o or negedge sys_rst_n_o) begin
    if (!sys_rst_n_o) begin
      r_div_cnt     <= 4'd0;
      sys_clkdiv4_o <= 1'b0;
    end else if (r_div_cnt == 4'd1) begin
      sys_clkdiv4_o <= ~sys_clkdiv4_o;
      r_div_cnt     <= 4'd0;
    end else r_div_cnt <= r_div_cnt + 1'b1;
  end

  // 24(bypass) 48(ext clk) 72 96
  // 120 144 168 192
  // 2 <= N <= 4
  // 7 <= M 
  always @(*) begin
    case (pll_cfg_i)
      3'b000: begin  //bypass 24MHz
        r_pll_bp = 1'b1;
        r_pll_M  = 8'd20;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd1;
      end
      3'b001: begin  //bypass 24MHz
        r_pll_bp = 1'b1;
        r_pll_M  = 8'd20;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd1;
      end
      3'b010: begin  //3*clk 72MHz
        r_pll_bp = 1'b0;
        r_pll_M  = 8'd24;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd2;
      end
      3'b011: begin  //4*clk 96MHz
        r_pll_bp = 1'b0;
        r_pll_M  = 8'd32;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd2;
      end
      3'b100: begin  //5*clk 120MHz
        r_pll_bp = 1'b0;
        r_pll_M  = 8'd40;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd2;
      end
      3'b101: begin  //6*clk 144MHz
        r_pll_bp = 1'b0;
        r_pll_M  = 8'd48;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd2;
      end
      3'b110: begin  //7*clk 168MHz
        r_pll_bp = 1'b0;
        r_pll_M  = 8'd56;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd2;
      end
      3'b111: begin  //8*clk 192MHz
        r_pll_bp = 1'b0;
        r_pll_M  = 8'd64;
        r_pll_N  = 4'd4;
        r_pll_OD = 2'd1;
      end
      default: begin  //bypass
        r_pll_bp = 1'b1;
        r_pll_M  = 8'd20;
        r_pll_N  = 4'd2;
        r_pll_OD = 2'd1;
      end
    endcase
  end

  tc_pll u_tc_pll (
      .fref_i    (s_xtal_clk_buf),
      .rst_n_i   (s_ext_rst_n_sync),
      .refdiv_i  (r_pll_M),
      .fbdiv_i   (),
      .postdiv1_i(r_pll_N),
      .postdiv2_i(r_pll_OD),
      .bp_i      (clk_bypass_i || r_pll_bp),
      .pll_lock_o(s_pll_lock),
      .pll_clk_o (s_pll_clk)
  );

endmodule
