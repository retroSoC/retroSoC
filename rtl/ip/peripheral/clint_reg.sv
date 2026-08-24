// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "clint_define.svh"

module clint_reg #(
    parameter int HartNum = 1
) (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic               clk_i,
    input  logic               rst_n_i,
    apb4_if.slave              apb4,
    input  logic [63:0]        mtime_i,
    output logic               mtime_load_o,
    output logic [63:0]        mtime_load_value_o,
    output logic [HartNum-1:0] msip_o,
    output logic [63:0]        mtimecmp_o [0:HartNum-1]
    // verilog_format: on
);

  localparam int HART_INDEX_WIDTH = HartNum > 1 ? $clog2(HartNum) : 1;
  localparam logic [11:0] HART_COUNT = 12'(HartNum);

  logic        s_req;
  logic        s_write;
  logic        s_req_accept;
  logic [15:0] s_offset;
  logic        s_aligned;
  logic        s_access_err;
  logic        s_msip_sel;
  logic        s_mtimecmp_sel;
  logic        s_mtimecmp_high;
  logic        s_mtime_sel;
  logic        s_mtime_high;
  logic [11:0] s_msip_hart;
  logic [11:0] s_mtimecmp_hart;

  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;

  logic [HartNum-1:0] s_msip_en;
  logic [HartNum-1:0] s_msip_d, s_msip_q;
  logic [HartNum-1:0] s_mtimecmp_en;
  logic [       63:0] s_mtimecmp_d  [0:HartNum-1];
  logic [       63:0] s_mtimecmp_q  [0:HartNum-1];

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic   [31:0] merged;
    integer        byte_index;
    begin
      merged = current;
      for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
        if (strobe[byte_index]) begin
          merged[byte_index*8+:8] = value[byte_index*8+:8];
        end
      end
      return merged;
    end
  endfunction

`ifndef SYNTHESIS
  initial begin
    if ((HartNum < 1) || (HartNum > 4095)) begin
      $fatal(1, "clint_reg: HartNum must be between 1 and 4095");
    end
  end
`endif

  assign s_req = apb4.psel && apb4.penable && !s_apb4_ready_q;
  assign s_write = apb4.pwrite;
  assign s_req_accept = s_req;
  assign s_offset = apb4.paddr[15:0];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;

  assign s_msip_hart = s_offset[13:2];
  assign s_mtimecmp_hart = s_offset[14:3] - 12'h800;
  assign s_msip_sel = (s_offset < `APB4_CLINT_MTIMECMP) && (s_msip_hart < HART_COUNT);
  assign s_mtimecmp_sel = (s_offset >= `APB4_CLINT_MTIMECMP) &&
                             (s_offset < `APB4_CLINT_MTIME) &&
                             (s_mtimecmp_hart < HART_COUNT);
  assign s_mtimecmp_high = s_offset[2];
  assign s_mtime_sel = (s_offset == `APB4_CLINT_MTIME) || (s_offset == `APB4_CLINT_MTIMEH);
  assign s_mtime_high = s_offset == `APB4_CLINT_MTIMEH;

  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;

  always_comb begin
    s_access_err   = !s_aligned || !(s_msip_sel || s_mtimecmp_sel || s_mtime_sel);
    s_apb4_rdata_d = '0;
    if (s_aligned) begin
      if (s_msip_sel) begin
        s_apb4_rdata_d = {31'd0, s_msip_q[s_msip_hart[HART_INDEX_WIDTH-1:0]]};
      end else if (s_mtimecmp_sel) begin
        if (s_mtimecmp_high) begin
          s_apb4_rdata_d = s_mtimecmp_q[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]][63:32];
        end else begin
          s_apb4_rdata_d = s_mtimecmp_q[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]][31:0];
        end
      end else if (s_mtime_sel) begin
        s_apb4_rdata_d = s_mtime_high ? mtime_i[63:32] : mtime_i[31:0];
      end
    end
  end

  always_comb begin
    s_msip_en = '0;
    s_msip_d  = s_msip_q;
    if (s_req_accept && s_write && !s_access_err && s_msip_sel && apb4.pstrb[0]) begin
      s_msip_en[s_msip_hart[HART_INDEX_WIDTH-1:0]] = 1'b1;
      s_msip_d[s_msip_hart[HART_INDEX_WIDTH-1:0]]  = apb4.pwdata[0];
    end
  end
  for (genvar hart = 0; hart < HartNum; hart++) begin : gen_msip
    dffer #(
        .DATA_WIDTH(1)
    ) u_msip_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_msip_en[hart]),
        .dat_i  (s_msip_d[hart]),
        .dat_o  (s_msip_q[hart])
    );
  end

  always_comb begin
    s_mtimecmp_en = '0;
    for (int hart = 0; hart < HartNum; hart++) begin
      s_mtimecmp_d[hart] = s_mtimecmp_q[hart];
    end
    if (s_req_accept && s_write && !s_access_err && s_mtimecmp_sel) begin
      s_mtimecmp_en[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]] = 1'b1;
      if (s_mtimecmp_high) begin
        s_mtimecmp_d[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]][63:32] = merge_wstrb(
            s_mtimecmp_q[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]][63:32], apb4.pwdata, apb4.pstrb);
      end else begin
        s_mtimecmp_d[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]][31:0] = merge_wstrb(
            s_mtimecmp_q[s_mtimecmp_hart[HART_INDEX_WIDTH-1:0]][31:0], apb4.pwdata, apb4.pstrb);
      end
    end
  end
  for (genvar hart = 0; hart < HartNum; hart++) begin : gen_mtimecmp
    dfferh #(
        .DATA_WIDTH(64)
    ) u_mtimecmp_dfferh (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_mtimecmp_en[hart]),
        .dat_i  (s_mtimecmp_d[hart]),
        .dat_o  (s_mtimecmp_q[hart])
    );
  end

  always_comb begin
    mtime_load_o       = 1'b0;
    mtime_load_value_o = mtime_i;
    if (s_req_accept && s_write && !s_access_err && s_mtime_sel) begin
      mtime_load_o = 1'b1;
      if (s_mtime_high) begin
        mtime_load_value_o[63:32] = merge_wstrb(mtime_i[63:32], apb4.pwdata, apb4.pstrb);
      end else begin
        mtime_load_value_o[31:0] = merge_wstrb(mtime_i[31:0], apb4.pwdata, apb4.pstrb);
      end
    end
  end

  assign msip_o            = s_msip_q;
  assign mtimecmp_o        = s_mtimecmp_q;

  assign s_apb4_ready_d    = s_req_accept;
  assign s_apb4_resp_err_d = s_access_err;

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );

endmodule
