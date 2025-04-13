// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// uart is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module rs232 #(
    parameter BAUD_RATE = 115200,
    parameter LOOPBACK  = 0
) (
    input  rs232_rx_i,
    output reg rs232_tx_o
);

  // unit: ns
  localparam DELAY_TIME = (10_0000_0000 / BAUD_RATE);
  reg [7:0] data;

  initial begin
    rs232_tx_o = 1'b1;
  end
  always @(negedge rs232_rx_i) begin
    receive(data);
    $write("%c", data);
    if (LOOPBACK) send(data);
  end

  task receive(output [7:0] value);
    begin : RECV_BLOCK
      integer i;
      value = 8'd0;
      #(DELAY_TIME * 1.5);
      for (i = 0; i < 8; i = i + 1) begin
        value[i] = rs232_rx_i;
        #(DELAY_TIME);
      end
    end
  endtask

  task send(input [7:0] value);
    begin : SEND_BLOCK
      integer i;
      rs232_tx_o = 1'b0;
      #(DELAY_TIME);
      for (i = 0; i < 8; i = i + 1) begin
        rs232_tx_o = value[i];
        #(DELAY_TIME);
      end
      rs232_tx_o = 1'b1;
      #(DELAY_TIME);
    end
  endtask
endmodule
