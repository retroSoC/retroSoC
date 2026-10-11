module tiny_r2_p5_fabric_formal (
    input logic clk_i,
    rst_n_i
);
`ifdef TINY_P5_RESET_FORMAL
  localparam bit TargetReset = 1'b1;
`else
  localparam bit TargetReset = 1'b0;
`endif
  logic started = 0;
  (* anyseq *) logic [2:0] arvalid, awvalid, wvalid, rready, bready;
  (* anyseq *)logic [2:0][1:0] length;
  (* anyseq *)logic            target_reset_n;
  wire             target_enable = !TargetReset || target_reset_n;
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) masters[3] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) target (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  logic idle, fault, fault_write, fault_instruction;
  logic [31:0] fault_addr;
  logic [1:0] fault_owner, fault_resp;
  always_ff @(posedge clk_i) begin
    started <= 1;
    assume (rst_n_i == started);
  end
  tiny_axi4_target u_target (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .enable_i           (target_enable),
      .masters            (masters),
      .target             (target),
      .idle_o             (idle),
      .fault_valid_o      (fault),
      .fault_addr_o       (fault_addr),
      .fault_master_o     (fault_owner),
      .fault_write_o      (fault_write),
      .fault_instruction_o(fault_instruction),
      .fault_resp_o       (fault_resp)
  );
  axi4_error_slave #(
      .Response(2'b10)
  ) u_endpoint (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i && target_enable),
      .axi4   (target)
  );
  for (genvar m = 0; m < 3; m++) begin : gen_master
    logic outstanding = 0;
    logic [2:0] remaining = 0;
    logic write_data_pending = 0;
    wire accept=(masters[m].arvalid && masters[m].arready)||(masters[m].awvalid && masters[m].awready);
    wire done=(masters[m].rvalid && masters[m].rready && masters[m].rlast)||
              (masters[m].bvalid && masters[m].bready);
    assign masters[m].araddr   = 32'h30000000 + 32'(m) * 32'h100;
    assign masters[m].awaddr   = 32'h30000000 + 32'(m) * 32'h100;
    assign masters[m].arlen    = {6'd0, length[m]};
    assign masters[m].awlen    = 0;
    assign masters[m].arsize   = 2;
    assign masters[m].awsize   = 2;
    assign masters[m].arburst  = 1;
    assign masters[m].awburst  = 1;
    assign masters[m].arlock   = 0;
    assign masters[m].awlock   = 0;
    assign masters[m].arid     = 1'(m);
    assign masters[m].awid     = 1'(m);
    assign masters[m].arcache  = 0;
    assign masters[m].awcache  = 0;
    assign masters[m].arprot   = 0;
    assign masters[m].awprot   = 0;
    assign masters[m].arqos    = 0;
    assign masters[m].awqos    = 0;
    assign masters[m].arregion = 0;
    assign masters[m].awregion = 0;
    assign masters[m].aruser   = 0;
    assign masters[m].awuser   = 0;
    assign masters[m].arvalid  = arvalid[m] && !outstanding;
    assign masters[m].awvalid  = awvalid[m] && !outstanding;
    assign masters[m].wvalid   = wvalid[m];
    assign masters[m].wlast    = 1;
    assign masters[m].wdata    = 32'(m);
    assign masters[m].wstrb    = 15;
    assign masters[m].wuser    = 0;
    assign masters[m].rready   = rready[m];
    assign masters[m].bready   = bready[m];
    always_ff @(posedge clk_i) begin
      if (!rst_n_i) begin
        outstanding        <= 0;
        remaining          <= 0;
        write_data_pending <= 0;
      end else begin
        if (masters[m].arvalid && masters[m].arready) remaining <= {1'b0, length[m]} + 3'd1;
        if (masters[m].rvalid) begin
          assert (remaining != 0);
          assert (masters[m].rlast == (remaining == 1));
          if (masters[m].rready) remaining <= remaining - 3'd1;
        end
        if (masters[m].awvalid && masters[m].awready) write_data_pending <= 1;
        if (masters[m].wvalid && masters[m].wready) write_data_pending <= 0;
        if (masters[m].bvalid) assert (!write_data_pending);
        if (accept) outstanding <= 1;
        if (done) outstanding <= 0;
        assert (!(accept && outstanding));
        assert (!done || outstanding);
        assert (!(masters[m].arready && masters[m].awready));
        if (done) begin
          assert (fault && fault_owner == 2'(m));
          if (TargetReset)
            assert (fault_resp == 2 || fault_resp == 3);
            else assert (fault_resp == 2);
          assert (fault_addr == 32'h30000000 + 32'(m) * 32'h100);
        end
      end
    end
  end
endmodule
