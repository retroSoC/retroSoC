// 32x4KB=128KB
module onchip_ram (
    input  logic        clk_i,
    input  logic [14:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [ 3:0] wstrb_i,
    output logic [31:0] rdata_o
);

  logic        s_cs   [31:0];
  logic [31:0] s_rdata[0:31];

  assign s_cs[0] = ~addr_i[14] && ~addr_i[13] && ~addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[1] = ~addr_i[14] && ~addr_i[13] && ~addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[2] = ~addr_i[14] && ~addr_i[13] && ~addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[3] = ~addr_i[14] && ~addr_i[13] && ~addr_i[12] & addr_i[11] && addr_i[10];
  assign s_cs[4] = ~addr_i[14] && ~addr_i[13] && addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[5] = ~addr_i[14] && ~addr_i[13] && addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[6] = ~addr_i[14] && ~addr_i[13] && addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[7] = ~addr_i[14] && ~addr_i[13] && addr_i[12] & addr_i[11] && addr_i[10];
  assign s_cs[8] = ~addr_i[14] && addr_i[13] && ~addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[9] = ~addr_i[14] && addr_i[13] && ~addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[10] = ~addr_i[14] && addr_i[13] && ~addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[11] = ~addr_i[14] && addr_i[13] && ~addr_i[12] & addr_i[11] && addr_i[10];
  assign s_cs[12] = ~addr_i[14] && addr_i[13] && addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[13] = ~addr_i[14] && addr_i[13] && addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[14] = ~addr_i[14] && addr_i[13] && addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[15] = ~addr_i[14] && addr_i[13] && addr_i[12] & addr_i[11] && addr_i[10];

  assign s_cs[16] = addr_i[14] && ~addr_i[13] && ~addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[17] = addr_i[14] && ~addr_i[13] && ~addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[18] = addr_i[14] && ~addr_i[13] && ~addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[19] = addr_i[14] && ~addr_i[13] && ~addr_i[12] & addr_i[11] && addr_i[10];
  assign s_cs[20] = addr_i[14] && ~addr_i[13] && addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[21] = addr_i[14] && ~addr_i[13] && addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[22] = addr_i[14] && ~addr_i[13] && addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[23] = addr_i[14] && ~addr_i[13] && addr_i[12] & addr_i[11] && addr_i[10];
  assign s_cs[24] = addr_i[14] && addr_i[13] && ~addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[25] = addr_i[14] && addr_i[13] && ~addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[26] = addr_i[14] && addr_i[13] && ~addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[27] = addr_i[14] && addr_i[13] && ~addr_i[12] & addr_i[11] && addr_i[10];
  assign s_cs[28] = addr_i[14] && addr_i[13] && addr_i[12] & ~addr_i[11] && ~addr_i[10];
  assign s_cs[29] = addr_i[14] && addr_i[13] && addr_i[12] & ~addr_i[11] && addr_i[10];
  assign s_cs[30] = addr_i[14] && addr_i[13] && addr_i[12] & addr_i[11] && ~addr_i[10];
  assign s_cs[31] = addr_i[14] && addr_i[13] && addr_i[12] & addr_i[11] && addr_i[10];

  assign rdata_o = ({32{s_cs[0]}}  & s_rdata[0])  | ({32{s_cs[1]}}  & s_rdata[1])  |
                 ({32{s_cs[2]}}  & s_rdata[2])  | ({32{s_cs[3]}}  & s_rdata[3])  |
                 ({32{s_cs[4]}}  & s_rdata[4])  | ({32{s_cs[5]}}  & s_rdata[5])  |
                 ({32{s_cs[6]}}  & s_rdata[6])  | ({32{s_cs[7]}}  & s_rdata[7])  |
                 ({32{s_cs[8]}}  & s_rdata[8])  | ({32{s_cs[9]}}  & s_rdata[9])  |
                 ({32{s_cs[10]}} & s_rdata[10]) | ({32{s_cs[11]}} & s_rdata[11]) |
                 ({32{s_cs[12]}} & s_rdata[12]) | ({32{s_cs[13]}} & s_rdata[13]) |
                 ({32{s_cs[14]}} & s_rdata[14]) | ({32{s_cs[15]}} & s_rdata[15]) |
                 ({32{s_cs[16]}} & s_rdata[16]) | ({32{s_cs[17]}} & s_rdata[17]) |
                 ({32{s_cs[18]}} & s_rdata[18]) | ({32{s_cs[19]}} & s_rdata[19]) |
                 ({32{s_cs[20]}} & s_rdata[20]) | ({32{s_cs[21]}} & s_rdata[21]) |
                 ({32{s_cs[22]}} & s_rdata[22]) | ({32{s_cs[23]}} & s_rdata[23]) |
                 ({32{s_cs[24]}} & s_rdata[24]) | ({32{s_cs[25]}} & s_rdata[25]) |
                 ({32{s_cs[26]}} & s_rdata[26]) | ({32{s_cs[27]}} & s_rdata[27]) |
                 ({32{s_cs[28]}} & s_rdata[28]) | ({32{s_cs[29]}} & s_rdata[29]) |
                 ({32{s_cs[30]}} & s_rdata[30]) | ({32{s_cs[31]}} & s_rdata[31]);

  for (genvar i = 0; i < 32; ++i) begin : gen_sram_block
    tc_sram_1024x32 u_ram (
        .clk_i (clk_i),
        .cs_i  (s_cs[i]),
        .addr_i(addr_i[9:0]),
        .data_i(wdata_i),
        .mask_i(wstrb_i),
        .wren_i(|wstrb_i),
        .data_o(s_rdata[i])
    );
  end

endmodule
