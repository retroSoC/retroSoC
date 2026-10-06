// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// One SYS clock, separate reset loads. Leaf zero owns the fabric; the remaining
// leaves follow the canonical APB target order. This is not a clock-domain split.
module tiny_reset_tree #(
    parameter int LeafCount = 17
) (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 watchdog_reset_req_i,
    output logic                 por_rst_n_o,
    output logic                 system_rst_n_o,
    output logic [LeafCount-1:0] leaf_rst_n_o,
    output logic                 cpu_ready_rst_n_o
);
  logic s_system_req_n;

  assign s_system_req_n    = por_rst_n_o && !watchdog_reset_req_i;
  // The core/debug wrapper adds its five local release edges after every
  // functional endpoint is ready. No external peripheral clock is a prerequisite.
  assign cpu_ready_rst_n_o = &leaf_rst_n_o;

  rst_sync #(
      .STAGE(5)
  ) u_por_rst_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rst_n_o(por_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_system_rst_sync (
      .clk_i  (clk_i),
      .rst_n_i(s_system_req_n),
      .rst_n_o(system_rst_n_o)
  );
  for (genvar leaf = 0; leaf < LeafCount; leaf++) begin : gen_leaf
    // Preserve independent reset drivers through the existing Yosys flow.
    // P2 validates the mapped drivers and loads; this is not a timing exception.
    (* keep = 1, keep_hierarchy = 1 *)
    rst_sync #(
        .STAGE(5)
    ) u_leaf_rst_sync (
        .clk_i  (clk_i),
        .rst_n_i(system_rst_n_o),
        .rst_n_o(leaf_rst_n_o[leaf])
    );
  end
endmodule
