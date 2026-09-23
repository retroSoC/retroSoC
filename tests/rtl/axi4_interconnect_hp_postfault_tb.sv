`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "rib_defs.svh"

/* APU-P8 post-fault visibility reproduction at the LP interconnect level.
 *
 * Mirrors the SoC wiring of axi4_bus: master 0 is the LP (management) core and
 * master 6 is the HP MMIO path (the legacy "usb2" port of axi4_bus). Target 0
 * is TARGET_CFG (APB4 peripheral window hosting the APU registers at
 * 0x10013000, UART1 at 0x10018000 and the HP mailbox at 0x10019000), target 3
 * is TARGET_SDRAM, target 7/8 are the DECERR/SLVERR error slaves exactly as
 * axi4_bus wires them.
 *
 * Sequence under test (MINI_PRODUCT, i.e. the apu_lp_only guard active):
 *   leg A: HP writes the mailbox window and LP reads it back (no fault yet)
 *   leg B: HP write-then-LP-read SDRAM round trip (no fault yet)
 *   leg C: HP stores to the LP-only APU register 0x10013040 -> SLVERR
 *   leg D: HP writes mailbox HP_EVENT/HP_ARG0/HP_SEQUENCE/HP_DOORBELL again
 *          and LP reads them back (the leg that fails at SoC level)
 *   leg E: HP writes the UART1 window post-fault (known to work on SoC)
 *   leg F: HP writes a legal APU offset post-fault (known to work on SoC)
 *   leg G: HP write-then-read SDRAM round trip post-fault
 */
module axi4_interconnect_hp_postfault_tb;
  localparam int NumMasters = 8;
  localparam int NumTargets = 10;

  localparam int TARGET_CFG = 0;
  localparam int TARGET_SDRAM = 3;
  localparam int TARGET_DECERR = 7;
  localparam int TARGET_SLVERR = 8;

  localparam logic [31:0] APU_LP_ONLY_ADDR = 32'h1001_3040;
  localparam logic [31:0] APU_LEGAL_ADDR = 32'h1001_301C;
  localparam logic [31:0] UART1_TXDATA = 32'h1001_8010;
  localparam logic [31:0] MAILBOX_HP_EVENT = 32'h1001_9020;
  localparam logic [31:0] MAILBOX_HP_ARG0 = 32'h1001_9024;
  localparam logic [31:0] MAILBOX_HP_SEQUENCE = 32'h1001_9028;
  localparam logic [31:0] MAILBOX_HP_DOORBELL = 32'h1001_902C;
  localparam logic [31:0] SDRAM_RESULT = 32'h3BC8_0080;
  localparam logic [31:0] RESULT_MAGIC = 32'h4852_3031;

  localparam int LP = 0;
  localparam int HP = 6;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_o;
  logic [31:0] fault_addr_o;
  logic [ 3:0] fault_wstrb_o;
  logic        fault_reserved_o;
  logic        fault_access_o;
  logic [ 2:0] fault_master_o;
  logic [ 2:0] fault_code_o;
  logic        user_bus_idle_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) masters[NumMasters] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) targets[NumTargets] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_interconnect #(
      .NumMasters(NumMasters),
      .NumTargets(NumTargets)
  ) u_dut (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .masters                (masters),
      .targets                (targets),
      .user_bus_enable_i      (1'b1),
      .user_bus_idle_o        (user_bus_idle_o),
      .mem_pad_mode_i         (2'd0),
      .perf_enable_i          (1'b0),
      .perf_clear_i           (1'b0),
      .fault_valid_o          (fault_valid_o),
      .fault_addr_o           (fault_addr_o),
      .fault_wstrb_o          (fault_wstrb_o),
      .fault_reserved_o       (fault_reserved_o),
      .fault_access_o         (fault_access_o),
      .fault_master_o         (fault_master_o),
      .fault_code_o           (fault_code_o),
      .perf_mgmt_wait_o       (),
      .perf_user_wait_o       (),
      .perf_dma_wait_o        (),
      .perf_sdio0_wait_o      (),
      .perf_sdio1_wait_o      (),
      .perf_usb2_wait_o       (),
      .perf_apb4_periph_wait_o(),
      .perf_apb4_system_wait_o(),
      .perf_sdram_wait_o      (),
      .perf_psram_wait_o      (),
      .perf_flash_wait_o      (),
      .perf_opipsram_wait_o   ()
  );

  // TARGET_CFG model: a small write/read store covering the APU, UART1 and
  // HP-mailbox windows used by the flow. Single outstanding transaction, which
  // matches how the interconnect serializes each target.
  logic [31:0] cfg_mem          [4096];
  logic [ 1:0] cfg_fsm_q = 2'd0;
  logic [31:0] cfg_addr_q = '0;
  logic        cfg_id_q = 1'b0;

  assign targets[TARGET_CFG].awready = (cfg_fsm_q == 2'd0) && !targets[TARGET_CFG].arvalid;
  assign targets[TARGET_CFG].arready = (cfg_fsm_q == 2'd0);
  assign targets[TARGET_CFG].wready  = (cfg_fsm_q == 2'd1);
  assign targets[TARGET_CFG].bvalid  = (cfg_fsm_q == 2'd2);
  assign targets[TARGET_CFG].bid     = cfg_id_q;
  assign targets[TARGET_CFG].bresp   = `AXI4_RESP_OKAY;
  assign targets[TARGET_CFG].buser   = '0;
  assign targets[TARGET_CFG].rvalid  = (cfg_fsm_q == 2'd3);
  assign targets[TARGET_CFG].rid     = cfg_id_q;
  assign targets[TARGET_CFG].rdata   = cfg_mem[cfg_addr_q[13:2]];
  assign targets[TARGET_CFG].rresp   = `AXI4_RESP_OKAY;
  assign targets[TARGET_CFG].rlast   = 1'b1;
  assign targets[TARGET_CFG].ruser   = '0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      cfg_fsm_q  <= 2'd0;
      cfg_addr_q <= '0;
      cfg_id_q   <= 1'b0;
    end else begin
      unique case (cfg_fsm_q)
        2'd0: begin
          if (targets[TARGET_CFG].arvalid && targets[TARGET_CFG].arready) begin
            cfg_addr_q <= targets[TARGET_CFG].araddr;
            cfg_id_q   <= targets[TARGET_CFG].arid;
            cfg_fsm_q  <= 2'd3;
          end else if (targets[TARGET_CFG].awvalid && targets[TARGET_CFG].awready) begin
            cfg_addr_q <= targets[TARGET_CFG].awaddr;
            cfg_id_q   <= targets[TARGET_CFG].awid;
            cfg_fsm_q  <= 2'd1;
          end
        end
        2'd1: begin
          if (targets[TARGET_CFG].wvalid && targets[TARGET_CFG].wready) begin
            cfg_mem[cfg_addr_q[13:2]] <= targets[TARGET_CFG].wdata;
            cfg_fsm_q                 <= 2'd2;
          end
        end
        2'd2:    if (targets[TARGET_CFG].bvalid && targets[TARGET_CFG].bready) cfg_fsm_q <= 2'd0;
        2'd3:    if (targets[TARGET_CFG].rvalid && targets[TARGET_CFG].rready) cfg_fsm_q <= 2'd0;
        default: cfg_fsm_q <= 2'd0;
      endcase
    end
  end

  // TARGET_SDRAM model: single-beat word store for the HP->LP round trip.
  logic [31:0] sdram_mem          [4096];
  logic [ 1:0] sdram_fsm_q = 2'd0;
  logic [31:0] sdram_addr_q = '0;
  logic        sdram_id_q = 1'b0;

  assign targets[TARGET_SDRAM].awready = (sdram_fsm_q == 2'd0) && !targets[TARGET_SDRAM].arvalid;
  assign targets[TARGET_SDRAM].arready = (sdram_fsm_q == 2'd0);
  assign targets[TARGET_SDRAM].wready  = (sdram_fsm_q == 2'd1);
  assign targets[TARGET_SDRAM].bvalid  = (sdram_fsm_q == 2'd2);
  assign targets[TARGET_SDRAM].bid     = sdram_id_q;
  assign targets[TARGET_SDRAM].bresp   = `AXI4_RESP_OKAY;
  assign targets[TARGET_SDRAM].buser   = '0;
  assign targets[TARGET_SDRAM].rvalid  = (sdram_fsm_q == 2'd3);
  assign targets[TARGET_SDRAM].rid     = sdram_id_q;
  assign targets[TARGET_SDRAM].rdata   = sdram_mem[sdram_addr_q[13:2]];
  assign targets[TARGET_SDRAM].rresp   = `AXI4_RESP_OKAY;
  assign targets[TARGET_SDRAM].rlast   = 1'b1;
  assign targets[TARGET_SDRAM].ruser   = '0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      sdram_fsm_q  <= 2'd0;
      sdram_addr_q <= '0;
      sdram_id_q   <= 1'b0;
    end else begin
      unique case (sdram_fsm_q)
        2'd0: begin
          if (targets[TARGET_SDRAM].arvalid && targets[TARGET_SDRAM].arready) begin
            sdram_addr_q <= targets[TARGET_SDRAM].araddr;
            sdram_id_q   <= targets[TARGET_SDRAM].arid;
            sdram_fsm_q  <= 2'd3;
          end else if (targets[TARGET_SDRAM].awvalid && targets[TARGET_SDRAM].awready) begin
            sdram_addr_q <= targets[TARGET_SDRAM].awaddr;
            sdram_id_q   <= targets[TARGET_SDRAM].awid;
            sdram_fsm_q  <= 2'd1;
          end
        end
        2'd1: begin
          if (targets[TARGET_SDRAM].wvalid && targets[TARGET_SDRAM].wready) begin
            sdram_mem[sdram_addr_q[13:2]] <= targets[TARGET_SDRAM].wdata;
            sdram_fsm_q                   <= 2'd2;
          end
        end
        2'd2: if (targets[TARGET_SDRAM].bvalid && targets[TARGET_SDRAM].bready) sdram_fsm_q <= 2'd0;
        2'd3: if (targets[TARGET_SDRAM].rvalid && targets[TARGET_SDRAM].rready) sdram_fsm_q <= 2'd0;
        default: sdram_fsm_q <= 2'd0;
      endcase
    end
  end

  // Every other target is an error slave so a mis-decoded access is loud:
  // target 7/8 keep the axi4_bus DECERR/SLVERR roles, the rest are DECERR.
  for (genvar target = 0; target < NumTargets; target++) begin : GEN_ERROR_TARGETS
    if ((target != TARGET_CFG) && (target != TARGET_SDRAM)) begin : gen_err
      localparam logic [1:0] Response =
          (target == TARGET_SLVERR) ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_DECODE_ERROR;
      axi4_error_slave #(
          .Response(Response)
      ) u_target (
          .clk_i  (clk_i),
          .rst_n_i(rst_n_i),
          .axi4   (targets[target])
      );
    end
  end

  `define INIT_MASTER(index)                                      \
  masters[index].awid     = '0;                                \
  masters[index].awaddr   = '0;                                \
  masters[index].awlen    = '0;                                \
  masters[index].awsize   = `AXI4_BURST_SIZE_4BYTES;           \
  masters[index].awburst  = `AXI4_BURST_TYPE_INCR;             \
  masters[index].awlock   = `AXI4_LOCK_NORM;                   \
  masters[index].awcache  = `AXI4_CACHE_NO_BUF;                \
  masters[index].awprot   = `AXI4_PROT_DATA;                   \
  masters[index].awqos    = `AXI4_QOS_NORMAL;                  \
  masters[index].awregion = `AXI4_REGION_NORMAL;               \
  masters[index].awuser   = '0;                                \
  masters[index].awvalid  = 1'b0;                              \
  masters[index].wdata    = '0;                                \
  masters[index].wstrb    = '0;                                \
  masters[index].wlast    = 1'b0;                              \
  masters[index].wuser    = '0;                                \
  masters[index].wvalid   = 1'b0;                              \
  masters[index].bready   = 1'b0;                              \
  masters[index].arid     = '0;                                \
  masters[index].araddr   = '0;                                \
  masters[index].arlen    = '0;                                \
  masters[index].arsize   = `AXI4_BURST_SIZE_4BYTES;           \
  masters[index].arburst  = `AXI4_BURST_TYPE_INCR;             \
  masters[index].arlock   = `AXI4_LOCK_NORM;                   \
  masters[index].arcache  = `AXI4_CACHE_NO_BUF;                \
  masters[index].arprot   = `AXI4_PROT_DATA;                   \
  masters[index].arqos    = `AXI4_QOS_NORMAL;                  \
  masters[index].arregion = `AXI4_REGION_NORMAL;               \
  masters[index].aruser   = '0;                                \
  masters[index].arvalid  = 1'b0;                              \
  masters[index].rready   = 1'b0;

  // Bounded single-beat write from the HP-attributed master 6.
  task automatic hp_write(input logic [31:0] address, input logic [31:0] data,
                          input logic [1:0] expected_response, input string leg);
    integer cycles;
    begin
      @(negedge clk_i);
      masters[HP].awaddr  = address;
      masters[HP].awlen   = 8'd0;
      masters[HP].awvalid = 1'b1;
      cycles              = 0;
      do begin
        @(posedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: AW handshake wedged at %h", leg, address);
      end while (!masters[HP].awready);
      @(negedge clk_i);
      masters[HP].awvalid = 1'b0;
      masters[HP].wdata   = data;
      masters[HP].wstrb   = 4'hF;
      masters[HP].wlast   = 1'b1;
      masters[HP].wvalid  = 1'b1;
      cycles              = 0;
      do begin
        @(posedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: W handshake wedged at %h", leg, address);
      end while (!masters[HP].wready);
      @(negedge clk_i);
      masters[HP].wvalid = 1'b0;
      masters[HP].bready = 1'b1;
      cycles             = 0;
      while (!masters[HP].bvalid) begin
        @(negedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: B response wedged at %h", leg, address);
      end
      #1;
      if (masters[HP].bresp != expected_response) begin
        $fatal(1, "%s: HP write at %h got resp=%0d, expected %0d", leg, address, masters[HP].bresp,
               expected_response);
      end
      @(negedge clk_i);
      masters[HP].bready = 1'b0;
    end
  endtask

  // Bounded single-beat read from the HP-attributed master 6.
  task automatic hp_read(input logic [31:0] address, input logic [31:0] expected_data,
                         input string leg);
    integer cycles;
    begin
      @(negedge clk_i);
      masters[HP].araddr  = address;
      masters[HP].arlen   = 8'd0;
      masters[HP].arvalid = 1'b1;
      cycles              = 0;
      do begin
        @(posedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: AR handshake wedged at %h", leg, address);
      end while (!masters[HP].arready);
      @(negedge clk_i);
      masters[HP].arvalid = 1'b0;
      masters[HP].rready  = 1'b1;
      cycles              = 0;
      while (!masters[HP].rvalid) begin
        @(negedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: R response wedged at %h", leg, address);
      end
      #1;
      if ((masters[HP].rresp != `AXI4_RESP_OKAY) || (masters[HP].rdata != expected_data)) begin
        $fatal(1, "%s: HP read at %h got resp=%0d data=%h, expected OKAY/%h", leg, address,
               masters[HP].rresp, masters[HP].rdata, expected_data);
      end
      @(negedge clk_i);
      masters[HP].rready = 1'b0;
    end
  endtask

  // Bounded single-beat read from the LP (management) master 0.
  task automatic lp_read(input logic [31:0] address, input logic [31:0] expected_data,
                         input string leg);
    integer cycles;
    begin
      @(negedge clk_i);
      masters[LP].araddr  = address;
      masters[LP].arlen   = 8'd0;
      masters[LP].arvalid = 1'b1;
      cycles              = 0;
      do begin
        @(posedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: AR handshake wedged at %h", leg, address);
      end while (!masters[LP].arready);
      @(negedge clk_i);
      masters[LP].arvalid = 1'b0;
      masters[LP].rready  = 1'b1;
      cycles              = 0;
      while (!masters[LP].rvalid) begin
        @(negedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: R response wedged at %h", leg, address);
      end
      #1;
      if ((masters[LP].rresp != `AXI4_RESP_OKAY) || (masters[LP].rdata != expected_data)) begin
        $fatal(1, "%s: LP read at %h got resp=%0d data=%h, expected OKAY/%h", leg, address,
               masters[LP].rresp, masters[LP].rdata, expected_data);
      end
      @(negedge clk_i);
      masters[LP].rready = 1'b0;
    end
  endtask

  // HP store to the LP-only APU register: the SLVERR response must complete
  // the AXI handshake and the fault record must classify it as PROTERR.
  task automatic hp_lp_only_probe(input string leg);
    integer cycles;
    begin
      @(negedge clk_i);
      masters[HP].awaddr  = APU_LP_ONLY_ADDR;
      masters[HP].awlen   = 8'd0;
      masters[HP].awvalid = 1'b1;
      cycles              = 0;
      do begin
        @(posedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: probe AW wedged", leg);
      end while (!masters[HP].awready);
      @(negedge clk_i);
      masters[HP].awvalid = 1'b0;
      masters[HP].wdata   = 32'h0000_0000;
      masters[HP].wstrb   = 4'hF;
      masters[HP].wlast   = 1'b1;
      masters[HP].wvalid  = 1'b1;
      cycles              = 0;
      do begin
        @(posedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: probe W wedged", leg);
      end while (!masters[HP].wready);
      @(negedge clk_i);
      masters[HP].wvalid = 1'b0;
      masters[HP].bready = 1'b1;
      cycles             = 0;
      while (!masters[HP].bvalid) begin
        @(negedge clk_i);
        cycles = cycles + 1;
        if (cycles > 64) $fatal(1, "%s: probe B wedged (SLVERR never completed)", leg);
      end
      #1;
      if ((masters[HP].bresp != `AXI4_RESP_SLAVE_ERROR) || !fault_valid_o || !fault_access_o ||
          (fault_addr_o != APU_LP_ONLY_ADDR) || (fault_wstrb_o != 4'hF) ||
          (fault_master_o != 3'(HP)) || (fault_code_o != `RIB_RESP_PROTERR)) begin
        $fatal(1,
               "%s: probe misclassified: resp=%0d fault=%0d access=%0d addr=%h master=%0d code=%0d",
               leg, masters[HP].bresp, fault_valid_o, fault_access_o, fault_addr_o, fault_master_o,
               fault_code_o);
      end
      @(negedge clk_i);
      masters[HP].bready = 1'b0;
    end
  endtask

  task automatic publish_mailbox(input logic [31:0] sequence_value, input string leg);
    begin
      hp_write(MAILBOX_HP_EVENT, 32'h0000_0002, `AXI4_RESP_OKAY, leg);
      hp_write(MAILBOX_HP_ARG0, 32'h0000_0005, `AXI4_RESP_OKAY, leg);
      hp_write(MAILBOX_HP_SEQUENCE, sequence_value, `AXI4_RESP_OKAY, leg);
      hp_write(MAILBOX_HP_DOORBELL, 32'h0000_0001, `AXI4_RESP_OKAY, leg);
    end
  endtask

  task automatic check_mailbox(input logic [31:0] sequence_value, input string leg);
    begin
      lp_read(MAILBOX_HP_SEQUENCE, sequence_value, leg);
      lp_read(MAILBOX_HP_EVENT, 32'h0000_0002, leg);
      lp_read(MAILBOX_HP_ARG0, 32'h0000_0005, leg);
      lp_read(MAILBOX_HP_DOORBELL, 32'h0000_0001, leg);
    end
  endtask

  integer watchdog;
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      watchdog = watchdog + 1;
      if (watchdog > 20000) $fatal(1, "global watchdog fired");
    end else begin
      watchdog = 0;
    end
  end

  initial begin
    `INIT_MASTER(0)
    `INIT_MASTER(1)
    `INIT_MASTER(2)
    `INIT_MASTER(3)
    `INIT_MASTER(4)
    `INIT_MASTER(5)
    `INIT_MASTER(6)
    `INIT_MASTER(7)
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

`ifndef MINI_PRODUCT
    $fatal(1, "this reproduction requires MINI_PRODUCT (the apu_lp_only guard)");
`endif

    // Leg A: control — HP mailbox publish round trip with no prior fault.
    publish_mailbox(32'h0000_0001, "leg A");
    check_mailbox(32'h0000_0001, "leg A");
    $display("LEG A PASS: pre-fault HP mailbox writes visible to LP");

    // Leg B: control — HP SDRAM store visible to an LP read.
    hp_write(SDRAM_RESULT, RESULT_MAGIC, `AXI4_RESP_OKAY, "leg B");
    lp_read(SDRAM_RESULT, RESULT_MAGIC, "leg B");
    $display("LEG B PASS: pre-fault HP SDRAM write visible to LP");

    // Leg C: the deliberate LP-only store probe -> SLVERR completes cleanly.
    hp_lp_only_probe("leg C");
    $display("LEG C PASS: LP-only APU probe returned SLVERR with PROTERR fault record");

    // Leg D: the SoC failure signature — post-fault HP mailbox publish.
    publish_mailbox(32'h0000_0009, "leg D");
    check_mailbox(32'h0000_0009, "leg D");
    $display("LEG D PASS: post-fault HP mailbox writes visible to LP");

    // Leg E: post-fault UART1 window write (the path that keeps working on SoC).
    hp_write(UART1_TXDATA, 32'h0000_0041, `AXI4_RESP_OKAY, "leg E");
    lp_read(UART1_TXDATA, 32'h0000_0041, "leg E");
    $display("LEG E PASS: post-fault HP UART1-window write visible to LP");

    // Leg F: post-fault write to a legal APU offset still lands.
    hp_write(APU_LEGAL_ADDR, 32'hDEAD_BEEF, `AXI4_RESP_OKAY, "leg F");
    lp_read(APU_LEGAL_ADDR, 32'hDEAD_BEEF, "leg F");
    $display("LEG F PASS: post-fault HP legal-APU-window write visible to LP");

    // Leg G: post-fault SDRAM round trip (HP store, LP read, HP read).
    hp_write(SDRAM_RESULT, RESULT_MAGIC, `AXI4_RESP_OKAY, "leg G");
    lp_read(SDRAM_RESULT, RESULT_MAGIC, "leg G");
    hp_read(SDRAM_RESULT, RESULT_MAGIC, "leg G");
    $display("LEG G PASS: post-fault HP SDRAM write/read round trip intact");

    // Repeat the probe once more to catch sticky state after a second fault.
    hp_lp_only_probe("leg H");
    publish_mailbox(32'h0000_000A, "leg H");
    check_mailbox(32'h0000_000A, "leg H");
    $display("LEG H PASS: second probe + publish round trip intact");

    $display("AXI4 interconnect HP post-fault visibility test passed");
    $finish;
  end

  `undef INIT_MASTER
endmodule
