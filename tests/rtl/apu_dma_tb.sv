`timescale 1ns / 1ps

`include "axi4_define.svh"

module apu_dma_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        abort_i = 1'b0;
  logic        quiesce_i = 1'b0;
  logic        counter_clear_i = 1'b0;
  logic [ 7:0] bridge_epoch_i = 8'd0;
  logic        request_valid_i = 1'b0;
  logic        request_ready_o;
  logic        request_write_i;
  logic [31:0] request_addr_i;
  logic [31:0] request_bytes_i;
  logic [31:0] timeout_i = 32'd32;
  logic [31:0] read_acl_base_i = 32'd0;
  logic [31:0] read_acl_limit_i = 32'h0000_ffff;
  logic [31:0] write_acl_base_i = 32'd0;
  logic [31:0] write_acl_limit_i = 32'h0000_ffff;
  logic busy_o, done_o, error_o, aborted_o, aborting_o;
  logic [ 5:0] error_code_o;
  logic [ 3:0] error_stage_o;
  logic [ 1:0] error_resp_o;
  logic [31:0] error_addr_o;
  logic [63:0] read_bytes_o, write_bytes_o;
  logic [31:0] memory     [0:32767];
  logic [31:0] buffer     [   0:31];
  logic [ 3:0] buffer_keep[   0:31];
  logic read_active, write_active, write_source_active;
  logic [31:0] read_base, write_base;
  logic [7:0] read_len, write_len, read_index, write_index, source_index;
  logic       bvalid;
  logic       allow_addresses = 1'b1;
  logic       read_sink_ready = 1'b1;
  logic [1:0] read_response = `AXI4_RESP_OKAY;
  logic [1:0] write_response = `AXI4_RESP_OKAY;
  logic       read_id = 1'b0;
  logic       write_id = 1'b0;
  logic       early_read_last = 1'b0;
  logic       suppress_read_last = 1'b0;
  logic       allow_write_response = 1'b1;
  logic [7:0] source_last_index = 8'd0;
  int unsigned read_bursts, write_bursts;
  string s_phase;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) read_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) write_axis (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;

  assign read_axis.tready = read_sink_ready;
  assign write_axis.tdata = buffer[source_index];
  assign write_axis.tkeep = buffer_keep[source_index];
  assign write_axis.tstrb = buffer_keep[source_index];
  assign write_axis.tlast = source_index == source_last_index;
  assign write_axis.tid = '0;
  assign write_axis.tdest = '0;
  assign write_axis.tuser = '0;
  assign write_axis.tvalid = write_source_active;

  assign axi4.arready = allow_addresses && !read_active;
  assign axi4.rid = read_id;
  assign axi4.rdata = memory[(read_base>>2)+read_index];
  assign axi4.rresp = read_response;
  assign axi4.rlast        = !suppress_read_last &&
      (early_read_last ? (read_index == 8'd0) : (read_index == read_len));
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = read_active;
  assign axi4.awready = allow_addresses && !write_active && !bvalid;
  assign axi4.wready = write_active;
  assign axi4.bid = write_id;
  assign axi4.bresp = write_response;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = bvalid && allow_write_response;

  apu_dma u_dut (
      .clk_i,
      .rst_n_i,
      .abort_i,
      .quiesce_i,
      .bridge_epoch_i,
      .perf_enable_i   (1'b1),
      .counter_clear_i,
      .request_valid_i,
      .request_ready_o,
      .request_write_i,
      .request_addr_i,
      .request_bytes_i,
      .read_base_i     (read_acl_base_i),
      .read_limit_i    (read_acl_limit_i),
      .write_base_i    (write_acl_base_i),
      .write_limit_i   (write_acl_limit_i),
      .timeout_i,
      .read_axis,
      .write_axis,
      .busy_o,
      .done_o,
      .error_o,
      .aborted_o,
      .aborting_o,
      .error_code_o,
      .error_stage_o,
      .error_resp_o,
      .error_addr_o,
      .input_pending_o (),
      .output_pending_o(),
      .read_bytes_o,
      .write_bytes_o,
      .read_stalls_o   (),
      .write_stalls_o  (),
      .axi4
  );

  task automatic issue_request(input logic write_i, input logic [31:0] addr_i,
                               input logic [31:0] bytes_i);
    begin
      @(negedge clk_i);
      request_write_i = write_i;
      request_addr_i  = addr_i;
      request_bytes_i = bytes_i;
      if (write_i) source_last_index = ((bytes_i + 32'd3) >> 2) - 1'b1;
      request_valid_i = 1'b1;
      while (!request_ready_o) @(negedge clk_i);
      @(posedge clk_i);
      @(negedge clk_i);
      request_valid_i = 1'b0;
    end
  endtask

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active  <= 1'b0;
      write_active <= 1'b0;
      bvalid       <= 1'b0;
      read_index   <= 8'd0;
      write_index  <= 8'd0;
      source_index <= 8'd0;
      read_bursts  <= 0;
      write_bursts <= 0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        read_active <= 1'b1;
        read_base   <= axi4.araddr;
        read_len    <= axi4.arlen;
        read_index  <= 8'd0;
        read_bursts <= read_bursts + 1;
      end else if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) read_active <= 1'b0;
        else read_index <= read_index + 1'b1;
      end
      if (read_axis.tvalid && read_axis.tready) begin
        buffer[source_index]      <= read_axis.tdata;
        buffer_keep[source_index] <= read_axis.tkeep;
        source_index              <= source_index + 1'b1;
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active <= 1'b1;
        write_base   <= axi4.awaddr;
        write_len    <= axi4.awlen;
        write_index  <= 8'd0;
        write_bursts <= write_bursts + 1;
      end
      if (axi4.wvalid && axi4.wready) begin
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
          if (axi4.wstrb[byte_index]) begin
            memory[(write_base>>2)+write_index][byte_index*8+:8] <= axi4.wdata[byte_index*8+:8];
          end
        end
        if (axi4.wlast) begin
          write_active <= 1'b0;
          bvalid       <= 1'b1;
        end else begin
          write_index <= write_index + 1'b1;
        end
      end
      if (write_axis.tvalid && write_axis.tready) source_index <= source_index + 1'b1;
      if (axi4.bvalid && axi4.bready) bvalid <= 1'b0;
    end
  end

  initial begin
    request_write_i     = 1'b0;
    request_addr_i      = 32'd0;
    request_bytes_i     = 32'd0;
    write_source_active = 1'b0;
    for (int index = 0; index < 32768; index++) memory[index] = 32'hdead_beef;
    for (int index = 0; index < 17; index++) memory[(32'h0ff0>>2)+index] = 32'h1000 + index;
    repeat (3) @(posedge clk_i);
    rst_n_i      = 1'b1;

    source_index = 8'd0;
    s_phase      = "read";
    issue_request(1'b0, 32'h0000_0ff0, 32'd67);
    while (!done_o) @(posedge clk_i);
    if (error_o || (read_bytes_o != 64'd67) || (read_bursts < 2)) begin
      $fatal(1, "APU DMA read/split failed");
    end
    source_index        = 8'd0;
    s_phase             = "write";
    write_source_active = 1'b1;
    issue_request(1'b1, 32'h0000_2000, 32'd67);
    while (!done_o) @(posedge clk_i);
    write_source_active = 1'b0;
    if (error_o || (write_bytes_o != 64'd67) || (write_bursts < 2)) begin
      $fatal(1, "APU DMA write/split failed");
    end
    for (int index = 0; index < 16; index++) begin
      if (memory[(32'h2000>>2)+index] != 32'h1000 + index) $fatal(1, "DMA copy mismatch");
    end
    if ((memory[(32'h2040>>2)][23:0] != 24'h001010) || (memory[(32'h2040>>2)][31:24] != 8'hde))
      $fatal(1, "DMA tail strobe mismatch");

    s_phase = "acl";
    issue_request(1'b0, 32'h0002_0000, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd15)) $fatal(1, "DMA ACL denial failed");
    read_acl_limit_i = 32'hffff_ffff;
    issue_request(1'b0, 32'hffff_fffc, 32'd8);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd15) || busy_o) begin
      $fatal(1, "DMA ACL arithmetic overflow was accepted");
    end
    read_acl_limit_i = 32'h0000_ffff;

    s_phase          = "read response faults";
    read_response    = `AXI4_RESP_SLAVE_ERROR;
    issue_request(1'b0, 32'h0000_4000, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd15) || (error_resp_o != `AXI4_RESP_SLAVE_ERROR))
      $fatal(1, "DMA read SLVERR failed");
    read_response = `AXI4_RESP_DECODE_ERROR;
    issue_request(1'b0, 32'h0000_4000, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_resp_o != `AXI4_RESP_DECODE_ERROR)) begin
      $fatal(1, "DMA read DECERR failed");
    end
    read_response = `AXI4_RESP_OKAY;
    read_id       = 1'b1;
    issue_request(1'b0, 32'h0000_4000, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd15)) $fatal(1, "DMA read ID failure missed");
    read_id         = 1'b0;
    early_read_last = 1'b1;
    issue_request(1'b0, 32'h0000_4000, 32'd8);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd15)) $fatal(1, "DMA malformed RLAST missed");
    early_read_last    = 1'b0;
    suppress_read_last = 1'b1;
    issue_request(1'b0, 32'h0000_4000, 32'd8);
    while (!done_o) @(posedge clk_i);
    if (!error_o || busy_o || (error_code_o != 6'd15)) begin
      $fatal(1, "DMA missing terminal RLAST did not terminate boundedly");
    end
    suppress_read_last = 1'b0;
    read_active        = 1'b0;

    s_phase            = "epoch/request coincidence";
    @(negedge clk_i);
    request_write_i = 1'b0;
    request_addr_i  = 32'h0000_4000;
    request_bytes_i = 32'd4;
    request_valid_i = 1'b1;
    bridge_epoch_i  = bridge_epoch_i + 1'b1;
    #1;
    if (request_ready_o) $fatal(1, "DMA accepted a request during epoch recovery");
    @(posedge clk_i);
    do @(posedge clk_i); while (!request_ready_o);
    @(negedge clk_i);
    request_valid_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    if (error_o || (read_bytes_o != 64'd75)) begin
      $fatal(1, "DMA lost the request coincident with epoch recovery");
    end

    s_phase             = "write response faults";
    source_index        = 8'd0;
    write_source_active = 1'b1;
    write_response      = `AXI4_RESP_SLAVE_ERROR;
    issue_request(1'b1, 32'h0000_5000, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd16) || (error_resp_o != `AXI4_RESP_SLAVE_ERROR))
      $fatal(1, "DMA write SLVERR failed");
    source_index   = 8'd0;
    write_response = `AXI4_RESP_DECODE_ERROR;
    issue_request(1'b1, 32'h0000_5004, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_resp_o != `AXI4_RESP_DECODE_ERROR)) begin
      $fatal(1, "DMA write DECERR failed");
    end
    source_index   = 8'd0;
    write_response = `AXI4_RESP_OKAY;
    write_id       = 1'b1;
    issue_request(1'b1, 32'h0000_5008, 32'd4);
    while (!done_o) @(posedge clk_i);
    if (!error_o || (error_code_o != 6'd16)) $fatal(1, "DMA write ID failure missed");
    write_id            = 1'b0;
    write_source_active = 1'b0;

    s_phase             = "read-start abort";
    issue_request(1'b0, 32'h0000_6000, 32'd4);
    if (u_dut.s_state_q != 3'd1) $fatal(1, "DMA did not hold ReadStart for abort injection");
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    if (error_o || !aborted_o || busy_o) $fatal(1, "DMA ReadStart abort failed");

    s_phase             = "write-start abort";
    source_index        = 8'd0;
    write_source_active = 1'b1;
    issue_request(1'b1, 32'h0000_5010, 32'd4);
    if (u_dut.s_state_q != 3'd3) $fatal(1, "DMA did not hold WriteStart for abort injection");
    abort_i = 1'b1;
    @(posedge clk_i);
    #1;
    if (!aborted_o || !aborting_o) begin
      $fatal(1, "DMA did not latch the WriteStart abort state=%0d drain=%0d", u_dut.s_state_q,
             u_dut.s_drain_q);
    end
    @(negedge clk_i);
    abort_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    write_source_active = 1'b0;
    if (error_o || !aborted_o || busy_o) begin
      $fatal(1, "DMA WriteStart abort failed error=%0d aborted=%0d busy=%0d code=%0d state=%0d",
             error_o, aborted_o, busy_o, error_code_o, u_dut.s_state_q);
    end

    s_phase             = "write-data abort";
    source_index        = 8'd0;
    write_source_active = 1'b0;
    issue_request(1'b1, 32'h0000_5020, 32'd16);
    wait (write_active && (u_dut.s_state_q == 3'd4));
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    if (error_o || !aborted_o || busy_o) $fatal(1, "DMA WriteData abort failed");

    s_phase              = "write response abort";
    source_index         = 8'd0;
    write_source_active  = 1'b1;
    allow_write_response = 1'b0;
    issue_request(1'b1, 32'h0000_5010, 32'd4);
    while (!bvalid) @(posedge clk_i);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    if (!aborting_o) $fatal(1, "DMA did not report aborting while waiting for B");
    allow_write_response = 1'b1;
    while (!done_o) @(posedge clk_i);
    write_source_active = 1'b0;
    if (error_o || !aborted_o || (error_code_o != 6'd20)) begin
      $fatal(1, "DMA write-response abort did not drain");
    end

    s_phase              = "write error over abort";
    source_index         = 8'd0;
    write_source_active  = 1'b1;
    write_response       = `AXI4_RESP_SLAVE_ERROR;
    allow_write_response = 1'b0;
    issue_request(1'b1, 32'h0000_5014, 32'd4);
    while (!bvalid) @(posedge clk_i);
    @(negedge clk_i);
    abort_i              = 1'b1;
    allow_write_response = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    write_source_active = 1'b0;
    write_response      = `AXI4_RESP_OKAY;
    if (!error_o || !aborted_o || (error_code_o != 6'd16) ||
        (error_resp_o != `AXI4_RESP_SLAVE_ERROR)) begin
      $fatal(1, "DMA write error did not outrank simultaneous abort");
    end

    s_phase         = "accepted abort drain";
    read_sink_ready = 1'b0;
    issue_request(1'b0, 32'h0000_6000, 32'd16);
    while (!read_active) @(posedge clk_i);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    if (!aborting_o) $fatal(1, "DMA live aborting status was not asserted");
    abort_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    read_sink_ready = 1'b1;
    if (error_o || !aborted_o || (error_code_o != 6'd20)) begin
      $fatal(1, "DMA accepted-read abort drain failed");
    end
    if (aborting_o) $fatal(1, "DMA live aborting status remained set after drain");

    s_phase         = "read error over abort";
    read_sink_ready = 1'b0;
    issue_request(1'b0, 32'h0000_6000, 32'd16);
    while (!read_active) @(posedge clk_i);
    read_response = `AXI4_RESP_SLAVE_ERROR;
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    while (!done_o) @(posedge clk_i);
    read_response   = `AXI4_RESP_OKAY;
    read_sink_ready = 1'b1;
    if (!error_o || !aborted_o || (error_code_o != 6'd15)) begin
      $fatal(1, "DMA read error did not outrank abort");
    end

    s_phase         = "unaccepted abort cancellation";
    allow_addresses = 1'b0;
    issue_request(1'b0, 32'h0000_6000, 32'd4);
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    while (!aborted_o) @(posedge clk_i);
    if (!axi4.arvalid || !busy_o) $fatal(1, "aborted AR was withdrawn before handshake");
    allow_addresses = 1'b1;
    while (!done_o) @(posedge clk_i);
    if (error_o || !aborted_o || (error_code_o != 6'd20)) begin
      $fatal(1, "DMA unaccepted-address abort drain failed");
    end

    s_phase = "deterministic random lengths";
    for (int unsigned transfer = 0; transfer < 12; transfer++) begin
      automatic int unsigned        length = ((transfer * 29) % 95) + 1;
      automatic int unsigned        source_addr = 32'h0000_7000 + (transfer * 32'h100);
      automatic int unsigned        dest_addr = 32'h0000_9000 + (transfer * 32'h100);
      automatic int unsigned        beats = (length + 3) / 4;
      automatic logic        [63:0] read_before = read_bytes_o;
      automatic logic        [63:0] write_before = write_bytes_o;
      for (int unsigned word_index = 0; word_index < beats; word_index++) begin
        memory[(source_addr>>2)+word_index] = 32'h600d_0000 ^ (transfer << 8) ^ word_index;
        memory[(dest_addr>>2)+word_index]   = 32'hdead_beef;
      end
      source_index = 8'd0;
      issue_request(1'b0, source_addr, length);
      while (!done_o) @(posedge clk_i);
      if (error_o || (read_bytes_o != read_before + length)) begin
        $fatal(1, "DMA randomized read failed");
      end
      source_index        = 8'd0;
      write_source_active = 1'b1;
      issue_request(1'b1, dest_addr, length);
      while (!done_o) @(posedge clk_i);
      write_source_active = 1'b0;
      if (error_o || (write_bytes_o != write_before + length)) begin
        $fatal(1, "DMA randomized write failed");
      end
      for (int unsigned byte_index = 0; byte_index < length; byte_index++) begin
        if (memory[(dest_addr >> 2) + (byte_index / 4)][(byte_index%4)*8+:8] !==
            memory[(source_addr >> 2) + (byte_index / 4)][(byte_index%4)*8+:8]) begin
          $fatal(1, "DMA randomized copy mismatch");
        end
      end
    end

    allow_addresses     = 1'b0;
    s_phase             = "timeout";
    timeout_i           = 32'd1;
    source_index        = 8'd0;
    write_source_active = 1'b1;
    issue_request(1'b1, 32'h0000_3000, 32'd4);
    while (!error_o) @(posedge clk_i);
    if (!axi4.awvalid || !busy_o || (error_code_o != 6'd17)) begin
      $fatal(1, "timed-out AW was withdrawn before handshake");
    end
    allow_addresses = 1'b1;
    while (!done_o) @(posedge clk_i);
    write_source_active = 1'b0;
    if (!error_o || (error_code_o != 6'd17) || aborted_o) $fatal(1, "DMA timeout failed");

    @(negedge clk_i);
    counter_clear_i = 1'b1;
    @(negedge clk_i);
    counter_clear_i = 1'b0;
    #1;
    if ((read_bytes_o != 64'd0) || (write_bytes_o != 64'd0) ||
        (u_dut.s_read_stalls_q != 64'd0) || (u_dut.s_write_stalls_q != 64'd0)) begin
      $fatal(1, "DMA counter clear failed");
    end

    $display("APU-P2 DMA tests passed");
    $finish;
  end

  initial begin
    repeat (3000) @(posedge clk_i);
    $fatal(1, "APU-P2 DMA test timed out in %s state=%0d remaining=%0d", s_phase, u_dut.s_state_q,
           u_dut.s_remaining_q);
  end
endmodule
