// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_packet_ram_tb;
  logic        s_clk;
  logic        s_rst_n;
  logic        s_write;
  logic        s_read;
  logic [11:0] s_addr;
  logic [31:0] s_write_data;
  logic        s_inject_single;
  logic        s_inject_double;
  logic [31:0] s_read_data;
  logic        s_read_valid;
  logic        s_corrected;
  logic        s_uncorrectable;

  usb2_packet_ram #(
      .EnableFaultInjection(1'b1)
  ) u_packet_ram (
      .clk_i          (s_clk),
      .rst_n_i        (s_rst_n),
      .write_i        (s_write),
      .read_i         (s_read),
      .addr_i         (s_addr),
      .write_data_i   (s_write_data),
      .inject_single_i(s_inject_single),
      .inject_double_i(s_inject_double),
      .read_data_o    (s_read_data),
      .read_valid_o   (s_read_valid),
      .corrected_o    (s_corrected),
      .uncorrectable_o(s_uncorrectable)
  );

  always #5 s_clk = ~s_clk;

  task automatic write_word(input logic [11:0] addr_i, input logic [31:0] data_i,
                            input logic single_i, input logic double_i);
    begin
      @(negedge s_clk);
      s_addr          = addr_i;
      s_write_data    = data_i;
      s_inject_single = single_i;
      s_inject_double = double_i;
      s_write         = 1'b1;
      @(negedge s_clk);
      s_write         = 1'b0;
      s_inject_single = 1'b0;
      s_inject_double = 1'b0;
    end
  endtask

  task automatic read_word(input logic [11:0] addr_i);
    begin
      @(negedge s_clk);
      s_addr = addr_i;
      s_read = 1'b1;
      @(posedge s_clk);
      #1;
      s_read = 1'b0;
    end
  endtask

  initial begin
    s_clk           = 1'b0;
    s_rst_n         = 1'b0;
    s_write         = 1'b0;
    s_read          = 1'b0;
    s_addr          = '0;
    s_write_data    = '0;
    s_inject_single = 1'b0;
    s_inject_double = 1'b0;
    repeat (2) @(negedge s_clk);
    s_rst_n = 1'b1;

    write_word(12'h010, 32'h1357_9BDF, 1'b0, 1'b0);
    read_word(12'h010);
    if (!s_read_valid || s_corrected || s_uncorrectable || (s_read_data != 32'h1357_9BDF)) begin
      $fatal(1, "USB2 packet RAM clean read failed");
    end

    write_word(12'h011, 32'h2468_ACE0, 1'b1, 1'b0);
    read_word(12'h011);
    if (!s_read_valid || !s_corrected || s_uncorrectable || (s_read_data != 32'h2468_ACE0)) begin
      $fatal(1, "USB2 packet RAM single-bit correction failed");
    end

    write_word(12'h012, 32'h55AA_F00D, 1'b0, 1'b1);
    read_word(12'h012);
    if (!s_read_valid || !s_uncorrectable) begin
      $fatal(1, "USB2 packet RAM double-bit detection failed");
    end
    $display("USB2 packet RAM ECC test passed");
    $finish;
  end
endmodule
