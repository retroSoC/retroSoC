`timescale 1ns / 1ps

// Directed unit test for npu_local_sram. Runs identically against the
// inferred behavioral banks (+define+PDK_BEHAV) and the IHP130 macro wrapper
// (+define+PDK_IHP130 +define+HAVE_SRAM_MACRO + the RM_IHPSG13_1P models).
module npu_local_sram_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          clear_i = 1'b0;
  logic          raw_write_valid_i = 1'b0;
  logic          raw_write_half_i = 1'b0;
  logic   [12:0] raw_write_addr_i = 13'd0;
  logic   [31:0] raw_write_data_i = 32'd0;
  logic   [ 3:0] raw_write_strb_i = 4'd0;
  logic          raw_read_valid_i = 1'b0;
  logic          raw_read_half_i = 1'b0;
  logic   [12:0] raw_read_addr_i = 13'd0;
  logic   [31:0] raw_read_data_o;
  logic          pack_write_valid_i = 1'b0;
  logic          pack_write_sel_w_i = 1'b0;
  logic          pack_write_half_i = 1'b0;
  logic   [12:0] pack_write_addr_i = 13'd0;
  logic   [63:0] pack_write_data_i = 64'd0;
  logic   [ 7:0] pack_write_strb_i = 8'd0;
  logic          a_read_valid_i = 1'b0;
  logic          a_read_half_i = 1'b0;
  logic   [12:0] a_read_addr_i = 13'd0;
  logic   [63:0] a_read_data_o;
  logic          w_read_valid_i = 1'b0;
  logic          w_read_half_i = 1'b0;
  logic   [12:0] w_read_addr_i = 13'd0;
  logic   [63:0] w_read_data_o;
  logic          out_req_valid_i = 1'b0;
  logic          out_req_write_i = 1'b0;
  logic          out_req_half_i = 1'b0;
  logic   [11:0] out_req_addr_i = 12'd0;
  logic   [31:0] out_req_data_i = 32'd0;
  logic   [ 3:0] out_req_strb_i = 4'd0;
  logic   [31:0] out_read_data_o;
  logic          param_write_valid_i = 1'b0;
  logic   [12:0] param_write_addr_i = 13'd0;
  logic   [31:0] param_write_data_i = 32'd0;
  logic   [ 3:0] param_write_strb_i = 4'd0;
  logic          param_read_valid_i = 1'b0;
  logic   [12:0] param_read_addr_i = 13'd0;
  logic   [31:0] param_read_data_o;
  logic          access_err_sticky_o;
  logic   [ 2:0] access_err_port_o;
  integer        checks = 0;

  always #5 clk_i = ~clk_i;

  npu_local_sram u_npu_local_sram (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .clear_i            (clear_i),
      .raw_write_valid_i  (raw_write_valid_i),
      .raw_write_half_i   (raw_write_half_i),
      .raw_write_addr_i   (raw_write_addr_i),
      .raw_write_data_i   (raw_write_data_i),
      .raw_write_strb_i   (raw_write_strb_i),
      .raw_read_valid_i   (raw_read_valid_i),
      .raw_read_half_i    (raw_read_half_i),
      .raw_read_addr_i    (raw_read_addr_i),
      .raw_read_data_o    (raw_read_data_o),
      .pack_write_valid_i (pack_write_valid_i),
      .pack_write_sel_w_i (pack_write_sel_w_i),
      .pack_write_half_i  (pack_write_half_i),
      .pack_write_addr_i  (pack_write_addr_i),
      .pack_write_data_i  (pack_write_data_i),
      .pack_write_strb_i  (pack_write_strb_i),
      .a_read_valid_i     (a_read_valid_i),
      .a_read_half_i      (a_read_half_i),
      .a_read_addr_i      (a_read_addr_i),
      .a_read_data_o      (a_read_data_o),
      .w_read_valid_i     (w_read_valid_i),
      .w_read_half_i      (w_read_half_i),
      .w_read_addr_i      (w_read_addr_i),
      .w_read_data_o      (w_read_data_o),
      .out_req_valid_i    (out_req_valid_i),
      .out_req_write_i    (out_req_write_i),
      .out_req_half_i     (out_req_half_i),
      .out_req_addr_i     (out_req_addr_i),
      .out_req_data_i     (out_req_data_i),
      .out_req_strb_i     (out_req_strb_i),
      .out_read_data_o    (out_read_data_o),
      .param_write_valid_i(param_write_valid_i),
      .param_write_addr_i (param_write_addr_i),
      .param_write_data_i (param_write_data_i),
      .param_write_strb_i (param_write_strb_i),
      .param_read_valid_i (param_read_valid_i),
      .param_read_addr_i  (param_read_addr_i),
      .param_read_data_o  (param_read_data_o),
      .access_err_sticky_o(access_err_sticky_o),
      .access_err_port_o  (access_err_port_o)
  );

  function automatic logic [31:0] merge32(input logic [31:0] old_i, input logic [31:0] new_i,
                                          input logic [3:0] strb_i);
    merge32 = old_i;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (strb_i[byte_idx]) merge32[byte_idx*8+:8] = new_i[byte_idx*8+:8];
    end
  endfunction

  function automatic logic [63:0] merge64(input logic [63:0] old_i, input logic [63:0] new_i,
                                          input logic [7:0] strb_i);
    merge64 = old_i;
    for (int byte_idx = 0; byte_idx < 8; byte_idx++) begin
      if (strb_i[byte_idx]) merge64[byte_idx*8+:8] = new_i[byte_idx*8+:8];
    end
  endfunction

  task automatic raw_write(input logic half_i, input logic [12:0] addr_i, input logic [31:0] data_i,
                           input logic [3:0] strb_i);
    @(negedge clk_i);
    raw_write_valid_i = 1'b1;
    raw_write_half_i  = half_i;
    raw_write_addr_i  = addr_i;
    raw_write_data_i  = data_i;
    raw_write_strb_i  = strb_i;
    @(negedge clk_i);
    raw_write_valid_i = 1'b0;
    raw_write_strb_i  = 4'd0;
  endtask

  task automatic raw_read_check(input logic half_i, input logic [12:0] addr_i,
                                input logic [31:0] expected_i);
    @(negedge clk_i);
    raw_read_valid_i = 1'b1;
    raw_read_half_i  = half_i;
    raw_read_addr_i  = addr_i;
    @(negedge clk_i);
    raw_read_valid_i = 1'b0;
    if (raw_read_data_o !== expected_i) begin
      $fatal(1, "raw read half=%0d addr=%h data=%h expected=%h", half_i, addr_i, raw_read_data_o,
             expected_i);
    end
    checks = checks + 1;
  endtask

  task automatic pack_write(input logic sel_w_i, input logic half_i, input logic [12:0] addr_i,
                            input logic [63:0] data_i, input logic [7:0] strb_i);
    @(negedge clk_i);
    pack_write_valid_i = 1'b1;
    pack_write_sel_w_i = sel_w_i;
    pack_write_half_i  = half_i;
    pack_write_addr_i  = addr_i;
    pack_write_data_i  = data_i;
    pack_write_strb_i  = strb_i;
    @(negedge clk_i);
    pack_write_valid_i = 1'b0;
    pack_write_strb_i  = 8'd0;
  endtask

  task automatic a_read_check(input logic half_i, input logic [12:0] addr_i,
                              input logic [63:0] expected_i);
    @(negedge clk_i);
    a_read_valid_i = 1'b1;
    a_read_half_i  = half_i;
    a_read_addr_i  = addr_i;
    @(negedge clk_i);
    a_read_valid_i = 1'b0;
    if (a_read_data_o !== expected_i) begin
      $fatal(1, "A read half=%0d addr=%h data=%h expected=%h", half_i, addr_i, a_read_data_o,
             expected_i);
    end
    checks = checks + 1;
  endtask

  task automatic w_read_check(input logic half_i, input logic [12:0] addr_i,
                              input logic [63:0] expected_i);
    @(negedge clk_i);
    w_read_valid_i = 1'b1;
    w_read_half_i  = half_i;
    w_read_addr_i  = addr_i;
    @(negedge clk_i);
    w_read_valid_i = 1'b0;
    if (w_read_data_o !== expected_i) begin
      $fatal(1, "W read half=%0d addr=%h data=%h expected=%h", half_i, addr_i, w_read_data_o,
             expected_i);
    end
    checks = checks + 1;
  endtask

  task automatic out_write(input logic half_i, input logic [11:0] addr_i, input logic [31:0] data_i,
                           input logic [3:0] strb_i);
    @(negedge clk_i);
    out_req_valid_i = 1'b1;
    out_req_write_i = 1'b1;
    out_req_half_i  = half_i;
    out_req_addr_i  = addr_i;
    out_req_data_i  = data_i;
    out_req_strb_i  = strb_i;
    @(negedge clk_i);
    out_req_valid_i = 1'b0;
    out_req_write_i = 1'b0;
    out_req_strb_i  = 4'd0;
  endtask

  task automatic out_read_check(input logic half_i, input logic [11:0] addr_i,
                                input logic [31:0] expected_i);
    @(negedge clk_i);
    out_req_valid_i = 1'b1;
    out_req_write_i = 1'b0;
    out_req_half_i  = half_i;
    out_req_addr_i  = addr_i;
    @(negedge clk_i);
    out_req_valid_i = 1'b0;
    if (out_read_data_o !== expected_i) begin
      $fatal(1, "out read half=%0d addr=%h data=%h expected=%h", half_i, addr_i, out_read_data_o,
             expected_i);
    end
    checks = checks + 1;
  endtask

  task automatic param_write(input logic [12:0] addr_i, input logic [31:0] data_i,
                             input logic [3:0] strb_i);
    @(negedge clk_i);
    param_write_valid_i = 1'b1;
    param_write_addr_i  = addr_i;
    param_write_data_i  = data_i;
    param_write_strb_i  = strb_i;
    @(negedge clk_i);
    param_write_valid_i = 1'b0;
    param_write_strb_i  = 4'd0;
  endtask

  task automatic param_read_check(input logic [12:0] addr_i, input logic [31:0] expected_i);
    @(negedge clk_i);
    param_read_valid_i = 1'b1;
    param_read_addr_i  = addr_i;
    @(negedge clk_i);
    param_read_valid_i = 1'b0;
    if (param_read_data_o !== expected_i) begin
      $fatal(1, "param read addr=%h data=%h expected=%h", addr_i, param_read_data_o, expected_i);
    end
    checks = checks + 1;
  endtask

  task automatic check_err(input logic [2:0] port_i);
    if (access_err_sticky_o !== 1'b1) begin
      $fatal(1, "sticky error not raised for port %0d", port_i);
    end
    if (access_err_port_o !== port_i) begin
      $fatal(1, "error port mismatch got=%0d expected=%0d", access_err_port_o, port_i);
    end
    checks = checks + 1;
  endtask

  task automatic sram_clear;
    @(negedge clk_i);
    clear_i = 1'b1;
    @(negedge clk_i);
    clear_i = 1'b0;
    if (access_err_sticky_o !== 1'b0) $fatal(1, "sticky error survived clear_i");
    if (access_err_port_o !== 3'd7) $fatal(1, "error port not cleared");
    checks = checks + 1;
  endtask

  initial begin
    repeat (4) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if (access_err_sticky_o !== 1'b0) $fatal(1, "sticky error after reset");
    if (access_err_port_o !== 3'd7) $fatal(1, "error port not None after reset");

    // ---- write/read every partition via its ports ----
    raw_write(1'b0, 13'h0000, 32'h10203040, 4'hf);
    raw_write(1'b0, 13'h1004, 32'h50607080, 4'hf);
    raw_write(1'b1, 13'h0004, 32'h90a0b0c0, 4'hf);
    raw_write(1'b1, 13'h1ffc, 32'hd0e0f000, 4'hf);
    raw_read_check(1'b0, 13'h0000, 32'h10203040);
    raw_read_check(1'b0, 13'h1004, 32'h50607080);
    raw_read_check(1'b1, 13'h0004, 32'h90a0b0c0);
    raw_read_check(1'b1, 13'h1ffc, 32'hd0e0f000);

    // ---- byte strobes: every 4-bit pattern on the raw port ----
    for (int pattern = 0; pattern < 16; pattern++) begin
      raw_write(1'b0, 13'h0040, 32'haabbccdd, 4'hf);
      raw_write(1'b0, 13'h0040, 32'h11223344, 4'(pattern));
      raw_read_check(1'b0, 13'h0040, merge32(32'haabbccdd, 32'h11223344, 4'(pattern)));
    end
    // ---- byte strobes on the packed A 64-bit port ----
    for (int pattern = 0; pattern < 256; pattern += 85) begin
      pack_write(1'b0, 1'b0, 13'h0080, 64'haabbccdd11223344, 8'hff);
      pack_write(1'b0, 1'b0, 13'h0080, 64'h55667788990abcde, 8'(pattern));
      a_read_check(1'b0, 13'h0080, merge64(64'haabbccdd11223344, 64'h55667788990abcde, 8'(pattern)
                   ));
    end

    // ---- 64-bit A/W accesses ----
    pack_write(1'b0, 1'b0, 13'h0100, 64'h1122334455667788, 8'hff);
    a_read_check(1'b0, 13'h0100, 64'h1122334455667788);
    pack_write(1'b1, 1'b1, 13'h0180, 64'hdeadbeefcafebabe, 8'hff);
    w_read_check(1'b1, 13'h0180, 64'hdeadbeefcafebabe);

    // ---- two independent A+W reads in one cycle ----
    @(negedge clk_i);
    a_read_valid_i = 1'b1;
    a_read_half_i  = 1'b0;
    a_read_addr_i  = 13'h0100;
    w_read_valid_i = 1'b1;
    w_read_half_i  = 1'b1;
    w_read_addr_i  = 13'h0180;
    @(negedge clk_i);
    a_read_valid_i = 1'b0;
    w_read_valid_i = 1'b0;
    if (a_read_data_o !== 64'h1122334455667788) $fatal(1, "concurrent A read mismatch");
    if (w_read_data_o !== 64'hdeadbeefcafebabe) $fatal(1, "concurrent W read mismatch");
    checks = checks + 1;

    // ---- inactive-half pack write concurrent with active-half read ----
    @(negedge clk_i);
    a_read_valid_i     = 1'b1;
    a_read_half_i      = 1'b0;
    a_read_addr_i      = 13'h0100;
    pack_write_valid_i = 1'b1;
    pack_write_sel_w_i = 1'b0;
    pack_write_half_i  = 1'b1;
    pack_write_addr_i  = 13'h0200;
    pack_write_data_i  = 64'h0123456789abcdef;
    pack_write_strb_i  = 8'hff;
    @(negedge clk_i);
    a_read_valid_i     = 1'b0;
    pack_write_valid_i = 1'b0;
    pack_write_strb_i  = 8'd0;
    if (a_read_data_o !== 64'h1122334455667788) $fatal(1, "cross-half concurrent read mismatch");
    if (access_err_sticky_o !== 1'b0) $fatal(1, "legal cross-half access flagged");
    a_read_check(1'b1, 13'h0200, 64'h0123456789abcdef);
    checks = checks + 1;

    // ---- output staging both halves ----
    out_write(1'b0, 12'h000, 32'h11112222, 4'hf);
    out_write(1'b1, 12'hffc, 32'h33334444, 4'hf);
    out_read_check(1'b0, 12'h000, 32'h11112222);
    out_read_check(1'b1, 12'hffc, 32'h33334444);

    // ---- parameter region both banks ----
    param_write(13'h0000, 32'h55556666, 4'hf);
    param_write(13'h1004, 32'h77778888, 4'hf);
    param_read_check(13'h0000, 32'h55556666);
    param_read_check(13'h1004, 32'h77778888);

    // ---- explicit synchronous-read latency probe ----
    raw_write(1'b0, 13'h0020, 32'h5555aaaa, 4'hf);
    @(negedge clk_i);
    raw_read_valid_i = 1'b1;
    raw_read_half_i  = 1'b0;
    raw_read_addr_i  = 13'h0020;
    #1;
    if (raw_read_data_o === 32'h5555aaaa) $fatal(1, "raw read is not synchronous");
    @(negedge clk_i);
    raw_read_valid_i = 1'b0;
    if (raw_read_data_o !== 32'h5555aaaa) $fatal(1, "raw read latency not one cycle");
    checks = checks + 1;

    // ---- invalid-word read errors on every read port ----
    sram_clear;
    @(negedge clk_i);
    raw_read_valid_i = 1'b1;
    raw_read_half_i  = 1'b1;
    raw_read_addr_i  = 13'h0800;
    @(negedge clk_i);
    raw_read_valid_i = 1'b0;
    check_err(3'd1);
    sram_clear;
    @(negedge clk_i);
    a_read_valid_i = 1'b1;
    a_read_half_i  = 1'b0;
    a_read_addr_i  = 13'h0800;
    @(negedge clk_i);
    a_read_valid_i = 1'b0;
    check_err(3'd3);
    sram_clear;
    @(negedge clk_i);
    w_read_valid_i = 1'b1;
    w_read_half_i  = 1'b1;
    w_read_addr_i  = 13'h1000;
    @(negedge clk_i);
    w_read_valid_i = 1'b0;
    check_err(3'd4);
    sram_clear;
    @(negedge clk_i);
    out_req_valid_i = 1'b1;
    out_req_write_i = 1'b0;
    out_req_half_i  = 1'b1;
    out_req_addr_i  = 12'h400;
    @(negedge clk_i);
    out_req_valid_i = 1'b0;
    check_err(3'd5);
    sram_clear;
    @(negedge clk_i);
    param_read_valid_i = 1'b1;
    param_read_addr_i  = 13'h1800;
    @(negedge clk_i);
    param_read_valid_i = 1'b0;
    check_err(3'd6);
    sram_clear;

    // ---- misaligned 64-bit accesses ----
    @(negedge clk_i);
    a_read_valid_i = 1'b1;
    a_read_half_i  = 1'b0;
    a_read_addr_i  = 13'h0004;
    @(negedge clk_i);
    a_read_valid_i = 1'b0;
    check_err(3'd3);
    sram_clear;
    @(negedge clk_i);
    w_read_valid_i = 1'b1;
    w_read_half_i  = 1'b0;
    w_read_addr_i  = 13'h0001;
    @(negedge clk_i);
    w_read_valid_i = 1'b0;
    check_err(3'd4);
    sram_clear;
    // misaligned pack write is suppressed and flagged
    pack_write(1'b0, 1'b0, 13'h0040, 64'haaaabbbbccccdddd, 8'hff);
    @(negedge clk_i);
    pack_write_valid_i = 1'b1;
    pack_write_sel_w_i = 1'b0;
    pack_write_half_i  = 1'b0;
    pack_write_addr_i  = 13'h0042;
    pack_write_data_i  = 64'h1111111111111111;
    pack_write_strb_i  = 8'hff;
    @(negedge clk_i);
    pack_write_valid_i = 1'b0;
    pack_write_strb_i  = 8'd0;
    check_err(3'd2);
    a_read_check(1'b0, 13'h0040, 64'haaaabbbbccccdddd);
    sram_clear;

    // ---- raw same-half conflict (same bank): read wins, write dropped ----
    raw_write(1'b0, 13'h0100, 32'haaaa0001, 4'hf);
    raw_write(1'b0, 13'h0104, 32'haaaa0002, 4'hf);
    @(negedge clk_i);
    raw_write_valid_i = 1'b1;
    raw_write_half_i  = 1'b0;
    raw_write_addr_i  = 13'h0100;
    raw_write_data_i  = 32'h99999999;
    raw_write_strb_i  = 4'hf;
    raw_read_valid_i  = 1'b1;
    raw_read_half_i   = 1'b0;
    raw_read_addr_i   = 13'h0100;
    @(negedge clk_i);
    raw_write_valid_i = 1'b0;
    raw_write_strb_i  = 4'd0;
    raw_read_valid_i  = 1'b0;
    if (raw_read_data_o !== 32'haaaa0001) $fatal(1, "raw read did not win the conflict");
    check_err(3'd0);
    raw_read_check(1'b0, 13'h0100, 32'haaaa0001);
    sram_clear;

    // ---- raw same-half conflict (different banks): still an error ----
    raw_write(1'b0, 13'h0000, 32'hbbbb0001, 4'hf);
    raw_write(1'b0, 13'h1000, 32'hbbbb0002, 4'hf);
    @(negedge clk_i);
    raw_write_valid_i = 1'b1;
    raw_write_half_i  = 1'b0;
    raw_write_addr_i  = 13'h1000;
    raw_write_data_i  = 32'h88888888;
    raw_write_strb_i  = 4'hf;
    raw_read_valid_i  = 1'b1;
    raw_read_half_i   = 1'b0;
    raw_read_addr_i   = 13'h0000;
    @(negedge clk_i);
    raw_write_valid_i = 1'b0;
    raw_write_strb_i  = 4'd0;
    raw_read_valid_i  = 1'b0;
    if (raw_read_data_o !== 32'hbbbb0001) $fatal(1, "raw read did not win cross-bank conflict");
    check_err(3'd0);
    raw_read_check(1'b0, 13'h1000, 32'hbbbb0002);
    sram_clear;

    // ---- pack write vs a_read same-half conflict ----
    pack_write(1'b0, 1'b0, 13'h0080, 64'hcccc000000000001, 8'hff);
    @(negedge clk_i);
    pack_write_valid_i = 1'b1;
    pack_write_sel_w_i = 1'b0;
    pack_write_half_i  = 1'b0;
    pack_write_addr_i  = 13'h0080;
    pack_write_data_i  = 64'h7777777777777777;
    pack_write_strb_i  = 8'hff;
    a_read_valid_i     = 1'b1;
    a_read_half_i      = 1'b0;
    a_read_addr_i      = 13'h0080;
    @(negedge clk_i);
    pack_write_valid_i = 1'b0;
    pack_write_strb_i  = 8'd0;
    a_read_valid_i     = 1'b0;
    if (a_read_data_o !== 64'hcccc000000000001) $fatal(1, "A read did not win the conflict");
    check_err(3'd2);
    a_read_check(1'b0, 13'h0080, 64'hcccc000000000001);
    sram_clear;

    // ---- pack write vs w_read same-half conflict ----
    pack_write(1'b1, 1'b1, 13'h0100, 64'hdddd000000000002, 8'hff);
    @(negedge clk_i);
    pack_write_valid_i = 1'b1;
    pack_write_sel_w_i = 1'b1;
    pack_write_half_i  = 1'b1;
    pack_write_addr_i  = 13'h0100;
    pack_write_data_i  = 64'h6666666666666666;
    pack_write_strb_i  = 8'hff;
    w_read_valid_i     = 1'b1;
    w_read_half_i      = 1'b1;
    w_read_addr_i      = 13'h0100;
    @(negedge clk_i);
    pack_write_valid_i = 1'b0;
    pack_write_strb_i  = 8'd0;
    w_read_valid_i     = 1'b0;
    if (w_read_data_o !== 64'hdddd000000000002) $fatal(1, "W read did not win the conflict");
    check_err(3'd2);
    w_read_check(1'b1, 13'h0100, 64'hdddd000000000002);
    sram_clear;

    // ---- first failing port is sticky until clear_i ----
    @(negedge clk_i);
    raw_read_valid_i = 1'b1;
    raw_read_half_i  = 1'b0;
    raw_read_addr_i  = 13'h0400;
    @(negedge clk_i);
    raw_read_valid_i = 1'b0;
    check_err(3'd1);
    @(negedge clk_i);
    a_read_valid_i = 1'b1;
    a_read_half_i  = 1'b0;
    a_read_addr_i  = 13'h0400;
    @(negedge clk_i);
    a_read_valid_i = 1'b0;
    if (access_err_port_o !== 3'd1) $fatal(1, "first failing port not retained");
    checks = checks + 1;
    sram_clear;

    // ---- clear_i invalidates previously written words ----
    raw_write(1'b0, 13'h0300, 32'hdddd0001, 4'hf);
    raw_read_check(1'b0, 13'h0300, 32'hdddd0001);
    sram_clear;
    @(negedge clk_i);
    raw_read_valid_i = 1'b1;
    raw_read_half_i  = 1'b0;
    raw_read_addr_i  = 13'h0300;
    @(negedge clk_i);
    raw_read_valid_i = 1'b0;
    check_err(3'd1);
    sram_clear;

    $display("NPU_LOCAL_SRAM_PASS checks=%0d", checks);
    $finish;
  end

  initial begin
    #5000000;
    $fatal(1, "npu_local_sram_tb timeout");
  end
endmodule
