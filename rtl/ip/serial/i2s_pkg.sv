// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "i2s_define.svh"

package i2s_pkg;
  typedef enum logic [1:0] {
    I2S_PRESET_16B_48K = 2'd0,
    I2S_PRESET_16B_96K = 2'd1,
    I2S_PRESET_24B_48K = 2'd2,
    I2S_PRESET_24B_96K = 2'd3
  } i2s_preset_e;

  function automatic logic [7:0] i2s_preset_sclk_div(input logic [1:0] preset_i);
    unique case (preset_i)
      `I2S_16b_48K: return 8'd5;
      `I2S_16b_96K: return 8'd2;
      `I2S_24b_48K: return 8'd3;
      default:      return 8'd1;
    endcase
  endfunction

  function automatic logic [7:0] i2s_preset_lrck_div(input logic [1:0] preset_i);
    unique case (preset_i)
      `I2S_16b_48K, `I2S_16b_96K: return 8'd15;
      default:                    return 8'd23;
    endcase
  endfunction

  function automatic logic i2s_preset_bitmode(input logic [1:0] preset_i);
    unique case (preset_i)
      `I2S_16b_48K, `I2S_16b_96K: return 1'b0;
      default:                    return 1'b1;
    endcase
  endfunction
endpackage
