// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module tc_opipsram_delay (
    input  logic       data_i,
    input  logic [4:0] fine_i,
    input  logic [2:0] coarse_i,
    output logic       data_o
);

`ifdef PDK_ICS55
  (* keep_hierarchy = "yes" *) (* dont_touch = "true" *)
  logic [ 7:0] s_coarse_tap;
  logic [31:0] s_fine_tap;
  logic [ 7:0] s_coarse_mux;
  logic [31:0] s_fine_mux;

  assign s_coarse_tap[0] = data_i;
  assign s_fine_tap[0]   = s_coarse_mux[6];

  for (genvar coarse_index = 0; coarse_index < 7; coarse_index++) begin : gen_coarse_delay
    DLY4X2H7R u_coarse_delay (
        .A(s_coarse_tap[coarse_index]),
        .Y(s_coarse_tap[coarse_index+1])
    );
  end

  for (genvar fine_index = 0; fine_index < 31; fine_index++) begin : gen_fine_delay
    DLY1X2H7R u_fine_delay (
        .A(s_fine_tap[fine_index]),
        .Y(s_fine_tap[fine_index+1])
    );
  end

  for (genvar coarse_mux_index = 0; coarse_mux_index < 4; coarse_mux_index++) begin : gen_coarse_mux
    MUX2X0P5H7R u_coarse_mux (
        .S0(coarse_i[0]),
        .A (s_coarse_tap[coarse_mux_index*2]),
        .B (s_coarse_tap[(coarse_mux_index*2)+1]),
        .Y (s_coarse_mux[coarse_mux_index])
    );
  end
  for (
      genvar coarse_mux_level_index = 0; coarse_mux_level_index < 2; coarse_mux_level_index++
  ) begin : gen_coarse_mux_level
    MUX2X0P5H7R u_coarse_mux_level (
        .S0(coarse_i[coarse_mux_level_index+1]),
        .A (s_coarse_mux[coarse_mux_level_index*2]),
        .B (s_coarse_mux[(coarse_mux_level_index*2)+1]),
        .Y (s_coarse_mux[coarse_mux_level_index+4])
    );
  end
  MUX2X0P5H7R u_coarse_mux_final (
      .S0(coarse_i[2]),
      .A (s_coarse_mux[4]),
      .B (s_coarse_mux[5]),
      .Y (s_coarse_mux[6])
  );

  for (genvar fine_mux_index = 0; fine_mux_index < 16; fine_mux_index++) begin : gen_fine_mux
    MUX2X0P5H7R u_fine_mux (
        .S0(fine_i[0]),
        .A (s_fine_tap[fine_mux_index*2]),
        .B (s_fine_tap[(fine_mux_index*2)+1]),
        .Y (s_fine_mux[fine_mux_index])
    );
  end
  for (
      genvar fine_mux_level1_index = 0; fine_mux_level1_index < 8; fine_mux_level1_index++
  ) begin : gen_fine_mux_level1
    MUX2X0P5H7R u_fine_mux_level1 (
        .S0(fine_i[1]),
        .A (s_fine_mux[fine_mux_level1_index*2]),
        .B (s_fine_mux[(fine_mux_level1_index*2)+1]),
        .Y (s_fine_mux[fine_mux_level1_index+16])
    );
  end
  for (
      genvar fine_mux_level2_index = 0; fine_mux_level2_index < 4; fine_mux_level2_index++
  ) begin : gen_fine_mux_level2
    MUX2X0P5H7R u_fine_mux_level2 (
        .S0(fine_i[2]),
        .A (s_fine_mux[16+(fine_mux_level2_index*2)]),
        .B (s_fine_mux[17+(fine_mux_level2_index*2)]),
        .Y (s_fine_mux[fine_mux_level2_index+24])
    );
  end
  for (
      genvar fine_mux_level3_index = 0; fine_mux_level3_index < 2; fine_mux_level3_index++
  ) begin : gen_fine_mux_level3
    MUX2X0P5H7R u_fine_mux_level3 (
        .S0(fine_i[3]),
        .A (s_fine_mux[24+(fine_mux_level3_index*2)]),
        .B (s_fine_mux[25+(fine_mux_level3_index*2)]),
        .Y (s_fine_mux[fine_mux_level3_index+28])
    );
  end
  MUX2X0P5H7R u_fine_mux_final (
      .S0(fine_i[4]),
      .A (s_fine_mux[28]),
      .B (s_fine_mux[29]),
      .Y (data_o)
  );
`else
  // Open-source and unqualified PDK paths are intentionally zero-delay. They
  // retain deterministic protocol behavior but do not claim PHY signoff.
  logic unused_delay_taps;
  assign unused_delay_taps = ^{fine_i, coarse_i};
  assign data_o            = data_i;
`endif

endmodule
