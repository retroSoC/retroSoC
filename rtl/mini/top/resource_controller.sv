// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module resource_controller #(
    parameter int unsigned ResourceCount = 6
) (
    // verilog_format: off -- preserve the resource ownership boundary columns
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    input  logic [ResourceCount-1:0]        idle_i,
    input  logic [ResourceCount-1:0]        block_ack_i,
    input  logic [ResourceCount-1:0]        irq_i,
    input  logic                            cache_request_i,
    output logic                            cache_clean_o,
    output logic [ResourceCount-1:0][1:0]   owner_o,
    output logic [ResourceCount-1:0]        quiesce_o,
    output logic [ResourceCount-1:0]        reset_o,
    output logic [ResourceCount-1:0]        irq_lp_o,
    output logic [ResourceCount-1:0]        irq_hp_o,
    output logic                            fault_irq_o,
    apb4_if.slave                           apb4
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h5253_4354;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [11:0] IpIdOffset = 12'h000;
  localparam logic [11:0] IpVersionOffset = 12'h004;
  localparam logic [11:0] CapabilityOffset = 12'h008;
  localparam logic [11:0] GlobalStatusOffset = 12'h00C;
  localparam logic [11:0] CacheControlOffset = 12'h010;
  localparam logic [11:0] ResourceBase = 12'h100;
  localparam logic [11:0] ResourceStride = 12'h020;
  localparam logic [11:0] OwnerOffset = 12'h000;
  localparam logic [11:0] ControlOffset = 12'h004;
  localparam logic [11:0] StatusOffset = 12'h008;
  localparam logic [11:0] FaultOffset = 12'h00C;
  localparam logic [11:0] HandoffCountOffset = 12'h010;
  localparam logic [1:0] OwnerLp = 2'd0;
  localparam logic [1:0] OwnerHp = 2'd1;

  logic [ResourceCount-1:0][ 1:0] s_owner_q;
  logic [ResourceCount-1:0]       s_owner_lock_q;
  logic [ResourceCount-1:0]       s_quiesce_q;
  logic [ResourceCount-1:0]       s_reset_q;
  logic [ResourceCount-1:0]       s_fault_q;
  logic [ResourceCount-1:0][15:0] s_handoff_count_q;
  logic                           s_cache_clean_q;
  logic                           s_ready_q;
  logic                           s_resp_err_q;
  logic [             31:0]       s_rdata_q;
  logic                           s_request;
  logic                           s_aligned;
  logic                           s_read_valid;
  logic                           s_write_valid;
  logic                           s_write_error;
  logic [             31:0]       s_read_data;
  logic [ResourceCount-1:0]       s_owner_write;
  logic [ResourceCount-1:0]       s_control_write;
  logic [ResourceCount-1:0]       s_fault_clear;
  logic                           s_cache_write;

  function automatic logic [15:0] saturating_increment(input logic [15:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_request     = apb4.psel && apb4.penable && !s_ready_q;
  assign s_aligned     = apb4.paddr[1:0] == 2'b00;
  assign apb4.pready   = s_ready_q;
  assign apb4.pslverr  = s_resp_err_q;
  assign apb4.prdata   = s_rdata_q;
  assign owner_o       = s_owner_q;
  assign quiesce_o     = s_quiesce_q;
  assign reset_o       = s_reset_q;
  assign cache_clean_o = s_cache_clean_q;
  assign fault_irq_o   = |s_fault_q;

  always_comb begin
    irq_lp_o = '0;
    irq_hp_o = '0;
    for (int resource = 0; resource < ResourceCount; resource++) begin
      irq_lp_o[resource] = irq_i[resource] && (s_owner_q[resource] == OwnerLp) &&
          !s_reset_q[resource];
      irq_hp_o[resource] = irq_i[resource] && (s_owner_q[resource] == OwnerHp) &&
          !s_reset_q[resource];
    end
  end

  always_comb begin
    s_read_valid    = 1'b1;
    s_write_valid   = 1'b0;
    s_write_error   = 1'b0;
    s_read_data     = 32'd0;
    s_owner_write   = '0;
    s_control_write = '0;
    s_fault_clear   = '0;
    s_cache_write   = 1'b0;
    unique case (apb4.paddr[11:0])
      IpIdOffset: s_read_data = IpId;
      IpVersionOffset: s_read_data = IpVersion;
      CapabilityOffset: s_read_data = {16'd0, 8'(ResourceCount), 6'd0, 2'd1};
      GlobalStatusOffset:
      s_read_data = {
        {(25 - ResourceCount) {1'b0}}, s_fault_q, 5'd0, cache_request_i, s_cache_clean_q
      };
      CacheControlOffset: begin
        s_read_data = {30'd0, cache_request_i, s_cache_clean_q};
        s_write_valid = 1'b1;
        s_cache_write = apb4.pwrite;
        s_write_error = apb4.pwrite && ((apb4.pstrb != 4'hF) ||
                                        apb4.pwdata[31:1] != 31'd0 ||
                                        (apb4.pwdata[0] && !cache_request_i));
      end
      default: begin
        s_read_valid = 1'b0;
        for (int resource = 0; resource < ResourceCount; resource++) begin
          if (apb4.paddr[11:0] == ResourceBase + 12'(resource) * ResourceStride + OwnerOffset) begin
            s_read_valid = 1'b1;
            s_read_data = {23'd0, s_owner_lock_q[resource], 6'd0, s_owner_q[resource]};
            s_write_valid = 1'b1;
            s_owner_write[resource] = apb4.pwrite;
            s_write_error = apb4.pwrite &&
                ((apb4.pstrb != 4'hF) || (apb4.pwdata[31:9] != 23'd0) ||
                 (apb4.pwdata[7:2] != 6'd0) || (apb4.pwdata[1:0] > OwnerHp) ||
                 s_owner_lock_q[resource] || !s_quiesce_q[resource] ||
                 !block_ack_i[resource] || !idle_i[resource]);
          end else if (apb4.paddr[11:0] ==
                       ResourceBase + 12'(resource) * ResourceStride + ControlOffset) begin
            s_read_valid = 1'b1;
            s_read_data = {30'd0, s_reset_q[resource], s_quiesce_q[resource]};
            s_write_valid = 1'b1;
            s_control_write[resource] = apb4.pwrite;
            s_write_error = apb4.pwrite && ((apb4.pstrb != 4'hF) || (apb4.pwdata[31:2] != 30'd0));
          end else if (apb4.paddr[11:0] ==
                       ResourceBase + 12'(resource) * ResourceStride + StatusOffset) begin
            s_read_valid = 1'b1;
            s_read_data = {
              24'd0,
              block_ack_i[resource],
              irq_i[resource],
              s_fault_q[resource],
              idle_i[resource],
              s_reset_q[resource],
              s_quiesce_q[resource],
              s_owner_q[resource]
            };
          end else if (apb4.paddr[11:0] ==
                       ResourceBase + 12'(resource) * ResourceStride + FaultOffset) begin
            s_read_valid = 1'b1;
            s_read_data = {31'd0, s_fault_q[resource]};
            s_write_valid = 1'b1;
            s_fault_clear[resource] = apb4.pwrite;
            s_write_error = apb4.pwrite && ((apb4.pstrb != 4'hF) || (apb4.pwdata[31:1] != 31'd0));
          end else if (apb4.paddr[11:0] ==
                       ResourceBase + 12'(resource) * ResourceStride + HandoffCountOffset) begin
            s_read_valid = 1'b1;
            s_read_data  = {16'd0, s_handoff_count_q[resource]};
          end
        end
      end
    endcase
    if (!s_aligned || (apb4.pwrite && !s_write_valid) || (!apb4.pwrite && !s_read_valid)) begin
      s_write_error = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_owner_q         <= '0;
      s_owner_lock_q    <= '0;
      s_quiesce_q       <= '0;
      s_reset_q         <= '0;
      s_fault_q         <= '0;
      s_handoff_count_q <= '0;
      s_cache_clean_q   <= 1'b0;
      s_ready_q         <= 1'b0;
      s_resp_err_q      <= 1'b0;
      s_rdata_q         <= '0;
    end else begin
      s_ready_q    <= s_request;
      s_resp_err_q <= s_request && s_write_error;
      if (s_request && !apb4.pwrite && s_read_valid) s_rdata_q <= s_read_data;
      if (!cache_request_i) s_cache_clean_q <= 1'b0;
      if (s_request && s_cache_write && !s_write_error) begin
        s_cache_clean_q <= apb4.pwdata[0];
      end
      for (int resource = 0; resource < ResourceCount; resource++) begin
        if (s_request && s_owner_write[resource]) begin
          if (s_write_error) begin
            s_fault_q[resource] <= 1'b1;
          end else begin
            if (s_owner_q[resource] != apb4.pwdata[1:0]) begin
              s_handoff_count_q[resource] <= saturating_increment(s_handoff_count_q[resource]);
            end
            s_owner_q[resource]      <= apb4.pwdata[1:0];
            s_owner_lock_q[resource] <= apb4.pwdata[8];
          end
        end
        if (s_request && s_control_write[resource] && !s_write_error) begin
          s_quiesce_q[resource] <= apb4.pwdata[0];
          s_reset_q[resource]   <= apb4.pwdata[1];
        end
        if (s_request && s_fault_clear[resource] && !s_write_error && apb4.pwdata[0]) begin
          s_fault_q[resource] <= 1'b0;
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((ResourceCount < 1) || (ResourceCount > 16)) begin
      $fatal(1, "resource_controller: ResourceCount must be in [1, 16]");
    end
  end
`endif
endmodule
