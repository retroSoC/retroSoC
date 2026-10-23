`timescale 1ns / 1ps
module tiny_r2_p6_shared_tb;
  logic clk_i = 0, clk_aud_i = 0, rst_n_i = 0, rst_aud_n_i = 0;
  always #20.833333 clk_i = !clk_i;
  always #27.126736111 clk_aud_i = !clk_aud_i;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) tx (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) rx (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  i2s_if i2s ();
  logic streaming = 0, wide = 0;
  integer sent = 0, received = 0, matched = 0, examined = 0;
  logic        found = 0;
  logic [31:0] value;
  assign i2s.adcdat_i = i2s.dacdat_o;
  assign tx.tvalid = streaming;
  assign tx.tdata = wide ? 32'h120000 + 32'(sent) :
      {16'(16'h2001 + 2*sent), 16'(16'h2000 + 2*sent)};
  assign tx.tstrb = 4'hf;
  assign tx.tkeep = 4'hf;
  assign tx.tlast = 0;
  assign tx.tuser = 0;
  assign tx.tid = 0;
  assign tx.tdest = 0;
  assign rx.tready = 1;
  apb4_i2s u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .clk_aud_i        (clk_aud_i),
      .rst_aud_n_i      (rst_aud_n_i),
      .dma_tx_stall_o   (),
      .dma_rx_stall_o   (),
      .tx_underrun_evt_o(),
      .rx_overrun_evt_o (),
      .rx_flush_busy_o  (),
      .apb4             (apb4),
      .tx_axis          (tx),
      .rx_axis          (rx),
      .i2s              (i2s)
  );
  task automatic write(input logic [31:0] address, input logic [31:0] data);
    @(negedge clk_i);
    apb4.paddr   = address;
    apb4.pwdata  = data;
    apb4.pstrb   = 15;
    apb4.pwrite  = 1;
    apb4.psel    = 1;
    apb4.penable = 0;
    @(negedge clk_i);
    apb4.penable = 1;
    do @(posedge clk_i); while (!apb4.pready);
    if (apb4.pslverr) $fatal(1, "SIM_TEST_FAIL P6 I2S APB write %h", address);
    @(negedge clk_i);
    apb4.psel    = 0;
    apb4.penable = 0;
  endtask
  task automatic sample (input logic [31:0] observed);
    logic [31:0] first;
    first = wide ? 32'h120020 : 32'h2020;
    if (!found && observed == first) found = 1;
    if (found && matched < 512) begin
      if (observed !== first + 32'(matched))
        $fatal(
            1,
            "SIM_TEST_FAIL P6 I2S sample bits=%0d index=%0d got=%h expected=%h",
            wide ? 24 : 16,
            matched,
            observed,
            first + 32'(matched)
        );
      matched++;
    end
    examined++;
    if (!found && examined > 40)
      $fatal(
          1,
          "SIM_TEST_FAIL P6 I2S startup/payload missing bits=%0d last=%h",
          wide ? 24 : 16,
          observed
      );
  endtask
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      if (tx.tvalid && tx.tready) sent <= sent + 1;
      if (rx.tvalid && rx.tready) begin
        if (rx.tkeep !== 4'hf || rx.tstrb !== 4'hf)
          $fatal(1, "SIM_TEST_FAIL P6 I2S receive qualifiers");
        if (wide) sample (rx.tdata);
        else begin
          sample ({16'd0, rx.tdata[15:0]});
          sample ({16'd0, rx.tdata[31:16]});
        end
        received++;
      end
    end
  end
  initial begin
    apb4.psel    = 0;
    apb4.penable = 0;
    apb4.pwrite  = 0;
    apb4.paddr   = 0;
    apb4.pwdata  = 0;
    apb4.pstrb   = 0;
    apb4.pprot   = 0;
    for (integer mode = 0; mode < 2; mode++) begin
      @(negedge clk_i);
      rst_n_i     = 0;
      rst_aud_n_i = 0;
      streaming   = 0;
      sent        = 0;
      received    = 0;
      matched     = 0;
      examined    = 0;
      found       = 0;
      wide        = mode != 0;
      repeat (8) @(negedge clk_i);
      rst_n_i = 1;
      repeat (8) @(negedge clk_aud_i);
      rst_aud_n_i = 1;
      repeat (32) @(negedge clk_i);
      write(4, 3);
      repeat (256) @(negedge clk_i);
      if (u_dut.s_tx_flush_busy || u_dut.s_rx_flush_busy)
        $fatal(1, "SIM_TEST_FAIL P6 initial disabled audio flush");
      write('h10, wide ? 2 : 0);
      write('h18, 'h00200060);
      write('hc, 3);
      streaming = 1;
      wait (sent >= 96);
      write(0, 7);
      wait (matched == 512);
      $display("P6_I2S bits=%0d samples=%0d", wide ? 24 : 16, matched);
    end
    $display("SIM_TEST_PASS Tiny P6 I2S payload");
    $finish;
  end
  initial begin
    #30000000;
    $fatal(1, "SIM_TEST_TIMEOUT P6 I2S payload");
  end
endmodule
