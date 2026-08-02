`timescale 1ns / 1ps

module tc_pdk_cells_tb;
  logic in_drive;
  logic in_drive_en;
  tri   in_pad;
  logic in_p2c;

  logic out_c2p;
  tri   out_pad;

  logic tri_c2p;
  logic tri_c2p_en;
  logic tri_drive;
  logic tri_drive_en;
  tri   tri_pad;
  logic tri_p2c;

  logic schmitt_c2p;
  logic schmitt_c2p_en;
  logic schmitt_drive;
  logic schmitt_drive_en;
  tri   schmitt_pad;
  logic schmitt_p2c;

  logic full_c2p;
  logic full_c2p_en;
  logic full_drive;
  logic full_drive_en;
  logic full_cs;
  logic full_pu;
  logic full_pd;
  tri   full_pad;
  logic full_p2c;

  logic clk0_i;
  logic clk1_i;
  logic clk_sel_i;
  logic clk_inv_o;
  logic clk_buf_o;
  logic clk_mux_o;
  logic clk_xor_o;

`ifdef PDK_GF180
  logic gf180_seq_clk;
  logic gf180_seq_d;
  logic gf180_seq_reset_n;
  logic gf180_dffq_q;
  logic gf180_dffrnq_q;
  logic gf180_dffsnq_q;

  gf180mcu_fd_sc_mcu7t5v0__dffq_1 u_gf180_dffq (
      .CLK     (gf180_seq_clk),
      .D       (gf180_seq_d),
      .Q       (gf180_dffq_q),
      .notifier()
  );

  gf180mcu_fd_sc_mcu7t5v0__dffrnq_1 u_gf180_dffrnq (
      .CLK     (gf180_seq_clk),
      .D       (gf180_seq_d),
      .RN      (gf180_seq_reset_n),
      .Q       (gf180_dffrnq_q),
      .notifier()
  );

  gf180mcu_fd_sc_mcu7t5v0__dffsnq_1 u_gf180_dffsnq (
      .CLK     (gf180_seq_clk),
      .D       (gf180_seq_d),
      .SETN    (gf180_seq_reset_n),
      .Q       (gf180_dffsnq_q),
      .notifier()
  );
`endif

`ifdef PDK_ICS55
  logic ics55_od_i;
  logic ics55_od_oe;
  logic ics55_od_mode;
  logic ics55_pu;
  logic ics55_pd;
  tri   ics55_pad;
  logic [2:0] ics55_mux_inputs;
  logic       ics55_mux_y;

  P65_1233_PBMUX u_ics55_open_drain_pad (
      .C  (),
      .A  (),
      .PAD(ics55_pad),
      .IE (1'b0),
      .CS (1'b1),
      .I  (ics55_od_i),
      .OE (ics55_od_oe),
      .OD (ics55_od_mode),
      .PU (ics55_pu),
      .PD (ics55_pd),
      .DS0(1'b0),
      .DS1(1'b1)
  );

  MUXI2X0P5H7R u_ics55_muxi2 (
      .A (ics55_mux_inputs[0]),
      .B (ics55_mux_inputs[1]),
      .S0(ics55_mux_inputs[2]),
      .Y (ics55_mux_y)
  );
`endif

  assign in_pad      = in_drive_en ? in_drive : 1'bz;
  assign tri_pad     = tri_drive_en ? tri_drive : 1'bz;
  assign schmitt_pad = schmitt_drive_en ? schmitt_drive : 1'bz;
  assign full_pad    = full_drive_en ? full_drive : 1'bz;

  tc_io_in_pad u_tc_io_in_pad (
      .pad(in_pad),
      .p2c(in_p2c)
  );

  tc_io_out_pad u_tc_io_out_pad (
      .pad(out_pad),
      .c2p(out_c2p)
  );

  tc_io_tri_pad u_tc_io_tri_pad (
      .pad   (tri_pad),
      .c2p   (tri_c2p),
      .c2p_en(tri_c2p_en),
      .p2c   (tri_p2c)
  );

  tc_io_tri_schmitt_pad u_tc_io_tri_schmitt_pad (
      .pad   (schmitt_pad),
      .c2p   (schmitt_c2p),
      .c2p_en(schmitt_c2p_en),
      .p2c   (schmitt_p2c)
  );

  tc_io_tri_full_pad u_tc_io_tri_full_pad (
      .pad   (full_pad),
      .c2p   (full_c2p),
      .c2p_en(full_c2p_en),
      .p2c   (full_p2c),
      .cs    (full_cs),
      .pu    (full_pu),
      .pd    (full_pd)
  );

  tc_clk_inv u_tc_clk_inv (
      .clk_i(clk0_i),
      .clk_o(clk_inv_o)
  );

  tc_clk_buf u_tc_clk_buf (
      .clk_i(clk0_i),
      .clk_o(clk_buf_o)
  );

  tc_clk_mux2 u_tc_clk_mux2 (
      .clk0_i   (clk0_i),
      .clk1_i   (clk1_i),
      .clk_sel_i(clk_sel_i),
      .clk_o    (clk_mux_o)
  );

  tc_clk_xor2 u_tc_clk_xor2 (
      .clk0_i(clk0_i),
      .clk1_i(clk1_i),
      .clk_o (clk_xor_o)
  );

  task automatic expect_bit(input logic actual, input logic expected, input string message);
    if (actual !== expected) begin
      $fatal(1, "%s: expected %b, got %b", message, expected, actual);
    end
  endtask

  initial begin
    in_drive         = 1'b0;
    in_drive_en      = 1'b0;
    out_c2p          = 1'b0;
    tri_c2p          = 1'b0;
    tri_c2p_en       = 1'b0;
    tri_drive        = 1'b0;
    tri_drive_en     = 1'b0;
    schmitt_c2p      = 1'b0;
    schmitt_c2p_en   = 1'b0;
    schmitt_drive    = 1'b0;
    schmitt_drive_en = 1'b0;
    full_c2p         = 1'b0;
    full_c2p_en      = 1'b0;
    full_drive       = 1'b0;
    full_drive_en    = 1'b0;
    full_cs          = 1'b0;
    full_pu          = 1'b0;
    full_pd          = 1'b0;
    clk0_i           = 1'b0;
    clk1_i           = 1'b1;
    clk_sel_i        = 1'b0;
`ifdef PDK_GF180
    gf180_seq_clk     = 1'b0;
    gf180_seq_d       = 1'b0;
    gf180_seq_reset_n = 1'b0;
`endif
`ifdef PDK_ICS55
    ics55_od_i    = 1'b1;
    ics55_od_oe   = 1'b0;
    ics55_od_mode = 1'b1;
    ics55_pu      = 1'b0;
    ics55_pd      = 1'b0;
    ics55_mux_inputs = 3'b000;
`endif

    #5;
    in_drive_en = 1'b1;
    in_drive    = 1'b1;
    #5;
    expect_bit(in_p2c, 1'b1, "input pad propagation");

    out_c2p = 1'b1;
    #5;
    expect_bit(out_pad, 1'b1, "output pad high drive");
    out_c2p = 1'b0;
    #5;
    expect_bit(out_pad, 1'b0, "output pad low drive");

    tri_drive_en = 1'b1;
    tri_drive    = 1'b1;
    #5;
    expect_bit(tri_p2c, 1'b1, "tri-state pad input");
    tri_drive_en = 1'b0;
    tri_c2p      = 1'b1;
    tri_c2p_en   = 1'b1;
    #5;
    expect_bit(tri_pad, 1'b1, "tri-state pad output");
`ifdef PDK_ICS55
    expect_bit(tri_p2c, 1'b0, "ICS55 tri-state output disables input receiver");
`else
    expect_bit(tri_p2c, 1'b1, "tri-state output readback");
`endif
    tri_c2p_en = 1'b0;
    #5;
    if (tri_pad !== 1'bz) begin
      $fatal(1, "tri-state pad did not release the line");
    end

    schmitt_drive_en = 1'b1;
    schmitt_drive    = 1'b1;
    #5;
    expect_bit(schmitt_p2c, 1'b1, "Schmitt pad input");
    schmitt_drive_en = 1'b0;
    schmitt_c2p      = 1'b1;
    schmitt_c2p_en   = 1'b1;
    #5;
    expect_bit(schmitt_pad, 1'b1, "Schmitt pad output");

    full_drive_en = 1'b1;
    full_drive    = 1'b1;
    full_cs       = 1'b1;
    #5;
    expect_bit(full_p2c, 1'b1, "full pad input");
    full_drive_en = 1'b0;
    full_c2p      = 1'b1;
    full_c2p_en   = 1'b1;
    #5;
    expect_bit(full_pad, 1'b1, "full pad output");

    #5;
    expect_bit(clk_inv_o, 1'b1, "clock inverter");
    expect_bit(clk_buf_o, 1'b0, "clock buffer");
    expect_bit(clk_mux_o, 1'b0, "clock mux select zero");
    expect_bit(clk_xor_o, 1'b1, "clock xor");
    clk_sel_i = 1'b1;
    clk0_i    = 1'b1;
    clk1_i    = 1'b0;
    #5;
    expect_bit(clk_inv_o, 1'b0, "clock inverter toggle");
    expect_bit(clk_buf_o, 1'b1, "clock buffer toggle");
    expect_bit(clk_mux_o, 1'b0, "clock mux select one");
    expect_bit(clk_xor_o, 1'b1, "clock xor toggle");

`ifdef PDK_GF180
    expect_bit(gf180_dffrnq_q, 1'b0, "GF180 reset-low DFF");
    expect_bit(gf180_dffsnq_q, 1'b1, "GF180 reset-high DFF");
    gf180_seq_reset_n = 1'b1;
    gf180_seq_d       = 1'b1;
    gf180_seq_clk     = 1'b1;
    #5;
    expect_bit(gf180_dffq_q, 1'b1, "GF180 DFF clock capture");
    expect_bit(gf180_dffrnq_q, 1'b1, "GF180 reset-low DFF clock capture");
    expect_bit(gf180_dffsnq_q, 1'b1, "GF180 reset-high DFF clock capture");
`endif
`ifdef PDK_ICS55
    ics55_od_oe = 1'b1;
    #5;
    if (ics55_pad !== 1'bz) begin
      $fatal(1, "ICS55 open-drain pad did not release high data");
    end
    ics55_od_i = 1'b0;
    #5;
    expect_bit(ics55_pad, 1'b0, "ICS55 open-drain low drive");
    ics55_od_oe = 1'b0;
    ics55_pu    = 1'b1;
    #5;
    expect_bit(ics55_pad, 1'b1, "ICS55 pull-up");
    ics55_pu = 1'b0;
    ics55_pd = 1'b1;
    #5;
    expect_bit(ics55_pad, 1'b0, "ICS55 pull-down");
    for (int mux_vector = 0; mux_vector < 8; mux_vector++) begin
      ics55_mux_inputs = mux_vector[2:0];
      #1;
      expect_bit(
          ics55_mux_y,
          ~(ics55_mux_inputs[2] ? ics55_mux_inputs[1] : ics55_mux_inputs[0]),
          $sformatf("ICS55 MUXI2 vector %0d", mux_vector)
      );
    end
`endif

    $display("technology IO and clock cell test passed");
    $finish;
  end
endmodule
