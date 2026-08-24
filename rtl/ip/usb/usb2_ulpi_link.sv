// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module usb2_ulpi_link #(
    parameter int ViewportTimeoutCycles = 1024
) (
    // verilog_format: off -- preserve ULPI, packet, and viewport port groups
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       enable_i,
    input  logic       phy_reset_n_i,
    input  logic       tx_start_valid_i,
    output logic       tx_start_ready_o,
    input  logic [3:0] tx_pid_i,
    input  logic       tx_has_data_i,
    input  logic       tx_data_valid_i,
    output logic       tx_data_ready_o,
    input  logic [7:0] tx_data_i,
    input  logic       tx_data_last_i,
    output logic       tx_done_o,
    output logic       tx_error_o,
    output logic       rx_start_o,
    output logic       rx_valid_o,
    output logic [7:0] rx_data_o,
    output logic       rx_end_o,
    output logic       rx_error_o,
    output logic [1:0] line_state_o,
    output logic [1:0] vbus_state_o,
    output logic       id_ground_o,
    input  logic       viewport_valid_i,
    output logic       viewport_ready_o,
    input  logic       viewport_write_i,
    input  logic [5:0] viewport_addr_i,
    input  logic [7:0] viewport_write_data_i,
    output logic       viewport_resp_valid_o,
    output logic [7:0] viewport_read_data_o,
    output logic       viewport_error_o,
    output logic       link_ready_o,
    usb2_ulpi_if.dut   ulpi
    // verilog_format: on
);
  localparam int ViewportCountWidth = (ViewportTimeoutCycles > 1) ? $clog2(
      ViewportTimeoutCycles + 1
  ) : 1;

  typedef enum logic [3:0] {
    Idle,
    TxCommand,
    TxPayload,
    TxStop,
    ViewCommand,
    ViewWriteData,
    ViewWriteStop,
    ViewReadTurn,
    ViewReadData,
    ViewReadRelease
  } link_state_e;

  link_state_e s_state_d, s_state_q;
  logic [3:0] s_state_bits_q;
  logic [3:0] s_tx_pid_d, s_tx_pid_q;
  logic s_tx_has_data_d, s_tx_has_data_q;
  logic s_view_write_d, s_view_write_q;
  logic [5:0] s_view_addr_d, s_view_addr_q;
  logic [7:0] s_view_write_data_d, s_view_write_data_q;
  logic [7:0] s_view_read_data_d, s_view_read_data_q;
  logic [ViewportCountWidth-1:0] s_view_timeout_d, s_view_timeout_q;
  logic [1:0] s_line_state_d, s_line_state_q;
  logic [1:0] s_vbus_state_d, s_vbus_state_q;
  logic s_id_ground_d, s_id_ground_q;
  logic s_rx_active_d, s_rx_active_q;
  logic s_rx_err_d, s_rx_err_q;
  logic s_tx_done_d, s_tx_done_q;
  logic s_tx_err_d, s_tx_err_q;
  logic s_view_resp_valid_d, s_view_resp_valid_q;
  logic s_view_err_d, s_view_err_q;
  logic s_view_timeout_expired;
  logic s_rx_cmd;
  logic s_rx_active_now;

  assign s_state_q = link_state_e'(s_state_bits_q);
  assign s_rx_cmd = enable_i && phy_reset_n_i && ulpi.dir_i && !ulpi.nxt_i && (s_state_q == Idle);
  assign s_rx_active_now = s_rx_cmd ? ulpi.data_di_i[4] : s_rx_active_q;
  assign s_view_timeout_expired = s_view_timeout_q == ViewportCountWidth'(ViewportTimeoutCycles);

  assign tx_start_ready_o = enable_i && phy_reset_n_i && (s_state_q == Idle) && !ulpi.dir_i;
  assign viewport_ready_o = phy_reset_n_i && (s_state_q == Idle) && !ulpi.dir_i &&
                            !tx_start_valid_i;
  assign tx_data_ready_o = (s_state_q == TxPayload) && !ulpi.dir_i && ulpi.nxt_i;
  assign tx_done_o = s_tx_done_q;
  assign tx_error_o = s_tx_err_q;
  assign viewport_resp_valid_o = s_view_resp_valid_q;
  assign viewport_read_data_o = s_view_read_data_q;
  assign viewport_error_o = s_view_err_q;
  assign link_ready_o = enable_i && phy_reset_n_i && (s_state_q == Idle) && !ulpi.dir_i;
  assign line_state_o = s_line_state_q;
  assign vbus_state_o = s_vbus_state_q;
  assign id_ground_o = s_id_ground_q;
  assign rx_start_o = s_rx_cmd && ulpi.data_di_i[4] && !s_rx_active_q;
  assign rx_end_o = s_rx_cmd && !ulpi.data_di_i[4] && s_rx_active_q;
  assign rx_valid_o = enable_i && phy_reset_n_i && (s_state_q == Idle) && ulpi.dir_i &&
                      ulpi.nxt_i && s_rx_active_q;
  assign rx_data_o = ulpi.data_di_i;
  assign rx_error_o = s_rx_err_q || (s_rx_cmd && ulpi.data_di_i[5]);

  always_comb begin
    s_state_d           = s_state_q;
    s_tx_pid_d          = s_tx_pid_q;
    s_tx_has_data_d     = s_tx_has_data_q;
    s_view_write_d      = s_view_write_q;
    s_view_addr_d       = s_view_addr_q;
    s_view_write_data_d = s_view_write_data_q;
    s_view_read_data_d  = s_view_read_data_q;
    s_view_timeout_d    = s_view_timeout_q;
    s_line_state_d      = s_line_state_q;
    s_vbus_state_d      = s_vbus_state_q;
    s_id_ground_d       = s_id_ground_q;
    s_rx_active_d       = s_rx_active_now;
    s_rx_err_d          = s_rx_err_q;
    s_tx_done_d         = 1'b0;
    s_tx_err_d          = 1'b0;
    s_view_resp_valid_d = 1'b0;
    s_view_err_d        = 1'b0;

    if (s_rx_cmd) begin
      s_line_state_d = ulpi.data_di_i[1:0];
      s_vbus_state_d = ulpi.data_di_i[3:2];
      s_id_ground_d  = ulpi.data_di_i[6];
      if (ulpi.data_di_i[5]) begin
        s_rx_err_d = 1'b1;
      end
      if (!ulpi.data_di_i[4]) begin
        s_rx_err_d = 1'b0;
      end
    end

    unique case (s_state_q)
      Idle: begin
        s_view_timeout_d = '0;
        if (!enable_i || !phy_reset_n_i) begin
          s_rx_active_d = 1'b0;
          s_rx_err_d    = 1'b0;
        end else if (tx_start_valid_i && tx_start_ready_o) begin
          s_tx_pid_d      = tx_pid_i;
          s_tx_has_data_d = tx_has_data_i;
          s_state_d       = TxCommand;
        end else if (viewport_valid_i && viewport_ready_o) begin
          s_view_write_d      = viewport_write_i;
          s_view_addr_d       = viewport_addr_i;
          s_view_write_data_d = viewport_write_data_i;
          s_state_d           = ViewCommand;
        end
      end
      TxCommand: begin
        if (ulpi.dir_i) begin
          s_state_d  = Idle;
          s_tx_err_d = 1'b1;
        end else if (ulpi.nxt_i) begin
          s_state_d = s_tx_has_data_q ? TxPayload : TxStop;
        end
      end
      TxPayload: begin
        if (ulpi.dir_i) begin
          s_state_d  = Idle;
          s_tx_err_d = 1'b1;
        end else if (tx_data_valid_i && tx_data_ready_o && tx_data_last_i) begin
          s_state_d = TxStop;
        end
      end
      TxStop: begin
        s_state_d   = Idle;
        s_tx_done_d = 1'b1;
      end
      ViewCommand: begin
        s_view_timeout_d = s_view_timeout_q + 1'b1;
        if (ulpi.dir_i || s_view_timeout_expired) begin
          s_state_d           = Idle;
          s_view_resp_valid_d = 1'b1;
          s_view_err_d        = 1'b1;
        end else if (ulpi.nxt_i) begin
          s_view_timeout_d = '0;
          s_state_d        = s_view_write_q ? ViewWriteData : ViewReadTurn;
        end
      end
      ViewWriteData: begin
        s_view_timeout_d = s_view_timeout_q + 1'b1;
        if (ulpi.dir_i || s_view_timeout_expired) begin
          s_state_d           = Idle;
          s_view_resp_valid_d = 1'b1;
          s_view_err_d        = 1'b1;
        end else if (ulpi.nxt_i) begin
          s_state_d = ViewWriteStop;
        end
      end
      ViewWriteStop: begin
        s_state_d           = Idle;
        s_view_resp_valid_d = 1'b1;
      end
      ViewReadTurn: begin
        s_view_timeout_d = s_view_timeout_q + 1'b1;
        if (s_view_timeout_expired) begin
          s_state_d           = Idle;
          s_view_resp_valid_d = 1'b1;
          s_view_err_d        = 1'b1;
        end else if (ulpi.dir_i) begin
          s_view_timeout_d = '0;
          s_state_d        = ViewReadData;
        end
      end
      ViewReadData: begin
        s_view_timeout_d = s_view_timeout_q + 1'b1;
        if (s_view_timeout_expired) begin
          s_state_d           = Idle;
          s_view_resp_valid_d = 1'b1;
          s_view_err_d        = 1'b1;
        end else if (ulpi.dir_i && ulpi.nxt_i) begin
          s_view_read_data_d = ulpi.data_di_i;
          s_view_timeout_d   = '0;
          s_state_d          = ViewReadRelease;
        end
      end
      ViewReadRelease: begin
        s_view_timeout_d = s_view_timeout_q + 1'b1;
        if (!ulpi.dir_i) begin
          s_state_d           = Idle;
          s_view_resp_valid_d = 1'b1;
        end else if (s_view_timeout_expired) begin
          s_state_d           = Idle;
          s_view_resp_valid_d = 1'b1;
          s_view_err_d        = 1'b1;
        end
      end
      default: begin
        s_state_d  = Idle;
        s_tx_err_d = 1'b1;
      end
    endcase
  end

  always_comb begin
    ulpi.data_do_o = 8'd0;
    ulpi.data_oe_o = 1'b0;
    ulpi.stp_o     = 1'b0;
    ulpi.reset_n_o = phy_reset_n_i;
    unique case (s_state_q)
      TxCommand: begin
        ulpi.data_do_o = {2'b01, 2'b00, s_tx_pid_q};
        ulpi.data_oe_o = !ulpi.dir_i;
      end
      TxPayload: begin
        ulpi.data_do_o = tx_data_i;
        ulpi.data_oe_o = !ulpi.dir_i && tx_data_valid_i;
      end
      TxStop: begin
        ulpi.stp_o = 1'b1;
      end
      ViewCommand: begin
        ulpi.data_do_o = {s_view_write_q ? 2'b10 : 2'b11, s_view_addr_q};
        ulpi.data_oe_o = !ulpi.dir_i;
      end
      ViewWriteData: begin
        ulpi.data_do_o = s_view_write_data_q;
        ulpi.data_oe_o = !ulpi.dir_i;
      end
      ViewWriteStop: begin
        ulpi.stp_o = 1'b1;
      end
      default: begin
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH(4)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_tx_pid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_pid_d),
      .dat_o  (s_tx_pid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_has_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_has_data_d),
      .dat_o  (s_tx_has_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_view_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_write_d),
      .dat_o  (s_view_write_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_view_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_addr_d),
      .dat_o  (s_view_addr_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_view_write_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_write_data_d),
      .dat_o  (s_view_write_data_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_view_read_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_read_data_d),
      .dat_o  (s_view_read_data_q)
  );
  dffr #(
      .DATA_WIDTH(ViewportCountWidth)
  ) u_view_timeout_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_timeout_d),
      .dat_o  (s_view_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_line_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_line_state_d),
      .dat_o  (s_line_state_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_vbus_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_vbus_state_d),
      .dat_o  (s_vbus_state_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_id_ground_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_id_ground_d),
      .dat_o  (s_id_ground_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_active_d),
      .dat_o  (s_rx_active_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_err_d),
      .dat_o  (s_rx_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_done_d),
      .dat_o  (s_tx_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_err_d),
      .dat_o  (s_tx_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_view_resp_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_resp_valid_d),
      .dat_o  (s_view_resp_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_view_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_err_d),
      .dat_o  (s_view_err_q)
  );

`ifndef SV_ASSRT_DISABLE
  property p_link_never_drives_with_dir;
    @(posedge clk_i) disable iff (!rst_n_i) ulpi.dir_i |-> !ulpi.data_oe_o;
  endproperty
  assert property (p_link_never_drives_with_dir);

  property p_tx_payload_stable_when_stalled;
    @(posedge clk_i) disable iff (!rst_n_i)
      (s_state_q == TxPayload && tx_data_valid_i && !tx_data_ready_o) |=>
          $stable(
        tx_data_i
    ) && $stable(
        tx_data_last_i
    );
  endproperty
  assert property (p_tx_payload_stable_when_stalled);
`endif

`ifndef SYNTHESIS
  initial begin
    if (ViewportTimeoutCycles < 2) begin
      $fatal(1, "usb2_ulpi_link: ViewportTimeoutCycles must be at least two");
    end
  end
`endif
endmodule
