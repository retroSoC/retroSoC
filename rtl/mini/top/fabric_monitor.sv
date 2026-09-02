// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module fabric_monitor #(
    parameter int unsigned NumMasters = 8,
    parameter int unsigned NumTargets = 6
) (
    // verilog_format: off -- preserve the monitor event boundary columns
    input  logic                               clk_i,
    input  logic                               rst_n_i,
    input  logic                               idle_i,
    input  logic                               recovery_i,
    input  logic                               flush_busy_i,
    input  logic                               flush_i,
    input  logic                         [7:0] outstanding_read_i,
    input  logic                         [7:0] outstanding_write_i,
    input  logic                               fault_valid_i,
    input  logic                         [2:0] fault_master_i,
    input  logic                         [2:0] fault_target_i,
    input  logic                        [31:0] fault_addr_i,
    input  logic                               fault_write_i,
    input  logic                         [3:0] fault_reason_i,
    input  logic              [NumMasters-1:0] master_read_accept_i,
    input  logic              [NumMasters-1:0] master_write_accept_i,
    input  logic              [NumMasters-1:0] master_read_beat_i,
    input  logic              [NumMasters-1:0] master_write_beat_i,
    input  logic              [NumMasters-1:0] master_wait_i,
    input  logic              [NumMasters-1:0] master_promotion_i,
    input  logic [NumMasters-1:0]       [2:0] master_read_outstanding_i,
    input  logic [NumMasters-1:0]       [2:0] master_write_outstanding_i,
    input  logic              [NumTargets-1:0] target_read_accept_i,
    input  logic              [NumTargets-1:0] target_write_accept_i,
    input  logic              [NumTargets-1:0] target_read_beat_i,
    input  logic              [NumTargets-1:0] target_write_beat_i,
    input  logic              [NumTargets-1:0] target_wait_i,
    input  logic              [NumTargets-1:0] target_timeout_i,
    input  logic              [NumTargets-1:0] target_isolated_i,
    input  logic [NumTargets-1:0]       [2:0] target_read_outstanding_i,
    input  logic [NumTargets-1:0]       [2:0] target_write_outstanding_i,
    apb4_if.slave                              apb4
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h4450_4D4E;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [11:0] IpIdOffset = 12'h000;
  localparam logic [11:0] IpVersionOffset = 12'h004;
  localparam logic [11:0] CapabilityOffset = 12'h008;
  localparam logic [11:0] ControlOffset = 12'h00C;
  localparam logic [11:0] StatusOffset = 12'h010;
  localparam logic [11:0] FaultOffset = 12'h014;
  localparam logic [11:0] FaultAddressOffset = 12'h018;
  localparam logic [11:0] FlushCountOffset = 12'h01C;
  localparam logic [11:0] FaultCountOffset = 12'h020;
  localparam logic [11:0] MasterBase = 12'h100;
  localparam logic [11:0] TargetBase = 12'h300;
  localparam logic [11:0] EntryStride = 12'h020;

  logic        s_en_q;
  logic        s_freeze_q;
  logic        s_flush_q;
  logic        s_fault_valid_q;
  logic        s_fault_write_q;
  logic [ 2:0] s_fault_master_q;
  logic [ 2:0] s_fault_target_q;
  logic [ 3:0] s_fault_reason_q;
  logic [31:0] s_fault_addr_q;
  logic [31:0] s_fault_count_q;
  logic [31:0] s_flush_count_q, s_flush_count_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_read_accept_q, s_master_read_accept_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_write_accept_q, s_master_write_accept_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_read_beat_q, s_master_read_beat_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_write_beat_q, s_master_write_beat_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_wait_q, s_master_wait_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_wait_streak_q;
  logic [NumMasters-1:0][31:0] s_master_max_wait_q, s_master_max_wait_snapshot_q;
  logic [NumMasters-1:0][31:0] s_master_promotion_q, s_master_promotion_snapshot_q;
  logic [NumMasters-1:0][5:0] s_master_high_water_q, s_master_high_water_snapshot_q;
  logic [NumTargets-1:0][31:0] s_target_read_accept_q, s_target_read_accept_snapshot_q;
  logic [NumTargets-1:0][31:0] s_target_write_accept_q, s_target_write_accept_snapshot_q;
  logic [NumTargets-1:0][31:0] s_target_read_beat_q, s_target_read_beat_snapshot_q;
  logic [NumTargets-1:0][31:0] s_target_write_beat_q, s_target_write_beat_snapshot_q;
  logic [NumTargets-1:0][31:0] s_target_wait_q, s_target_wait_snapshot_q;
  logic [NumTargets-1:0][31:0] s_target_timeout_q, s_target_timeout_snapshot_q;
  logic [NumTargets-1:0][5:0] s_target_high_water_q, s_target_high_water_snapshot_q;
  logic        s_ready_q;
  logic        s_resp_err_q;
  logic [31:0] s_rdata_q;
  logic        s_request;
  logic        s_write;
  logic        s_aligned;
  logic        s_read_valid;
  logic        s_control_write;
  logic        s_write_error;
  logic [31:0] s_read_data;

  function automatic logic [31:0] saturating_increment(input logic [31:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_request    = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write      = s_request && apb4.pwrite;
  assign s_aligned    = apb4.paddr[1:0] == 2'b00;
  assign apb4.pready  = s_ready_q;
  assign apb4.pslverr = s_resp_err_q;
  assign apb4.prdata  = s_rdata_q;

  always_comb begin
    s_read_valid    = 1'b1;
    s_control_write = 1'b0;
    s_write_error   = 1'b0;
    s_read_data     = 32'd0;
    unique case (apb4.paddr[11:0])
      IpIdOffset: s_read_data = IpId;
      IpVersionOffset: s_read_data = IpVersion;
      CapabilityOffset: s_read_data = {8'(NumTargets), 8'(NumMasters), 14'd0, 2'b11};
      ControlOffset: begin
        s_read_data = {30'd0, s_freeze_q, s_en_q};
        s_control_write = s_write;
        s_write_error = s_write &&
            ((apb4.pstrb != 4'hF) || (apb4.pwdata[31:4] != 28'd0) ||
             (apb4.pwdata[3] && apb4.pwdata[2]));
      end
      StatusOffset:
      s_read_data = {
        8'(outstanding_write_i), 8'(outstanding_read_i), 13'd0, flush_busy_i, recovery_i, idle_i
      };
      FaultOffset:
      s_read_data = {
        20'd0,
        s_fault_reason_q,
        s_fault_target_q,
        s_fault_master_q,
        s_fault_write_q,
        s_fault_valid_q
      };
      FaultAddressOffset: s_read_data = s_fault_addr_q;
      FlushCountOffset: s_read_data = s_flush_count_snapshot_q;
      FaultCountOffset: s_read_data = s_fault_count_q;
      default: begin
        s_read_valid = 1'b0;
        for (int master = 0; master < NumMasters; master++) begin
          if ((apb4.paddr[11:0] >= MasterBase + 12'(master) * EntryStride) &&
              (apb4.paddr[11:0] < MasterBase + 12'(master + 1) * EntryStride)) begin
            unique case (apb4.paddr[11:0] - MasterBase - 12'(master) * EntryStride)
              12'h000: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_read_accept_snapshot_q[master];
              end
              12'h004: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_write_accept_snapshot_q[master];
              end
              12'h008: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_read_beat_snapshot_q[master];
              end
              12'h00C: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_write_beat_snapshot_q[master];
              end
              12'h010: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_wait_snapshot_q[master];
              end
              12'h014: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_max_wait_snapshot_q[master];
              end
              12'h018: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = s_master_promotion_snapshot_q[master];
              end
              12'h01C: begin
                s_read_valid = apb4.paddr[11:0] >= MasterBase;
                s_read_data  = {26'd0, s_master_high_water_snapshot_q[master]};
              end
              default: begin
              end
            endcase
          end
        end
        for (int target = 0; target < NumTargets; target++) begin
          if ((apb4.paddr[11:0] >= TargetBase + 12'(target) * EntryStride) &&
              (apb4.paddr[11:0] < TargetBase + 12'(target + 1) * EntryStride)) begin
            unique case (apb4.paddr[11:0] - TargetBase - 12'(target) * EntryStride)
              12'h000: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = s_target_read_accept_snapshot_q[target];
              end
              12'h004: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = s_target_write_accept_snapshot_q[target];
              end
              12'h008: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = s_target_read_beat_snapshot_q[target];
              end
              12'h00C: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = s_target_write_beat_snapshot_q[target];
              end
              12'h010: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = s_target_wait_snapshot_q[target];
              end
              12'h014: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = s_target_timeout_snapshot_q[target];
              end
              12'h018: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = {31'd0, target_isolated_i[target]};
              end
              12'h01C: begin
                s_read_valid = apb4.paddr[11:0] >= TargetBase;
                s_read_data  = {26'd0, s_target_high_water_snapshot_q[target]};
              end
              default: begin
              end
            endcase
          end
        end
      end
    endcase
    if (!s_aligned || (s_write && !s_control_write) || (!s_write && !s_read_valid)) begin
      s_write_error = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_en_q                           <= 1'b0;
      s_freeze_q                       <= 1'b0;
      s_flush_q                        <= 1'b0;
      s_fault_valid_q                  <= 1'b0;
      s_fault_write_q                  <= 1'b0;
      s_fault_master_q                 <= '0;
      s_fault_target_q                 <= '0;
      s_fault_reason_q                 <= '0;
      s_fault_addr_q                   <= '0;
      s_fault_count_q                  <= '0;
      s_flush_count_q                  <= '0;
      s_flush_count_snapshot_q         <= '0;
      s_master_read_accept_q           <= '0;
      s_master_read_accept_snapshot_q  <= '0;
      s_master_write_accept_q          <= '0;
      s_master_write_accept_snapshot_q <= '0;
      s_master_read_beat_q             <= '0;
      s_master_read_beat_snapshot_q    <= '0;
      s_master_write_beat_q            <= '0;
      s_master_write_beat_snapshot_q   <= '0;
      s_master_wait_q                  <= '0;
      s_master_wait_snapshot_q         <= '0;
      s_master_wait_streak_q           <= '0;
      s_master_max_wait_q              <= '0;
      s_master_max_wait_snapshot_q     <= '0;
      s_master_promotion_q             <= '0;
      s_master_promotion_snapshot_q    <= '0;
      s_master_high_water_q            <= '0;
      s_master_high_water_snapshot_q   <= '0;
      s_target_read_accept_q           <= '0;
      s_target_read_accept_snapshot_q  <= '0;
      s_target_write_accept_q          <= '0;
      s_target_write_accept_snapshot_q <= '0;
      s_target_read_beat_q             <= '0;
      s_target_read_beat_snapshot_q    <= '0;
      s_target_write_beat_q            <= '0;
      s_target_write_beat_snapshot_q   <= '0;
      s_target_wait_q                  <= '0;
      s_target_wait_snapshot_q         <= '0;
      s_target_timeout_q               <= '0;
      s_target_timeout_snapshot_q      <= '0;
      s_target_high_water_q            <= '0;
      s_target_high_water_snapshot_q   <= '0;
      s_ready_q                        <= 1'b0;
      s_resp_err_q                     <= 1'b0;
      s_rdata_q                        <= '0;
    end else begin
      s_ready_q    <= s_request;
      s_resp_err_q <= s_request && s_write_error;
      if (s_request && !s_write && s_read_valid) s_rdata_q <= s_read_data;
      s_flush_q <= flush_i;
      if (s_request && s_control_write && !s_write_error) begin
        s_en_q     <= apb4.pwdata[0];
        s_freeze_q <= apb4.pwdata[1];
      end
      if (s_request && s_control_write && !s_write_error && apb4.pwdata[2]) begin
        s_flush_count_q                  <= '0;
        s_flush_count_snapshot_q         <= '0;
        s_fault_valid_q                  <= 1'b0;
        s_fault_write_q                  <= 1'b0;
        s_fault_master_q                 <= '0;
        s_fault_target_q                 <= '0;
        s_fault_reason_q                 <= '0;
        s_fault_addr_q                   <= '0;
        s_fault_count_q                  <= '0;
        s_master_read_accept_q           <= '0;
        s_master_read_accept_snapshot_q  <= '0;
        s_master_write_accept_q          <= '0;
        s_master_write_accept_snapshot_q <= '0;
        s_master_read_beat_q             <= '0;
        s_master_read_beat_snapshot_q    <= '0;
        s_master_write_beat_q            <= '0;
        s_master_write_beat_snapshot_q   <= '0;
        s_master_wait_q                  <= '0;
        s_master_wait_snapshot_q         <= '0;
        s_master_wait_streak_q           <= '0;
        s_master_max_wait_q              <= '0;
        s_master_max_wait_snapshot_q     <= '0;
        s_master_promotion_q             <= '0;
        s_master_promotion_snapshot_q    <= '0;
        s_master_high_water_q            <= '0;
        s_master_high_water_snapshot_q   <= '0;
        s_target_read_accept_q           <= '0;
        s_target_read_accept_snapshot_q  <= '0;
        s_target_write_accept_q          <= '0;
        s_target_write_accept_snapshot_q <= '0;
        s_target_read_beat_q             <= '0;
        s_target_read_beat_snapshot_q    <= '0;
        s_target_write_beat_q            <= '0;
        s_target_write_beat_snapshot_q   <= '0;
        s_target_wait_q                  <= '0;
        s_target_wait_snapshot_q         <= '0;
        s_target_timeout_q               <= '0;
        s_target_timeout_snapshot_q      <= '0;
        s_target_high_water_q            <= '0;
        s_target_high_water_snapshot_q   <= '0;
      end else begin
        if (s_en_q && !s_freeze_q) begin
          if (flush_i && !s_flush_q) s_flush_count_q <= saturating_increment(s_flush_count_q);
          if (fault_valid_i) begin
            s_fault_count_q <= saturating_increment(s_fault_count_q);
            if (!s_fault_valid_q) begin
              s_fault_valid_q  <= 1'b1;
              s_fault_write_q  <= fault_write_i;
              s_fault_master_q <= fault_master_i;
              s_fault_target_q <= fault_target_i;
              s_fault_reason_q <= fault_reason_i;
              s_fault_addr_q   <= fault_addr_i;
            end
          end
          for (int master = 0; master < NumMasters; master++) begin
            if (master_read_accept_i[master])
              s_master_read_accept_q[master] <= saturating_increment(
                  s_master_read_accept_q[master]
              );
            if (master_write_accept_i[master])
              s_master_write_accept_q[master] <= saturating_increment(
                  s_master_write_accept_q[master]
              );
            if (master_read_beat_i[master])
              s_master_read_beat_q[master] <= saturating_increment(s_master_read_beat_q[master]);
            if (master_write_beat_i[master])
              s_master_write_beat_q[master] <= saturating_increment(s_master_write_beat_q[master]);
            if (master_wait_i[master]) begin
              s_master_wait_q[master] <= saturating_increment(s_master_wait_q[master]);
              s_master_wait_streak_q[master] <= saturating_increment(
                  s_master_wait_streak_q[master]
              );
              if (s_master_wait_streak_q[master] >= s_master_max_wait_q[master]) begin
                s_master_max_wait_q[master] <= saturating_increment(s_master_wait_streak_q[master]);
              end
            end else begin
              s_master_wait_streak_q[master] <= '0;
            end
            if (master_promotion_i[master])
              s_master_promotion_q[master] <= saturating_increment(s_master_promotion_q[master]);
            if (master_read_outstanding_i[master] > s_master_high_water_q[master][2:0])
              s_master_high_water_q[master][2:0] <= master_read_outstanding_i[master];
            if (master_write_outstanding_i[master] > s_master_high_water_q[master][5:3])
              s_master_high_water_q[master][5:3] <= master_write_outstanding_i[master];
          end
          for (int target = 0; target < NumTargets; target++) begin
            if (target_read_accept_i[target])
              s_target_read_accept_q[target] <= saturating_increment(
                  s_target_read_accept_q[target]
              );
            if (target_write_accept_i[target])
              s_target_write_accept_q[target] <= saturating_increment(
                  s_target_write_accept_q[target]
              );
            if (target_read_beat_i[target])
              s_target_read_beat_q[target] <= saturating_increment(s_target_read_beat_q[target]);
            if (target_write_beat_i[target])
              s_target_write_beat_q[target] <= saturating_increment(s_target_write_beat_q[target]);
            if (target_wait_i[target])
              s_target_wait_q[target] <= saturating_increment(s_target_wait_q[target]);
            if (target_timeout_i[target])
              s_target_timeout_q[target] <= saturating_increment(s_target_timeout_q[target]);
            if (target_read_outstanding_i[target] > s_target_high_water_q[target][2:0])
              s_target_high_water_q[target][2:0] <= target_read_outstanding_i[target];
            if (target_write_outstanding_i[target] > s_target_high_water_q[target][5:3])
              s_target_high_water_q[target][5:3] <= target_write_outstanding_i[target];
          end
        end
        if (s_request && s_control_write && !s_write_error && apb4.pwdata[3]) begin
          s_flush_count_snapshot_q         <= s_flush_count_q;
          s_master_read_accept_snapshot_q  <= s_master_read_accept_q;
          s_master_write_accept_snapshot_q <= s_master_write_accept_q;
          s_master_read_beat_snapshot_q    <= s_master_read_beat_q;
          s_master_write_beat_snapshot_q   <= s_master_write_beat_q;
          s_master_wait_snapshot_q         <= s_master_wait_q;
          s_master_max_wait_snapshot_q     <= s_master_max_wait_q;
          s_master_promotion_snapshot_q    <= s_master_promotion_q;
          s_master_high_water_snapshot_q   <= s_master_high_water_q;
          s_target_read_accept_snapshot_q  <= s_target_read_accept_q;
          s_target_write_accept_snapshot_q <= s_target_write_accept_q;
          s_target_read_beat_snapshot_q    <= s_target_read_beat_q;
          s_target_write_beat_snapshot_q   <= s_target_write_beat_q;
          s_target_wait_snapshot_q         <= s_target_wait_q;
          s_target_timeout_snapshot_q      <= s_target_timeout_q;
          s_target_high_water_snapshot_q   <= s_target_high_water_q;
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((NumMasters != 8) || (NumTargets != 6)) begin
      $fatal(1, "fabric_monitor: product topology must remain 8x6");
    end
  end
`endif
endmodule
