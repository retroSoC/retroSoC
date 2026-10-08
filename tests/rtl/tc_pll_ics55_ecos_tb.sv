`timescale 1ns / 1ps
module tc_pll_ics55_ecos_tb;
  logic       s_ref = 0;
  logic       s_reset_n = 0;
  logic [2:0] s_selection = 0;
  logic       s_apply = 0;
  wire s_capable, s_locked, s_clock;
  integer s_edges = 0;
  tc_pll #(
      .UseIcs55EcosPll(1'b1)
  ) u_dut (
      .fref_i       (s_ref),
      .rst_n_i      (s_reset_n),
      .cfg_sel_i    (s_selection),
      .cfg_apply_i  (s_apply),
      .pll_capable_o(s_capable),
      .pll_lock_o   (s_locked),
      .pll_clk_o    (s_clock)
  );
  always #20.833333 s_ref = ~s_ref;
  always @(posedge s_clock) s_edges++;

  task automatic cycle(input integer count);
    repeat (count) @(negedge s_ref);
  endtask
  task automatic configure(input logic [2:0] selection);
    @(negedge s_ref);
    s_selection = selection;
    s_apply     = 1;
    cycle(1);
    s_apply = 0;
  endtask
  task automatic await_lock;
    integer waited;
    waited = 0;
    while (!s_locked && waited < 2000) begin
      cycle(1);
      waited++;
    end
    if (!s_locked || !s_capable) $fatal(1, "PLL did not qualify");
  endtask
  task automatic measure(input integer multiplier);
    integer before_edges;
    before_edges = s_edges;
    cycle(128);
    if (s_edges-before_edges < multiplier*128-2 ||
        s_edges-before_edges > multiplier*128+2)
      $fatal(1, "wrong measured PLL rate");
  endtask
  initial begin
    cycle(2);
    s_reset_n = 1;
    cycle(8);
    if (s_locked || s_clock) $fatal(1, "unrequested PLL started");
    configure(5);
    cycle(510);
    if (s_locked) $fatal(1, "early lock without clock observations");
    await_lock();
    measure(8);
    configure(7);
    cycle(1);
    if (s_locked) $fatal(1, "reconfiguration retained stale lock");
    await_lock();
    measure(10);
    // A held APPLY is one command, not an endless restart.
    @(negedge s_ref);
    s_selection = 5;
    s_apply     = 1;
    cycle(1);
    await_lock();
    measure(8);
    s_apply = 0;
    force u_dut.gen_ecos.u_backend.u_PLL_TOP.N = 8'd40;
    cycle(136);
    if (s_locked) $fatal(1, "wrong-frequency output retained lock");
    release u_dut.gen_ecos.u_backend.u_PLL_TOP.N;
    await_lock();
    measure(8);
    // Stop both polarities. No internal model-ready signal is consulted.
    force u_dut.gen_ecos.u_backend.pll_clk_o = 1'b0;
    cycle(136);
    if (s_locked) $fatal(1, "stopped-low output retained lock");
    release u_dut.gen_ecos.u_backend.pll_clk_o;
    await_lock();
    force u_dut.gen_ecos.u_backend.pll_clk_o = 1'b1;
    cycle(136);
    if (s_locked) $fatal(1, "stopped-high output retained lock");
    cycle(4100);
    if (u_dut.gen_ecos.u_backend.u_PLL_TOP.EN) $fatal(1, "acquisition timeout left PLL enabled");
    release u_dut.gen_ecos.u_backend.pll_clk_o;
    configure(7);
    await_lock();
    measure(10);
    configure(0);
    cycle(1500);
    if (s_locked || u_dut.gen_ecos.u_backend.u_PLL_TOP.EN) $fatal(1, "invalid selection accepted");
    configure(5);
    await_lock();
    @(negedge s_ref);
    s_reset_n = 0;
    #1;
    if (s_locked) $fatal(1, "reset retained lock");
    cycle(10);
    s_reset_n = 1;
    cycle(20);
    if (s_locked) $fatal(1, "reset replayed old configuration");
    $display("SIM_TEST_PASS ICS55 PLL backend");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "SIM_TEST_TIMEOUT PLL backend");
  end
endmodule
