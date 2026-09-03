`timescale 1ns / 1ps

module hp_axi4_mux3_rr_tb;
  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic        [ 7:0] epoch_i = 8'd0;
  logic        [ 2:0] read_request = 3'd0;
  logic        [ 2:0] write_request = 3'd0;
  logic        [ 2:0] write_data_valid = 3'b111;
  logic        [ 2:0] read_ready = 3'b111;
  logic        [ 2:0] write_response_ready = 3'b111;
  logic               response_valid_q;
  logic        [31:0] response_data_q;
  logic               write_active_q;
  logic               write_response_valid_q;
  logic        [31:0] write_address_q;
  logic               mixed_mode_q;
  logic               recovery_response_q = 1'b0;
  logic               allow_read_address = 1'b1;
  logic               allow_write_address = 1'b1;
  int unsigned        response_count                [0:2];
  int unsigned        write_response_count          [0:2];
  int unsigned        mixed_response_count          [0:2];
  int unsigned        total_responses;
  int unsigned        total_write_responses;
  int unsigned        total_mixed_responses;
  logic        [15:0] cycle_q;
  string              s_phase;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) icache (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dcache (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mmio (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;

  assign icache.arid = 1'b0;
  assign icache.araddr = 32'h0000_1000;
  assign dcache.arid = 1'b0;
  assign dcache.araddr = 32'h0000_2000;
  assign mmio.arid = 1'b0;
  assign mmio.araddr = 32'h0000_3000;
  assign icache.arvalid = read_request[0];
  assign dcache.arvalid = read_request[1];
  assign mmio.arvalid = read_request[2];

  assign icache.arlen = 8'd0;
  assign dcache.arlen = 8'd0;
  assign mmio.arlen = 8'd0;
  assign icache.arsize = 3'd2;
  assign dcache.arsize = 3'd2;
  assign mmio.arsize = 3'd2;
  assign icache.arburst = 2'd1;
  assign dcache.arburst = 2'd1;
  assign mmio.arburst = 2'd1;
  assign icache.arlock = 1'b0;
  assign dcache.arlock = 1'b0;
  assign mmio.arlock = 1'b0;
  assign icache.arcache = 4'd0;
  assign dcache.arcache = 4'd0;
  assign mmio.arcache = 4'd0;
  assign icache.arprot = 3'd0;
  assign dcache.arprot = 3'd0;
  assign mmio.arprot = 3'd0;
  assign icache.arqos = 4'd0;
  assign dcache.arqos = 4'd0;
  assign mmio.arqos = 4'd0;
  assign icache.arregion = 4'd0;
  assign dcache.arregion = 4'd0;
  assign mmio.arregion = 4'd0;
  assign icache.aruser = 1'b0;
  assign dcache.aruser = 1'b0;
  assign mmio.aruser = 1'b0;
  assign icache.rready = read_ready[0];
  assign dcache.rready = read_ready[1];
  assign mmio.rready = read_ready[2];

  assign icache.awid = 1'b0;
  assign dcache.awid = 1'b0;
  assign mmio.awid = 1'b0;
  assign icache.awaddr = 32'h0000_4000;
  assign dcache.awaddr = 32'h0000_5000;
  assign mmio.awaddr = 32'h0000_6000;
  assign icache.awlen = 8'd0;
  assign dcache.awlen = 8'd0;
  assign mmio.awlen = 8'd0;
  assign icache.awsize = 3'd2;
  assign dcache.awsize = 3'd2;
  assign mmio.awsize = 3'd2;
  assign icache.awburst = 2'd1;
  assign dcache.awburst = 2'd1;
  assign mmio.awburst = 2'd1;
  assign icache.awlock = 1'b0;
  assign dcache.awlock = 1'b0;
  assign mmio.awlock = 1'b0;
  assign icache.awcache = 4'd0;
  assign dcache.awcache = 4'd0;
  assign mmio.awcache = 4'd0;
  assign icache.awprot = 3'd0;
  assign dcache.awprot = 3'd0;
  assign mmio.awprot = 3'd0;
  assign icache.awqos = 4'd0;
  assign dcache.awqos = 4'd0;
  assign mmio.awqos = 4'd0;
  assign icache.awregion = 4'd0;
  assign dcache.awregion = 4'd0;
  assign mmio.awregion = 4'd0;
  assign icache.awuser = 1'b0;
  assign dcache.awuser = 1'b0;
  assign mmio.awuser = 1'b0;
  assign icache.awvalid = write_request[0];
  assign dcache.awvalid = write_request[1];
  assign mmio.awvalid = write_request[2];
  assign icache.wdata = 32'ha000_0000;
  assign dcache.wdata = 32'hb000_0000;
  assign mmio.wdata = 32'hc000_0000;
  assign icache.wstrb = 4'hf;
  assign dcache.wstrb = 4'hf;
  assign mmio.wstrb = 4'hf;
  assign icache.wlast = 1'b1;
  assign dcache.wlast = 1'b1;
  assign mmio.wlast = 1'b1;
  assign icache.wuser = 1'b0;
  assign dcache.wuser = 1'b0;
  assign mmio.wuser = 1'b0;
  assign icache.wvalid = write_request[0] && write_data_valid[0];
  assign dcache.wvalid = write_request[1] && write_data_valid[1];
  assign mmio.wvalid = write_request[2] && write_data_valid[2];
  assign icache.bready = write_response_ready[0];
  assign dcache.bready = write_response_ready[1];
  assign mmio.bready = write_response_ready[2];

  assign axi4.awready    = allow_write_address && !write_active_q &&
      !write_response_valid_q && cycle_q[0];
  assign axi4.wready = write_active_q && cycle_q[1];
  assign axi4.bid = 1'b0;
  assign axi4.bresp = 2'd0;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = write_response_valid_q;
  assign axi4.arready = allow_read_address && !response_valid_q && cycle_q[0];
  assign axi4.rid = 1'b0;
  assign axi4.rdata = response_data_q;
  assign axi4.rresp = 2'd0;
  assign axi4.rlast = 1'b1;
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = response_valid_q;

  hp_axi4_mux3 #(
      .RoundRobin       (1'b1),
      .Client0EpochAware(1'b1)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .epoch_i,
      .icache,
      .dcache,
      .mmio,
      .axi4
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      response_valid_q        <= 1'b0;
      response_data_q         <= 32'd0;
      response_count[0]       <= 0;
      response_count[1]       <= 0;
      response_count[2]       <= 0;
      write_response_count[0] <= 0;
      write_response_count[1] <= 0;
      write_response_count[2] <= 0;
      mixed_response_count[0] <= 0;
      mixed_response_count[1] <= 0;
      mixed_response_count[2] <= 0;
      total_responses         <= 0;
      total_write_responses   <= 0;
      total_mixed_responses   <= 0;
      write_active_q          <= 1'b0;
      write_response_valid_q  <= 1'b0;
      write_address_q         <= 32'd0;
      cycle_q                 <= 16'd0;
    end else if (epoch_i != u_dut.s_epoch_q) begin
      response_valid_q       <= 1'b0;
      write_active_q         <= 1'b0;
      write_response_valid_q <= 1'b0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (axi4.arvalid && axi4.arready) begin
        response_valid_q <= 1'b1;
        response_data_q  <= axi4.araddr;
      end
      if (axi4.rvalid && axi4.rready) response_valid_q <= 1'b0;
      if (axi4.awvalid && axi4.awready) begin
        write_active_q  <= 1'b1;
        write_address_q <= axi4.awaddr;
      end
      if (axi4.wvalid && axi4.wready) begin
        unique case (write_address_q)
          32'h0000_4000: if (axi4.wdata != 32'ha000_0000) $fatal(1, "APU write data mismatch");
          32'h0000_5000: if (axi4.wdata != 32'hb000_0000) $fatal(1, "SDIO0 write data mismatch");
          32'h0000_6000: if (axi4.wdata != 32'hc000_0000) $fatal(1, "USB2 write data mismatch");
          default:       $fatal(1, "Gateway A write owner address changed");
        endcase
        write_active_q         <= 1'b0;
        write_response_valid_q <= 1'b1;
      end
      if (axi4.bvalid && axi4.bready) write_response_valid_q <= 1'b0;
      if (icache.rvalid && icache.rready) begin
        if (recovery_response_q) begin
          if ((icache.rresp != 2'b11) || !icache.rlast) begin
            $fatal(1, "Gateway A malformed synthetic APU read response");
          end
        end else if ((!mixed_mode_q && ((total_responses % 3) != 0)) ||
            (icache.rdata != 32'h0000_1000)) begin
          $fatal(1, "Gateway A round-robin order/ownership failure for APU");
        end
        if (mixed_mode_q) begin
          mixed_response_count[0] <= mixed_response_count[0] + 1;
          total_mixed_responses   <= total_mixed_responses + 1;
        end else begin
          response_count[0] <= response_count[0] + 1;
          total_responses   <= total_responses + 1;
        end
      end
      if (dcache.rvalid && dcache.rready) begin
        if (recovery_response_q) begin
          if ((dcache.rresp != 2'b11) || !dcache.rlast) begin
            $fatal(1, "Gateway A malformed synthetic SDIO0 read response");
          end
        end else if ((!mixed_mode_q && ((total_responses % 3) != 1)) ||
            (dcache.rdata != 32'h0000_2000)) begin
          $fatal(1, "Gateway A round-robin order/ownership failure for SDIO0");
        end
        if (mixed_mode_q) begin
          mixed_response_count[1] <= mixed_response_count[1] + 1;
          total_mixed_responses   <= total_mixed_responses + 1;
        end else begin
          response_count[1] <= response_count[1] + 1;
          total_responses   <= total_responses + 1;
        end
      end
      if (mmio.rvalid && mmio.rready) begin
        if (recovery_response_q) begin
          if ((mmio.rresp != 2'b11) || !mmio.rlast) begin
            $fatal(1, "Gateway A malformed synthetic USB2 read response");
          end
        end else if ((!mixed_mode_q && ((total_responses % 3) != 2)) ||
                     (mmio.rdata != 32'h0000_3000)) begin
          $fatal(1, "Gateway A round-robin order/ownership failure for USB2");
        end
        if (mixed_mode_q) begin
          mixed_response_count[2] <= mixed_response_count[2] + 1;
          total_mixed_responses   <= total_mixed_responses + 1;
        end else begin
          response_count[2] <= response_count[2] + 1;
          total_responses   <= total_responses + 1;
        end
      end
      if (icache.bvalid && icache.bready) begin
        if (recovery_response_q) begin
          if (icache.bresp != 2'b11) $fatal(1, "Gateway A malformed synthetic APU B response");
        end else if (mixed_mode_q) begin
          mixed_response_count[0] <= mixed_response_count[0] + 1;
          total_mixed_responses   <= total_mixed_responses + 1;
        end else begin
          write_response_count[0] <= write_response_count[0] + 1;
          total_write_responses   <= total_write_responses + 1;
        end
      end
      if (dcache.bvalid && dcache.bready) begin
        if (recovery_response_q) begin
          if (dcache.bresp != 2'b11) begin
            $fatal(1, "Gateway A malformed synthetic SDIO0 B response");
          end
        end else if (mixed_mode_q) begin
          mixed_response_count[1] <= mixed_response_count[1] + 1;
          total_mixed_responses   <= total_mixed_responses + 1;
        end else begin
          write_response_count[1] <= write_response_count[1] + 1;
          total_write_responses   <= total_write_responses + 1;
        end
      end
      if (mmio.bvalid && mmio.bready) begin
        if (recovery_response_q) begin
          if (mmio.bresp != 2'b11) $fatal(1, "Gateway A malformed synthetic USB2 B response");
        end else if (mixed_mode_q) begin
          mixed_response_count[2] <= mixed_response_count[2] + 1;
          total_mixed_responses   <= total_mixed_responses + 1;
        end else begin
          write_response_count[2] <= write_response_count[2] + 1;
          total_write_responses   <= total_write_responses + 1;
        end
      end
    end
  end

  initial begin
    s_phase      = "read fairness";
    mixed_mode_q = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    read_request = 3'b111;
    read_ready   = 3'd0;
    wait (axi4.rvalid);
    repeat (3) begin
      @(posedge clk_i);
      #1;
      unique case (response_data_q)
        32'h0000_1000:
        if (!icache.rvalid || dcache.rvalid || mmio.rvalid || !axi4.rlast)
          $fatal(1, "Gateway A did not retain the APU R owner/RLAST");
        32'h0000_2000:
        if (icache.rvalid || !dcache.rvalid || mmio.rvalid || !axi4.rlast)
          $fatal(1, "Gateway A did not retain the SDIO0 R owner/RLAST");
        32'h0000_3000:
        if (icache.rvalid || dcache.rvalid || !mmio.rvalid || !axi4.rlast)
          $fatal(1, "Gateway A did not retain the USB2 R owner/RLAST");
        default: $fatal(1, "Gateway A retained an unknown R owner");
      endcase
    end
    read_ready = 3'b111;
    wait (total_responses >= 18);
    @(negedge clk_i);
    read_request = 3'd0;
    if ((response_count[0] != 6) || (response_count[1] != 6) || (response_count[2] != 6)) begin
      $fatal(1, "Gateway A client starvation detected");
    end

    s_phase              = "write fairness";
    write_response_ready = 3'd0;
    write_request        = 3'b111;
    wait (axi4.bvalid);
    repeat (3) begin
      @(posedge clk_i);
      #1;
      unique case (write_address_q)
        32'h0000_4000:
        if (!icache.bvalid || dcache.bvalid || mmio.bvalid || !axi4.bvalid)
          $fatal(1, "Gateway A did not retain the APU B owner");
        32'h0000_5000:
        if (icache.bvalid || !dcache.bvalid || mmio.bvalid || !axi4.bvalid)
          $fatal(1, "Gateway A did not retain the SDIO0 B owner");
        32'h0000_6000:
        if (icache.bvalid || dcache.bvalid || !mmio.bvalid || !axi4.bvalid)
          $fatal(1, "Gateway A did not retain the USB2 B owner");
        default: $fatal(1, "Gateway A retained an unknown B owner");
      endcase
    end
    write_response_ready = 3'b111;
    wait (total_write_responses >= 18);
    @(negedge clk_i);
    write_request = 3'd0;
    if ((write_response_count[0] != 6) || (write_response_count[1] != 6) ||
        (write_response_count[2] != 6)) begin
      $fatal(1, "Gateway A write client starvation detected");
    end

    s_phase = "mixed fairness";
    wait (!write_active_q && !write_response_valid_q);
    mixed_mode_q  = 1'b1;
    read_request  = 3'b101;
    write_request = 3'b010;
    wait (total_mixed_responses >= 9);
    @(negedge clk_i);
    read_request  = 3'd0;
    write_request = 3'd0;
    if ((mixed_response_count[0] != 3) || (mixed_response_count[1] != 3) ||
        (mixed_response_count[2] != 3)) begin
      $fatal(1, "Gateway A mixed-traffic fairness mismatch");
    end

    s_phase = "dynamic read address hold";
    wait (!response_valid_q && !write_active_q && !write_response_valid_q);
    mixed_mode_q       = 1'b1;
    allow_read_address = 1'b0;
    read_request       = 3'b010;
    wait (axi4.arvalid);
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    read_request = 3'b011;
    repeat (3) begin
      @(posedge clk_i);
      #1;
      if (!axi4.arvalid || (axi4.araddr != 32'h0000_2000)) begin
        $fatal(1, "Gateway A changed a stalled read address owner");
      end
    end
    allow_read_address = 1'b1;
    do @(posedge clk_i); while (!dcache.arready);
    @(negedge clk_i);
    read_request = 3'd0;
    wait (u_dut.s_state_q == 3'd0);

    s_phase             = "dynamic write address hold";
    allow_write_address = 1'b0;
    write_request       = 3'b100;
    wait (axi4.awvalid);
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    write_request = 3'b101;
    repeat (3) begin
      @(posedge clk_i);
      #1;
      if (!axi4.awvalid || (axi4.awaddr != 32'h0000_6000)) begin
        $fatal(1, "Gateway A changed a stalled write address owner");
      end
    end
    allow_write_address = 1'b1;
    do @(posedge clk_i); while (!mmio.awready);
    @(negedge clk_i);
    write_request = 3'b100;
    wait (u_dut.s_state_q == 3'd0);
    write_request = 3'd0;

    s_phase       = "active response flush recovery";
    read_ready    = 3'd0;
    read_request  = 3'b001;
    wait (icache.rvalid);
    @(negedge clk_i);
    epoch_i = epoch_i + 1'b1;
    @(negedge clk_i);
    read_request = 3'b010;
    read_ready   = 3'b111;
    do @(posedge clk_i); while (!dcache.arready);
    @(negedge clk_i);
    read_request = 3'd0;
    wait (u_dut.s_state_q == 3'd0);

    @(negedge clk_i);
    s_phase      = "non-aware read recovery";
    read_ready   = 3'd0;
    read_request = 3'b010;
    s_phase      = "non-aware read accepted";
    do @(posedge clk_i); while (!dcache.rvalid);
    @(negedge clk_i);
    epoch_i      = epoch_i + 1'b1;
    read_request = 3'd0;
    s_phase      = "non-aware read recovery state";
    wait (u_dut.s_state_q == 3'd3);
    s_phase = "non-aware read retained response";
    repeat (3) begin
      @(posedge clk_i);
      #1;
      if (!dcache.rvalid || icache.rvalid || mmio.rvalid || (dcache.rresp != 2'b11) ||
          !dcache.rlast || axi4.arvalid || axi4.awvalid) begin
        $fatal(1, "Gateway A did not retain synthetic read recovery response");
      end
    end
    @(negedge clk_i);
    recovery_response_q = 1'b1;
    read_ready          = 3'b111;
    @(posedge clk_i);
    @(negedge clk_i);
    recovery_response_q = 1'b0;
    s_phase             = "non-aware read completion";
    wait (u_dut.s_state_q == 3'd0);

    s_phase              = "non-aware write recovery";
    write_response_ready = 3'd0;
    write_data_valid     = 3'b011;
    write_request        = 3'b100;
    wait (u_dut.s_state_q == 3'd2);
    @(negedge clk_i);
    epoch_i = epoch_i + 1'b1;
    wait (u_dut.s_state_q == 3'd4);
    if (axi4.awvalid || axi4.arvalid) $fatal(1, "Gateway A issued an address during recovery");
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    write_data_valid = 3'b111;
    wait (u_dut.s_state_q == 3'd5);
    write_request = 3'd0;
    repeat (3) begin
      @(posedge clk_i);
      #1;
      if (!mmio.bvalid || icache.bvalid || dcache.bvalid || (mmio.bresp != 2'b11) ||
          axi4.awvalid || axi4.arvalid) begin
        $fatal(1, "Gateway A did not retain synthetic write recovery response");
      end
    end
    @(negedge clk_i);
    recovery_response_q  = 1'b1;
    write_response_ready = 3'b111;
    @(posedge clk_i);
    @(negedge clk_i);
    recovery_response_q = 1'b0;
    wait (u_dut.s_state_q == 3'd0);
    $display("APU-P2 Gateway A round-robin fairness passed with read/write/mixed retention");
    $finish;
  end

  initial begin
    repeat (1000) @(posedge clk_i);
    $fatal(
        1,
        "Gateway A round-robin test timed out in %s state=%0d rr=%0d read=%b write=%b rv=%0d bv=%0d",
        s_phase, u_dut.s_state_q, u_dut.s_rr_selected, read_request, write_request,
        response_valid_q, write_response_valid_q);
  end

endmodule
