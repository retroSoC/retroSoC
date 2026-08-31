`timescale 1ns / 1ps
`include "axi4_define.svh"

module apb4_jpeg_ring_tb;
  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic [63:0] memory       [0:2047];
  logic        read_active;
  logic [31:0] read_base;
  logic [ 7:0] read_len;
  logic [ 7:0] read_index;
  logic        write_active;
  logic [31:0] write_base;
  logic [ 7:0] write_index;
  logic        bvalid;
  logic        irq;

  apb4_if apb4 (
      .pclk   (clk),
      .presetn(rst_n)
  );
  axi4_if #(
      .DATA_WIDTH(64),
      .ID_WIDTH  (3)
  ) axi4 (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  apb4_jpeg u_dut (
      .clk_i           (clk),
      .rst_n_i         (rst_n),
      .quiesce_i       (1'b0),
      .resource_reset_i(1'b0),
      .apb4            (apb4),
      .axi4            (axi4),
      .idle_o          (),
      .irq_o           (irq)
  );

  assign axi4.arready = !read_active;
  assign axi4.rid     = 3'd0;
  assign axi4.rdata   = memory[(read_base>>3)+read_index];
  assign axi4.rresp   = `AXI4_RESP_OKAY;
  assign axi4.rlast   = read_index == read_len;
  assign axi4.ruser   = '0;
  assign axi4.rvalid  = read_active;
  assign axi4.awready = !write_active && !bvalid;
  assign axi4.wready  = write_active;
  assign axi4.bid     = 3'd0;
  assign axi4.bresp   = `AXI4_RESP_OKAY;
  assign axi4.buser   = '0;
  assign axi4.bvalid  = bvalid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_active  <= 1'b0;
      read_base    <= '0;
      read_len     <= '0;
      read_index   <= '0;
      write_active <= 1'b0;
      write_base   <= '0;
      write_index  <= '0;
      bvalid       <= 1'b0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        read_active <= 1'b1;
        read_base   <= axi4.araddr;
        read_len    <= axi4.arlen;
        read_index  <= 8'd0;
      end else if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          read_active <= 1'b0;
        end else begin
          read_index <= read_index + 1'b1;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active <= 1'b1;
        write_base   <= axi4.awaddr;
        write_index  <= 8'd0;
      end
      if (axi4.wvalid && axi4.wready) begin
        for (int byte_index = 0; byte_index < 8; byte_index++) begin
          if (axi4.wstrb[byte_index]) begin
            memory[(write_base>>3)+write_index][byte_index*8+:8] <= axi4.wdata[byte_index*8+:8];
          end
        end
        if (axi4.wlast) begin
          write_active <= 1'b0;
          bvalid       <= 1'b1;
        end else begin
          write_index <= write_index + 1'b1;
        end
      end
      if (axi4.bvalid && axi4.bready) begin
        bvalid <= 1'b0;
      end
    end
  end

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] data_i);
    begin
      @(negedge clk);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwdata  = data_i;
      apb4.pstrb   = 4'hf;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk);
      apb4.penable = 1'b1;
      #1;
      if (!apb4.pready || apb4.pslverr) $fatal(1, "APB write failed at %h", offset_i);
      @(negedge clk);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] data_o);
    begin
      @(negedge clk);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk);
      apb4.penable = 1'b1;
      #1;
      if (!apb4.pready || apb4.pslverr) $fatal(1, "APB read failed at %h", offset_i);
      data_o = apb4.prdata;
      @(negedge clk);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] value;
    int          timeout;

    for (int index = 0; index < 2048; index++) begin
      memory[index] = 64'd0;
    end
    memory[32'h1000>>3] = 64'h0000000000000001;
    apb4.paddr   = '0;
    apb4.pprot   = '0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    apb_write(12'h01c, 32'h12);
    apb_write(12'h100, 32'h00001000);
    apb_write(12'h104, 32'd2);
    apb_write(12'h10c, 32'd1);
    apb_write(12'h110, 32'd1);
    apb_write(12'h11c, 32'd1);
    timeout = 2000;
    value   = 32'd1;
    while ((value[0] != 1'b0) && (timeout > 0)) begin
      apb_read(12'h014, value);
      timeout--;
    end
    if (timeout == 0) $fatal(1, "ring job did not complete");
    apb_read(12'h108, value);
    if (value != 32'd1) $fatal(1, "ring head was not advanced");
    apb_read(12'h018, value);
    if ((value & 32'h12) != 32'h12 || !irq) $fatal(1, "ring IRQ status mismatch");
    if (memory[32'h1000>>3][31:0] != 32'd0 || memory[32'h1000>>3][63:32] != 32'h00000103) begin
      $fatal(1, "descriptor error writeback mismatch: %h", memory[32'h1000>>3]);
    end
    $display("JPEG APB ring tests passed");
    $finish;
  end
endmodule
