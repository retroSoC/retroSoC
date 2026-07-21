`timescale 1ns / 1ps

module apb4_if_bridge_tb;
  logic pclk = 1'b0;
  logic presetn = 1'b0;
  apb4_pure_if apb_pure ();
  apb4_if apb_timed (
      .pclk   (pclk),
      .presetn(presetn)
  );

  apb4_if_bridge u_apb4_if_bridge (
      .apb_pure(apb_pure),
      .timed   (apb_timed)
  );

  initial begin
    apb_pure.paddr    = 32'h1234_5678;
    apb_pure.pprot    = 3'b101;
    apb_pure.psel     = 1'b1;
    apb_pure.penable  = 1'b1;
    apb_pure.pwrite   = 1'b1;
    apb_pure.pwdata   = 32'hCAFE_BABE;
    apb_pure.pstrb    = 4'b1101;
    apb_timed.pready  = 1'b1;
    apb_timed.prdata  = 32'hDEAD_BEEF;
    apb_timed.pslverr = 1'b0;
    #1;

    if ({apb_timed.paddr, apb_timed.pprot, apb_timed.psel, apb_timed.penable,
         apb_timed.pwrite, apb_timed.pwdata, apb_timed.pstrb} !==
        {apb_pure.paddr, apb_pure.pprot, apb_pure.psel, apb_pure.penable,
         apb_pure.pwrite, apb_pure.pwdata, apb_pure.pstrb}) begin
      $fatal(1, "APB request fields did not cross the bridge");
    end
    if ({apb_pure.pready, apb_pure.prdata, apb_pure.pslverr} !==
        {apb_timed.pready, apb_timed.prdata, apb_timed.pslverr}) begin
      $fatal(1, "APB response fields did not cross the bridge");
    end

    $display("apb4 interface bridge test passed");
    $finish;
  end
endmodule
