// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "opipsram_define.svh"

module opipsram_tb;
  localparam logic [31:0] APERTURE_BASE = 32'h4800_0000;
  localparam logic [31:0] DEVICE_BYTES = 32'd4096;

  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          clk_phy_i = 1'b0;
  logic          rst_phy_n_i = 1'b0;
  logic   [31:0] reg_data;
  logic   [31:0] read_data;
  logic   [31:0] held_data;
  logic   [ 1:0] held_resp;
  logic          held_last;
  logic          indirect_launch_armed;
  logic          indirect_launch_seen;
  integer        transaction_count_before_bounds;

  apb4_if cfg_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mem_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  opipsram_if psram ();

  tri [7:0] dq_bus;
  tri       rwds_bus;

  assign dq_bus       = psram.dq_oe_o ? psram.dq_o : 8'hzz;
  assign psram.dq_i   = dq_bus;
  assign rwds_bus     = psram.rwds_oe_o ? psram.rwds_o : 1'bz;
  assign psram.rwds_i = rwds_bus;

  always #5 clk_i = ~clk_i;
  assign clk_phy_i = clk_i;

  initial begin
    #100000;
    $fatal(1, "OPIPSRAM test timeout: core_state=%0d phy_state=%0d abort_valid=%b abort_ready=%b",
           u_dut.u_opipsram_core.s_state_q, u_dut.u_opipsram_phy.s_state_q,
           u_dut.s_phy_abort_valid, u_dut.s_phy_abort_ready);
  end

  apb4_opipsram u_dut (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_phy_i  (clk_phy_i),
      .rst_phy_n_i(rst_phy_n_i),
      .cfg_apb4   (cfg_apb4),
      .mem_axi4   (mem_axi4),
      .psram      (psram)
  );

  opipsram_model #(
      .MEMORY_BYTES         (DEVICE_BYTES),
      .INITIALIZE_MEMORY    (1),
      .OPI_ADDRESS_BYTES    (3),
      .OPI_READ_DUMMY_BYTES (16),
      .OPI_WRITE_DUMMY_BYTES(16),
      .HYPER_LATENCY        (12)
  ) u_model (
      .source_clk_i(clk_phy_i),
      .ck_i        (psram.ck_o),
      .cs_n_i      (psram.cs_n_o),
      .dq_oe_i     (psram.dq_oe_o),
      .dq_o_i      (psram.dq_o),
      .dq_io       (dq_bus),
      .rwds_oe_i   (psram.rwds_oe_o),
      .rwds_o_i    (psram.rwds_o),
      .rwds_io     (rwds_bus)
  );

  always @(posedge clk_i) begin
    if (indirect_launch_armed && u_dut.s_phy_req_valid && u_dut.s_phy_req_ready) begin
      if (!u_dut.s_phy_req_profile_hyper || !u_dut.s_phy_req_write ||
          !u_dut.s_phy_req_indirect_register || (u_dut.s_phy_req_len != 4'd8) ||
          (u_dut.s_phy_req_wdata != 64'h4433_2211_8877_6655))
        $fatal(1, "indirect launch fields were not transferred atomically");
      indirect_launch_seen  = 1'b1;
      indirect_launch_armed = 1'b0;
    end
  end

  task automatic init_axi4;
    begin
      mem_axi4.awid     = '0;
      mem_axi4.awaddr   = '0;
      mem_axi4.awlen    = '0;
      mem_axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awlock   = `AXI4_LOCK_NORM;
      mem_axi4.awcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.awprot   = `AXI4_PROT_DATA;
      mem_axi4.awqos    = `AXI4_QOS_NORMAL;
      mem_axi4.awregion = `AXI4_REGION_NORMAL;
      mem_axi4.awuser   = '0;
      mem_axi4.awvalid  = 1'b0;
      mem_axi4.wdata    = '0;
      mem_axi4.wstrb    = '0;
      mem_axi4.wlast    = 1'b0;
      mem_axi4.wuser    = '0;
      mem_axi4.wvalid   = 1'b0;
      mem_axi4.bready   = 1'b0;
      mem_axi4.arid     = '0;
      mem_axi4.araddr   = '0;
      mem_axi4.arlen    = '0;
      mem_axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arlock   = `AXI4_LOCK_NORM;
      mem_axi4.arcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.arprot   = `AXI4_PROT_DATA;
      mem_axi4.arqos    = `AXI4_QOS_NORMAL;
      mem_axi4.arregion = `AXI4_REGION_NORMAL;
      mem_axi4.aruser   = '0;
      mem_axi4.arvalid  = 1'b0;
      mem_axi4.rready   = 1'b0;
    end
  endtask

  task automatic apb4_write(input logic [31:0] offset, input logic [31:0] data,
                            input logic [3:0] strobe, input logic expected_error);
    begin
      @(negedge clk_i);
      cfg_apb4.paddr   = offset;
      cfg_apb4.pwdata  = data;
      cfg_apb4.pstrb   = strobe;
      cfg_apb4.pwrite  = 1'b1;
      cfg_apb4.psel    = 1'b1;
      cfg_apb4.penable = 1'b0;
      @(negedge clk_i);
      cfg_apb4.penable = 1'b1;
      do @(posedge clk_i); while (!cfg_apb4.pready);
      if (cfg_apb4.pslverr !== expected_error)
        $fatal(1, "APB write %h error=%b expected=%b", offset, cfg_apb4.pslverr, expected_error);
      cfg_apb4.psel    = 1'b0;
      cfg_apb4.penable = 1'b0;
      cfg_apb4.pwrite  = 1'b0;
      cfg_apb4.pstrb   = '0;
    end
  endtask

  task automatic apb4_read(input logic [31:0] offset, input logic expected_error,
                           output logic [31:0] data);
    begin
      @(negedge clk_i);
      cfg_apb4.paddr   = offset;
      cfg_apb4.pwdata  = '0;
      cfg_apb4.pstrb   = '0;
      cfg_apb4.pwrite  = 1'b0;
      cfg_apb4.psel    = 1'b1;
      cfg_apb4.penable = 1'b0;
      @(negedge clk_i);
      cfg_apb4.penable = 1'b1;
      do @(posedge clk_i); while (!cfg_apb4.pready);
      if (cfg_apb4.pslverr !== expected_error)
        $fatal(1, "APB read %h error=%b expected=%b", offset, cfg_apb4.pslverr, expected_error);
      data             = cfg_apb4.prdata;
      cfg_apb4.psel    = 1'b0;
      cfg_apb4.penable = 1'b0;
    end
  endtask

  task automatic wait_interrupt(input logic [4:0] bit_index);
    begin
      for (int poll = 0; poll < 200; poll++) begin
        repeat (4) @(posedge clk_i);
        apb4_read(`APB4_OPIPSRAM__INTR_STATE, 1'b0, reg_data);
        if (reg_data[bit_index]) return;
      end
      $fatal(1, "interrupt bit %0d did not arrive", bit_index);
    end
  endtask

  task automatic cold_reset;
    begin
      @(negedge clk_i);
      rst_n_i     = 1'b0;
      rst_phy_n_i = 1'b0;
      repeat (4) @(posedge clk_i);
      rst_n_i     = 1'b1;
      rst_phy_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic axi_write_single(input logic [31:0] address, input logic [2:0] size,
                                  input logic [31:0] data, input logic [3:0] strobe,
                                  input logic [1:0] expected_response);
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = 8'd0;
      mem_axi4.awsize  = size;
      mem_axi4.awburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      mem_axi4.wdata   = data;
      mem_axi4.wstrb   = strobe;
      mem_axi4.wlast   = 1'b1;
      mem_axi4.wvalid  = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.wready);
      @(negedge clk_i);
      mem_axi4.wvalid = 1'b0;
      do @(negedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != expected_response)
        $fatal(1, "AXI write response mismatch at %08x", address);
      mem_axi4.bready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
      mem_axi4.wlast  = 1'b0;
      repeat (40) @(posedge clk_i);
    end
  endtask

  task automatic axi_read_single(input logic [31:0] address, input logic [2:0] size,
                                 input logic [1:0] expected_response, output logic [31:0] data);
    begin
      @(negedge clk_i);
      mem_axi4.araddr  = address;
      mem_axi4.arlen   = 8'd0;
      mem_axi4.arsize  = size;
      mem_axi4.arburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.arready);
      @(negedge clk_i);
      mem_axi4.arvalid = 1'b0;
      do @(negedge clk_i); while (!mem_axi4.rvalid);
      held_data = mem_axi4.rdata;
      held_resp = mem_axi4.rresp;
      held_last = mem_axi4.rlast;
      repeat (3) begin
        @(negedge clk_i);
        if (!mem_axi4.rvalid || (mem_axi4.rdata != held_data) ||
            (mem_axi4.rresp != held_resp) || (mem_axi4.rlast != held_last))
          $fatal(1, "AXI read response changed under backpressure");
      end
      if ((held_resp != expected_response) || !held_last)
        $fatal(1, "AXI read response mismatch at %08x", address);
      data            = held_data;
      mem_axi4.rready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_axi4.rready = 1'b0;
      repeat (40) @(posedge clk_i);
    end
  endtask

  task automatic axi_invalid_write_drain;
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = APERTURE_BASE + 32'h100;
      mem_axi4.awlen   = 8'd16;
      mem_axi4.awsize  = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      for (int beat = 0; beat < 17; beat++) begin
        mem_axi4.wdata  = 32'hC000_0000 + beat;
        mem_axi4.wstrb  = 4'hF;
        mem_axi4.wlast  = beat == 16;
        mem_axi4.wvalid = 1'b1;
        do @(posedge clk_i); while (!mem_axi4.wready);
        @(negedge clk_i);
        mem_axi4.wvalid = 1'b0;
      end
      do @(negedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != `AXI4_RESP_SLAVE_ERROR)
        $fatal(1, "invalid write was not drained with SLVERR");
      mem_axi4.bready = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
      mem_axi4.wlast  = 1'b0;
      repeat (40) @(posedge clk_i);
    end
  endtask

  initial begin
    cfg_apb4.psel         = 1'b0;
    cfg_apb4.paddr        = '0;
    cfg_apb4.pwdata       = '0;
    cfg_apb4.pstrb        = '0;
    indirect_launch_armed = 1'b0;
    indirect_launch_seen  = 1'b0;
    init_axi4();

    repeat (5) @(posedge clk_i);
    rst_n_i     = 1'b1;
    rst_phy_n_i = 1'b1;

    $display("OPIPSRAM_TB_STAGE apb_reset_config");
    apb4_read(`APB4_OPIPSRAM__IP_ID, 1'b0, reg_data);
    if (reg_data != `APB4_OPIPSRAM__IP_ID_VALUE) $fatal(1, "IP ID mismatch");
    apb4_read(`APB4_OPIPSRAM__IP_VERSION, 1'b0, reg_data);
    if (reg_data != `APB4_OPIPSRAM__IP_VERSION_VALUE) $fatal(1, "IP version mismatch");
    apb4_read(`APB4_OPIPSRAM__TRAIN_STATUS, 1'b0, reg_data);
    if (reg_data != 32'd0) $fatal(1, "training status reset mismatch: %08x", reg_data);
    apb4_write(`APB4_OPIPSRAM__DEVICE_SIZE, DEVICE_BYTES, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__POWERUP_CYCLES, 32'd1, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__TIMEOUT_CYCLES, 32'd1000, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CS_TIMING, 32'h0001_0101, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_ENABLE, 32'h1F, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CTRL, 32'h3, 4'h1, 1'b0);

    $display("OPIPSRAM_TB_STAGE opi_init_lock_train");
    apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h1, 4'h1, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INIT_DONE);
    apb4_read(`APB4_OPIPSRAM__STATUS, 1'b0, reg_data);
    if (!reg_data[`APB4_OPIPSRAM__STATUS_READY] ||
        !reg_data[`APB4_OPIPSRAM__STATUS_PROFILE_LOCK] ||
        reg_data[`APB4_OPIPSRAM__STATUS_HYPER])
      $fatal(1, "OPI profile did not initialize and lock");
    apb4_write(`APB4_OPIPSRAM__PROTOCOL_CFG, 32'd1, 4'h1, 1'b1);
    apb4_write(`APB4_OPIPSRAM__RX_DELAY, 32'h25, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h8, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__RX_DELAY, 32'h26, 4'h1, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_TRAIN_DONE);
    apb4_read(`APB4_OPIPSRAM__TRAIN_STATUS, 1'b0, reg_data);
    if (reg_data != 32'h0001_0502) $fatal(1, "training status layout mismatch: %08x", reg_data);

    $display("OPIPSRAM_TB_STAGE opi_axi");
    axi_write_single(APERTURE_BASE + 32'h100, `AXI4_BURST_SIZE_4BYTES, 32'hDEAD_BEEF, 4'hF,
                     `AXI4_RESP_OKAY);
    if (u_model.mem_array[32'h100] != 8'hEF)
      $fatal(
          1,
          "BLOCKER: OPI address serialization did not reach local address 0x100 (model[0]=%02x model[0x100]=%02x)",
          u_model.mem_array[0],
          u_model.mem_array[32'h100]
      );
    axi_read_single(APERTURE_BASE + 32'h100, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_OKAY, read_data);
    if (read_data != 32'hDEAD_BEEF)
      $fatal(
          1,
          "BLOCKER: first AXI read after a completed write returned stale data (rdata=%08x model=%02x)",
          read_data,
          u_model.mem_array[32'h100]
      );
    axi_read_single(APERTURE_BASE + DEVICE_BYTES - 2, `AXI4_BURST_SIZE_4BYTES,
                    `AXI4_RESP_SLAVE_ERROR, read_data);
    axi_invalid_write_drain();

    $display("OPIPSRAM_TB_STAGE hyper_init_axi");
    cold_reset();
    apb4_write(`APB4_OPIPSRAM__DEVICE_SIZE, DEVICE_BYTES, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__POWERUP_CYCLES, 32'd1, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__TIMEOUT_CYCLES, 32'd1000, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CS_TIMING, 32'h0001_0101, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_ENABLE, 32'h1F, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CTRL, 32'h3, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__PROTOCOL_CFG, 32'd1, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h1, 4'h1, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INIT_DONE);
    apb4_read(`APB4_OPIPSRAM__STATUS, 1'b0, reg_data);
    if (!reg_data[`APB4_OPIPSRAM__STATUS_HYPER] || !reg_data[`APB4_OPIPSRAM__STATUS_PROFILE_LOCK])
      $fatal(1, "HyperBus profile did not initialize and lock");
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'h20, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_WDATA_LO, 32'h8877_6655, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_WDATA_HI, 32'h4433_2211, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    indirect_launch_armed = 1'b1;
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h183, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    if (!indirect_launch_seen) $fatal(1, "indirect launch did not reach the PHY");
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h182, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    apb4_read(`APB4_OPIPSRAM__INDIRECT_RDATA_LO, 1'b0, reg_data);
    if (reg_data != 32'h8877_6655)
      $fatal(
          1,
          "HyperBus register-space mismatch rdata=%08x model=%02x%02x%02x%02x",
          reg_data,
          u_model.register_array[32'h23],
          u_model.register_array[32'h22],
          u_model.register_array[32'h21],
          u_model.register_array[32'h20]
      );
    apb4_read(`APB4_OPIPSRAM__INDIRECT_RDATA_HI, 1'b0, reg_data);
    if (reg_data != 32'h4433_2211)
      $fatal(1, "HyperBus register-space high mismatch rdata=%08x", reg_data);
    transaction_count_before_bounds = u_model.transaction_count;
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'h21, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h113, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    apb4_read(`APB4_OPIPSRAM__LAST_ERROR, 1'b0, reg_data);
    if ((reg_data[3:0] != 4'd7) ||
        (u_model.transaction_count != transaction_count_before_bounds) ||
        (psram.cs_n_o !== 1'b1))
      $fatal(1, "invalid HyperBus register write generated pin activity");
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'h200, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_WDATA_LO, 32'h78, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h111, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    if ((u_model.mem_array[32'h200] != 8'h78) ||
        (u_model.hyper_write_physical_count != 2) ||
        (u_model.hyper_write_masked_count != 1))
      $fatal(1, "HyperBus one-byte write word/mask mismatch");
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'h210, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_WDATA_LO, 32'h0033_2211, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h131, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    if ((u_model.mem_array[32'h210] != 8'h11) ||
        (u_model.mem_array[32'h211] != 8'h22) ||
        (u_model.mem_array[32'h212] != 8'h33) ||
        (u_model.hyper_write_physical_count != 4) ||
        (u_model.hyper_write_masked_count != 1))
      $fatal(1, "HyperBus three-byte write word/mask mismatch");
    u_model.mem_array[32'h220] = 8'hC0;
    u_model.mem_array[32'h221] = 8'hC1;
    u_model.mem_array[32'h222] = 8'hC2;
    u_model.mem_array[32'h223] = 8'hC3;
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'h221, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_WDATA_LO, 32'h0033_2211, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h131, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    if ((u_model.mem_array[32'h220] != 8'hC0) ||
        (u_model.mem_array[32'h221] != 8'h11) ||
        (u_model.mem_array[32'h222] != 8'h22) ||
        (u_model.mem_array[32'h223] != 8'h33) ||
        (u_model.hyper_write_physical_count != 4) ||
        (u_model.hyper_write_masked_count != 1))
      $fatal(1, "HyperBus odd-address write alignment/mask mismatch");
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h130, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    apb4_read(`APB4_OPIPSRAM__INDIRECT_RDATA_LO, 1'b0, reg_data);
    if (reg_data[23:0] != 24'h33_2211)
      $fatal(1, "HyperBus odd-address read alignment mismatch: %08x", reg_data);
    transaction_count_before_bounds = u_model.transaction_count;
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'hFFF, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h2, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h120, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    apb4_read(`APB4_OPIPSRAM__LAST_ERROR, 1'b0, reg_data);
    if ((reg_data[3:0] != 4'd8) ||
        (u_model.transaction_count != transaction_count_before_bounds) ||
        (psram.cs_n_o !== 1'b1))
      $fatal(1, "indirect memory bounds generated pin activity");
    axi_write_single(APERTURE_BASE + 32'h200, `AXI4_BURST_SIZE_1BYTE, 32'h0000_0078, 4'h1,
                     `AXI4_RESP_OKAY);
    axi_read_single(APERTURE_BASE + 32'h200, `AXI4_BURST_SIZE_1BYTE, `AXI4_RESP_OKAY, read_data);
    if (read_data[7:0] != 8'h78) $fatal(1, "HyperBus readback mismatch");

    $display("OPIPSRAM_TB_STAGE abort");
    fork
      begin
        axi_read_single(APERTURE_BASE + 32'h240, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_SLAVE_ERROR,
                        read_data);
      end
      begin
        repeat (3) @(posedge clk_i);
        apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h2, 4'h1, 1'b0);
      end
    join
    apb4_read(`APB4_OPIPSRAM__INTR_STATUS, 1'b0, reg_data);
    if (!reg_data[`APB4_OPIPSRAM__INTR_ERROR]) $fatal(1, "abort error IRQ missing");

    $display("OPIPSRAM_TB_STAGE issue_cycle_abort");
    cold_reset();
    apb4_write(`APB4_OPIPSRAM__DEVICE_SIZE, DEVICE_BYTES, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__POWERUP_CYCLES, 32'd1, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__TIMEOUT_CYCLES, 32'd1000, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CS_TIMING, 32'h0001_0101, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_ENABLE, 32'h1F, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CTRL, 32'h3, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__PROTOCOL_CFG, 32'd1, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h1, 4'h1, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INIT_DONE);
    fork
      begin
        axi_read_single(APERTURE_BASE + 32'h260, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_SLAVE_ERROR,
                        read_data);
      end
      begin
        wait ((u_dut.u_opipsram_core.s_state_q == 4'd2) && u_dut.s_phy_req_ready);
        force u_dut.s_abort = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        release u_dut.s_abort;
      end
    join
    cold_reset();
    apb4_write(`APB4_OPIPSRAM__DEVICE_SIZE, DEVICE_BYTES, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__POWERUP_CYCLES, 32'd1, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__TIMEOUT_CYCLES, 32'd1000, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CS_TIMING, 32'h0001_0101, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CTRL, 32'h3, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__PROTOCOL_CFG, 32'd1, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h1, 4'h1, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INIT_DONE);
    axi_read_single(APERTURE_BASE + 32'h220, `AXI4_BURST_SIZE_1BYTE, `AXI4_RESP_OKAY, read_data);
    if (read_data[7:0] != 8'hC0) $fatal(1, "post-abort response stream was stale");

    $display("OPIPSRAM_TB_STAGE opi_timeout_irq");
    cold_reset();
    apb4_write(`APB4_OPIPSRAM__DEVICE_SIZE, DEVICE_BYTES, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__POWERUP_CYCLES, 32'd1, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__TIMEOUT_CYCLES, 32'd1, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CS_TIMING, 32'h0001_0101, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INTR_ENABLE, 32'h1F, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__CTRL, 32'h3, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__COMMAND, 32'h1, 4'h1, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INIT_DONE);
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h1F, 4'h1, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_ADDR, 32'h180, 4'hF, 1'b0);
    apb4_write(`APB4_OPIPSRAM__INDIRECT_CTRL, 32'h140, 4'hF, 1'b0);
    wait_interrupt(`APB4_OPIPSRAM__INTR_INDIRECT_DONE);
    apb4_read(`APB4_OPIPSRAM__INTR_STATUS, 1'b0, reg_data);
    if (!reg_data[`APB4_OPIPSRAM__INTR_ERROR] || !reg_data[`APB4_OPIPSRAM__INTR_TIMEOUT])
      $fatal(1, "indirect timeout/error interrupts were not reported");
    apb4_write(`APB4_OPIPSRAM__INTR_STATE, 32'h1F, 4'h1, 1'b0);
    axi_read_single(APERTURE_BASE + 32'h180, `AXI4_BURST_SIZE_4BYTES, `AXI4_RESP_SLAVE_ERROR,
                    read_data);
    apb4_read(`APB4_OPIPSRAM__INTR_STATUS, 1'b0, reg_data);
    if (!reg_data[`APB4_OPIPSRAM__INTR_ERROR] || !reg_data[`APB4_OPIPSRAM__INTR_TIMEOUT])
      $fatal(1, "timeout/error interrupts were not reported");

    $display("OPIPSRAM controller integration test passed");
    $finish;
  end
endmodule
