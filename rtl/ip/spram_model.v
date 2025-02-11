// 32x4KB=128KB
module spram_model (
    input         clk,
    input  [ 3:0] wen,
    input  [14:0] addr,
    input  [31:0] wdata,
    output [31:0] rdata
);

  wire        s_cs   [31:0];
  wire [31:0] s_rdata[0:31];

  assign s_cs[0] = ~addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[1] = ~addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && addr[10]);
  assign s_cs[2] = ~addr[14] && (~addr[13] && ~addr[12] & addr[11] && ~addr[10]);
  assign s_cs[3] = ~addr[14] && (~addr[13] && ~addr[12] & addr[11] && addr[10]);
  assign s_cs[4] = ~addr[14] && (~addr[13] && addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[5] = ~addr[14] && (~addr[13] && addr[12] & ~addr[11] && addr[10]);
  assign s_cs[6] = ~addr[14] && (~addr[13] && addr[12] & addr[11] && ~addr[10]);
  assign s_cs[7] = ~addr[14] && (~addr[13] && addr[12] & addr[11] && addr[10]);
  assign s_cs[8] = ~addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[9] = ~addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && addr[10]);
  assign s_cs[10] = ~addr[14] && (addr[13] && ~addr[12] & addr[11] && ~addr[10]);
  assign s_cs[11] = ~addr[14] && (addr[13] && ~addr[12] & addr[11] && addr[10]);
  assign s_cs[12] = ~addr[14] && (addr[13] && addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[13] = ~addr[14] && (addr[13] && addr[12] & ~addr[11] && addr[10]);
  assign s_cs[14] = ~addr[14] && (addr[13] && addr[12] & addr[11] && ~addr[10]);
  assign s_cs[15] = ~addr[14] && (addr[13] && addr[12] & addr[11] && addr[10]);
  assign s_cs[16] = addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[17] = addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && addr[10]);
  assign s_cs[18] = addr[14] && (~addr[13] && ~addr[12] & addr[11] && ~addr[10]);
  assign s_cs[19] = addr[14] && (~addr[13] && ~addr[12] & addr[11] && addr[10]);
  assign s_cs[20] = addr[14] && (~addr[13] && addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[21] = addr[14] && (~addr[13] && addr[12] & ~addr[11] && addr[10]);
  assign s_cs[22] = addr[14] && (~addr[13] && addr[12] & addr[11] && ~addr[10]);
  assign s_cs[23] = addr[14] && (~addr[13] && addr[12] & addr[11] && addr[10]);
  assign s_cs[24] = addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[25] = addr[14] && (~addr[13] && ~addr[12] & ~addr[11] && addr[10]);
  assign s_cs[26] = addr[14] && (addr[13] && ~addr[12] & addr[11] && ~addr[10]);
  assign s_cs[27] = addr[14] && (addr[13] && ~addr[12] & addr[11] && addr[10]);
  assign s_cs[28] = addr[14] && (addr[13] && addr[12] & ~addr[11] && ~addr[10]);
  assign s_cs[29] = addr[14] && (addr[13] && addr[12] & ~addr[11] && addr[10]);
  assign s_cs[30] = addr[14] && (addr[13] && addr[12] & addr[11] && ~addr[10]);
  assign s_cs[31] = addr[14] && (addr[13] && addr[12] & addr[11] && addr[10]);

  assign rdata = ({32{s_cs[0]}}  & s_rdata[0])  | ({32{s_cs[1]}}  & s_rdata[1])  |
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

  genvar i;
  generate
    for (i = 0; i < 32; i = i + 1) begin : gen_sram_block
      tc_sram_1024x32 u_ram (
          .clk_i (clk),
          .cs_i  (s_cs[i]),
          .addr_i(addr[9:0]),
          .data_i(wdata),
          .mask_i(wen),
          .wren_i(|wen),
          .data_o(s_rdata[i])
      );
    end
  endgenerate

endmodule
