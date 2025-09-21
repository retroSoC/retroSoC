

module onewire_core (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [7:0]  clkdiv_i,
    input  logic [7:0]  zerocnt_i,
    input  logic [7:0]  onecnt_i,
    input  logic [7:0]  rstnum_i,
    input  logic        start_i,
    output logic        data_req_o,
    input  logic        data_rdy_i,
    input  logic [23:0] data_i,
    output logic        done_o,
    onewire_if.dut      onewire
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_XFER = 2'd1;
  localparam FSM_RST = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic s_clkdiv_cnt_en;
  logic [7:0] s_clkdiv_cnt_d, s_clkdiv_cnt_q;
  logic [7:0] s_rst_cnt_d, s_rst_cnt_q;
  logic [4:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [23:0] s_xfer_data_d, s_xfer_data_q;
  logic s_done_d, s_done_q;

  assign done_o = s_done_q;

  always_comb begin
    s_fsm_d        = s_fsm_q;
    s_clkdiv_cnt_d = s_clkdiv_cnt_q;
    s_bit_cnt_d    = s_bit_cnt_q;
    s_rst_cnt_d    = s_rst_cnt_q;
    s_xfer_data_d  = s_xfer_data_q;
    s_done_d       = s_done_q;
    data_req_o     = '0;
    onewire.dat_o  = '0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_done_d = 1'b0;
        if (start_i && data_rdy_i) begin
          data_req_o    = 1'b1;
          s_xfer_data_d = data_i;
          s_fsm_d       = FSM_XFER;
        end
      end
      FSM_XFER: begin
        // handle the data
        // xfer '1'
        if (s_xfer_data_q[23]) begin
          if (s_clkdiv_cnt_q <= onecnt_i) onewire.dat_o = 1'b1;
          else onewire.dat_o = 1'b0;
        end else begin
          if (s_clkdiv_cnt_q <= zerocnt_i) onewire.dat_o = 1'b1;
          else onewire.dat_o = 1'b0;
        end
        s_clkdiv_cnt_d = s_clkdiv_cnt_q + 1'b1;
        if (s_clkdiv_cnt_q == clkdiv_i) begin
          s_clkdiv_cnt_d = '0;
          s_xfer_data_d  = {s_xfer_data_q[22:0], 1'b0};
          s_bit_cnt_d    = s_bit_cnt_q + 1'b1;
        end

        if (s_bit_cnt_q == 5'd23 && s_clkdiv_cnt_q == clkdiv_i) begin
          s_bit_cnt_d = '0;
          if (~data_rdy_i) begin
            s_fsm_d = FSM_RST;
          end else begin
            data_req_o    = 1'b1;
            s_xfer_data_d = data_i;
          end
        end
      end
      FSM_RST: begin
        if (s_rst_cnt_q == rstnum_i) begin
          s_rst_cnt_d    = '0;
          s_clkdiv_cnt_d = '0;
          s_fsm_d        = FSM_IDLE;
          s_done_d       = 1'b1;
        end else begin
          s_clkdiv_cnt_d = s_clkdiv_cnt_q + 1'b1;
          if (s_clkdiv_cnt_q == clkdiv_i) begin
            s_clkdiv_cnt_d = '0;
            s_rst_cnt_d    = s_rst_cnt_q + 1'b1;
          end
        end
      end
      default: begin
        s_fsm_d        = s_fsm_q;
        s_clkdiv_cnt_d = s_clkdiv_cnt_q;
        s_bit_cnt_d    = s_bit_cnt_q;
        s_rst_cnt_d    = s_rst_cnt_q;
        s_xfer_data_d  = s_xfer_data_q;
        s_done_d       = s_done_q;
        onewire.dat_o  = '0;
      end
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  assign s_clkdiv_cnt_en = s_fsm_q != FSM_IDLE;
  dffer #(8) u_clkdiv_cnt_dffer (
      clk_i,
      rst_n_i,
      s_clkdiv_cnt_en,
      s_clkdiv_cnt_d,
      s_clkdiv_cnt_q
  );

  dffr #(1) u_done_dffr (
      clk_i,
      rst_n_i,
      s_done_d,
      s_done_q
  );

  dffr #(5) u_bit_cnt_dffr (
      clk_i,
      rst_n_i,
      s_bit_cnt_d,
      s_bit_cnt_q
  );

  dffr #(8) u_rst_cnt_dffr (
      clk_i,
      rst_n_i,
      s_rst_cnt_d,
      s_rst_cnt_q
  );

  dffr #(24) u_xfer_data_dffr (
      clk_i,
      rst_n_i,
      s_xfer_data_d,
      s_xfer_data_q
  );

endmodule
