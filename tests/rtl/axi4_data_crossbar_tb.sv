`timescale 1ns / 1ps

module axi4_data_crossbar_tb;
  localparam int NumMasters = 10;
  localparam int NumTargets = 6;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        idle_o;
  logic [ 9:0] master_block_i = '0;
  logic [ 9:0] master_idle_o;
  logic [ 7:0] outstanding_read_o;
  logic [ 7:0] outstanding_write_o;
  logic        fault_valid_o;
  logic        fault_ready_i = 1'b1;
  logic [ 3:0] fault_master_o;
  logic [ 2:0] fault_target_o;
  logic [31:0] fault_addr_o;
  logic        fault_write_o;
  logic [ 3:0] fault_reason_o;
  logic        recovery_i = 1'b0;
  logic        flush_i = 1'b0;
  logic [ 9:0] monitor_master_promotion_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) masters[NumMasters] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) targets[NumTargets] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  initial begin
    repeat (500) @(posedge clk_i);
    $fatal(1, "AXI4 data crossbar test timed out");
  end

  axi4_data_crossbar #(
      .StarvationCycles(4),
      .ReadTargetMask(
      '{
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111,
          5'b11111
      }
      ),
      .WriteTargetMask(
      '{
          5'b01111,
          5'b01111,
          5'b01111,
          5'b01111,
          5'b01111,
          5'b01111,
          5'b01111,
          5'b01111,
          5'b01111,
          5'b00000
      }
      ),
      .AllowInstruction(10'b0000000001),
      .RequireNoncacheable(10'b1111111100)
  ) u_dut (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .block_new_i               (1'b0),
      .master_block_i            (master_block_i),
      .recovery_i                (recovery_i),
      .flush_i                   (flush_i),
      .fault_ready_i             (fault_ready_i),
      .mem_pad_mode_i            (2'd1),
      .ext_h_read_base_i         (32'h3000_0000),
      .ext_h_read_limit_i        (32'h4FFF_FFFF),
      .ext_h_write_base_i        (32'h3000_0000),
      .ext_h_write_limit_i       (32'h4FFF_FFFF),
      .masters                   (masters),
      .targets                   (targets),
      .idle_o                    (idle_o),
      .master_idle_o             (master_idle_o),
      .outstanding_read_o        (outstanding_read_o),
      .outstanding_write_o       (outstanding_write_o),
      .fault_valid_o             (fault_valid_o),
      .fault_master_o            (fault_master_o),
      .fault_target_o            (fault_target_o),
      .fault_addr_o              (fault_addr_o),
      .fault_write_o             (fault_write_o),
      .fault_reason_o            (fault_reason_o),
      .monitor_master_promotion_o(monitor_master_promotion_o)
  );

  task automatic issue_master1_read(input logic [6:0] id, input logic [31:0] addr);
    begin
      @(negedge clk_i);
      masters[1].arid    = id;
      masters[1].araddr  = addr;
      masters[1].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[1].arready);
      @(negedge clk_i);
      masters[1].arvalid = 1'b0;
    end
  endtask

  task automatic return_target0_read(input logic [6:0] id, input logic [63:0] data);
    begin
      @(negedge clk_i);
      targets[0].rid    = id;
      targets[0].rdata  = data;
      targets[0].rresp  = 2'b00;
      targets[0].rlast  = 1'b1;
      targets[0].rvalid = 1'b1;
      do @(posedge clk_i); while (!targets[0].rready);
      @(negedge clk_i);
      targets[0].rvalid = 1'b0;
    end
  endtask

  task automatic return_target1_read(input logic [6:0] id, input logic [63:0] data);
    begin
      @(negedge clk_i);
      targets[1].rid    = id;
      targets[1].rdata  = data;
      targets[1].rresp  = 2'b00;
      targets[1].rlast  = 1'b1;
      targets[1].rvalid = 1'b1;
      do @(posedge clk_i); while (!targets[1].rready);
      @(negedge clk_i);
      targets[1].rvalid = 1'b0;
    end
  endtask

  task automatic return_target5_read(input logic [6:0] id);
    begin
      @(negedge clk_i);
      targets[5].rid    = id;
      targets[5].rresp  = 2'b10;
      targets[5].rlast  = 1'b1;
      targets[5].rvalid = 1'b1;
      do @(posedge clk_i); while (!targets[5].rready);
      @(negedge clk_i);
      targets[5].rvalid = 1'b0;
    end
  endtask

  task automatic return_target0_write(input logic [6:0] id);
    begin
      @(negedge clk_i);
      targets[0].bid    = id;
      targets[0].bresp  = 2'b00;
      targets[0].bvalid = 1'b1;
      do @(posedge clk_i); while (!targets[0].bready);
      @(negedge clk_i);
      targets[0].bvalid = 1'b0;
    end
  endtask

  task automatic return_invalid_target0_response(input logic [3:0] prefix,
                                                 input logic write_access);
    logic [6:0] id;
    begin
      id = {prefix, 3'd0};
      @(negedge clk_i);
      if (write_access) begin
        targets[0].bid    = id;
        targets[0].bresp  = 2'b00;
        targets[0].bvalid = 1'b1;
      end else begin
        targets[0].rid    = id;
        targets[0].rdata  = 64'hDEAD_BEEF_0000_0000 | id;
        targets[0].rresp  = 2'b00;
        targets[0].rlast  = 1'b1;
        targets[0].rvalid = 1'b1;
      end
      #1;
      if (!(write_access ? targets[0].bready : targets[0].rready)) begin
        $fatal(1, "invalid returned master prefix was not accepted for containment");
      end
      @(posedge clk_i);
      #1;
      if (!fault_valid_o || (fault_master_o != prefix) || (fault_target_o != 3'd0) ||
          (fault_reason_o != 4'd4) || (fault_write_o != write_access)) begin
        $fatal(1, "invalid returned master prefix was not contained");
      end
      if (masters[0].rvalid || masters[0].bvalid) begin
        $fatal(1, "invalid response prefix fell back to master 0");
      end
      @(negedge clk_i);
      if (write_access) begin
        targets[0].bvalid = 1'b0;
      end else begin
        targets[0].rvalid = 1'b0;
      end
    end
  endtask

  `define INIT_MASTER(index)                       \
    masters[index].awid = '0;                      \
    masters[index].awaddr = '0;                    \
    masters[index].awlen = '0;                     \
    masters[index].awsize = 3'd3;                  \
    masters[index].awburst = 2'b01;                \
    masters[index].awlock = 1'b0;                  \
    masters[index].awcache = '0;                   \
    masters[index].awprot = '0;                    \
    masters[index].awqos = '0;                     \
    masters[index].awregion = '0;                  \
    masters[index].awuser = '0;                    \
    masters[index].awvalid = 1'b0;                 \
    masters[index].wdata = '0;                     \
    masters[index].wstrb = '0;                     \
    masters[index].wlast = 1'b1;                   \
    masters[index].wuser = '0;                     \
    masters[index].wvalid = 1'b0;                  \
    masters[index].bready = 1'b1;                  \
    masters[index].arid = '0;                      \
    masters[index].araddr = '0;                    \
    masters[index].arlen = '0;                     \
    masters[index].arsize = 3'd3;                  \
    masters[index].arburst = 2'b01;                \
    masters[index].arlock = 1'b0;                  \
    masters[index].arcache = '0;                   \
    masters[index].arprot = '0;                    \
    masters[index].arqos = '0;                     \
    masters[index].arregion = '0;                  \
    masters[index].aruser = '0;                    \
    masters[index].arvalid = 1'b0;                 \
    masters[index].rready = 1'b1;

  `define INIT_TARGET(index)                       \
    targets[index].awready = 1'b1;                 \
    targets[index].wready = 1'b1;                  \
    targets[index].bid = '0;                       \
    targets[index].bresp = '0;                     \
    targets[index].buser = '0;                     \
    targets[index].bvalid = 1'b0;                  \
    targets[index].arready = 1'b1;                 \
    targets[index].rid = '0;                       \
    targets[index].rdata = '0;                     \
    targets[index].rresp = '0;                     \
    targets[index].rlast = 1'b1;                   \
    targets[index].ruser = '0;                     \
    targets[index].rvalid = 1'b0;

  initial begin
    `INIT_MASTER(0)
    `INIT_MASTER(1)
    `INIT_MASTER(2)
    `INIT_MASTER(3)
    `INIT_MASTER(4)
    `INIT_MASTER(5)
    `INIT_MASTER(6)
    `INIT_MASTER(7)
    `INIT_MASTER(8)
    `INIT_MASTER(9)
    `INIT_TARGET(0)
    `INIT_TARGET(1)
    `INIT_TARGET(2)
    `INIT_TARGET(3)
    `INIT_TARGET(4)
    `INIT_TARGET(5)

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    @(negedge clk_i);
    master_block_i[1]  = 1'b1;
    masters[1].arid    = 6'b001_111;
    masters[1].araddr  = 32'h3000_0000;
    masters[1].arvalid = 1'b1;
    #1;
    if (masters[1].arready || master_idle_o[1]) begin
      $fatal(1, "blocked master was accepted or reported idle with VALID held");
    end
    masters[1].arvalid = 1'b0;
    master_block_i[1]  = 1'b0;

    issue_master1_read(6'b001_000, 32'h3000_0000);
    issue_master1_read(6'b001_001, 32'h3800_0000);
    if (outstanding_read_o != 8'd2 || idle_o) begin
      $fatal(1, "different-target reads were not tracked concurrently");
    end

    @(negedge clk_i);
    masters[1].arid    = 6'b001_000;
    masters[1].araddr  = 32'h4000_0000;
    masters[1].arvalid = 1'b1;
    #1;
    if (masters[1].arready) $fatal(1, "same source ID was accepted before completion");
    masters[1].arvalid = 1'b0;

    fork
      return_target1_read(6'b001_001, 64'h2222_2222_2222_2222);
      begin
        wait (masters[1].rvalid);
        if ((masters[1].rid != 6'b001_001) || (masters[1].rdata != 64'h2222_2222_2222_2222)) begin
          $fatal(1, "out-of-order different-ID response was misrouted");
        end
      end
    join
    return_target0_read(6'b001_000, 64'h1111_1111_1111_1111);
    @(negedge clk_i);
    if (!idle_o || (outstanding_read_o != 8'd0)) begin
      $fatal(1, "read completion did not drain the crossbar");
    end

    ga2d_master_id_credit_and_qos : begin
      @(negedge clk_i);
      targets[0].arready = 1'b0;
      masters[8].arid    = 7'h40;
      masters[8].araddr  = 32'h3000_0040;
      masters[8].arqos   = 4'hF;
      masters[8].arvalid = 1'b1;
      #1;
      if (!targets[0].arvalid || (targets[0].arid != 7'h40) || (targets[0].arqos != 4'd0)) begin
        $fatal(1, "GA2D read ID prefix or AxQOS was not preserved");
      end
      targets[0].arready = 1'b1;
      do @(posedge clk_i); while (!masters[8].arready);
      @(negedge clk_i);
      masters[8].arvalid = 1'b0;
      masters[8].arqos   = '0;

      @(negedge clk_i);
      targets[0].awready = 1'b0;
      masters[8].awid    = 7'h41;
      masters[8].awaddr  = 32'h3000_0080;
      masters[8].awqos   = 4'hF;
      masters[8].awvalid = 1'b1;
      #1;
      if (!targets[0].awvalid || (targets[0].awid != 7'h41) || (targets[0].awqos != 4'd0)) begin
        $fatal(1, "GA2D write ID prefix or AxQOS was not preserved");
      end
      targets[0].awready = 1'b1;
      do @(posedge clk_i); while (!masters[8].awready);
      @(negedge clk_i);
      masters[8].awvalid = 1'b0;
      masters[8].awqos   = '0;
      masters[8].wdata   = 64'hA5A5_5A5A_1122_3344;
      masters[8].wstrb   = 8'hFF;
      masters[8].wvalid  = 1'b1;
      do @(posedge clk_i); while (!masters[8].wready);
      @(negedge clk_i);
      masters[8].wvalid = 1'b0;

      @(negedge clk_i);
      masters[8].arid    = 7'h42;
      masters[8].araddr  = 32'h3000_00C0;
      masters[8].arvalid = 1'b1;
      masters[8].awid    = 7'h43;
      masters[8].awaddr  = 32'h3000_0100;
      masters[8].awvalid = 1'b1;
      #1;
      if (masters[8].arready || masters[8].awready) begin
        $fatal(1, "GA2D exceeded its one-read plus one-write credit");
      end
      masters[8].arvalid = 1'b0;
      masters[8].awvalid = 1'b0;

      fork
        return_target0_read(7'h40, 64'h8888_8888_8888_0040);
        begin
          wait (masters[8].rvalid);
          if ((masters[8].rid != 7'h40) || (masters[8].rdata != 64'h8888_8888_8888_0040)) begin
            $fatal(1, "GA2D read response did not return to master 8");
          end
        end
      join
      fork
        return_target0_write(7'h41);
        begin
          wait (masters[8].bvalid);
          if (masters[8].bid != 7'h41) begin
            $fatal(1, "GA2D write response did not return to master 8");
          end
        end
      join
      @(negedge clk_i);
      if (!idle_o || (outstanding_read_o != 8'd0) || (outstanding_write_o != 8'd0)) begin
        $fatal(1, "GA2D master credits did not drain independently");
      end
    end

    issue_master1_read(6'b001_010, 32'h3000_0040);
    issue_master1_read(6'b001_011, 32'h3000_0080);
    if (outstanding_read_o != 8'd2) begin
      $fatal(1, "same-target reads were not tracked concurrently");
    end
    fork
      return_target0_read(6'b001_011, 64'h3333_3333_3333_3333);
      begin
        wait (masters[1].rvalid);
        if ((masters[1].rid != 6'b001_011) || (masters[1].rdata != 64'h3333_3333_3333_3333)) begin
          $fatal(1, "same-target out-of-order response was misrouted");
        end
      end
    join
    @(posedge clk_i);
    fork
      return_target0_read(6'b001_010, 64'h4444_4444_4444_4444);
      begin
        wait (masters[1].rvalid);
        if ((masters[1].rid != 6'b001_010) || (masters[1].rdata != 64'h4444_4444_4444_4444)) begin
          $fatal(1, "same-target older response was misrouted");
        end
      end
    join
    @(negedge clk_i);
    if (!idle_o || (outstanding_read_o != 8'd0)) begin
      $fatal(1, "same-target reads did not drain the crossbar");
    end

    jpeg_master_admission_credit_priority_and_acl : begin
      // JPEG's normal class is above the LP gateway's class before aging.
      @(negedge clk_i);
      targets[0].arready = 1'b0;
      masters[6].arid    = 7'h30;
      masters[6].araddr  = 32'h3000_0000;
      masters[6].arvalid = 1'b1;
      masters[5].arid    = 7'h28;
      masters[5].araddr  = 32'h3000_0020;
      masters[5].arvalid = 1'b1;
      #1;
      if (!targets[0].arvalid || (targets[0].arid != 7'h30)) begin
        $fatal(1, "JPEG class-8 read did not outrank the LP gateway");
      end
      targets[0].arready = 1'b1;
      do @(posedge clk_i); while (!masters[6].arready);
      @(negedge clk_i);
      masters[6].arvalid = 1'b0;
      masters[5].arvalid = 1'b0;
      fork
        return_target0_read(7'h30, 64'h6666_6666_6666_0030);
        begin
          wait (masters[6].rvalid);
          if (masters[6].rid != 7'h30) begin
            $fatal(1, "JPEG class-8 response did not route to master 6");
          end
        end
      join

      // A continuously eligible JPEG request must still receive aging promotion.
      @(negedge clk_i);
      targets[0].arready = 1'b0;
      masters[6].arid    = 7'h32;
      masters[6].araddr  = 32'h3000_0040;
      masters[6].arvalid = 1'b1;
      repeat (4) @(posedge clk_i);
      @(negedge clk_i);
      masters[0].arid    = 7'h02;
      masters[0].araddr  = 32'h3000_0060;
      masters[0].arvalid = 1'b1;
      #1;
      if (!targets[0].arvalid || (targets[0].arid != 7'h32)) begin
        $fatal(1, "aged JPEG request did not outrank a newer CPU request");
      end
      targets[0].arready = 1'b1;
      #1;
      if (!monitor_master_promotion_o[6]) begin
        $fatal(1, "JPEG aging promotion was not reported");
      end
      do @(posedge clk_i); while (!masters[6].arready);
      @(negedge clk_i);
      masters[6].arvalid = 1'b0;
      do @(posedge clk_i); while (!masters[0].arready);
      @(negedge clk_i);
      masters[0].arvalid = 1'b0;
      return_target0_read(7'h32, 64'h6666_6666_6666_0032);
      return_target0_read(7'h02, 64'h0000_0000_0000_0002);

      // One normal read and one normal write may overlap, but no second
      // transaction per direction can pass before the terminal response.
      @(negedge clk_i);
      targets[0].arready = 1'b0;
      targets[0].awready = 1'b0;
      masters[6].arid    = 7'h30;
      masters[6].araddr  = 32'h3000_0080;
      masters[6].arvalid = 1'b1;
      masters[6].awid    = 7'h31;
      masters[6].awaddr  = 32'h3000_00C0;
      masters[6].awvalid = 1'b1;
      #1;
      if (!targets[0].arvalid || (targets[0].arid != 7'h30) ||
          !targets[0].awvalid || (targets[0].awid != 7'h31)) begin
        $fatal(1, "JPEG did not present independent normal read and write addresses");
      end
      targets[0].arready = 1'b1;
      targets[0].awready = 1'b1;
      @(posedge clk_i);
      #1;
      if ((outstanding_read_o != 8'd1) || (outstanding_write_o != 8'd1)) begin
        $fatal(1, "JPEG did not consume exactly one read and one write credit");
      end
      @(negedge clk_i);
      masters[6].arvalid = 1'b0;
      masters[6].awvalid = 1'b0;
      masters[6].wdata   = 64'h0123_4567_89AB_CDEF;
      masters[6].wstrb   = 8'hFF;
      masters[6].wvalid  = 1'b1;
      do @(posedge clk_i); while (!masters[6].wready);
      @(negedge clk_i);
      masters[6].wvalid = 1'b0;

      @(negedge clk_i);
      masters[6].arid    = 7'h32;
      masters[6].araddr  = 32'h3000_0100;
      masters[6].arvalid = 1'b1;
      masters[6].awid    = 7'h33;
      masters[6].awaddr  = 32'h3000_0140;
      masters[6].awvalid = 1'b1;
      #1;
      if (masters[6].arready || masters[6].awready) begin
        $fatal(1, "JPEG exceeded its one-read plus one-write credit");
      end
      masters[6].arvalid = 1'b0;
      masters[6].awvalid = 1'b0;
      fork
        return_target0_read(7'h30, 64'h6666_6666_6666_0030);
        begin
          wait (masters[6].rvalid);
          if ((masters[6].rid != 7'h30) || (masters[6].rdata != 64'h6666_6666_6666_0030)) begin
            $fatal(1, "JPEG read response did not return to master 6");
          end
        end
      join
      fork
        return_target0_write(7'h31);
        begin
          wait (masters[6].bvalid);
          if (masters[6].bid != 7'h31) begin
            $fatal(1, "JPEG write response did not return to master 6");
          end
        end
      join
      @(negedge clk_i);
      if (!idle_o || (outstanding_read_o != 8'd0) || (outstanding_write_o != 8'd0)) begin
        $fatal(1, "JPEG master credits did not drain independently");
      end

      @(negedge clk_i);
      masters[6].arid    = 7'h32;
      masters[6].araddr  = 32'h3000_0100;
      masters[6].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[6].arready);
      @(negedge clk_i);
      masters[6].arvalid = 1'b0;
      fork
        return_target0_read(7'h32, 64'h6666_6666_6666_0032);
        begin
          wait (masters[6].rvalid);
          if (masters[6].rid != 7'h32) begin
            $fatal(1, "JPEG did not recover read admission after terminal response");
          end
        end
      join

      // Enabling normal credit must not weaken JPEG's non-cacheable ACL.
      @(negedge clk_i);
      masters[6].arid    = 7'h30;
      masters[6].araddr  = 32'h3000_0180;
      masters[6].arcache = 4'b0011;
      masters[6].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[6].arready);
      #1;
      if (!fault_valid_o || (fault_master_o != 4'd6) || (fault_reason_o != 4'd3)) begin
        $fatal(1, "JPEG cache-attribute ACL fault attribution mismatch");
      end
      @(negedge clk_i);
      masters[6].arvalid = 1'b0;
      masters[6].arcache = '0;
      return_target5_read(7'h30);
    end

    fault_backpressure : begin
      @(negedge clk_i);
      fault_ready_i      = 1'b0;
      masters[2].arid    = 6'b010_110;
      masters[2].araddr  = 32'h3000_0060;
      masters[2].arcache = 4'b0011;
      masters[2].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[2].arready);
      #1;
      if (!fault_valid_o || (fault_master_o != 4'd2) ||
          (fault_addr_o != 32'h3000_0060) || (fault_reason_o != 4'd3)) begin
        $fatal(1, "first backpressured fault was not retained");
      end
      @(negedge clk_i);
      masters[2].arvalid = 1'b0;
      masters[2].arcache = '0;
      masters[1].arid    = 6'b001_110;
      masters[1].araddr  = 32'h3000_00A0;
      masters[1].arprot  = 3'b100;
      masters[1].arvalid = 1'b1;
      #1;
      if (masters[1].arready) begin
        $fatal(1, "second faulting request bypassed a full fault slot");
      end
      repeat (2) begin
        @(posedge clk_i);
        #1;
        if (!fault_valid_o || (fault_master_o != 4'd2) ||
            (fault_addr_o != 32'h3000_0060) || (fault_reason_o != 4'd3) ||
            masters[1].arready) begin
          $fatal(1, "backpressured fault payload or admission was not held");
        end
      end
      return_target5_read(6'b010_110);
      @(negedge clk_i);
      fault_ready_i = 1'b1;
      do @(posedge clk_i); while (!masters[1].arready);
      #1;
      if (!fault_valid_o || (fault_master_o != 4'd1) ||
          (fault_addr_o != 32'h3000_00A0) || (fault_reason_o != 4'd3)) begin
        $fatal(1, "second backpressured fault was not delivered after release");
      end
      @(negedge clk_i);
      masters[1].arvalid = 1'b0;
      masters[1].arprot  = '0;
      return_target5_read(6'b001_110);
      @(posedge clk_i);
    end

    @(negedge clk_i);
    masters[2].arid    = 6'b010_001;
    masters[2].araddr  = 32'h3000_0000;
    masters[2].arcache = 4'b0011;
    masters[2].arvalid = 1'b1;
    do @(posedge clk_i); while (!masters[2].arready);
    #1;
    if (!fault_valid_o || (fault_master_o != 3'd2) || (fault_reason_o != 4'd3)) begin
      $fatal(1, "cache-attribute ACL fault attribution mismatch");
    end
    @(negedge clk_i);
    masters[2].arvalid = 1'b0;
    masters[2].arcache = 4'd0;
    return_target5_read(6'b010_001);

    @(negedge clk_i);
    masters[1].arid    = 6'b001_100;
    masters[1].araddr  = 32'h3000_0000;
    masters[1].arprot  = 3'b100;
    masters[1].arvalid = 1'b1;
    do @(posedge clk_i); while (!masters[1].arready);
    #1;
    if (!fault_valid_o || (fault_master_o != 3'd1) || (fault_reason_o != 4'd3)) begin
      $fatal(1, "instruction ACL fault attribution mismatch");
    end
    @(negedge clk_i);
    masters[1].arvalid = 1'b0;
    masters[1].arprot  = 3'd0;
    return_target5_read(6'b001_100);

    @(negedge clk_i);
    masters[1].awid    = 6'b001_101;
    masters[1].awaddr  = 32'h5000_0000;
    masters[1].awvalid = 1'b1;
    do @(posedge clk_i); while (!masters[1].awready);
    #1;
    if (!fault_valid_o || (fault_master_o != 3'd1) || (fault_reason_o != 4'd3) ||
        !fault_write_o) begin
      $fatal(1, "write-target ACL fault attribution mismatch");
    end
    @(negedge clk_i);
    masters[1].awvalid = 1'b0;
    masters[1].wdata   = 64'hA5A5_5A5A_1122_3344;
    masters[1].wstrb   = 8'hFF;
    masters[1].wvalid  = 1'b1;
    do @(posedge clk_i); while (!masters[1].wready);
    @(negedge clk_i);
    masters[1].wvalid = 1'b0;
    targets[5].bid    = 6'b001_101;
    targets[5].bresp  = 2'b10;
    targets[5].bvalid = 1'b1;
    do @(posedge clk_i); while (!targets[5].bready);
    @(negedge clk_i);
    targets[5].bvalid = 1'b0;

    target0_recovery_priority : begin
      @(negedge clk_i);
      recovery_i         = 1'b1;
      targets[0].arready = 1'b0;
      masters[0].arid    = 6'b000_100;
      masters[0].araddr  = 32'h3000_0100;
      masters[0].arvalid = 1'b1;
      masters[5].arid    = 6'b101_000;
      masters[5].araddr  = 32'h3000_0180;
      masters[5].arvalid = 1'b1;
      #1;
      if (!targets[0].arvalid || (targets[0].arid != 6'b101_000)) begin
        $fatal(1, "recovery master did not receive emergency priority");
      end
      targets[0].arready = 1'b1;
      do @(posedge clk_i); while (!masters[5].arready);
      @(negedge clk_i);
      masters[5].arvalid = 1'b0;
      do @(posedge clk_i); while (!masters[0].arready);
      @(negedge clk_i);
      masters[0].arvalid = 1'b0;
      recovery_i         = 1'b0;
      return_target0_read(6'b101_000, 64'h5555_5555_5555_5555);
      return_target0_read(6'b000_100, 64'h0000_0000_0000_0100);
    end

    target0_starvation_bound : begin
      @(negedge clk_i);
      targets[0].arready = 1'b0;
      masters[5].arid    = 6'b101_001;
      masters[5].araddr  = 32'h3000_0200;
      masters[5].arvalid = 1'b1;
      repeat (4) @(posedge clk_i);
      @(negedge clk_i);
      masters[0].arid    = 6'b000_101;
      masters[0].araddr  = 32'h3000_0280;
      masters[0].arvalid = 1'b1;
      #1;
      if (!targets[0].arvalid || (targets[0].arid != 6'b101_001)) begin
        $fatal(1, "aged LP request did not override a newer latency request");
      end
      targets[0].arready = 1'b1;
      #1;
      if (!monitor_master_promotion_o[5]) begin
        $fatal(1, "aged LP service was not reported as a promotion");
      end
      do @(posedge clk_i); while (!masters[5].arready);
      @(negedge clk_i);
      masters[5].arvalid = 1'b0;
      do @(posedge clk_i); while (!masters[0].arready);
      @(negedge clk_i);
      masters[0].arvalid = 1'b0;
      return_target0_read(6'b101_001, 64'h5555_5555_0000_0200);
      return_target0_read(6'b000_101, 64'h0000_0000_0000_0280);
    end

    invalid_return_prefix_recovery : begin
      for (int prefix = 10; prefix < 16; prefix++) begin
        return_invalid_target0_response(4'(prefix), prefix[0]);

        if (prefix == 10) begin
          masters[8].arid    = 7'h42;
          masters[8].araddr  = 32'h3000_0140;
          masters[8].arvalid = 1'b1;
          #1;
          if (masters[8].arready || idle_o) begin
            $fatal(1, "protocol recovery accepted a new request before flush");
          end
          masters[8].arvalid = 1'b0;
        end

        flush_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        flush_i = 1'b0;
      end

      masters[8].arid    = 7'h42;
      masters[8].araddr  = 32'h3000_0140;
      masters[8].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[8].arready);
      @(negedge clk_i);
      masters[8].arvalid = 1'b0;
      fork
        return_target0_read(7'h42, 64'h8888_8888_8888_0042);
        begin
          wait (masters[8].rvalid);
          if ((masters[8].rid != 7'h42) || (masters[8].rdata != 64'h8888_8888_8888_0042)) begin
            $fatal(1, "crossbar did not recover after protocol flush");
          end
        end
      join
    end

    @(negedge clk_i);
    if (!idle_o || (outstanding_read_o != 8'd0) || (outstanding_write_o != 8'd0)) begin
      $fatal(1, "ACL and QoS transactions did not drain the crossbar");
    end

    $display("AXI4 data crossbar concurrency, ACL, and QoS test passed");
    $finish;
  end

  `undef INIT_MASTER
  `undef INIT_TARGET
endmodule
