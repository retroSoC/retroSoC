// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "rib_defs.svh"

module rib_bus (
    // verilog_format: off
    input logic              clk_i,
    input logic              rst_n_i,
`ifdef HAVE_SRAM_IF
    ram_if.master            ram,
`endif
    ribp_if.slave          mgmt_ribp,
    rib_if.slave           user_rib,
    rib_if.slave           dma_rib,
    input logic              user_bus_enable_i,
    output logic             user_bus_idle_o,
    rib_if.master          rib,
    rib_if.master          apb_rib,
    input logic              perf_enable_i,
    input logic              perf_clear_i,
    output logic             fault_valid_o,
    output logic [31:0]      fault_addr_o,
    output logic [3:0]       fault_wstrb_o,
    output logic             fault_reserved_o,
    output logic             fault_access_o,
    output logic [1:0]       fault_master_o,
    output logic [2:0]       fault_code_o,
    output logic [63:0]      perf_mgmt_wait_o,
    output logic [63:0]      perf_user_wait_o,
    output logic [63:0]      perf_dma_wait_o,
    output logic [63:0]      perf_ribp_wait_o,
    output logic [63:0]      perf_apb_wait_o,
    output logic [63:0]      perf_sdram_wait_o,
    output logic [63:0]      perf_psram_wait_o,
    output logic [63:0]      perf_flash_wait_o
    // verilog_format: on
);

  localparam logic [1:0] MSTR_MGMT = 2'd0;
  localparam logic [1:0] MSTR_USER = 2'd1;
  localparam logic [1:0] MSTR_DMA = 2'd2;

  localparam logic [1:0] TARGET_RIBP = 2'd0;
  localparam logic [1:0] TARGET_APB = 2'd1;
  localparam logic [1:0] TARGET_RAM = 2'd2;
  localparam logic [1:0] TARGET_FAULT = 2'd3;

  rib_if u_mgmt_rib_if ();
  rib_if u_mstr_rib_if ();
  rib_if u_ram_rib_if ();
  rib_if u_fault_rib_if ();

  logic s_mstr_lock_d, s_mstr_lock_q;
  logic s_cmd_accepted_d, s_cmd_accepted_q;
  logic [1:0] s_mstr_id_d, s_mstr_id_q;
  logic [1:0] s_mstr_rr_d, s_mstr_rr_q;
  logic [1:0] s_target_d, s_target_q;
  logic s_user_req;
  logic s_terminal_rsp;
  logic s_ribp_sel, s_apb_sel, s_ram_sel, s_fault_sel;
  logic s_access_denied, s_burst_legal, s_len_legal;
  logic        s_user_access_allowed;
  logic [31:0] s_last_addr;
  logic [ 2:0] s_fault_code;
  logic [31:0] s_xfer_addr_q;
  logic [31:0] s_fault_addr_q;
  logic [3:0] s_fault_wstrb_d, s_fault_wstrb_q;
  logic [1:0] s_fault_master_q;
  logic [2:0] s_fault_code_q;
  logic       s_fault_cmd_hdshk;
  logic       s_fault_w_hdshk;
  logic       s_xfer_stalled;

  logic [63:0] s_perf_mgmt_wait_d, s_perf_mgmt_wait_q;
  logic [63:0] s_perf_user_wait_d, s_perf_user_wait_q;
  logic [63:0] s_perf_dma_wait_d, s_perf_dma_wait_q;
  logic [63:0] s_perf_ribp_wait_d, s_perf_ribp_wait_q;
  logic [63:0] s_perf_apb_wait_d, s_perf_apb_wait_q;
  logic [63:0] s_perf_sdram_wait_d, s_perf_sdram_wait_q;
  logic [63:0] s_perf_psram_wait_d, s_perf_psram_wait_q;
  logic [63:0] s_perf_flash_wait_d, s_perf_flash_wait_q;

  ribp2rib u_mgmt_ribp2rib (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (mgmt_ribp),
      .rib    (u_mgmt_rib_if)
  );

  rib_error_slave u_fault_slave (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .error_code_i(s_fault_code),
      .rib         (u_fault_rib_if)
  );

`ifdef HAVE_SRAM_IF
  rib2ram u_rib2ram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rib    (u_ram_rib_if),
      .ram    (ram)
  );
`else
  assign u_ram_rib_if.cmd_ready = 1'b0;
  assign u_ram_rib_if.w_ready   = 1'b0;
  assign u_ram_rib_if.rsp_valid = 1'b0;
  assign u_ram_rib_if.rdata     = '0;
  assign u_ram_rib_if.resp_err  = 1'b0;
  assign u_ram_rib_if.resp_code = `RIB_RESP_OK;
  assign u_ram_rib_if.rsp_beat  = '0;
  assign u_ram_rib_if.rsp_last  = 1'b0;
`endif

  assign s_user_req = user_bus_enable_i && user_rib.cmd_valid;
  assign user_bus_idle_o = ~s_mstr_lock_q || (s_mstr_id_q != MSTR_USER);
  assign s_terminal_rsp  = s_cmd_accepted_q && u_mstr_rib_if.rsp_valid &&
                           u_mstr_rib_if.rsp_ready &&
                           u_mstr_rib_if.rsp_last;

  always_comb begin
    s_mstr_lock_d = s_mstr_lock_q;
    s_mstr_id_d   = s_mstr_id_q;
    s_mstr_rr_d   = s_mstr_rr_q;
    if (~s_mstr_lock_q) begin
      unique case (s_mstr_rr_q)
        MSTR_MGMT: begin
          if (u_mgmt_rib_if.cmd_valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_MGMT;
          end else if (s_user_req) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_USER;
          end else if (dma_rib.cmd_valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_DMA;
          end
        end
        MSTR_USER: begin
          if (s_user_req) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_USER;
          end else if (dma_rib.cmd_valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_DMA;
          end else if (u_mgmt_rib_if.cmd_valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_MGMT;
          end
        end
        default: begin
          if (dma_rib.cmd_valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_DMA;
          end else if (u_mgmt_rib_if.cmd_valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_MGMT;
          end else if (s_user_req) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_USER;
          end
        end
      endcase
    end else if (s_terminal_rsp) begin
      s_mstr_lock_d = 1'b0;
      unique case (s_mstr_id_q)
        MSTR_MGMT: s_mstr_rr_d = MSTR_USER;
        MSTR_USER: s_mstr_rr_d = MSTR_DMA;
        default:   s_mstr_rr_d = MSTR_MGMT;
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_mstr_lock_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mstr_lock_d),
      .dat_o  (s_mstr_lock_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_mstr_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mstr_id_d),
      .dat_o  (s_mstr_id_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_mstr_rr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mstr_rr_d),
      .dat_o  (s_mstr_rr_q)
  );

  always_comb begin
    s_cmd_accepted_d = s_cmd_accepted_q;
    if (u_mstr_rib_if.cmd_valid && u_mstr_rib_if.cmd_ready) begin
      s_cmd_accepted_d = 1'b1;
    end else if (s_terminal_rsp) begin
      s_cmd_accepted_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_cmd_accepted_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_accepted_d),
      .dat_o  (s_cmd_accepted_q)
  );

  // Master mux. The grant is held until the terminal response is consumed.
  always_comb begin
    u_mstr_rib_if.cmd_valid = 1'b0;
    u_mstr_rib_if.cmd_addr  = '0;
    u_mstr_rib_if.cmd_write = 1'b0;
    u_mstr_rib_if.cmd_len   = `RIB_LEN_INCR1;
    u_mstr_rib_if.w_valid   = 1'b0;
    u_mstr_rib_if.wdata     = '0;
    u_mstr_rib_if.wstrb     = '0;
    u_mstr_rib_if.wlast     = 1'b0;
    u_mstr_rib_if.rsp_ready = 1'b0;
    if (s_mstr_lock_q) begin
      unique case (s_mstr_id_q)
        MSTR_MGMT: begin
          u_mstr_rib_if.cmd_valid = u_mgmt_rib_if.cmd_valid;
          u_mstr_rib_if.cmd_addr  = u_mgmt_rib_if.cmd_addr;
          u_mstr_rib_if.cmd_write = u_mgmt_rib_if.cmd_write;
          u_mstr_rib_if.cmd_len   = u_mgmt_rib_if.cmd_len;
          u_mstr_rib_if.w_valid   = u_mgmt_rib_if.w_valid;
          u_mstr_rib_if.wdata     = u_mgmt_rib_if.wdata;
          u_mstr_rib_if.wstrb     = u_mgmt_rib_if.wstrb;
          u_mstr_rib_if.wlast     = u_mgmt_rib_if.wlast;
          u_mstr_rib_if.rsp_ready = u_mgmt_rib_if.rsp_ready;
        end
        MSTR_USER: begin
          u_mstr_rib_if.cmd_valid = user_rib.cmd_valid;
          u_mstr_rib_if.cmd_addr  = user_rib.cmd_addr;
          u_mstr_rib_if.cmd_write = user_rib.cmd_write;
          u_mstr_rib_if.cmd_len   = user_rib.cmd_len;
          u_mstr_rib_if.w_valid   = user_rib.w_valid;
          u_mstr_rib_if.wdata     = user_rib.wdata;
          u_mstr_rib_if.wstrb     = user_rib.wstrb;
          u_mstr_rib_if.wlast     = user_rib.wlast;
          u_mstr_rib_if.rsp_ready = user_rib.rsp_ready;
        end
        default: begin
          u_mstr_rib_if.cmd_valid = dma_rib.cmd_valid;
          u_mstr_rib_if.cmd_addr  = dma_rib.cmd_addr;
          u_mstr_rib_if.cmd_write = dma_rib.cmd_write;
          u_mstr_rib_if.cmd_len   = dma_rib.cmd_len;
          u_mstr_rib_if.w_valid   = dma_rib.w_valid;
          u_mstr_rib_if.wdata     = dma_rib.wdata;
          u_mstr_rib_if.wstrb     = dma_rib.wstrb;
          u_mstr_rib_if.wlast     = dma_rib.wlast;
          u_mstr_rib_if.rsp_ready = dma_rib.rsp_ready;
        end
      endcase
    end
  end

  // Responses are visible only to the granted master.
  assign u_mgmt_rib_if.cmd_ready = s_mstr_lock_q && (s_mstr_id_q == MSTR_MGMT) ?
                                     u_mstr_rib_if.cmd_ready : 1'b0;
  assign u_mgmt_rib_if.w_ready = s_mstr_lock_q && (s_mstr_id_q == MSTR_MGMT) ?
                                   u_mstr_rib_if.w_ready : 1'b0;
  assign u_mgmt_rib_if.rsp_valid = s_mstr_lock_q && (s_mstr_id_q == MSTR_MGMT) ?
                                     u_mstr_rib_if.rsp_valid : 1'b0;
  assign u_mgmt_rib_if.rdata = u_mstr_rib_if.rdata;
  assign u_mgmt_rib_if.resp_err = u_mstr_rib_if.resp_err;
  assign u_mgmt_rib_if.resp_code = u_mstr_rib_if.resp_code;
  assign u_mgmt_rib_if.rsp_beat = u_mstr_rib_if.rsp_beat;
  assign u_mgmt_rib_if.rsp_last = u_mstr_rib_if.rsp_last;

  assign user_rib.cmd_ready = s_mstr_lock_q && (s_mstr_id_q == MSTR_USER) ?
                              u_mstr_rib_if.cmd_ready : 1'b0;
  assign user_rib.w_ready = s_mstr_lock_q && (s_mstr_id_q == MSTR_USER) ?
                            u_mstr_rib_if.w_ready : 1'b0;
  assign user_rib.rsp_valid = s_mstr_lock_q && (s_mstr_id_q == MSTR_USER) ?
                              u_mstr_rib_if.rsp_valid : 1'b0;
  assign user_rib.rdata = u_mstr_rib_if.rdata;
  assign user_rib.resp_err = u_mstr_rib_if.resp_err;
  assign user_rib.resp_code = u_mstr_rib_if.resp_code;
  assign user_rib.rsp_beat = u_mstr_rib_if.rsp_beat;
  assign user_rib.rsp_last = u_mstr_rib_if.rsp_last;

  assign dma_rib.cmd_ready = s_mstr_lock_q && (s_mstr_id_q == MSTR_DMA) ?
                             u_mstr_rib_if.cmd_ready : 1'b0;
  assign dma_rib.w_ready = s_mstr_lock_q && (s_mstr_id_q == MSTR_DMA) ?
                           u_mstr_rib_if.w_ready : 1'b0;
  assign dma_rib.rsp_valid = s_mstr_lock_q && (s_mstr_id_q == MSTR_DMA) ?
                             u_mstr_rib_if.rsp_valid : 1'b0;
  assign dma_rib.rdata = u_mstr_rib_if.rdata;
  assign dma_rib.resp_err = u_mstr_rib_if.resp_err;
  assign dma_rib.resp_code = u_mstr_rib_if.resp_code;
  assign dma_rib.rsp_beat = u_mstr_rib_if.rsp_beat;
  assign dma_rib.rsp_last = u_mstr_rib_if.rsp_last;

  // verilog_format: off
  assign s_last_addr = u_mstr_rib_if.cmd_addr +
      (u_mstr_rib_if.cmd_len == `RIB_LEN_INCR4 ? 32'd12 : 32'd0);
  assign s_len_legal =
      (u_mstr_rib_if.cmd_len == `RIB_LEN_INCR1) ||
      (u_mstr_rib_if.cmd_len == `RIB_LEN_INCR4);
  assign s_burst_legal =
      s_len_legal &&
      ((u_mstr_rib_if.cmd_len == `RIB_LEN_INCR1) ||
       ((u_mstr_rib_if.cmd_addr[3:0] == 4'b0000) &&
        `SOC_ADDR_SUPPORTS_INCR4(u_mstr_rib_if.cmd_addr) &&
        `SOC_ADDR_SUPPORTS_INCR4(s_last_addr)));
  assign s_user_access_allowed = u_mstr_rib_if.cmd_write ?
      (`SOC_USER_ADDR_WRITABLE(u_mstr_rib_if.cmd_addr) &&
       `SOC_USER_ADDR_WRITABLE(s_last_addr)) :
      (`SOC_USER_ADDR_READABLE(u_mstr_rib_if.cmd_addr) &&
       `SOC_USER_ADDR_READABLE(s_last_addr));
  // verilog_format: on
  assign s_access_denied = (s_mstr_id_q == MSTR_USER) && ~s_user_access_allowed;

  // verilog_format: off
  assign s_ribp_sel = u_mstr_rib_if.cmd_valid && ~s_cmd_accepted_q && ~s_access_denied &&
                     s_burst_legal && `SOC_ADDR_IS_RIB_LEGACY_TARGET(u_mstr_rib_if.cmd_addr);
  assign s_apb_sel = u_mstr_rib_if.cmd_valid && ~s_cmd_accepted_q && ~s_access_denied &&
                     (u_mstr_rib_if.cmd_len == `RIB_LEN_INCR1) &&
                     `SOC_ADDR_IS_APB(u_mstr_rib_if.cmd_addr);
`ifdef HAVE_SRAM_IF
  assign s_ram_sel = u_mstr_rib_if.cmd_valid && ~s_cmd_accepted_q && ~s_access_denied &&
                     s_burst_legal && `SOC_ADDR_IS_RAM(u_mstr_rib_if.cmd_addr);
`else
  assign s_ram_sel = 1'b0;
`endif
  assign s_fault_sel = u_mstr_rib_if.cmd_valid && ~s_cmd_accepted_q &&
                       ~(s_ribp_sel || s_apb_sel || s_ram_sel);
  // verilog_format: on

  always_comb begin
    s_fault_code = `RIB_RESP_DECERR;
    if (s_access_denied) begin
      s_fault_code = `RIB_RESP_PROTERR;
    end else if (`SOC_ADDR_IS_RESERVED(u_mstr_rib_if.cmd_addr)) begin
      s_fault_code = `RIB_RESP_RESERVED;
      // verilog_format: off
    end else if ((`SOC_ADDR_IS_RIB_LEGACY_TARGET(u_mstr_rib_if.cmd_addr) ||
                  `SOC_ADDR_IS_APB(u_mstr_rib_if.cmd_addr) ||
                  `SOC_ADDR_IS_RAM(u_mstr_rib_if.cmd_addr)) &&
                 (~s_burst_legal ||
                  (`SOC_ADDR_IS_APB(u_mstr_rib_if.cmd_addr) &&
                   (u_mstr_rib_if.cmd_len != `RIB_LEN_INCR1)))) begin
      // verilog_format: on
      s_fault_code = `RIB_RESP_BURSTERR;
    end
  end

  // Command routing. Target selection is captured on command acceptance.
  assign rib.cmd_valid            = s_ribp_sel;
  assign rib.cmd_addr             = u_mstr_rib_if.cmd_addr;
  assign rib.cmd_write            = u_mstr_rib_if.cmd_write;
  assign rib.cmd_len              = u_mstr_rib_if.cmd_len;
  assign apb_rib.cmd_valid        = s_apb_sel;
  assign apb_rib.cmd_addr         = u_mstr_rib_if.cmd_addr;
  assign apb_rib.cmd_write        = u_mstr_rib_if.cmd_write;
  assign apb_rib.cmd_len          = u_mstr_rib_if.cmd_len;
  assign u_ram_rib_if.cmd_valid   = s_ram_sel;
  assign u_ram_rib_if.cmd_addr    = u_mstr_rib_if.cmd_addr;
  assign u_ram_rib_if.cmd_write   = u_mstr_rib_if.cmd_write;
  assign u_ram_rib_if.cmd_len     = u_mstr_rib_if.cmd_len;
  assign u_fault_rib_if.cmd_valid = s_fault_sel;
  assign u_fault_rib_if.cmd_addr  = u_mstr_rib_if.cmd_addr;
  assign u_fault_rib_if.cmd_write = u_mstr_rib_if.cmd_write;
  assign u_fault_rib_if.cmd_len   = u_mstr_rib_if.cmd_len;

  always_comb begin
    u_mstr_rib_if.cmd_ready = 1'b0;
    if (s_ribp_sel) begin
      u_mstr_rib_if.cmd_ready = rib.cmd_ready;
    end else if (s_apb_sel) begin
      u_mstr_rib_if.cmd_ready = apb_rib.cmd_ready;
    end else if (s_ram_sel) begin
      u_mstr_rib_if.cmd_ready = u_ram_rib_if.cmd_ready;
    end else if (s_fault_sel) begin
      u_mstr_rib_if.cmd_ready = u_fault_rib_if.cmd_ready;
    end
  end

  always_comb begin
    s_target_d = s_target_q;
    if (u_mstr_rib_if.cmd_valid && u_mstr_rib_if.cmd_ready) begin
      if (s_ribp_sel) begin
        s_target_d = TARGET_RIBP;
      end else if (s_apb_sel) begin
        s_target_d = TARGET_APB;
      end else if (s_ram_sel) begin
        s_target_d = TARGET_RAM;
      end else begin
        s_target_d = TARGET_FAULT;
      end
    end
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_target_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_target_d),
      .dat_o  (s_target_q)
  );

  // Write-data and response routing uses the captured target.
  assign rib.w_valid = s_mstr_lock_q && s_cmd_accepted_q && (s_target_q == TARGET_RIBP) ?
                       u_mstr_rib_if.w_valid : 1'b0;
  assign rib.wdata = u_mstr_rib_if.wdata;
  assign rib.wstrb = u_mstr_rib_if.wstrb;
  assign rib.wlast = u_mstr_rib_if.wlast;
  assign rib.rsp_ready = s_mstr_lock_q && s_cmd_accepted_q && (s_target_q == TARGET_RIBP) ?
                         u_mstr_rib_if.rsp_ready : 1'b0;

  assign apb_rib.w_valid = s_mstr_lock_q && s_cmd_accepted_q &&
                            (s_target_q == TARGET_APB) ? u_mstr_rib_if.w_valid : 1'b0;
  assign apb_rib.wdata = u_mstr_rib_if.wdata;
  assign apb_rib.wstrb = u_mstr_rib_if.wstrb;
  assign apb_rib.wlast = u_mstr_rib_if.wlast;
  assign apb_rib.rsp_ready = s_mstr_lock_q && s_cmd_accepted_q &&
                              (s_target_q == TARGET_APB) ? u_mstr_rib_if.rsp_ready : 1'b0;

  assign u_ram_rib_if.w_valid = s_mstr_lock_q && s_cmd_accepted_q &&
                                  (s_target_q == TARGET_RAM) ?
                                  u_mstr_rib_if.w_valid : 1'b0;
  assign u_ram_rib_if.wdata = u_mstr_rib_if.wdata;
  assign u_ram_rib_if.wstrb = u_mstr_rib_if.wstrb;
  assign u_ram_rib_if.wlast = u_mstr_rib_if.wlast;
  assign u_ram_rib_if.rsp_ready = s_mstr_lock_q && s_cmd_accepted_q &&
                                    (s_target_q == TARGET_RAM) ?
                                    u_mstr_rib_if.rsp_ready : 1'b0;

  assign u_fault_rib_if.w_valid = s_mstr_lock_q && s_cmd_accepted_q &&
                                    (s_target_q == TARGET_FAULT) ?
                                    u_mstr_rib_if.w_valid : 1'b0;
  assign u_fault_rib_if.wdata = u_mstr_rib_if.wdata;
  assign u_fault_rib_if.wstrb = u_mstr_rib_if.wstrb;
  assign u_fault_rib_if.wlast = u_mstr_rib_if.wlast;
  assign u_fault_rib_if.rsp_ready = s_mstr_lock_q && s_cmd_accepted_q &&
                                      (s_target_q == TARGET_FAULT) ?
                                      u_mstr_rib_if.rsp_ready : 1'b0;

  always_comb begin
    u_mstr_rib_if.w_ready   = 1'b0;
    u_mstr_rib_if.rsp_valid = 1'b0;
    u_mstr_rib_if.rdata     = '0;
    u_mstr_rib_if.resp_err  = 1'b0;
    u_mstr_rib_if.resp_code = `RIB_RESP_OK;
    u_mstr_rib_if.rsp_beat  = '0;
    u_mstr_rib_if.rsp_last  = 1'b0;
    unique case (s_target_q)
      TARGET_RIBP: begin
        u_mstr_rib_if.w_ready   = s_cmd_accepted_q && rib.w_ready;
        u_mstr_rib_if.rsp_valid = s_cmd_accepted_q && rib.rsp_valid;
        u_mstr_rib_if.rdata     = rib.rdata;
        u_mstr_rib_if.resp_err  = rib.resp_err;
        u_mstr_rib_if.resp_code = rib.resp_code;
        u_mstr_rib_if.rsp_beat  = rib.rsp_beat;
        u_mstr_rib_if.rsp_last  = rib.rsp_last;
      end
      TARGET_APB: begin
        u_mstr_rib_if.w_ready   = s_cmd_accepted_q && apb_rib.w_ready;
        u_mstr_rib_if.rsp_valid = s_cmd_accepted_q && apb_rib.rsp_valid;
        u_mstr_rib_if.rdata     = apb_rib.rdata;
        u_mstr_rib_if.resp_err  = apb_rib.resp_err;
        u_mstr_rib_if.resp_code = apb_rib.resp_code;
        u_mstr_rib_if.rsp_beat  = apb_rib.rsp_beat;
        u_mstr_rib_if.rsp_last  = apb_rib.rsp_last;
      end
      TARGET_RAM: begin
        u_mstr_rib_if.w_ready   = s_cmd_accepted_q && u_ram_rib_if.w_ready;
        u_mstr_rib_if.rsp_valid = s_cmd_accepted_q && u_ram_rib_if.rsp_valid;
        u_mstr_rib_if.rdata     = u_ram_rib_if.rdata;
        u_mstr_rib_if.resp_err  = u_ram_rib_if.resp_err;
        u_mstr_rib_if.resp_code = u_ram_rib_if.resp_code;
        u_mstr_rib_if.rsp_beat  = u_ram_rib_if.rsp_beat;
        u_mstr_rib_if.rsp_last  = u_ram_rib_if.rsp_last;
      end
      default: begin
        u_mstr_rib_if.w_ready   = s_cmd_accepted_q && u_fault_rib_if.w_ready;
        u_mstr_rib_if.rsp_valid = s_cmd_accepted_q && u_fault_rib_if.rsp_valid;
        u_mstr_rib_if.rdata     = u_fault_rib_if.rdata;
        u_mstr_rib_if.resp_err  = u_fault_rib_if.resp_err;
        u_mstr_rib_if.resp_code = u_fault_rib_if.resp_code;
        u_mstr_rib_if.rsp_beat  = u_fault_rib_if.rsp_beat;
        u_mstr_rib_if.rsp_last  = u_fault_rib_if.rsp_last;
      end
    endcase
  end

  assign s_fault_cmd_hdshk = s_fault_sel && u_fault_rib_if.cmd_ready;
  assign s_fault_w_hdshk = (s_target_q == TARGET_FAULT) &&
                           u_fault_rib_if.w_valid && u_fault_rib_if.w_ready;
  always_comb begin
    s_fault_wstrb_d = s_fault_wstrb_q;
    if (s_fault_cmd_hdshk) begin
      s_fault_wstrb_d = '0;
    end else if (s_fault_w_hdshk && (s_fault_wstrb_q == '0)) begin
      s_fault_wstrb_d = u_fault_rib_if.wstrb;
    end
  end
  dffr #(
      .DATA_WIDTH(4)
  ) u_fault_wstrb_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_wstrb_d),
      .dat_o  (s_fault_wstrb_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_fault_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fault_cmd_hdshk),
      .dat_i  (u_mstr_rib_if.cmd_addr),
      .dat_o  (s_fault_addr_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_fault_master_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fault_cmd_hdshk),
      .dat_i  (s_mstr_id_q),
      .dat_o  (s_fault_master_q)
  );
  dffer #(
      .DATA_WIDTH(3)
  ) u_fault_code_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fault_cmd_hdshk),
      .dat_i  (s_fault_code),
      .dat_o  (s_fault_code_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_xfer_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (u_mstr_rib_if.cmd_valid && u_mstr_rib_if.cmd_ready),
      .dat_i  (u_mstr_rib_if.cmd_addr),
      .dat_o  (s_xfer_addr_q)
  );

  assign fault_valid_o = s_cmd_accepted_q && (s_target_q == TARGET_FAULT) &&
                         u_fault_rib_if.rsp_valid && u_fault_rib_if.rsp_ready;
  assign fault_addr_o = s_fault_addr_q;
  assign fault_wstrb_o = s_fault_wstrb_q;
  assign fault_reserved_o = s_fault_code_q == `RIB_RESP_RESERVED;
  assign fault_access_o = s_fault_code_q == `RIB_RESP_PROTERR;
  assign fault_master_o = s_fault_master_q;
  assign fault_code_o = s_fault_code_q;

  assign s_xfer_stalled = s_mstr_lock_q &&
                          ((u_mstr_rib_if.cmd_valid && ~u_mstr_rib_if.cmd_ready) ||
                           (u_mstr_rib_if.w_valid && ~u_mstr_rib_if.w_ready) ||
                           (~u_mstr_rib_if.cmd_valid && ~u_mstr_rib_if.w_valid &&
                            ~u_mstr_rib_if.rsp_valid));

  always_comb begin
    s_perf_mgmt_wait_d  = s_perf_mgmt_wait_q;
    s_perf_user_wait_d  = s_perf_user_wait_q;
    s_perf_dma_wait_d   = s_perf_dma_wait_q;
    s_perf_ribp_wait_d  = s_perf_ribp_wait_q;
    s_perf_apb_wait_d   = s_perf_apb_wait_q;
    s_perf_sdram_wait_d = s_perf_sdram_wait_q;
    s_perf_psram_wait_d = s_perf_psram_wait_q;
    s_perf_flash_wait_d = s_perf_flash_wait_q;
    if (perf_clear_i) begin
      s_perf_mgmt_wait_d  = '0;
      s_perf_user_wait_d  = '0;
      s_perf_dma_wait_d   = '0;
      s_perf_ribp_wait_d  = '0;
      s_perf_apb_wait_d   = '0;
      s_perf_sdram_wait_d = '0;
      s_perf_psram_wait_d = '0;
      s_perf_flash_wait_d = '0;
    end else if (perf_enable_i && s_xfer_stalled) begin
      unique case (s_mstr_id_q)
        MSTR_MGMT: s_perf_mgmt_wait_d = s_perf_mgmt_wait_q + 1'b1;
        MSTR_USER: s_perf_user_wait_d = s_perf_user_wait_q + 1'b1;
        default:   s_perf_dma_wait_d = s_perf_dma_wait_q + 1'b1;
      endcase
      if (s_target_q == TARGET_RIBP) s_perf_ribp_wait_d = s_perf_ribp_wait_q + 1'b1;
      if (s_target_q == TARGET_APB) s_perf_apb_wait_d = s_perf_apb_wait_q + 1'b1;
      if (`SOC_ADDR_IS_SDRAM(s_xfer_addr_q)) begin
        s_perf_sdram_wait_d = s_perf_sdram_wait_q + 1'b1;
      end
      if (`SOC_ADDR_IS_PSRAM(s_xfer_addr_q)) begin
        s_perf_psram_wait_d = s_perf_psram_wait_q + 1'b1;
      end
      if (`SOC_ADDR_IS_FLASH(s_xfer_addr_q)) begin
        s_perf_flash_wait_d = s_perf_flash_wait_q + 1'b1;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_mgmt_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_mgmt_wait_d),
      .dat_o  (s_perf_mgmt_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_user_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_user_wait_d),
      .dat_o  (s_perf_user_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_dma_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_dma_wait_d),
      .dat_o  (s_perf_dma_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_ribp_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_ribp_wait_d),
      .dat_o  (s_perf_ribp_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_apb_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_apb_wait_d),
      .dat_o  (s_perf_apb_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_sdram_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_sdram_wait_d),
      .dat_o  (s_perf_sdram_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_psram_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_psram_wait_d),
      .dat_o  (s_perf_psram_wait_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_perf_flash_wait_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_flash_wait_d),
      .dat_o  (s_perf_flash_wait_q)
  );

  assign perf_mgmt_wait_o  = s_perf_mgmt_wait_q;
  assign perf_user_wait_o  = s_perf_user_wait_q;
  assign perf_dma_wait_o   = s_perf_dma_wait_q;
  assign perf_ribp_wait_o  = s_perf_ribp_wait_q;
  assign perf_apb_wait_o   = s_perf_apb_wait_q;
  assign perf_sdram_wait_o = s_perf_sdram_wait_q;
  assign perf_psram_wait_o = s_perf_psram_wait_q;
  assign perf_flash_wait_o = s_perf_flash_wait_q;

endmodule

module axi4_bus (
    // verilog_format: off
    input  logic          clk_i,
    input  logic          rst_n_i,
    axi4_if.slave         mgmt_axi4,
    axi4_if.slave         user_axi4,
    axi4_if.slave         dma_axi4,
    axi4_if.master        cfg_axi4,
    axi4_if.master        apb_axi4,
`ifdef HAVE_SRAM_IF
    ram_if.master         ram,
`endif
    axi4_if.master        sdram_axi4,
    axi4_if.master        psram_axi4,
    axi4_if.master        xpi_axi4,
    axi4_if.master        spisd_axi4,
    input  logic          user_bus_enable_i,
    output logic          user_bus_idle_o,
    input  logic          perf_enable_i,
    input  logic          perf_clear_i,
    output logic          fault_valid_o,
    output logic [31:0]   fault_addr_o,
    output logic [3:0]    fault_wstrb_o,
    output logic          fault_reserved_o,
    output logic          fault_access_o,
    output logic [1:0]    fault_master_o,
    output logic [2:0]    fault_code_o,
    output logic [63:0]   perf_mgmt_wait_o,
    output logic [63:0]   perf_user_wait_o,
    output logic [63:0]   perf_dma_wait_o,
    output logic [63:0]   perf_ribp_wait_o,
    output logic [63:0]   perf_apb_wait_o,
    output logic [63:0]   perf_sdram_wait_o,
    output logic [63:0]   perf_psram_wait_o,
    output logic [63:0]   perf_flash_wait_o
    // verilog_format: on
);
  localparam int NUM_MASTERS = 3;
  localparam int NUM_TARGETS = 9;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_master_axi4_if[NUM_MASTERS] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_target_axi4_if[NUM_TARGETS] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_ram_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_connector u_mgmt_connector (
      .source(mgmt_axi4),
      .sink  (u_master_axi4_if[0])
  );

  axi4_connector u_user_connector (
      .source(user_axi4),
      .sink  (u_master_axi4_if[1])
  );

  axi4_connector u_dma_connector (
      .source(dma_axi4),
      .sink  (u_master_axi4_if[2])
  );

  axi4_connector u_cfg_connector (
      .source(u_target_axi4_if[0]),
      .sink  (cfg_axi4)
  );

  axi4_connector u_apb_connector (
      .source(u_target_axi4_if[1]),
      .sink  (apb_axi4)
  );

  axi4_connector u_ram_connector (
      .source(u_target_axi4_if[2]),
      .sink  (u_ram_axi4_if)
  );

  axi4_connector u_sdram_connector (
      .source(u_target_axi4_if[3]),
      .sink  (sdram_axi4)
  );

  axi4_connector u_psram_connector (
      .source(u_target_axi4_if[4]),
      .sink  (psram_axi4)
  );

  axi4_connector u_xpi_connector (
      .source(u_target_axi4_if[5]),
      .sink  (xpi_axi4)
  );

  axi4_connector u_spisd_connector (
      .source(u_target_axi4_if[6]),
      .sink  (spisd_axi4)
  );

  axi4_interconnect #(
      .NUM_MASTERS(NUM_MASTERS),
      .NUM_TARGETS(NUM_TARGETS)
  ) u_axi4_interconnect (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .masters          (u_master_axi4_if),
      .targets          (u_target_axi4_if),
      .user_bus_enable_i(user_bus_enable_i),
      .user_bus_idle_o  (user_bus_idle_o),
      .perf_enable_i    (perf_enable_i),
      .perf_clear_i     (perf_clear_i),
      .fault_valid_o    (fault_valid_o),
      .fault_addr_o     (fault_addr_o),
      .fault_wstrb_o    (fault_wstrb_o),
      .fault_reserved_o (fault_reserved_o),
      .fault_access_o   (fault_access_o),
      .fault_master_o   (fault_master_o),
      .fault_code_o     (fault_code_o),
      .perf_mgmt_wait_o (perf_mgmt_wait_o),
      .perf_user_wait_o (perf_user_wait_o),
      .perf_dma_wait_o  (perf_dma_wait_o),
      .perf_ribp_wait_o (perf_ribp_wait_o),
      .perf_apb_wait_o  (perf_apb_wait_o),
      .perf_sdram_wait_o(perf_sdram_wait_o),
      .perf_psram_wait_o(perf_psram_wait_o),
      .perf_flash_wait_o(perf_flash_wait_o)
  );

`ifdef HAVE_SRAM_IF
  axi42ram u_axi42ram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_ram_axi4_if),
      .ram    (ram)
  );
`else
  axi4_error_slave #(
      .RESPONSE(2'b11)
  ) u_ram_error_slave (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_ram_axi4_if)
  );
`endif

  axi4_error_slave #(
      .RESPONSE(2'b11)
  ) u_decode_error_slave (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_target_axi4_if[7])
  );

  axi4_error_slave #(
      .RESPONSE(2'b10)
  ) u_slave_error_slave (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_target_axi4_if[8])
  );
endmodule
