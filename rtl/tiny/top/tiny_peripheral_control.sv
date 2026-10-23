// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Atomic Tiny gate/reset transactions on REF24. Inputs are synchronized to
// REF24 by the integration; gate masks exclude non-gateable boot infrastructure.
module tiny_peripheral_control (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        warm_reset_i,
    input  logic        apply_i,
    input  logic        reset_command_i,
    input  logic [16:0] request_i,
    input  logic [16:0] idle_i,
    input  logic        bus_idle_i,
    input  logic [16:0] gate_actual_i,
    input  logic [16:0] reset_held_i,
    input  logic [16:0] reset_ready_i,
    input  logic [31:0] timeout_i,
    output logic [16:0] gate_o,
    output logic [16:0] reset_o,
    output logic        block_o,
    output logic        done_o,
    output logic [ 4:0] fault_o,
    output logic [16:0] reset_done_o
);
  typedef enum logic [2:0] {
    Idle,
    Drain,
    GateWait,
    Hold,
    Release,
    Complete
  } state_e;
  typedef struct packed {
    state_e      state;
    logic        reset_command;
    logic [16:0] request_mask,  gates, previous_gates, resets, reset_done, affected;
    logic [31:0] count;
    logic        done;
    logic [4:0]  fault;
  } control_t;
  control_t s_ctrl_d, s_ctrl_q;
  logic [16:0] s_affected;
  assign s_affected   = s_ctrl_q.affected;
  assign gate_o       = s_ctrl_q.gates;
  assign reset_o      = s_ctrl_q.resets;
  assign reset_done_o = s_ctrl_q.reset_done;
  // Arming the WFI leaf permission must not pause an unrelated DMA job.
  // The CPU leaf itself waits for its accepted I/D work before stopping.
  assign block_o      = (s_ctrl_q.state != Idle) && (s_affected[16:1] != 0);
  assign done_o       = s_ctrl_q.done;
  assign fault_o      = s_ctrl_q.fault;
  always_comb begin
    s_ctrl_d       = s_ctrl_q;
    s_ctrl_d.done  = 1'b0;
    s_ctrl_d.fault = 0;
    s_ctrl_d.count = s_ctrl_q.count + 32'd1;
    unique case (s_ctrl_q.state)
      Idle: begin
        s_ctrl_d.count = 0;
        if (apply_i) begin
          if (reset_command_i && (request_i == 0 || request_i[0] ||
              (request_i & s_ctrl_q.gates) != 0)) begin
            s_ctrl_d.done     = 1'b1;
            s_ctrl_d.fault[0] = 1'b1;
          end else begin
            s_ctrl_d.request_mask   = request_i;
            s_ctrl_d.previous_gates = s_ctrl_q.gates;
            s_ctrl_d.affected       = reset_command_i ? request_i : s_ctrl_q.gates ^ request_i;
            s_ctrl_d.reset_command  = reset_command_i;
            if (reset_command_i) s_ctrl_d.reset_done = 0;
            s_ctrl_d.state = Drain;
          end
        end
      end
      Drain: begin
        if (s_ctrl_q.count >= 16 && ((s_affected[16:1] == 0) || (bus_idle_i && idle_i[9])) &&
            ((idle_i[16:1] & s_affected[16:1]) == s_affected[16:1])) begin
          s_ctrl_d.count = 0;
          if (s_ctrl_q.reset_command) begin
            s_ctrl_d.resets = s_ctrl_q.request_mask;
            s_ctrl_d.state  = Hold;
          end else begin
            s_ctrl_d.gates = s_ctrl_q.request_mask;
            s_ctrl_d.state = GateWait;
          end
        end else if (s_ctrl_q.count >= timeout_i) begin
          s_ctrl_d.fault[1] = 1'b1;
          s_ctrl_d.done     = 1'b1;
          s_ctrl_d.state    = Idle;
        end
      end
      GateWait: if (gate_actual_i[16:1] == s_ctrl_q.gates[16:1]) s_ctrl_d.state = Complete;
      Hold:
      if ((reset_held_i & s_ctrl_q.request_mask) == s_ctrl_q.request_mask) begin
        s_ctrl_d.resets = 0;
        s_ctrl_d.count  = 0;
        s_ctrl_d.state  = Release;
      end
      Release:
      if ((reset_ready_i & s_ctrl_q.request_mask) == s_ctrl_q.request_mask) begin
        s_ctrl_d.reset_done = s_ctrl_q.request_mask;
        s_ctrl_d.state      = Complete;
      end
      Complete: begin
        s_ctrl_d.done  = 1'b1;
        s_ctrl_d.state = Idle;
      end
      default: begin
        s_ctrl_d.state    = Idle;
        s_ctrl_d.fault[4] = 1'b1;
      end
    endcase
    if ((s_ctrl_q.state == GateWait || s_ctrl_q.state == Hold || s_ctrl_q.state == Release) &&
        s_ctrl_q.count >= timeout_i) begin
      s_ctrl_d.fault[4] = 1'b1;
      s_ctrl_d.done     = 1'b1;
      s_ctrl_d.state    = Idle;
      // A failed reset retains isolation; it has no RESET_DONE acknowledgement.
      if (s_ctrl_q.reset_command) s_ctrl_d.resets = s_ctrl_q.request_mask;
      else s_ctrl_d.gates = s_ctrl_q.previous_gates;
    end
    if (warm_reset_i) s_ctrl_d = '0;
  end
  dffr #(
      .DATA_WIDTH($bits(control_t))
  ) u_control (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
endmodule
