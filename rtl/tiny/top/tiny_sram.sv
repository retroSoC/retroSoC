// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

module tiny_sram (
    input logic                   clk_i,
    input logic                   rst_n_i,
    input logic                   perf_enable_i,
    input logic                   perf_clear_i,
          tiny_sram_port_if.slave local_ports   [2],
          axi4_if.slave           external_ports[4],
          apb4_if.slave           cfg_apb4
);
  logic [3:0] s_local_ready[2], s_local_valid[2];
  logic [31:0] s_local_data[2] [4];
  logic [ 3:0] s_events    [6];
  logic [31:0] s_count_d[6], s_count_q[6];
  logic [ 2:0] s_increment[6];
  logic [32:0] s_sum      [6];

  for (genvar group = 0; group < 4; group++) begin : gen_group
    tiny_sram_port_if u_ports[3] ();
    for (genvar client = 0; client < 2; client++) begin : gen_local
      assign u_ports[client].req_valid = local_ports[client].req_valid &&
          (local_ports[client].addr[16:15] == 2'(group));
      assign u_ports[client].addr = local_ports[client].addr;
      assign u_ports[client].write = local_ports[client].write;
      assign u_ports[client].wdata = local_ports[client].wdata;
      assign u_ports[client].wstrb = local_ports[client].wstrb;
      assign u_ports[client].rsp_ready = local_ports[client].rsp_ready &&
          (local_ports[client].addr[16:15] == 2'(group));
      assign s_local_ready[client][group] = u_ports[client].req_ready;
      assign s_local_valid[client][group] = u_ports[client].rsp_valid;
      assign s_local_data[client][group] = u_ports[client].rdata;
    end
    tiny_sram_group u_group (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .ports  (u_ports)
    );
    tiny_sram_axi4 #(
        .GroupBase(32'h3000_0000 + 32'(group) * 32'h8000)
    ) u_external (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .axi4   (external_ports[group]),
        .memory (u_ports[2])
    );
    assign s_events[0][group] = external_ports[group].arvalid && external_ports[group].arready;
    assign s_events[1][group] = external_ports[group].awvalid && external_ports[group].awready;
    assign s_events[2][group] = external_ports[group].rvalid && external_ports[group].rready;
    assign s_events[3][group] = external_ports[group].wvalid && external_ports[group].wready;
    assign s_events[4][group] =
        (external_ports[group].arvalid && !external_ports[group].arready) ||
        (external_ports[group].awvalid && !external_ports[group].awready) ||
        (external_ports[group].wvalid && !external_ports[group].wready) ||
        (external_ports[group].rvalid && !external_ports[group].rready) ||
        (external_ports[group].bvalid && !external_ports[group].bready);
    assign s_events[5][group] =
        (external_ports[group].bvalid && external_ports[group].bready &&
         (external_ports[group].bresp != 2'b00)) ||
        (external_ports[group].rvalid && external_ports[group].rready &&
         external_ports[group].rlast && (external_ports[group].rresp != 2'b00));
  end
  for (genvar client = 0; client < 2; client++) begin : gen_local_response
    assign local_ports[client].req_ready = s_local_ready[client][local_ports[client].addr[16:15]];
    assign local_ports[client].rsp_valid = s_local_valid[client][local_ports[client].addr[16:15]];
    assign local_ports[client].rdata     = s_local_data[client][local_ports[client].addr[16:15]];
  end
  // Preserve the public external-AXI counter meanings. Four simultaneous stalls
  // are one stalled cycle; request/beat events are counted individually.
  for (genvar counter = 0; counter < 6; counter++) begin : gen_counter
    if (counter == 4) begin : gen_cycle_count
      assign s_increment[counter] = {2'b0, |s_events[counter]};
    end else begin : gen_event_count
      assign s_increment[counter] = {2'b0, s_events[counter][0]} +
          {2'b0, s_events[counter][1]} + {2'b0, s_events[counter][2]} +
          {2'b0, s_events[counter][3]};
    end
    assign s_sum[counter] = {1'b0, s_count_q[counter]} + {30'd0, s_increment[counter]};
    assign s_count_d[counter] = perf_clear_i ? 32'd0 :
        perf_enable_i ? (s_sum[counter][32] ? 32'hffff_ffff : s_sum[counter][31:0]) :
        s_count_q[counter];
    dffr #(
        .DATA_WIDTH(32)
    ) u_counter (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_count_d[counter]),
        .dat_o  (s_count_q[counter])
    );
  end
  onchip_ram_reg #(
      .Present    (1'b1),
      .CapacityKiB(128),
      .DataBytes  (4)
  ) u_reg (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .apb4                  (cfg_apb4),
      .perf_read_requests_i  (s_count_q[0]),
      .perf_write_requests_i (s_count_q[1]),
      .perf_read_beats_i     (s_count_q[2]),
      .perf_write_beats_i    (s_count_q[3]),
      .perf_stall_cycles_i   (s_count_q[4]),
      .perf_error_responses_i(s_count_q[5])
  );
endmodule
