// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
`include "crypto_define.svh"
module crypto_v2_tb;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;
  apb4_if apb4 (
      .pclk   (clk),
      .presetn(rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) crypto_in_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) crypto_out_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  logic          irq;
  logic [  31:0] constants   [0:2047];
  logic [ 255:0] expected_sha[  0:21];
  logic [2047:0] rsa_vectors [   0:5];
  string constant_path, sha_path, rsa_path;
  int unsigned        transactions = 0;
  int unsigned        max_wait = 0;
  logic               check_erased = 0;
  logic               output_stalled = 0;
  logic        [36:0] held_output;
  always @(posedge clk) begin
    if (rst_n && output_stalled &&
        (!crypto_out_axis.tvalid ||
         {crypto_out_axis.tlast, crypto_out_axis.tkeep, crypto_out_axis.tdata} !== held_output))
      $fatal(1, "stalled output beat changed");
    output_stalled <= rst_n && crypto_out_axis.tvalid && !crypto_out_axis.tready;
    held_output    <= {crypto_out_axis.tlast, crypto_out_axis.tkeep, crypto_out_axis.tdata};
    if (check_erased) begin
      for (int index = 0; index < 8; index++) begin
        if (u_dut.u_aes.u_input_fifo.u_payload.r_storage[index] !== 37'd0 ||
            u_dut.u_aes.u_output_fifo.u_payload.r_storage[index] !== 37'd0)
          $fatal(1, "AES FIFO payload retained after erasure");
      end
      for (int index = 0; index < 16; index++)
      if (u_dut.u_sha.u_input_fifo.u_payload.r_storage[index] !== 37'd0)
        $fatal(1, "SHA FIFO payload retained after erasure");
    end
  end
  for (genvar bank = 2; bank < 6; bank++) begin : gen_erase_check
    always @(posedge clk)
      if (check_erased) begin
        for (int row = 0; row < 1024; row++) begin
`ifdef HAVE_SRAM_MACRO
          if (u_dut.u_storage.gen_bank[
              bank].gen_macro.u_sram.u_mem.i_SRAM_1P_behavioral_bm_bist.memory[row] !== 32'd0)
            $fatal(1, "bank %0d row %0d retained after erasure", bank, row);
`else
          if (u_dut.u_storage.gen_bank[bank].s_storage_q[row] !== 32'd0)
            $fatal(1, "bank %0d row %0d retained after erasure", bank, row);
`endif
        end
      end
  end
`ifdef CRYPTO_RESPONSE_DELAY
  localparam int TestResponseDelay = `CRYPTO_RESPONSE_DELAY;
`else
  localparam int TestResponseDelay = 0;
`endif
`ifdef CRYPTO_RESPONSE_DROP_MASK
  localparam logic [5:0] TestDropResponseMask = 6'(`CRYPTO_RESPONSE_DROP_MASK);
`else
  localparam logic [5:0] TestDropResponseMask = 6'd0;
`endif
`ifdef CRYPTO_RESPONSE_DUPLICATE
  localparam bit TestDuplicateResponse = 1'b1;
`else
  localparam bit TestDuplicateResponse = 1'b0;
`endif
  apb4_crypto #(
      .ResponseDelay    (TestResponseDelay),
      .DropResponseMask (TestDropResponseMask),
      .DuplicateResponse(TestDuplicateResponse)
  ) u_dut (
      .clk_i            (clk),
      .rst_n_i          (rst_n),
      .dma_input_proc_o (),
      .dma_output_proc_o(),
      .irq_o            (irq),
      .apb4             (apb4),
      .crypto_in_axis   (crypto_in_axis),
      .crypto_out_axis  (crypto_out_axis)
  );
  task automatic access (input logic write, input logic [11:0] address, input logic [31:0] data,
                         input logic [3:0] mask, input logic expected_error,
                         output logic [31:0] result);
    int unsigned cycles;
    @(negedge clk);
    apb4.psel    = 1;
    apb4.penable = 0;
    apb4.pwrite  = write;
    apb4.paddr   = {20'd0, address};
    apb4.pwdata  = data;
    apb4.pstrb   = mask;
    @(negedge clk);
    apb4.penable = 1;
    cycles       = 0;
    #1;
    while (!apb4.pready) begin
      @(negedge clk);
      #1;
      cycles++;
      if (cycles > 4) $fatal(1, "APB exceeded wait bound at %h", address);
    end
    if (cycles > max_wait) max_wait = cycles;
    if (apb4.pslverr !== expected_error)
      $fatal(
          1,
          "APB error mismatch write=%b addr=%h data=%h error=%b expected=%b",
          write,
          address,
          data,
          apb4.pslverr,
          expected_error
      );
    result = apb4.prdata;
    @(negedge clk);
    apb4.psel    = 0;
    apb4.penable = 0;
    transactions++;
  endtask
  task automatic put(input logic [11:0] address, input logic [31:0] data);
    logic [31:0] unused_data;
    access (1, address, data, 4'hf, 0, unused_data);
  endtask
  task automatic get(input logic [11:0] address, output logic [31:0] data);
    access (0, address, 0, 4'hf, 0, data);
  endtask
  task automatic expect_reg(input logic [11:0] address, input logic [31:0] mask,
                            input logic [31:0] expected);
    logic [31:0] value;
    get(address, value);
    if ((value & mask) !== expected)
      $fatal(1, "register %h got %h mask %h expected %h", address, value, mask, expected);
  endtask
  task automatic poll(input logic [11:0] address, input logic [31:0] mask,
                      input logic [31:0] expected, input int unsigned limit);
    logic [31:0] value;
    for (int unsigned attempt = 0; attempt < limit; attempt++) begin
      get(address, value);
      if ((value & mask) == expected) return;
    end
    $fatal(1, "poll timeout %h mask=%h expected=%h last=%h", address, mask, expected, value);
  endtask
  function automatic logic [31:0] reverse_word(input logic [31:0] value);
    return {value[7:0], value[15:8], value[23:16], value[31:24]};
  endfunction
  task automatic initialize;
    logic [31:0] unused_data;
    poll(12'h028, 4, 0, 800);
    expect_reg(12'h018, 32'h10, 0);
    expect_reg(12'h004, 32'hffffffff, 32'h00020000);
    expect_reg(12'h030, 32'hffffffff, 32'h43525901);
    access (1, 12'h100, 1, 4'hf, 1, unused_data);
    // Count and padding failures invalidate an attempt and permit retry.
    put(12'h02c, 1);
    put(12'h038, constants[0]);
    access (1, 12'h02c, 2, 4'hf, 1, unused_data);
    expect_reg(12'h040, 32'h800000ff, 32'h80000001);
    put(12'h02c, 1);
    access (1, 12'h038, 32'h100, 4'hf, 1, unused_data);
    expect_reg(12'h040, 32'h800000ff, 32'h80000002);
    put(12'h02c, 1);
    access (1, 12'h038, constants[0], 4'h1, 1, unused_data);
    expect_reg(12'h034, 32'hffffffff, 0);
    put(12'h02c, 4);
    // A complete but corrupted input is rejected before readback.
    put(12'h02c, 1);
    for (int index = 0; index < 2048; index++)
      put(12'h038, constants[index] ^ (index == 0 ? 32'd1 : 32'd0));
    access (1, 12'h02c, 2, 4'hf, 1, unused_data);
    expect_reg(12'h040, 32'h800000ff, 32'h80000003);
    // Inject one post-load SRAM fault, never a hierarchical initialization.
    put(12'h02c, 1);
    for (int index = 0; index < 2048; index++) put(12'h038, constants[index]);
`ifdef HAVE_SRAM_MACRO
    u_dut.u_storage.gen_bank[0].gen_macro.u_sram.u_mem.i_SRAM_1P_behavioral_bm_bist.memory[0] =
        constants[0] ^ 32'd1;
`else
    u_dut.u_storage.gen_bank[0].s_storage_q[0] = constants[0] ^ 32'd1;
`endif
    put(12'h02c, 2);
    poll(12'h028, 16, 0, 2800);
    expect_reg(12'h040, 32'h800000ff, 32'h80000004);
    expect_reg(12'h028, 35, 0);
    // CRC-neutral padding corruption must fail the independent row check.
    put(12'h02c, 1);
    for (int index = 0; index < 2048; index++) put(12'h038, constants[index]);
`ifdef HAVE_SRAM_MACRO
    u_dut.u_storage.gen_bank[0].gen_macro.u_sram.u_mem.i_SRAM_1P_behavioral_bm_bist.memory[528] = 1;
    u_dut.u_storage.gen_bank[0].gen_macro.u_sram.u_mem.i_SRAM_1P_behavioral_bm_bist.memory[529] =
        32'hb8bc6765;
`else
    u_dut.u_storage.gen_bank[0].s_storage_q[528] = 1;
    u_dut.u_storage.gen_bank[0].s_storage_q[529] = 32'hb8bc6765;
`endif
    put(12'h02c, 2);
    poll(12'h028, 16, 0, 2800);
    expect_reg(12'h040, 32'hffffffff, 32'h80108002);
    expect_reg(12'h028, 35, 0);
    put(12'h02c, 1);
    for (int index = 0; index < 2048; index++) put(12'h038, constants[index]);
    expect_reg(12'h034, 32'hffffffff, 2048);
    put(12'h02c, 2);
    expect_reg(12'h028, 32'h23, 0);
    poll(12'h028, 32'h7f, 32'h23, 2800);
    expect_reg(12'h03c, 32'hffffffff, 32'h99ca52fe);
    expect_reg(12'h018, 32'h20, 32'h20);
    access (1, 12'h038, 0, 4'hf, 1, unused_data);
    access (1, 12'h02c, 4, 4'hf, 1, unused_data);
    expect_reg(12'h028, 32'h7f, 32'h23);
    put(12'h024, 31);
    put(12'h018, 63);
  endtask
  task automatic aes_key(input logic [255:0] value, input logic [1:0] size);
    logic [31:0] unused_data;
    put(12'h104, {26'd0, size, 4'd0});
    for (int word_index = 0; word_index < 8; word_index++)
      put(12'h140 + 12'(word_index * 4), reverse_word(value[255-word_index*32-:32]));
    access (0, 12'h140, 0, 4'hf, 1, unused_data);
    put(12'h128, 1);
    poll(12'h12c, 3, 1, 700);
    get(12'h124, unused_data);
    if (unused_data > 2048) $fatal(1, "AES key cycle bound %0d", unused_data);
  endtask
  task automatic aes_block(input logic [1:0] size, input logic [1:0] mode, input logic decrypt,
                           input logic [127:0] iv, input logic [127:0] plaintext,
                           input logic [127:0] expected, input int unsigned length);
    logic [31:0] value;
    put(12'h104, {26'd0, size, 1'b0, decrypt, mode});
    put(12'h10c, length);
    for (int word_index = 0; word_index < 4; word_index++)
      put(12'h160 + 12'(word_index * 4), reverse_word(iv[127-word_index*32-:32]));
    put(12'h100, 1);
    expect_reg(12'h108, 3, 1);
    for (int word_index = 0; word_index < int'((length + 3) / 4); word_index++) begin
      logic [3:0] mask;
      mask = (word_index * 4 + 4 <= int'(length)) ? 4'hf : 4'((1 << (length % 4)) - 1);
      poll(12'h118, 1, 1, 1000);
      access (1, 12'h110, reverse_word(plaintext[127-word_index*32-:32]), mask, 0, value);
    end
    for (int word_index = 0; word_index < int'((length + 3) / 4); word_index++) begin
      logic [31:0] mask;
      poll(12'h118, 2, 2, 1000);
      get(12'h114, value);
      mask = (word_index * 4 + 4 <= int'(length)) ?
          32'hffffffff : (32'd1 << ((length % 4) * 8)) - 1;
      if ((value & mask) !== (reverse_word(expected[127-word_index*32-:32]) & mask))
        $fatal(
            1,
            "AES mismatch size=%0d mode=%0d decrypt=%b word=%0d got=%h expected=%h",
            size,
            mode,
            decrypt,
            word_index,
            value,
            reverse_word(
                expected[127-word_index*32-:32]
            )
        );
    end
    poll(12'h108, 3, 2, 1000);
    get(12'h124, value);
    if (value > 1152) $fatal(1, "AES block cycle bound %0d", value);
    $display("CRYPTO_V2_AES size=%0d mode=%0d decrypt=%b bytes=%0d cycles=%0d", size, mode,
             decrypt, length, value);
  endtask
  task automatic sha_cases;
    for (int mode = 0; mode < 2; mode++) begin
      for (int test_id = 0; test_id < 11; test_id++) begin
        int           length;
        logic [255:0] digest;
        logic [ 31:0] value;
        case (test_id)
          0:       length = 0;
          1:       length = 1;
          2:       length = 3;
          3:       length = 55;
          4:       length = 56;
          5:       length = 63;
          6:       length = 64;
          7:       length = 65;
          8:       length = 127;
          9:       length = 128;
          default: length = 129;
        endcase
        put(12'h204, 32'(mode));
        put(12'h20c, 32'(length));
        put(12'h210, 0);
        put(12'h200, 1);
        expect_reg(12'h208, 3, 1);
        for (int offset = 0; offset < length; offset += 4) begin
          logic [31:0] data;
          logic [ 3:0] keep;
          data = 0;
          keep = 0;
          for (int lane = 0; lane < 4; lane++)
          if (offset + lane < length) begin
            data[lane*8+:8] = 8'(offset + lane);
            keep[lane]      = 1;
          end
          poll(12'h218, 1, 1, 1000);
          access (1, 12'h214, data, keep, 0, value);
        end
        poll(12'h208, 9, 8, 3000);
        for (int index = 0; index < 8; index++) begin
          get(12'h240 + 12'(index * 4), value);
          digest[255-index*32-:32] = value;
        end
        if (digest !== expected_sha[mode*11+test_id])
          $fatal(
              1,
              "SHA mismatch mode=%0d bytes=%0d got=%h expected=%h",
              mode,
              length,
              digest,
              expected_sha[mode*11+test_id]
          );
        get(12'h224, value);
        if (value > 32'(((length + 9 + 63) / 64) * 2048 + 128)) $fatal(1, "SHA cycle ceiling");
        $display("CRYPTO_V2_SHA mode=%0d bytes=%0d cycles=%0d", mode, length, value);
      end
    end
  endtask

  task automatic aes_multiblock(input logic [1:0] mode, input logic decrypt, input logic [127:0] iv,
                                input logic [255:0] data, input logic [255:0] expected,
                                input int length);
    logic [31:0] value;
    put(12'h104, {29'd0, decrypt, mode});
    put(12'h10c, 32'(length));
    for (int index = 0; index < 4; index++)
      put(12'h160 + 12'(index * 4), reverse_word(iv[127-index*32-:32]));
    put(12'h018, 1);
    put(12'h100, 1);
    for (int index = 0; index < (length + 3) / 4; index++) begin
      poll(12'h118, 1, 1, 1000);
      put(12'h110, reverse_word(data[255-index*32-:32]));
    end
    for (int index = 0; index < (length + 3) / 4; index++) begin
      poll(12'h118, 2, 2, 1000);
      get(12'h114, value);
      if (value !== reverse_word(expected[255-index*32-:32]))
        $fatal(1, "AES multi-block word %0d", index);
    end
    poll(12'h108, 3, 2, 100);
  endtask

  task automatic reset_boundaries;
    int count;
    for (int cut = 0; cut < 4; cut++) begin
      @(negedge clk);
      rst_n = 0;
      repeat (3) @(negedge clk);
      rst_n = 1;
      // Joining reset scrub is idempotent but requests a fresh completion.
      put(12'h010, 1);
      poll(12'h028, 4, 0, 800);
      expect_reg(12'h028, 127, 0);
      expect_reg(12'h018, 16, 16);
      put(12'h02c, 1);
      case (cut)
        0:       count = 0;
        1:       count = 1;
        2:       count = 1024;
        default: count = 2048;
      endcase
      for (int index = 0; index < count; index++) put(12'h038, constants[index]);
      if (cut == 3) begin
        put(12'h02c, 2);
        repeat (97) @(negedge clk);
      end
    end
    @(negedge clk);
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    poll(12'h028, 4, 0, 800);
    expect_reg(12'h028, 127, 0);
    expect_reg(12'h018, 63, 0);
    expect_reg(12'h034, 32'hffffffff, 0);
    $display("CRYPTO_V2_RESET_BOUNDARIES_PASS");
  endtask

  task automatic timeout_cancel_boundaries;
    logic locked_at_accept;
    for (int cut = 0; cut < 6; cut++) begin
      @(negedge clk);
      rst_n = 0;
      repeat (3) @(negedge clk);
      rst_n = 1;
      poll(12'h028, 4, 0, 800);
      put(12'h02c, 1);
      for (int index = 0; index < 2048; index++) put(12'h038, constants[index]);
      put(12'h02c, 2);
      if (cut != 0) repeat (2041 + cut) @(negedge clk);
      // Model the HAL timeout cleanup before, across and after lock. Capture
      // the old lock on the exact APB acceptance edge, not on a prior poll.
      fork
        begin
          wait (u_dut.s_zeroize);
          @(posedge clk);
          locked_at_accept = u_dut.s_mem_stat[5];
        end
        put(12'h010, 1);
      join
      poll(12'h028, 4, 0, 800);
      expect_reg(12'h028, 35, locked_at_accept ? 35 : 0);
      expect_reg(12'h024, 8, 0);
      if (!locked_at_accept) begin
        put(12'h02c, 1);
        put(12'h02c, 4);
        expect_reg(12'h034, 32'hffffffff, 0);
      end
    end
    $display("CRYPTO_V2_CANCEL_BOUNDARIES_PASS");
  endtask

  task automatic scrub_failure;
    logic [31:0] value;
    put(12'h010, 1);
    repeat (1200) @(negedge clk);
    // The row has been written but has not yet reached readback.
`ifdef HAVE_SRAM_MACRO
    u_dut.u_storage.gen_bank[2].gen_macro.u_sram.u_mem.i_SRAM_1P_behavioral_bm_bist.memory[1023] =
        32'hbad;
`else
    u_dut.u_storage.gen_bank[2].s_storage_q[1023] = 32'hbad;
`endif
    poll(12'h028, 64, 64, 400);
    expect_reg(12'h028, 65, 64);
    expect_reg(12'h018, 16, 0);
    expect_reg(12'h040, 32'hffffffff, 32'h801ffa05);
    put(12'h024, 16);
    expect_reg(12'h040, 32'hffffffff, 0);
    expect_reg(12'h028, 65, 64);
    access (1, 12'h010, 1, 4'hf, 1, value);
    $display("CRYPTO_V2_SCRUB_FAILURE_PASS");
  endtask

  task automatic fifo_scrub_failure;
    put(12'h018, 16);
    put(12'h010, 2);
    // Corrupt the first FIFO row after zero filling, before readback begins.
    wait (u_dut.u_aes.u_input_fifo.s_state_q == 3'd2);
    @(negedge clk);
    u_dut.u_aes.u_input_fifo.u_payload.r_storage[0] = 37'd1;
    poll(12'h028, 64, 64, 100);
    expect_reg(12'h040, 32'hffffffff, 32'h80000005);
    expect_reg(12'h018, 16, 0);
    @(negedge clk);
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    initialize();
    $display("CRYPTO_V2_FIFO_FAILURE_PASS");
  endtask
  task automatic rsa_operand(input logic [11:0] address, input logic [2047:0] value);
    for (int index = 0; index < 64; index++) put(address + 12'(index * 4), value[index*32+:32]);
  endtask
  task automatic rsa_result(input logic [2047:0] expected);
    logic [31:0] value;
    for (int index = 0; index < 64; index++) begin
      get(12'ha00 + 12'(index * 4), value);
      if (value !== expected[index*32+:32])
        $fatal(1, "RSA limb %0d got=%h expected=%h", index, value, expected[index*32+:32]);
    end
  endtask
  task automatic rsa_cases;
    logic [31:0] value, private_cycles;
    rsa_operand(12'h400, rsa_vectors[0]);
    rsa_operand(12'h600, 2048'd65537);
    rsa_operand(12'h800, rsa_vectors[2]);
    put(12'h300, 1);
    expect_reg(12'h308, 3, 1);
    poll(12'h308, 9, 8, 1400000);
    get(12'h30c, value);
    if (value > 4194304) $fatal(1, "RSA prepare bound");
    $display("CRYPTO_CYCLES operation=rsa2048_prepare cycles=%0d", value);
    put(12'h300, 2);
    expect_reg(12'h308, 3, 1);
    poll(12'h308, 17, 16, 10000000);
    rsa_result(rsa_vectors[3]);
    get(12'h30c, value);
    $display("CRYPTO_CYCLES operation=rsa2048_public cycles=%0d", value);
    rsa_operand(12'h600, rsa_vectors[1]);
    rsa_operand(12'h800, rsa_vectors[3]);
    put(12'h300, 4);
    expect_reg(12'h308, 3, 1);
    poll(12'h308, 17, 16, 170000000);
    rsa_result(rsa_vectors[2]);
    get(12'h30c, private_cycles);
    if (private_cycles > 536870912) $fatal(1, "RSA private bound");
    $display("CRYPTO_CYCLES operation=rsa2048_private cycles=%0d", private_cycles);
    rsa_operand(12'h600, rsa_vectors[1] ^ 2048'd2);
    put(12'h300, 4);
    expect_reg(12'h308, 3, 1);
    poll(12'h308, 5, 4, 170000000);
    rsa_result(2048'd0);
    get(12'h30c, value);
    if (value != private_cycles)
      $fatal(1, "private schedule changed %0d/%0d", value, private_cycles);
    $display("CRYPTO_CYCLES operation=rsa2048_bad_private cycles=%0d", value);
  endtask

  task automatic fault_with_stalled_output;
    logic [31:0] value;
    aes_key(256'h000102030405060708090a0b0c0d0e0f00000000000000000000000000000000, 0);
    put(12'h104, 32'h100);
    put(12'h10c, 16);
    put(12'h018, 63);
    put(12'h100, 1);
    for (int index = 0; index < 4; index++) begin
      @(negedge clk);
      crypto_in_axis.tvalid = 1;
      crypto_in_axis.tdata  = 32'h11223344;
      crypto_in_axis.tkeep  = 15;
      crypto_in_axis.tstrb  = 15;
      crypto_in_axis.tlast  = index == 3;
      do @(posedge clk); while (!crypto_in_axis.tready);
      @(negedge clk);
      crypto_in_axis.tvalid = 0;
    end
    wait (crypto_out_axis.tvalid);
    put(12'h010, 4);
    wait (u_dut.u_sha.u_input_fifo.s_state_q == 3'd2);
    @(negedge clk);
    u_dut.u_sha.u_input_fifo.u_payload.r_storage[0] = 37'd1;
    poll(12'h028, 65, 64, 100);
    repeat (16) @(negedge clk);
    if (!crypto_out_axis.tvalid || crypto_in_axis.tready)
      $fatal(1, "fatal fault retracted held output or accepted input");
    expect_reg(12'h12c, 1, 0);
    expect_reg(12'h018, 1, 0);
    crypto_out_axis.tready = 1;
    @(posedge clk);
    @(negedge clk);
    crypto_out_axis.tready = 0;
    repeat (50) @(negedge clk);
    if (crypto_out_axis.tvalid) $fatal(1, "fatal drain published another beat");
    for (int index = 0; index < 8; index++)
      if (u_dut.u_aes.u_output_fifo.u_payload.r_storage[index] !== 37'd0)
        $fatal(1, "fatal drain retained output payload");
    access (1, 12'h100, 1, 15, 1, value);
    @(negedge clk);
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    initialize();
    $display("CRYPTO_V2_FATAL_DMA_DRAIN_PASS");
  endtask
  task automatic erasure;
    logic [31:0] value;
    put(12'h020, 16);
    put(12'h010, 1);
    expect_reg(12'h028, 5, 4);
    expect_reg(12'h018, 16, 0);
    poll(12'h028, 32'h7f, 32'h23, 800);
    expect_reg(12'h018, 16, 16);
    expect_reg(12'h12c, 3, 0);
    expect_reg(12'h208, 9, 0);
    expect_reg(12'h308, 25, 0);
    get(12'h044, value);
    if (value > 2056) $fatal(1, "global scrub cycle bound %0d", value);
    for (int index = 0; index < 64; index++) begin
      expect_reg(12'h400 + 12'(index * 4), 32'hffffffff, 0);
      expect_reg(12'h800 + 12'(index * 4), 32'hffffffff, 0);
    end
    $display("CRYPTO_V2_SCRUB cycles=%0d", value);
    check_erased = 1;
    repeat (2) @(negedge clk);
    check_erased = 0;
  endtask

  task automatic abort_and_concurrency;
    logic [31:0] value;
    // AES keeps its completed key; abort must preserve an AXIS beat that has
    // already been presented while backpressured, then erase local storage.
    put(12'h104, 32'h100);
    put(12'h10c, 16);
    put(12'h018, 63);
    put(12'h100, 1);
    for (int index = 0; index < 4; index++) begin
      @(negedge clk);
      crypto_in_axis.tvalid = 1;
      crypto_in_axis.tdata  = 32'h11223344;
      crypto_in_axis.tkeep  = 4'hf;
      crypto_in_axis.tstrb  = 4'hf;
      crypto_in_axis.tlast  = index == 3;
      do @(posedge clk); while (!crypto_in_axis.tready);
      @(negedge clk);
      crypto_in_axis.tvalid = 0;
    end
    wait (crypto_out_axis.tvalid);
    access (1, 12'h010, 1, 4'hf, 1, value);
    // SHA progresses independently while AES is held at its output.
    put(12'h204, 1);
    put(12'h20c, 0);
    put(12'h200, 1);
    poll(12'h208, 9, 8, 1000);
    put(12'h010, 2);
    repeat (8) @(negedge clk);
    expect_reg(12'h108, 3, 1);
    if (!crypto_out_axis.tvalid) $fatal(1, "AES abort discarded held beat");
    crypto_out_axis.tready = 1;
    @(posedge clk);
    @(negedge clk);
    crypto_out_axis.tready = 0;
    poll(12'h108, 1, 0, 800);
    expect_reg(12'h12c, 3, 1);
    expect_reg(12'h018, 1, 0);
    // Partial SHA abort and RSA prepare/abort have private scrub ownership.
    put(12'h204, 1);
    put(12'h20c, 64);
    put(12'h200, 1);
    poll(12'h218, 1, 1, 100);
    put(12'h214, 32'hdeadbeef);
    put(12'h010, 4);
    aes_block(0, 2, 0, 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff, 128'h6bc1be00000000000000000000000000,
              128'h874d6100000000000000000000000000, 3);
    poll(12'h208, 9, 0, 800);
    rsa_operand(12'h400, rsa_vectors[0]);
    put(12'h300, 1);
    repeat (100) @(negedge clk);
    put(12'h010, 8);
    expect_reg(12'h308, 25, 1);
    poll(12'h308, 25, 0, 800);
    expect_reg(12'h028, 127, 35);
    $display("CRYPTO_V2_ABORT_CONCURRENCY_PASS");
  endtask
  initial begin
    #10000000000;
    $fatal(1, "Crypto V2 watchdog");
  end
  initial begin
    apb4.psel              = 0;
    apb4.penable           = 0;
    apb4.pwrite            = 0;
    apb4.paddr             = 0;
    apb4.pwdata            = 0;
    apb4.pstrb             = 0;
    apb4.pprot             = 0;
    crypto_in_axis.tvalid  = 0;
    crypto_in_axis.tdata   = 0;
    crypto_in_axis.tkeep   = 0;
    crypto_in_axis.tlast   = 0;
    crypto_in_axis.tstrb   = 0;
    crypto_in_axis.tid     = 0;
    crypto_in_axis.tdest   = 0;
    crypto_in_axis.tuser   = 0;
    crypto_out_axis.tready = 0;
    if (!$value$plusargs("constants=%s", constant_path)) $fatal(1, "missing constants");
    if (!$value$plusargs("sha=%s", sha_path)) $fatal(1, "missing SHA");
    if (!$value$plusargs("rsa=%s", rsa_path)) $fatal(1, "missing RSA");
    $readmemh(constant_path, constants);
    $readmemh(sha_path, expected_sha);
    $readmemh(rsa_path, rsa_vectors);
    repeat (3) @(negedge clk);
    rst_n = 1;
    initialize();
    aes_key(256'h000102030405060708090a0b0c0d0e0f00000000000000000000000000000000, 0);
    aes_block(0, 0, 0, 0, 128'h00112233445566778899aabbccddeeff,
              128'h69c4e0d86a7b0430d8cdb78070b4c55a, 16);
    aes_block(0, 0, 1, 0, 128'h69c4e0d86a7b0430d8cdb78070b4c55a,
              128'h00112233445566778899aabbccddeeff, 16);
    aes_key(256'h000102030405060708090a0b0c0d0e0f10111213141516170000000000000000, 1);
    aes_block(1, 0, 0, 0, 128'h00112233445566778899aabbccddeeff,
              128'hdda97ca4864cdfe06eaf70a0ec0d7191, 16);
    aes_block(1, 0, 1, 0, 128'hdda97ca4864cdfe06eaf70a0ec0d7191,
              128'h00112233445566778899aabbccddeeff, 16);
    aes_key(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, 2);
    aes_block(2, 0, 0, 0, 128'h00112233445566778899aabbccddeeff,
              128'h8ea2b7ca516745bfeafc49904b496089, 16);
    aes_block(2, 0, 1, 0, 128'h8ea2b7ca516745bfeafc49904b496089,
              128'h00112233445566778899aabbccddeeff, 16);
    aes_key(256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000, 0);
    aes_block(0, 1, 0, 128'h000102030405060708090a0b0c0d0e0f, 128'h6bc1bee22e409f96e93d7e117393172a,
              128'h7649abac8119b246cee98e9b12e9197d, 16);
    aes_block(0, 1, 1, 128'h000102030405060708090a0b0c0d0e0f, 128'h7649abac8119b246cee98e9b12e9197d,
              128'h6bc1bee22e409f96e93d7e117393172a, 16);
    aes_block(0, 2, 0, 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff, 128'h6bc1be00000000000000000000000000,
              128'h874d6100000000000000000000000000, 3);
    sha_cases();
    aes_multiblock(1, 0, 128'h000102030405060708090a0b0c0d0e0f,
                   256'h6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51,
                   256'h7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2, 32);
    aes_multiblock(1, 1, 128'h000102030405060708090a0b0c0d0e0f,
                   256'h7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2,
                   256'h6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51, 32);
    aes_multiblock(2, 0, 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff,
                   256'h6bc1bee22e409f96e93d7e117393172aae2d8a57000000000000000000000000,
                   256'h874d6191b620e3261bef6864990db6ce9806f66b000000000000000000000000, 20);
    abort_and_concurrency();
    if ($test$plusargs("full_rsa")) rsa_cases();
    erasure();
    fault_with_stalled_output();
    fifo_scrub_failure();
    scrub_failure();
    reset_boundaries();
    timeout_cancel_boundaries();
    $display("CRYPTO_V2_PASS transactions=%0d max_wait=%0d full_rsa=%0d", transactions, max_wait,
             $test$plusargs("full_rsa"));
    $finish;
  end
endmodule
