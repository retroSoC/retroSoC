// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module extension_slot #(
    parameter int unsigned SlotId             = 0,
    parameter bit          KindExtH           = 1'b0,
    parameter int unsigned IrqCount           = 1,
    parameter int unsigned ResetTimeoutCycles = 1024
) (
    input  logic         clk_i,
    input  logic         rst_n_i,
           apb4_if.slave cfg_apb4,
    output logic         irq_o,
    output logic         idle_o,
    output logic         quiesce_o,
    output logic         reset_o
);
  localparam logic [11:0] Identification = 12'h000;
  localparam logic [11:0] Version = 12'h004;
  localparam logic [11:0] Capability = 12'h008;
  localparam logic [11:0] Owner = 12'h00C;
  localparam logic [11:0] Command = 12'h010;
  localparam logic [11:0] Status = 12'h014;
  localparam logic [11:0] ReadBase = 12'h018;
  localparam logic [11:0] ReadLimit = 12'h01C;
  localparam logic [11:0] WriteBase = 12'h020;
  localparam logic [11:0] WriteLimit = 12'h024;
  localparam logic [11:0] Timeout = 12'h028;
  localparam logic [11:0] Fault = 12'h02C;
  localparam logic [11:0] FaultAddress = 12'h030;
  localparam logic [11:0] RequestCount = 12'h034;

  localparam logic [31:0] Identifier = KindExtH ? 32'h4558_5448 : 32'h4558_544C;
  localparam logic [31:0] Capabilities = {
    16'd0, 8'(IrqCount), 4'd0, KindExtH, KindExtH, KindExtH, 1'b1
  };

  logic        s_apb4_ready_d;
  logic        s_apb4_ready_q;
  logic        s_apb4_resp_err_d;
  logic        s_apb4_resp_err_q;
  logic [31:0] s_apb4_rdata_d;
  logic [31:0] s_apb4_rdata_q;
  logic [ 1:0] s_owner_d;
  logic [ 1:0] s_owner_q;
  logic        s_owner_lock_d;
  logic        s_owner_lock_q;
  logic        s_quiesce_d;
  logic        s_quiesce_q;
  logic        s_reset_d;
  logic        s_reset_q;
  logic [31:0] s_read_base_d;
  logic [31:0] s_read_base_q;
  logic [31:0] s_read_limit_d;
  logic [31:0] s_read_limit_q;
  logic [31:0] s_write_base_d;
  logic [31:0] s_write_base_q;
  logic [31:0] s_write_limit_d;
  logic [31:0] s_write_limit_q;
  logic [31:0] s_timeout_d;
  logic [31:0] s_timeout_q;
  logic        s_fault_sticky_d;
  logic        s_fault_sticky_q;
  logic [31:0] s_fault_addr_d;
  logic [31:0] s_fault_addr_q;
  logic [31:0] s_req_count_d;
  logic [31:0] s_req_count_q;
  logic        s_req_accept;
  logic        s_write;
  logic        s_cfg_write_legal;

  assign s_req_accept     = cfg_apb4.psel && cfg_apb4.penable && !s_apb4_ready_q;
  assign s_write          = s_req_accept && (|cfg_apb4.pstrb);
  assign idle_o           = 1'b1;
  assign quiesce_o        = s_quiesce_q;
  assign reset_o          = s_reset_q;
  assign irq_o            = s_fault_sticky_q;
  assign cfg_apb4.pready  = s_apb4_ready_q;
  assign cfg_apb4.prdata  = s_apb4_rdata_q;
  assign cfg_apb4.pslverr = s_apb4_resp_err_q;

  always_comb begin
    s_owner_d         = s_owner_q;
    s_owner_lock_d    = s_owner_lock_q;
    s_quiesce_d       = s_quiesce_q;
    s_reset_d         = s_reset_q;
    s_read_base_d     = s_read_base_q;
    s_read_limit_d    = s_read_limit_q;
    s_write_base_d    = s_write_base_q;
    s_write_limit_d   = s_write_limit_q;
    s_timeout_d       = s_timeout_q;
    s_fault_sticky_d  = s_fault_sticky_q;
    s_fault_addr_d    = s_fault_addr_q;
    s_req_count_d     = s_req_count_q;
    s_cfg_write_legal = 1'b0;
    if (s_req_accept && !(&s_req_count_q)) begin
      s_req_count_d = s_req_count_q + 1'b1;
    end
    if (s_write) begin
      unique case (cfg_apb4.paddr[11:0])
        Owner: begin
          s_cfg_write_legal = !s_owner_lock_q && (cfg_apb4.pwdata[1:0] <= 2'd1);
          if (s_cfg_write_legal) begin
            s_owner_d      = cfg_apb4.pwdata[1:0];
            s_owner_lock_d = cfg_apb4.pwdata[8];
          end
        end
        Command: begin
          s_cfg_write_legal = (cfg_apb4.pwdata & 32'hFFFF_FFF8) == 32'd0;
          if (s_cfg_write_legal) begin
            s_quiesce_d = cfg_apb4.pwdata[0];
            s_reset_d   = cfg_apb4.pwdata[1];
            if (cfg_apb4.pwdata[2]) begin
              s_fault_sticky_d = 1'b0;
            end
          end
        end
        ReadBase: begin
          s_cfg_write_legal = KindExtH;
          s_read_base_d     = cfg_apb4.pwdata;
        end
        ReadLimit: begin
          s_cfg_write_legal = KindExtH && (cfg_apb4.pwdata >= s_read_base_q);
          if (s_cfg_write_legal) s_read_limit_d = cfg_apb4.pwdata;
        end
        WriteBase: begin
          s_cfg_write_legal = KindExtH;
          s_write_base_d    = cfg_apb4.pwdata;
        end
        WriteLimit: begin
          s_cfg_write_legal = KindExtH && (cfg_apb4.pwdata >= s_write_base_q);
          if (s_cfg_write_legal) s_write_limit_d = cfg_apb4.pwdata;
        end
        Timeout: begin
          s_cfg_write_legal = KindExtH && (cfg_apb4.pwdata != 32'd0);
          if (s_cfg_write_legal) s_timeout_d = cfg_apb4.pwdata;
        end
        default: s_cfg_write_legal = 1'b0;
      endcase
      if (!s_cfg_write_legal) begin
        s_fault_sticky_d = 1'b1;
        s_fault_addr_d   = cfg_apb4.paddr;
      end
    end
  end

  always_comb begin
    s_apb4_rdata_d = '0;
    unique case (cfg_apb4.paddr[11:0])
      Identification: s_apb4_rdata_d = Identifier;
      Version: s_apb4_rdata_d = 32'h0001_0000;
      Capability: s_apb4_rdata_d = Capabilities;
      Owner: s_apb4_rdata_d = {23'd0, s_owner_lock_q, 6'd0, s_owner_q};
      Command: s_apb4_rdata_d = {30'd0, s_reset_q, s_quiesce_q};
      Status: s_apb4_rdata_d = {27'd0, s_fault_sticky_q, s_reset_q, s_quiesce_q, idle_o, 1'b1};
      ReadBase: s_apb4_rdata_d = s_read_base_q;
      ReadLimit: s_apb4_rdata_d = s_read_limit_q;
      WriteBase: s_apb4_rdata_d = s_write_base_q;
      WriteLimit: s_apb4_rdata_d = s_write_limit_q;
      Timeout: s_apb4_rdata_d = s_timeout_q;
      Fault: s_apb4_rdata_d = {31'd0, s_fault_sticky_q};
      FaultAddress: s_apb4_rdata_d = s_fault_addr_q;
      RequestCount: s_apb4_rdata_d = s_req_count_q;
      default: s_apb4_rdata_d = '0;
    endcase
  end

  assign s_apb4_ready_d    = s_req_accept;
  assign s_apb4_resp_err_d = s_write && !s_cfg_write_legal;

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept && !s_write),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_owner_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_owner_d),
      .dat_o  (s_owner_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_owner_lock_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_owner_lock_d),
      .dat_o  (s_owner_lock_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_quiesce_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_quiesce_d),
      .dat_o  (s_quiesce_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_reset_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reset_d),
      .dat_o  (s_reset_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_base_d),
      .dat_o  (s_read_base_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_limit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_limit_d),
      .dat_o  (s_read_limit_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_base_d),
      .dat_o  (s_write_base_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_limit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_limit_d),
      .dat_o  (s_write_limit_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (ResetTimeoutCycles)
  ) u_timeout_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_sticky_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_sticky_d),
      .dat_o  (s_fault_sticky_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_addr_d),
      .dat_o  (s_fault_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_req_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_req_count_d),
      .dat_o  (s_req_count_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((IrqCount < 1) || (IrqCount > 4) || (SlotId > 255)) begin
      $fatal(1, "extension_slot: invalid slot or IRQ count");
    end
  end
`endif
endmodule
