// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// spisd is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//

module spisd_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        rd_req_i,
    output logic        rd_vld_o,
    output logic [ 7:0] rd_data_o,
    input  logic        wr_req_i,
    output logic        wr_byte_done_o,
    input  logic [ 7:0] wr_data_i,
    input  logic [22:0] addr_i,
    output logic        init_done_o,
    output logic        spisd_sclk_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

  localparam CMD0 = 8'h40;  // GO_IDLE_STATE
  localparam CMD8 = 8'h48;  // SEND_IF_COND
  localparam CMD17 = 8'h51;  // READ_SINGLE_BLOCK
  localparam CMD24 = 8'h58;  // WRITE_BLOCK
  localparam CMD55 = 8'h77;  // APP_CMD
  localparam CMD58 = 8'h7A;  // READ_OCR
  localparam ACMD41 = 8'h69;  // SD_SEND_OP_COND

  localparam FSM_RST = 5'd0;
  localparam FSM_RST2CMD0 = 5'd1;
  localparam FSM_CMD0 = 5'd2;
  localparam FSM_CMD8 = 5'd3;
  localparam FSM_CMD55 = 5'd4;
  localparam FSM_ACMD41 = 5'd5;
  localparam FSM_CHECK_INIT = 5'd6;
  localparam FSM_CMD58 = 5'd7;
  localparam FSM_IDLE = 5'd8;

  localparam FSM_SEND_CMD = 5'd9;
  localparam FSM_RESP_WAIT = 5'd10;
  localparam FSM_RESP_DATA = 5'd11;

  localparam FSM_READ_CMD = 5'd12;
  localparam FSM_READ_WAIT = 5'd13;
  localparam FSM_READ_DATA = 5'd14;
  localparam FSM_READ_CRC = 5'd15;

  localparam FSM_WRITE_CMD = 5'd16;
  localparam FSM_WRITE_INIT = 5'd17;
  localparam FSM_WRITE_DATA = 5'd18;
  localparam FSM_WRITE_BYTE = 5'd19;
  localparam FSM_WRITE_WAIT = 5'd20;
  localparam FSM_XFER_DONE = 5'd21;

  // 100M / 200K = 500
  // spi signal
  logic s_spisd_sclk_d, s_spisd_sclk_q;
  logic s_spisd_cs_d, s_spisd_cs_q;
  logic [4:0] s_fsm_d, s_fsm_q;
  logic [4:0] s_ret_fsm_d, s_ret_fsm_q;
  logic [7:0] s_boot_cnt_d, s_boot_cnt_q;  // 256 cycle
  logic [9:0] s_byte_cnt_d, s_byte_cnt_q;
  logic [5:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [7:0] s_clk_cnt_d, s_clk_cnt_q;  // 256
  logic [47:0] s_xfer_cmd_d, s_xfer_cmd_q;
  logic [1:0] s_resp_type_d, s_resp_type_q;
  logic [39:0] s_recv_data_d, s_recv_data_q;
  logic [7:0] s_send_data_d, s_send_data_q;
  logic s_first_fall_edge_d, s_first_fall_edge_q;
  logic s_cmd_mode;
  // user reg
  logic [1:0] s_clk_div_d, s_clk_div_q;

  assign init_done_o  = s_fsm_q == FSM_IDLE;
  assign spisd_sclk_o = s_spisd_sclk_q;
  assign spisd_cs_o   = s_spisd_cs_q;
  assign spisd_mosi_o = s_cmd_mode ? s_xfer_cmd_q[47] : s_send_data_q[7];

  always_comb begin
    s_fsm_d             = s_fsm_q;
    s_ret_fsm_d         = s_ret_fsm_q;
    s_boot_cnt_d        = s_boot_cnt_q;
    s_byte_cnt_d        = s_byte_cnt_q;
    s_bit_cnt_d         = s_bit_cnt_q;
    s_clk_cnt_d         = s_clk_cnt_q;
    s_xfer_cmd_d        = s_xfer_cmd_q;
    s_resp_type_d       = s_resp_type_q;
    s_recv_data_d       = s_recv_data_q;
    s_send_data_d       = s_send_data_q;
    s_first_fall_edge_d = s_first_fall_edge_q;
    // spi_if
    s_spisd_sclk_d      = s_spisd_sclk_q;
    s_spisd_cs_d        = s_spisd_cs_q;
    rd_vld_o            = '0;
    rd_data_o           = '0;
    wr_byte_done_o      = '0;
    s_cmd_mode          = '1;
    // user reg
    s_clk_div_d         = s_clk_div_q;
    unique case (s_fsm_q)
      FSM_RST: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = '1;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
          s_boot_cnt_d   = s_boot_cnt_q - 1'b1;
          if (s_boot_cnt_q == '0) begin
            s_boot_cnt_d = '1;
            s_fsm_d      = FSM_RST2CMD0;
          end
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end
      end
      // wait some cycles before operating
      FSM_RST2CMD0: begin
        if (s_boot_cnt_q == '0) s_fsm_d = FSM_CMD0;
        else s_boot_cnt_d = s_boot_cnt_q - 1'b1;
      end
      FSM_CMD0: begin
        s_xfer_cmd_d        = {CMD0, 32'h0, 8'h95};
        s_resp_type_d       = 2'd0;
        s_ret_fsm_d         = FSM_CMD8;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
      end
      FSM_CMD8: begin
        s_xfer_cmd_d        = {CMD8, 20'h0, 4'h1, 8'hAA, 8'h87};
        s_resp_type_d       = 2'd2;
        s_ret_fsm_d         = FSM_CMD55;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
      end
      FSM_CMD55: begin  // maybe crc can be set 0xFF?
        s_xfer_cmd_d        = {CMD55, 32'h0, 8'h65};
        s_resp_type_d       = 2'd0;
        s_ret_fsm_d         = FSM_ACMD41;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
      end
      FSM_ACMD41: begin
        s_xfer_cmd_d        = {ACMD41, 1'h1, 3'h0, 4'h1, 24'h0, 8'hFF};
        s_resp_type_d       = 2'd1;
        s_ret_fsm_d         = FSM_CHECK_INIT;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
      end
      FSM_CHECK_INIT: begin
        if (s_recv_data_q[0] == 1'b0) s_fsm_d = FSM_CMD58;
        else s_fsm_d = FSM_CMD55;
      end
      FSM_CMD58: begin
        s_xfer_cmd_d        = {CMD58, 32'h0, 8'hFF};
        s_resp_type_d       = 2'd1;
        s_ret_fsm_d         = FSM_IDLE;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
      end
      FSM_IDLE: begin
        if (rd_req_i) s_fsm_d = FSM_READ_CMD;
        else if (wr_req_i) s_fsm_d = FSM_WRITE_CMD;
      end
      FSM_READ_CMD: begin
        s_xfer_cmd_d        = {CMD17, addr_i, 8'hFF};
        s_resp_type_d       = 2'd1;
        s_ret_fsm_d         = FSM_READ_WAIT;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
      end
      FSM_READ_WAIT: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          if (spisd_miso_i == 1'b0) begin
            s_byte_cnt_d = 9'd511;
            s_bit_cnt_d  = 6'd7;
            s_ret_fsm_d  = FSM_READ_DATA;
            s_fsm_d      = FSM_RESP_DATA;
          end
        end
      end
      FSM_READ_DATA: begin
        rd_vld_o  = 1'b1;
        rd_data_o = s_recv_data_q[7:0];
        if (s_byte_cnt_q == '0) begin
          s_bit_cnt_d = 6'd7;
          s_ret_fsm_d = FSM_READ_CRC;
          s_fsm_d     = FSM_RESP_DATA;  // rd the last data
        end else begin
          s_byte_cnt_d = s_byte_cnt_q - 1'b1;
          s_bit_cnt_d  = 6'd7;
          s_ret_fsm_d  = FSM_READ_DATA;
          s_fsm_d      = FSM_RESP_DATA;
        end
      end
      FSM_READ_CRC: begin
        s_bit_cnt_d = 6'd7;
        s_ret_fsm_d = FSM_IDLE;
        s_fsm_d     = FSM_RESP_DATA;
      end
      FSM_WRITE_CMD: begin
        s_xfer_cmd_d        = {CMD24, addr_i, 8'hFF};
        s_resp_type_d       = 2'd1;
        s_ret_fsm_d         = FSM_WRITE_WAIT;
        s_fsm_d             = FSM_SEND_CMD;
        s_clk_cnt_d         = s_clk_div_q;
        s_bit_cnt_d         = 6'd48;
        s_first_fall_edge_d = 1'b1;
        s_spisd_cs_d        = 1'b0;
        wr_byte_done_o      = 1'b1;
      end
      FSM_WRITE_INIT: begin
        s_cmd_mode   = 1'b0;
        s_byte_cnt_d = 10'd515;
        s_fsm_d      = FSM_WRITE_DATA;
      end
      FSM_WRITE_DATA: begin
        s_cmd_mode = 1'b0;
        if (s_byte_cnt_q == '0) begin
          s_ret_fsm_d = FSM_WRITE_WAIT;
          s_fsm_d     = FSM_RESP_WAIT;
        end else begin
          s_byte_cnt_d = s_byte_cnt_q - 1'b1;
          s_bit_cnt_d  = 6'd7;
          s_fsm_d      = FSM_WRITE_BYTE;
          if ((s_byte_cnt_q == 10'd2) || (s_byte_cnt_q == 10'd1)) begin
            s_send_data_d = 8'hFF;
          end else if (s_byte_cnt_q == 10'd515) begin
            s_send_data_d = 8'hFE;
          end else begin
            s_send_data_d     = wr_data_i;  // HACK:
            wr_byte_done_o = 1'b1;
          end
        end
      end
      FSM_WRITE_BYTE: begin
        s_cmd_mode = 1'b0;
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          if (s_bit_cnt_q == '0) begin
            s_fsm_d = FSM_WRITE_DATA;
          end else begin
            s_send_data_d = {s_send_data_q[6:0], 1'b1};
            s_bit_cnt_d   = s_bit_cnt_q - 1'b1;
          end
        end
      end
      FSM_WRITE_WAIT: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          if (spisd_miso_i == 1'b1) begin
            s_fsm_d = FSM_IDLE;
          end
        end
      end
      FSM_SEND_CMD: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          if (s_bit_cnt_q == '0) begin
            s_fsm_d = FSM_RESP_WAIT;
          end else begin
            s_bit_cnt_d = s_bit_cnt_q - 1'b1;
            if (s_first_fall_edge_q) begin
              s_first_fall_edge_d = 1'b0;
            end else begin
              s_xfer_cmd_d = {s_xfer_cmd_q[46:0], 1'b1};
            end
          end
        end
      end
      FSM_RESP_WAIT: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          if (spisd_miso_i == 1'b0) begin
            s_recv_data_d = '0;
            unique case (s_resp_type_q)
              2'd0:    s_bit_cnt_d = 6'd6;
              2'd1:    s_bit_cnt_d = 6'd38;
              2'd2:    s_bit_cnt_d = 6'd38;
              default: s_bit_cnt_d = 6'd6;
            endcase
            s_fsm_d = FSM_RESP_DATA;
          end
        end
      end
      FSM_RESP_DATA: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          s_recv_data_d = {s_recv_data_q[38:0], spisd_miso_i};
          if (s_bit_cnt_q == '0) begin
            s_fsm_d      = FSM_XFER_DONE;
            s_bit_cnt_d  = 6'd23;
            s_spisd_cs_d = 1'b1;
          end else begin
            s_bit_cnt_d = s_bit_cnt_q - 1'b1;
          end
        end
      end
      FSM_XFER_DONE: begin
        if (s_clk_cnt_q == '0) begin
          s_clk_cnt_d    = s_clk_div_q;
          s_spisd_sclk_d = ~s_spisd_sclk_q;
        end else begin
          s_clk_cnt_d = s_clk_cnt_q - 1'b1;
        end

        if (s_spisd_sclk_q && s_clk_cnt_q == '0) begin
          if (s_bit_cnt_q == '0) begin
            s_fsm_d = s_ret_fsm_q;
          end else begin
            s_bit_cnt_d = s_bit_cnt_q - 1'b1;
          end
        end
      end
      default: begin
      end
    endcase
  end
  dffr #(5) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  dffr #(5) u_ret_fsm_dffr (
      clk_i,
      rst_n_i,
      s_ret_fsm_d,
      s_ret_fsm_q
  );

  dffrh #(8) u_boot_cnt_dffrh (
      clk_i,
      rst_n_i,
      s_boot_cnt_d,
      s_boot_cnt_q
  );


  dffrh #(10) u_byte_cnt_dffrh (
      clk_i,
      rst_n_i,
      s_byte_cnt_d,
      s_byte_cnt_q
  );

  dffrh #(6) u_bit_cnt_dffrh (
      clk_i,
      rst_n_i,
      s_bit_cnt_d,
      s_bit_cnt_q
  );

  dffrh #(8) u_clk_cnt_dffrh (
      clk_i,
      rst_n_i,
      s_clk_cnt_d,
      s_clk_cnt_q
  );

  dffrh #(1) u_spisd_sclk_dffrh (
      clk_i,
      rst_n_i,
      s_spisd_sclk_d,
      s_spisd_sclk_q
  );

  dffrh #(1) u_spisd_cs_dffrh (
      clk_i,
      rst_n_i,
      s_spisd_cs_d,
      s_spisd_cs_q
  );

  dffrh #(48) u_xfer_cmd_dffrh (
      clk_i,
      rst_n_i,
      s_xfer_cmd_d,
      s_xfer_cmd_q
  );

  dffr #(2) u_resp_data_dffr (
      clk_i,
      rst_n_i,
      s_resp_type_d,
      s_resp_type_q
  );

  dffr #(40) u_recv_data_dffr (
      clk_i,
      rst_n_i,
      s_recv_data_d,
      s_recv_data_q
  );

  dffr #(8) u_send_data_dffr (
      clk_i,
      rst_n_i,
      s_send_data_d,
      s_send_data_q
  );

  dffrh #(2) u_clk_div_dffrh (
      clk_i,
      rst_n_i,
      s_clk_div_d,
      s_clk_div_q
  );

  dffrh #(1) u_first_fall_edge_dffrh (
      clk_i,
      rst_n_i,
      s_first_fall_edge_d,
      s_first_fall_edge_q
  );
endmodule
