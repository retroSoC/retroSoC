// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_role_controller #(
    parameter int ResetCycles = 8
) (
    // verilog_format: off -- preserve control, PHY sense, and status groups
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 enable_i,
    input  logic                 soft_reset_i,
    input  logic                 auto_role_i,
    input  logic [1:0]           force_role_i,
    input  logic                 id_ground_i,
    input  logic                 vbus_valid_i,
    input  logic                 transaction_busy_i,
    output usb2_pkg::usb2_role_e active_role_o,
    output logic                 role_change_o,
    output logic                 role_reset_o,
    output logic                 switch_pending_o
    // verilog_format: on
);
  localparam int ResetCountWidth = (ResetCycles > 1) ? $clog2(ResetCycles + 1) : 1;

  usb2_pkg::usb2_role_e s_requested_role;
  usb2_pkg::usb2_role_e s_active_role_d, s_active_role_q;
  logic [1:0] s_active_role_bits_q;
  logic [ResetCountWidth-1:0] s_reset_count_d, s_reset_count_q;
  logic s_role_change_d, s_role_change_q;

  always_comb begin
    if (!enable_i) begin
      s_requested_role = usb2_pkg::Usb2RoleIdle;
    end else if (auto_role_i) begin
      if (id_ground_i) begin
        s_requested_role = usb2_pkg::Usb2RoleHost;
      end else if (vbus_valid_i) begin
        s_requested_role = usb2_pkg::Usb2RoleDevice;
      end else begin
        s_requested_role = usb2_pkg::Usb2RoleIdle;
      end
    end else begin
      unique case (force_role_i)
        2'd1:    s_requested_role = usb2_pkg::Usb2RoleDevice;
        2'd2:    s_requested_role = usb2_pkg::Usb2RoleHost;
        default: s_requested_role = usb2_pkg::Usb2RoleIdle;
      endcase
    end
  end

  assign s_active_role_q  = usb2_pkg::usb2_role_e'(s_active_role_bits_q);
  assign active_role_o    = s_active_role_q;
  assign role_change_o    = s_role_change_q;
  assign role_reset_o     = soft_reset_i || (s_reset_count_q != '0);
  assign switch_pending_o = s_requested_role != s_active_role_q;

  always_comb begin
    s_active_role_d = s_active_role_q;
    s_reset_count_d = s_reset_count_q;
    s_role_change_d = 1'b0;

    if (s_reset_count_q != '0) begin
      s_reset_count_d = s_reset_count_q - 1'b1;
    end
    if (soft_reset_i) begin
      s_active_role_d = usb2_pkg::Usb2RoleIdle;
      s_reset_count_d = ResetCountWidth'(ResetCycles);
      s_role_change_d = s_active_role_q != usb2_pkg::Usb2RoleIdle;
    end else if ((s_requested_role != s_active_role_q) && !transaction_busy_i &&
                 (s_reset_count_q == '0)) begin
      s_active_role_d = s_requested_role;
      s_reset_count_d = ResetCountWidth'(ResetCycles);
      s_role_change_d = 1'b1;
    end
  end

  dffr #(
      .DATA_WIDTH(2)
  ) u_active_role_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_active_role_d),
      .dat_o  (s_active_role_bits_q)
  );
  dffr #(
      .DATA_WIDTH(ResetCountWidth)
  ) u_reset_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reset_count_d),
      .dat_o  (s_reset_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_role_change_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_role_change_d),
      .dat_o  (s_role_change_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (ResetCycles < 2) begin
      $fatal(1, "usb2_role_controller: ResetCycles must be at least two");
    end
  end
`endif
endmodule
