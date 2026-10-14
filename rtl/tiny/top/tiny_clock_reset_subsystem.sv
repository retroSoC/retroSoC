// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Control runs on normalized REF24. All live changes drain first, park SYS,
// prepare conservative divisors, qualify the requested source, and commit last.
// A lost PLL resets the data session before resetting the safe mux. REF/XIN
// loss cannot be recovered by logic which depends on that same input.
module tiny_clock_reset_subsystem #(
    parameter int unsigned RefClkHz     = 24_000_000,
    parameter bit          HavePll      = 1'b0,
    parameter int unsigned SwitchCycles = 128
) (
    input  logic        ref_clk_i,
    input  logic        rst_n_i,
    input  logic [ 1:0] profile_i,
    input  logic        apply_i,
    input  logic        idle_i,
    input  logic        clients_idle_i,
    input  logic        warm_reset_i,
    input  logic        system_request_i,
    input  logic        command_ack_i,
    input  logic [31:0] timeout_i,
    output logic [ 1:0] current_profile_o,
    output logic        busy_o,
    output logic        fault_o,
    output logic [ 4:0] fault_code_o,
    output logic        done_o,
    output logic        block_o,
    output logic        ref_clk_o,
    output logic        ref_rst_n_o,
    output logic        system_reset_n_o,
    output logic        pll_locked_o,
    output logic        pll_selected_o,
    output logic        sys_clk_o,
    output logic        mem_clk_o,
    output logic        pclk_o,
    output logic        sys_rst_n_o,
    output logic        mem_rst_n_o,
    output logic        pclk_rst_n_o,
    output logic [31:0] xin_hz_o,
    output logic [31:0] ref_hz_o,
    output logic [31:0] sys_hz_o,
    output logic [31:0] mem_hz_o,
    output logic [31:0] pclk_hz_o
);
  typedef enum logic [3:0] {
    Idle,
    Drain,
    Park,
    Program,
    Unlock,
    Lock,
    Divide,
    Switch,
    Commit,
    Recover,
    WarmDrain
  } state_e;
  typedef struct packed {
    state_e      state;
    logic [1:0]  requested;
    logic [1:0]  current;
    logic        fast;
    logic        mem_div;
    logic [1:0]  pclk_div;
    logic [2:0]  pll_sel;
    logic        pll_apply;
    logic        reset_n;
    logic        done;
    logic [4:0]  fault;
    logic [31:0] count;
  } control_t;
  localparam control_t ResetValue = {
    Idle, 2'd0, 2'd0, 1'b0, 1'b0, 2'd0, 3'd5, 1'b0, 1'b1, 1'b0, 5'd0, 32'd0
  };
  control_t s_ctrl_d, s_ctrl_q;
  logic s_pll_capable, s_pll_lock, s_pll_clk, s_fast_clk;
  logic s_div2_clk, s_div4_clk, s_pclk_mid;
  logic s_mux_rst_n;
  logic [31:0] s_limit, s_req_hz;
  logic s_idle_ref, s_clients_idle_ref;
  logic s_cmd_ack_ref;
  logic s_fault_sticky_d, s_fault_sticky_q;

  if (RefClkHz == 24_000_000) begin : gen_ref_direct
    assign ref_clk_o = ref_clk_i;
  end else begin : gen_ref_divided
    (* keep_hierarchy = 1 *)
    clock_divider #(
        .DIV_WIDTH(2),
        .RESET_DIV(2'(RefClkHz / 48_000_000))
    ) u_ref_div (
        .clk_i      (ref_clk_i),
        .rst_n_i    (rst_n_i),
        .enable_i   (1'b1),
        .div_i      (2'(RefClkHz / 48_000_000)),
        .div_valid_i(1'b0),
        .div_ready_o(),
        .clk_o      (ref_clk_o),
        .count_o    ()
    );
  end
  rst_sync #(
      .STAGE(5)
  ) u_ref_rst (
      .clk_i  (ref_clk_o),
      .rst_n_i(rst_n_i),
      .rst_n_o(ref_rst_n_o)
  );
`ifdef HAVE_PLL
  tc_pll #(
      .UseIcs55EcosPll(1'b1),
      .Ics55Parked    (1'b0)
  ) u_pll (
      .fref_i       (ref_clk_o),
      .rst_n_i      (ref_rst_n_o),
      .cfg_sel_i    (s_ctrl_q.pll_sel),
      .cfg_apply_i  (s_ctrl_q.pll_apply),
      .pll_capable_o(s_pll_capable),
      .pll_lock_o   (s_pll_lock),
      .pll_clk_o    (s_pll_clk)
  );
`else
  assign s_pll_capable = 1'b0;
  assign s_pll_lock    = 1'b0;
  assign s_pll_clk     = 1'b0;
`endif
  assign s_fast_clk  = HavePll ? s_pll_clk : ref_clk_i;
  assign s_mux_rst_n = ref_rst_n_o && s_ctrl_q.reset_n;
  (* keep_hierarchy = 1 *)
  safe_clock_mux u_sys_mux (
      .clk0_i  (ref_clk_o),
      .clk1_i  (s_fast_clk),
      .rst_n_i (s_mux_rst_n),
      .select_i(s_ctrl_q.fast),
      .clk_o   (sys_clk_o)
  );
  // Both divided sources remain live across handover, including returning to
  // SAFE24. Disabling a selected source would deadlock Common safe_clock_mux.
  clock_divider #(
      .DIV_WIDTH(1),
      .RESET_DIV(1'b1)
  ) u_div2 (
      .clk_i      (sys_clk_o),
      .rst_n_i    (sys_rst_n_o),
      .enable_i   (1'b1),
      .div_i      (1'b1),
      .div_valid_i(1'b0),
      .div_ready_o(),
      .count_o    (),
      .clk_o      (s_div2_clk)
  );
  clock_divider #(
      .DIV_WIDTH(2),
      .RESET_DIV(2'd2)
  ) u_div4 (
      .clk_i      (sys_clk_o),
      .rst_n_i    (sys_rst_n_o),
      .enable_i   (1'b1),
      .div_i      (2'd2),
      .div_valid_i(1'b0),
      .div_ready_o(),
      .count_o    (),
      .clk_o      (s_div4_clk)
  );
  (* keep_hierarchy = 1 *)
  safe_clock_mux u_mem_mux (
      .clk0_i  (sys_clk_o),
      .clk1_i  (s_div2_clk),
      .rst_n_i (s_mux_rst_n),
      .select_i(s_ctrl_q.mem_div),
      .clk_o   (mem_clk_o)
  );
  (* keep_hierarchy = 1 *)
  safe_clock_mux u_pclk_div2_mux (
      .clk0_i  (sys_clk_o),
      .clk1_i  (s_div2_clk),
      .rst_n_i (s_mux_rst_n),
      .select_i(s_ctrl_q.pclk_div != 0),
      .clk_o   (s_pclk_mid)
  );
  (* keep_hierarchy = 1 *)
  safe_clock_mux u_pclk_mux (
      .clk0_i  (s_pclk_mid),
      .clk1_i  (s_div4_clk),
      .rst_n_i (s_mux_rst_n),
      .select_i(s_ctrl_q.pclk_div == 2),
      .clk_o   (pclk_o)
  );
  assign system_reset_n_o = rst_n_i && s_ctrl_q.reset_n;
  rst_sync #(
      .STAGE(5)
  ) u_sys_rst (
      .clk_i  (sys_clk_o),
      .rst_n_i(system_reset_n_o),
      .rst_n_o(sys_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_mem_rst (
      .clk_i  (mem_clk_o),
      .rst_n_i(system_reset_n_o),
      .rst_n_o(mem_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_pclk_rst (
      .clk_i  (pclk_o),
      .rst_n_i(system_reset_n_o),
      .rst_n_o(pclk_rst_n_o)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_idle_sync (
      .clk_i  (ref_clk_o),
      .rst_n_i(ref_rst_n_o),
      .dat_i  (idle_i),
      .dat_o  (s_idle_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_client_sync (
      .clk_i  (ref_clk_o),
      .rst_n_i(ref_rst_n_o),
      .dat_i  (clients_idle_i),
      .dat_o  (s_clients_idle_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_command_ack_sync (
      .clk_i  (ref_clk_o),
      .rst_n_i(ref_rst_n_o),
      .dat_i  (command_ack_i),
      .dat_o  (s_cmd_ack_ref)
  );
  assign s_limit = timeout_i == 0 ? 32'd1 : timeout_i;
  assign s_req_hz = s_ctrl_q.requested == 2 ? 32'd192_000_000 :
      s_ctrl_q.requested == 3 ? 32'd240_000_000 :
      s_ctrl_q.requested == 1 ? 32'(RefClkHz) : 32'd24_000_000;
  always_comb begin
    s_ctrl_d           = s_ctrl_q;
    s_ctrl_d.done      = 1'b0;
    s_ctrl_d.pll_apply = 1'b0;
    s_ctrl_d.fault     = 5'd0;
    s_ctrl_d.count     = s_ctrl_q.count + 32'd1;
    unique case (s_ctrl_q.state)
      Idle: begin
        s_ctrl_d.count = 0;
        if (system_request_i) s_ctrl_d.state = WarmDrain;
        else if (apply_i) begin
          s_ctrl_d.requested = profile_i;
          if ((HavePll && profile_i == 1) || (profile_i >= 2 && (!HavePll || !s_pll_capable))) begin
            s_ctrl_d.done     = 1'b1;
            s_ctrl_d.fault[0] = 1'b1;
          end else s_ctrl_d.state = Drain;
        end
      end
      WarmDrain: begin
        if (s_ctrl_q.count >= 16 && s_cmd_ack_ref) begin
          s_ctrl_d.reset_n = 1'b0;
          s_ctrl_d.fast    = 1'b0;
          s_ctrl_d.count   = 0;
          s_ctrl_d.state   = Recover;
        end else if (s_ctrl_q.count >= s_limit) begin
          s_ctrl_d.fault[1] = 1'b1;
          s_ctrl_d.done     = 1'b1;
          s_ctrl_d.state    = Idle;
        end
      end
      Drain: begin
        // Delay covers block propagation and the accepted command's response.
        if (s_limit >= SwitchCycles && s_ctrl_q.count >= 16 &&
            s_idle_ref && s_clients_idle_ref) begin
          s_ctrl_d.fast  = 1'b0;
          s_ctrl_d.count = 0;
          s_ctrl_d.state = Park;
        end else if (s_ctrl_q.count >= s_limit) begin
          s_ctrl_d.fault[1] = 1'b1;
          s_ctrl_d.done     = 1'b1;
          s_ctrl_d.state    = Idle;
        end
      end
      Park:
      if (s_ctrl_q.count >= SwitchCycles) begin
        s_ctrl_d.count = 0;
        s_ctrl_d.state = s_ctrl_q.requested >= 2 ? Program : Divide;
      end
      Program: begin
        s_ctrl_d.pll_sel   = s_ctrl_q.requested == 2 ? 3'd5 : 3'd7;
        s_ctrl_d.pll_apply = 1'b1;
        s_ctrl_d.count     = 0;
        s_ctrl_d.state     = Unlock;
      end
      Unlock:
      if (!s_pll_lock) begin
        s_ctrl_d.count = 0;
        s_ctrl_d.state = Lock;
      end else if (s_ctrl_q.count >= s_limit) begin
        s_ctrl_d.requested = 0;
        s_ctrl_d.fault[2]  = 1'b1;
        s_ctrl_d.count     = 0;
        s_ctrl_d.state     = Divide;
      end
      Lock:
      if (s_pll_lock) begin
        s_ctrl_d.count = 0;
        s_ctrl_d.state = Divide;
      end else if (s_ctrl_q.count >= s_limit) begin
        s_ctrl_d.requested = 0;
        s_ctrl_d.fault[2]  = 1'b1;
        s_ctrl_d.count     = 0;
        s_ctrl_d.state     = Divide;
      end
      Divide: begin
        s_ctrl_d.mem_div  = s_req_hz > 120_000_000;
        s_ctrl_d.pclk_div = s_req_hz > 120_000_000 ? 2'd2 : s_req_hz > 60_000_000 ? 2'd1 : 2'd0;
        if (s_ctrl_q.count >= SwitchCycles) begin
          s_ctrl_d.fast  = s_ctrl_q.requested != 0;
          s_ctrl_d.count = 0;
          s_ctrl_d.state = Switch;
        end
      end
      Switch:
      if (s_ctrl_q.count >= SwitchCycles) begin
        s_ctrl_d.current = s_ctrl_q.requested;
        s_ctrl_d.state   = Commit;
        s_ctrl_d.count   = 0;
      end
      Commit:
      if (s_ctrl_q.count >= SwitchCycles) begin
        // Keep admissions blocked while domain-local rate snapshots cross.
        s_ctrl_d.done  = 1'b1;
        s_ctrl_d.state = Idle;
      end
      Recover: begin
        s_ctrl_d.fast     = 1'b0;
        s_ctrl_d.mem_div  = 1'b0;
        s_ctrl_d.pclk_div = 0;
        s_ctrl_d.current  = 0;
        if (s_ctrl_q.count >= SwitchCycles && !warm_reset_i) begin
          s_ctrl_d.reset_n = 1'b1;
          s_ctrl_d.state   = Idle;
        end
      end
      default: begin
        s_ctrl_d          = ResetValue;
        s_ctrl_d.reset_n  = 1'b0;
        s_ctrl_d.state    = Recover;
        s_ctrl_d.fault[4] = 1'b1;
      end
    endcase
    if (s_ctrl_q.state != Recover && (warm_reset_i ||
        (HavePll && s_ctrl_q.fast && !s_pll_lock))) begin
      // Only the session-reset path may break a stopped-clock mux deadlock.
      s_ctrl_d.reset_n = 1'b0;
      s_ctrl_d.fast    = 1'b0;
      s_ctrl_d.count   = 0;
      s_ctrl_d.state   = Recover;
      if (!warm_reset_i) s_ctrl_d.fault[3] = 1'b1;
    end
    if ((apply_i || system_request_i) && s_ctrl_q.state != Idle) s_ctrl_d.fault[0] = 1'b1;
  end
  dffrc #(
      .DATA_WIDTH($bits(control_t)),
      .RESET_VAL (ResetValue)
  ) u_control (
      .clk_i  (ref_clk_o),
      .rst_n_i(ref_rst_n_o),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  assign s_fault_sticky_d = s_fault_sticky_q || (s_ctrl_q.fault != 0);
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_sticky (
      .clk_i  (ref_clk_o),
      .rst_n_i(ref_rst_n_o),
      .dat_i  (s_fault_sticky_d),
      .dat_o  (s_fault_sticky_q)
  );
  assign current_profile_o = s_ctrl_q.current;
  assign busy_o = s_ctrl_q.state != Idle;
  assign block_o = s_ctrl_q.state != Idle;
  assign fault_o = s_fault_sticky_q;
  assign fault_code_o = s_ctrl_q.fault;
  assign done_o = s_ctrl_q.done;
  assign pll_locked_o = s_pll_lock;
  assign pll_selected_o = s_ctrl_q.fast && HavePll;
  assign xin_hz_o = RefClkHz;
  assign ref_hz_o = 24_000_000;
  assign sys_hz_o = s_ctrl_q.current == 2 ? 32'd192_000_000 :
      s_ctrl_q.current == 3 ? 32'd240_000_000 :
      s_ctrl_q.current == 1 ? 32'(RefClkHz) : 32'd24_000_000;
  assign mem_hz_o = sys_hz_o > 120_000_000 ? sys_hz_o / 2 : sys_hz_o;
  assign pclk_hz_o = sys_hz_o > 120_000_000 ? sys_hz_o / 4 :
      sys_hz_o > 60_000_000 ? sys_hz_o / 2 : sys_hz_o;
`ifndef SYNTHESIS
  initial begin
    if (!(RefClkHz == 24_000_000 || RefClkHz == 48_000_000 || RefClkHz == 96_000_000) ||
        (HavePll && RefClkHz != 24_000_000) || SwitchCycles < 128)
      $fatal(1, "Tiny clock source configuration is invalid");
  end
`endif
endmodule
