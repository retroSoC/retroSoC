`timescale 1ns / 1ps
`include "axi4_define.svh"

module jpeg_dma_tb;
  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        read_start;
  logic        write_start;
  logic        read_busy;
  logic        write_busy;
  logic        read_done;
  logic        write_done;
  logic        error_flag;
  logic [31:0] read_bytes;
  logic [31:0] write_bytes;
  logic [63:0] memory       [0:2047];
  logic        read_active;
  logic [31:0] read_base;
  logic [ 7:0] read_len;
  logic [ 7:0] read_index;
  logic        write_active;
  logic [31:0] write_base;
  logic [ 7:0] write_len;
  logic [ 7:0] write_index;
  logic        bvalid;
  int          read_bursts;

  axi4_if #(
      .DATA_WIDTH(64),
      .ID_WIDTH  (3)
  ) axi4 (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) read_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) write_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  assign write_axis.tdata  = read_axis.tdata;
  assign write_axis.tkeep  = read_axis.tkeep;
  assign write_axis.tstrb  = read_axis.tstrb;
  assign write_axis.tlast  = read_axis.tlast;
  assign write_axis.tid    = '0;
  assign write_axis.tdest  = '0;
  assign write_axis.tuser  = read_axis.tuser;
  assign write_axis.tvalid = read_axis.tvalid;
  assign read_axis.tready  = write_axis.tready;

  jpeg_dma u_dut (
      .clk_i             (clk),
      .rst_n_i           (rst_n),
      .abort_i           (1'b0),
      .quiesce_i         (1'b0),
      .read_start_i      (read_start),
      .read_addr_i       (32'h00000ff0),
      .read_line_bytes_i (32'd20),
      .read_stride_i     (32'd32),
      .read_lines_i      (16'd2),
      .read_busy_o       (read_busy),
      .read_done_o       (read_done),
      .read_axis         (read_axis),
      .write_start_i     (write_start),
      .write_addr_i      (32'h00002000),
      .write_line_bytes_i(32'd20),
      .write_stride_i    (32'd32),
      .write_lines_i     (16'd2),
      .write_busy_o      (write_busy),
      .write_done_o      (write_done),
      .write_axis        (write_axis),
      .error_o           (error_flag),
      .error_read_o      (),
      .error_resp_o      (),
      .error_addr_o      (),
      .read_bytes_o      (read_bytes),
      .write_bytes_o     (write_bytes),
      .read_stall_o      (),
      .write_stall_o     (),
      .axi4              (axi4)
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
      write_len    <= '0;
      write_index  <= '0;
      bvalid       <= 1'b0;
      read_bursts  <= 0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        read_active <= 1'b1;
        read_base   <= axi4.araddr;
        read_len    <= axi4.arlen;
        read_index  <= 8'd0;
        read_bursts <= read_bursts + 1;
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
        write_len    <= axi4.awlen;
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

  initial begin
    for (int index = 0; index < 2048; index++) begin
      memory[index] = 64'hdeadbeefdeadbeef;
    end
    memory[32'h0ff0>>3] = 64'h0706050403020100;
    memory[32'h0ff8>>3] = 64'h0f0e0d0c0b0a0908;
    memory[32'h1000>>3] = 64'h1716151413121110;
    memory[32'h1010>>3] = 64'h2726252423222120;
    memory[32'h1018>>3] = 64'h2f2e2d2c2b2a2928;
    memory[32'h1020>>3] = 64'h3736353433323130;
    read_start          = 1'b0;
    write_start         = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    read_start  = 1'b1;
    write_start = 1'b1;
    @(negedge clk);
    read_start  = 1'b0;
    write_start = 1'b0;
    while (read_busy || write_busy) @(negedge clk);
    if (error_flag || read_bytes != 32'd40 || write_bytes != 32'd40) begin
      $fatal(1, "DMA status mismatch: err=%0d read=%0d write=%0d", error_flag, read_bytes,
             write_bytes);
    end
    if (read_bursts < 3) $fatal(1, "4 KiB or line boundary was not split");
    if (memory[32'h2000>>3] != 64'h0706050403020100 ||
        memory[32'h2008>>3] != 64'h0f0e0d0c0b0a0908 ||
        memory[32'h2010>>3][31:0] != 32'h13121110 ||
        memory[32'h2020>>3] != 64'h2726252423222120 ||
        memory[32'h2028>>3] != 64'h2f2e2d2c2b2a2928 ||
        memory[32'h2030>>3][31:0] != 32'h33323130) begin
      $fatal(1, "2D DMA payload mismatch");
    end
    if (memory[32'h2010>>3][63:32] != 32'hdeadbeef ||
        memory[32'h2030>>3][63:32] != 32'hdeadbeef) begin
      $fatal(1, "tail strobe corrupted memory");
    end
    $display("JPEG DMA tests passed");
    $finish;
  end
endmodule
