// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
module crypto_apb_formal (
    input logic        clk_i,
    select_i,
    enable_i,
    write_i,
    input logic [11:0] address_i,
    input logic [31:0] data_i,
    input logic [ 3:0] strobe_i
);
  logic       rst_n_i = 0;
  logic       past_valid = 0;
  logic [2:0] waits = 0;
  apb4_if bus_if (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_stream_if in_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if out_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  assign bus_if.psel     = select_i;
  assign bus_if.penable  = enable_i;
  assign bus_if.pwrite   = write_i;
  assign bus_if.paddr    = {20'd0, address_i};
  assign bus_if.pwdata   = data_i;
  assign bus_if.pstrb    = strobe_i;
  assign bus_if.pprot    = 0;
  assign in_axis.tvalid  = 0;
  assign in_axis.tdata   = 0;
  assign in_axis.tkeep   = 0;
  assign in_axis.tstrb   = 0;
  assign in_axis.tlast   = 0;
  assign in_axis.tid     = 0;
  assign in_axis.tdest   = 0;
  assign in_axis.tuser   = 0;
  assign out_axis.tready = 1;
  apb4_crypto u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .dma_input_proc_o (),
      .dma_output_proc_o(),
      .irq_o            (),
      .apb4             (bus_if),
      .crypto_in_axis   (in_axis),
      .crypto_out_axis  (out_axis)
  );
  always @(posedge clk_i) begin
    rst_n_i    <= 1;
    past_valid <= 1;
    assume (!enable_i || select_i);
    // ACCESS must follow SETUP (or another wait cycle), never IDLE directly.
    assume (!enable_i || (past_valid && $past(select_i)));
    if (!rst_n_i) assume (!select_i);
    if (past_valid && $past(select_i && (!enable_i || !bus_if.pready))) begin
      assume (select_i && enable_i);
      assume ({address_i, data_i, strobe_i, write_i} == $past(
          {address_i, data_i, strobe_i, write_i}
      ));
    end
    if (past_valid && $past(enable_i && bus_if.pready)) assume (!enable_i);
    if (rst_n_i && select_i && enable_i && !bus_if.pready) waits <= waits + 1'b1;
    else waits <= 0;
    if (rst_n_i) begin
      // Capture invariants connect the slave transaction to the legal APB
      // master history during induction (state encoding zero is ApbIdle).
      if (!enable_i) assert (u_dut.s_regs_q.state == 2'd0);
      if (select_i && enable_i) begin
        assert (u_dut.s_req);
        assert (u_dut.s_offset == address_i);
        assert (u_dut.s_regs_q.write == write_i);
        assert (u_dut.s_wdata == data_i && u_dut.s_strb == strobe_i);
      end
      assert (waits <= 4);
      assert (u_dut.s_start == 0 || u_dut.s_mem_stat[0]);
      // A new erase command supersedes a completion pulse from the prior
      // erase; ordinary IRQ_STATE W1C still loses to a simultaneous event.
      if (u_dut.s_zeroize) assert (!u_dut.s_regs_d.irq_state[4]);
      assert ((u_dut.s_regs_d.irq_state[2:0] & u_dut.s_command) == 0);
      // These are universal next-state properties, not a sampled list of
      // simulation interruption points. They include arithmetic/copy states.
      if (u_dut.s_mem_clear) begin
        assert (u_dut.u_aes.s_regs_d == 0);
        assert (u_dut.u_aes.u_core.s_regs_d == 0);
      end
      if (u_dut.s_engine_clear) begin
        assert (u_dut.u_sha.s_regs_d == 0);
        assert (u_dut.u_rsa.s_regs_d == 0);
      end
      if (!u_dut.s_engine_clear) begin
        if (u_dut.s_abort[0] && u_dut.u_aes.s_regs_q.state < 5'd13) begin
          assert (u_dut.u_aes.s_regs_d.state ==
                  (u_dut.s_aes_output_valid && !u_dut.s_aes_output_ready ? 5'd13 : 5'd14));
          assert (!u_dut.u_aes.s_regs_d.done);
          assert (!u_dut.u_aes.work_req_o.valid);
        end
        if (u_dut.s_abort[1] && u_dut.u_sha.s_regs_q.state < 5'd16) begin
          assert (!u_dut.u_sha.s_regs_d.digest_valid);
          assert (!u_dut.u_sha.s_regs_d.done);
        end
        if (u_dut.s_abort[2] && u_dut.u_rsa.s_regs_q.state < 6'd51) begin
          assert (!u_dut.u_rsa.s_regs_d.result_valid);
          assert (!u_dut.u_rsa.s_regs_d.prepared);
          assert (!u_dut.u_rsa.s_regs_d.done);
        end
      end
      if (bus_if.pslverr) assert (bus_if.prdata == 0);
      if(select_i && enable_i && !write_i &&
         ((address_i>=12'h140 && address_i<12'h160) ||
          (address_i>=12'h600 && address_i<12'h700))) begin
        assert (bus_if.pslverr);
        assert (bus_if.prdata == 0);
      end
      for (int bank = 0; bank < 6; bank++) begin
        if (u_dut.s_engine_resp[bank].valid && (bank < 2))
          assert (u_dut.s_engine_resp[bank].epoch == u_dut.s_epoch_q[3:0]);
        if (u_dut.s_engine_resp[bank].valid && (bank >= 2) && (bank < 4))
          assert (u_dut.s_engine_resp[bank].epoch == u_dut.s_epoch_q[7:4]);
        if (u_dut.s_engine_resp[bank].valid && (bank >= 4))
          assert (u_dut.s_engine_resp[bank].epoch == u_dut.s_epoch_q[11:8]);
        if (u_dut.s_store_req[bank].valid && u_dut.s_store_req[bank].tag == 2) begin
          assert (bank >= 2 && bank <= 4);
          if (u_dut.s_store_req[bank].write) assert (u_dut.s_write_accept);
          if (bank == 2) assert (!u_dut.s_busy[0]);
          if (bank == 3) assert (!u_dut.s_busy[1]);
          if (bank == 4) assert (!u_dut.s_busy[2]);
        end
        if (bank < 2 && u_dut.s_store_req[bank].valid && u_dut.s_store_req[bank].write)
          assert (u_dut.s_store_req[bank].tag == 1);
      end
    end
  end
endmodule
