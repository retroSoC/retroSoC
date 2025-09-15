module i2c_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 6:0] clk_div_i,
    input  logic [ 6:0] dev_addr_i,
    input  logic        wr_en_i,
    input  logic        rd_en_i,
    input  logic        start_i,
    output logic        end_o,
    input  logic        extn_addr_i,
    input  logic [15:0] reg_addr_i,
    input  logic [ 7:0] wr_data_i,
    output logic [ 7:0] rd_data_o,
    output logic        oper_clk_pos_o,
    output logic        oper_clk_fall_o,
    output logic        scl_o,
    output logic        sda_oe_o,
    output logic        sda_o,
    input  logic        sda_i
);

  localparam FSM_IDLE = 4'd0;
  localparam FSM_START_F = 4'd1;
  localparam FSM_SEND_DEV_ADDR = 4'd2;
  localparam FSM_ACK_1 = 4'd3;
  localparam FSM_SEND_REG_ADDR_H = 4'd4;
  localparam FSM_ACK_2 = 4'd5;
  localparam FSM_SEND_REG_ADDR_L = 4'd6;
  localparam FSM_ACK_3 = 4'd7;
  localparam FSM_WR_DATA = 4'd8;
  localparam FSM_ACK_4 = 4'd9;
  localparam FSM_START_S = 4'd10;
  localparam FSM_SEND_RD_ADDR = 4'd11;
  localparam FSM_ACK_5 = 4'd12;
  localparam FSM_RD_DATA = 4'd13;
  localparam FSM_N_ACK = 4'd14;
  localparam FSM_STOP = 4'd15;

  logic s_ack;
  // oper clk: i2c clk = 4:1
  logic [6:0] s_oper_clk_cnt_d, s_oper_clk_cnt_q;
  logic s_oper_clk_d, s_oper_clk_q;
  logic s_oper_clk_pos, s_oper_clk_fall;
  logic s_i2c_clk_en_d, s_i2c_clk_en_q;
  logic [1:0] s_i2c_clk_cnt_d, s_i2c_clk_cnt_q;
  logic [2:0] s_xfer_bit_cnt_d, s_xfer_bit_cnt_q;
  logic [3:0] s_fsm_d, s_fsm_q;
  logic s_i2c_sda_out;
  logic [7:0] s_i2c_data_in_d, s_i2c_data_in_q;
  logic s_xfer_end_d, s_xfer_end_q;


  assign s_oper_clk_pos  = (~s_oper_clk_q) & (s_oper_clk_cnt_q == clk_div_i);
  assign s_oper_clk_fall = s_oper_clk_q & (s_oper_clk_cnt_q == clk_div_i);
  assign oper_clk_pos_o  = s_oper_clk_pos;
  assign oper_clk_fall_o = s_oper_clk_fall;
  assign end_o           = s_xfer_end_q;
  assign rd_data_o       = s_i2c_data_in_q;

  // verilog_format: off
  assign sda_o    = s_i2c_sda_out;
  assign sda_oe_o = ((s_fsm_q == FSM_RD_DATA) || (s_fsm_q == FSM_ACK_1) || (s_fsm_q == FSM_ACK_2)
                  || (s_fsm_q == FSM_ACK_3)   || (s_fsm_q == FSM_ACK_4) || (s_fsm_q == FSM_ACK_5))
                  ? 1'b0 : 1'b1;
  // verilog_format: on


  always_comb begin
    s_oper_clk_cnt_d = s_oper_clk_cnt_q;
    s_oper_clk_d     = s_oper_clk_q;
    if (s_oper_clk_cnt_q == clk_div_i) begin
      s_oper_clk_cnt_d = '0;
      s_oper_clk_d     = ~s_oper_clk_q;
    end else begin
      s_oper_clk_cnt_d = s_oper_clk_cnt_q + 1'b1;
    end
  end
  dffr #(7) u_oper_clk_cnt_dffr (
      clk_i,
      rst_n_i,
      s_oper_clk_cnt_d,
      s_oper_clk_cnt_q
  );
  dffrh #(1) u_oper_clk_dffrh (
      clk_i,
      rst_n_i,
      s_oper_clk_d,
      s_oper_clk_q
  );


  always_comb begin
    s_i2c_clk_en_d = s_i2c_clk_en_q;
    if (start_i) s_i2c_clk_en_d = 1'b1;
    else if ((s_fsm_q == FSM_STOP) && (s_xfer_bit_cnt_q == 3'd3) && (s_i2c_clk_cnt_q == 2'd3)) begin
      s_i2c_clk_en_d = 1'b0;
    end
  end
  dffer #(1) u_i2c_clk_en_dffer (
      clk_i,
      rst_n_i,
      s_oper_clk_pos,
      s_i2c_clk_en_d,
      s_i2c_clk_en_q
  );

  assign s_i2c_clk_cnt_d = s_i2c_clk_en_q ? s_i2c_clk_cnt_q + 1'b1 : s_i2c_clk_cnt_q;
  dffer #(2) u_i2c_clk_cnt_dffer (
      clk_i,
      rst_n_i,
      s_oper_clk_pos,
      s_i2c_clk_cnt_d,
      s_i2c_clk_cnt_q
  );


  always_comb begin
    s_xfer_bit_cnt_d = s_xfer_bit_cnt_q;
    if((s_fsm_q == FSM_IDLE) || (s_fsm_q == FSM_START_F) || (s_fsm_q == FSM_START_S)
    || (s_fsm_q == FSM_ACK_1) || (s_fsm_q == FSM_ACK_2) || (s_fsm_q == FSM_ACK_3)
    || (s_fsm_q == FSM_ACK_4) || (s_fsm_q == FSM_ACK_5) || (s_fsm_q == FSM_N_ACK)) begin
      s_xfer_bit_cnt_d = '0;
    end else if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
      s_xfer_bit_cnt_d = '0;
    end else if ((s_i2c_clk_cnt_q == 2'd3) && (s_fsm_q != FSM_IDLE)) begin
      s_xfer_bit_cnt_d = s_xfer_bit_cnt_q + 1'b1;
    end
  end
  dffer #(3) u_xfer_bit_cnt_dffer (
      clk_i,
      rst_n_i,
      s_oper_clk_pos,
      s_xfer_bit_cnt_d,
      s_xfer_bit_cnt_q
  );


  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (start_i == 1'b1) s_fsm_d = FSM_START_F;
      end
      FSM_START_F: begin
        if (s_i2c_clk_cnt_q == 2'd3) s_fsm_d = FSM_SEND_DEV_ADDR;
      end
      FSM_SEND_DEV_ADDR: begin
        if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_ACK_1;
        end
      end
      FSM_ACK_1: begin
        if ((s_i2c_clk_cnt_q == 2'd3) && (s_ack == 1'b0)) begin
          if (extn_addr_i == 1'b1) s_fsm_d = FSM_SEND_REG_ADDR_H;
          else s_fsm_d = FSM_SEND_REG_ADDR_L;
        end
      end
      FSM_SEND_REG_ADDR_H: begin
        if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_ACK_2;
        end
      end
      FSM_ACK_2: begin
        if ((s_i2c_clk_cnt_q == 2'd3) && (s_ack == 1'b0)) begin
          s_fsm_d = FSM_SEND_REG_ADDR_L;
        end
      end
      FSM_SEND_REG_ADDR_L: begin
        if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_ACK_3;
        end
      end
      FSM_ACK_3: begin
        if ((s_i2c_clk_cnt_q == 2'd3) && (s_ack == 1'b0)) begin
          if (wr_en_i == 1'b1) s_fsm_d = FSM_WR_DATA;
          else if (rd_en_i == 1'b1) s_fsm_d = FSM_START_S;
        end
      end
      FSM_WR_DATA: begin
        if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_ACK_4;
        end
      end
      FSM_ACK_4: begin
        if ((s_i2c_clk_cnt_q == 2'd3) && (s_ack == 1'b0)) begin
          s_fsm_d = FSM_STOP;
        end
      end
      FSM_START_S: begin
        if (s_i2c_clk_cnt_q == 2'd3) s_fsm_d = FSM_SEND_RD_ADDR;
      end
      FSM_SEND_RD_ADDR: begin
        if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_ACK_5;
        end
      end
      FSM_ACK_5: begin
        if ((s_i2c_clk_cnt_q == 2'd3) && (s_ack == 1'b0)) begin
          s_fsm_d = FSM_RD_DATA;
        end
      end
      FSM_RD_DATA: begin
        if ((s_xfer_bit_cnt_q == 3'd7) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_N_ACK;
        end
      end
      FSM_N_ACK: begin
        if (s_i2c_clk_cnt_q == 2'd3) s_fsm_d = FSM_STOP;
      end
      FSM_STOP: begin
        if ((s_xfer_bit_cnt_q == 3'd3) && (s_i2c_clk_cnt_q == 2'd3)) begin
          s_fsm_d = FSM_IDLE;
        end
      end
      default: s_fsm_d = FSM_IDLE;
    endcase
  end
  dffer #(4) u_fsm_dffer (
      clk_i,
      rst_n_i,
      s_oper_clk_pos,
      s_fsm_d,
      s_fsm_q
  );


  always_comb begin
    s_ack = 1'b1;
    if((s_fsm_q == FSM_ACK_1) || (s_fsm_q == FSM_ACK_2) || (s_fsm_q == FSM_ACK_3)
        || (s_fsm_q == FSM_ACK_4) || (s_fsm_q == FSM_ACK_5)) begin
      if (s_i2c_clk_cnt_q == 2'd1) s_ack = sda_i;
      // if (s_i2c_clk_cnt_q == 2'd0) s_ack = sda_i;  // BUG:
    end
  end

  always_comb begin
    scl_o = 1'b1;
    unique case (s_fsm_q)
      FSM_IDLE: scl_o = 1'b1;
      FSM_START_F: begin
        if (s_i2c_clk_cnt_q == 2'd3) scl_o = 1'b0;
        else scl_o = 1'b1;
      end
      FSM_SEND_DEV_ADDR,FSM_ACK_1,FSM_SEND_REG_ADDR_H,FSM_ACK_2,FSM_SEND_REG_ADDR_L,
      FSM_ACK_3,FSM_WR_DATA,FSM_ACK_4,FSM_START_S,FSM_SEND_RD_ADDR,FSM_ACK_5,FSM_RD_DATA,FSM_N_ACK: begin
        if ((s_i2c_clk_cnt_q == 2'd1) || (s_i2c_clk_cnt_q == 2'd2)) scl_o = 1'b1;
        else scl_o = 1'b0;
      end
      FSM_STOP: begin
        if ((s_xfer_bit_cnt_q == 3'd0) && (s_i2c_clk_cnt_q == 2'd0)) scl_o = 1'b0;
        else scl_o = 1'b1;
      end
      default:  scl_o = 1'b1;
    endcase
  end

  always_comb begin
    s_i2c_sda_out = 1'b1;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_START_F: begin
        if (s_i2c_clk_cnt_q == 2'd0) s_i2c_sda_out = 1'b1;
        else s_i2c_sda_out = 1'b0;
      end
      FSM_SEND_DEV_ADDR: begin
        if (s_xfer_bit_cnt_q <= 3'd6) begin
          s_i2c_sda_out = dev_addr_i[6-s_xfer_bit_cnt_q];
        end else s_i2c_sda_out = 1'b0;
      end
      FSM_ACK_1: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_SEND_REG_ADDR_H: begin
        s_i2c_sda_out = reg_addr_i[15-s_xfer_bit_cnt_q];
      end
      FSM_ACK_2: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_SEND_REG_ADDR_L: begin
        s_i2c_sda_out = reg_addr_i[7-s_xfer_bit_cnt_q];
      end
      FSM_ACK_3: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_WR_DATA: begin
        s_i2c_sda_out = wr_data_i[7-s_xfer_bit_cnt_q];
      end
      FSM_ACK_4: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_START_S: begin
        if (s_i2c_clk_cnt_q <= 2'd1) s_i2c_sda_out = 1'b1;
        else s_i2c_sda_out = 1'b0;
      end
      FSM_SEND_RD_ADDR: begin
        if (s_xfer_bit_cnt_q <= 3'd6) begin
          s_i2c_sda_out = dev_addr_i[6-s_xfer_bit_cnt_q];
        end else s_i2c_sda_out = 1'b1;
      end
      FSM_ACK_5: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_RD_DATA: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_N_ACK: begin
        s_i2c_sda_out = 1'b1;
      end
      FSM_STOP: begin
        if ((s_xfer_bit_cnt_q == 3'd0) && (s_i2c_clk_cnt_q < 2'd3)) s_i2c_sda_out = 1'b0;
        else s_i2c_sda_out = 1'b1;
      end
      default: begin
        s_i2c_sda_out = 1'b1;
      end
    endcase
  end

  always_comb begin
    s_i2c_data_in_d = s_i2c_data_in_q;
    if (s_fsm_q == FSM_RD_DATA && s_i2c_clk_cnt_q == 2'd1) begin
      s_i2c_data_in_d[7-s_xfer_bit_cnt_q] = sda_i;
    end
  end
  dffer #(8) u_i2c_data_in_dffer (
      clk_i,
      rst_n_i,
      s_oper_clk_pos,
      s_i2c_data_in_d,
      s_i2c_data_in_q
  );

  always_comb begin
    if ((s_fsm_q == FSM_STOP) && (s_xfer_bit_cnt_q == 3'd3) && (s_i2c_clk_cnt_q == 3)) begin
      s_xfer_end_d = 1'b1;
    end else s_xfer_end_d = 1'b0;
  end
  dffer #(1) u_xfer_end_dffer (
      clk_i,
      rst_n_i,
      s_oper_clk_pos,
      s_xfer_end_d,
      s_xfer_end_q
  );

endmodule
