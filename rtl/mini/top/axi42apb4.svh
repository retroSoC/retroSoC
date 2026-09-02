// Shared AXI4-to-APB4 decoder body for both APB4 islands.
assign axi4.awready = (s_fsm_q == FSM_IDLE) && !axi4.arvalid;
assign axi4.arready = (s_fsm_q == FSM_IDLE);
assign axi4.wready = (s_fsm_q == FSM_WR_DATA) || (s_fsm_q == FSM_ERR_WR_DATA);
assign axi4.bid = s_id_q;
assign axi4.bresp = s_resp_q;
assign axi4.buser = '0;
assign axi4.bvalid = (s_fsm_q == FSM_WR_RESP) || (s_fsm_q == FSM_ERR_WR_RESP);
assign axi4.rid = s_id_q;
assign axi4.rdata = (s_fsm_q == FSM_RD_RESP) ? s_rdata_q : '0;
assign axi4.rresp = s_resp_q;
assign axi4.rlast = (s_fsm_q == FSM_RD_RESP) ||
                      ((s_fsm_q == FSM_ERR_RD_RESP) && (s_beat_q == s_len_q));
assign axi4.ruser = '0;
assign axi4.rvalid = (s_fsm_q == FSM_RD_RESP) || (s_fsm_q == FSM_ERR_RD_RESP);

always_comb begin
  s_fsm_d   = s_fsm_q;
  s_addr_d  = s_addr_q;
  s_wdata_d = s_wdata_q;
  s_wstrb_d = s_wstrb_q;
  s_write_d = s_write_q;
  s_id_d    = s_id_q;
  s_len_d   = s_len_q;
  s_beat_d  = s_beat_q;
  s_rdata_d = s_rdata_q;
  s_resp_d  = s_resp_q;

  unique case (s_fsm_q)
    FSM_IDLE: begin
      s_beat_d = '0;
      s_resp_d = `AXI4_RESP_OKAY;
      if (axi4.arvalid && axi4.arready) begin
        s_addr_d  = axi4.araddr;
        s_wstrb_d = '0;
        s_write_d = 1'b0;
        s_id_d    = axi4.arid;
        s_len_d   = axi4.arlen;
        if ((axi4.arlen != 8'd0) || (axi4.arburst != `AXI4_BURST_TYPE_INCR) || axi4.arlock) begin
          s_resp_d = `AXI4_RESP_SLAVE_ERROR;
          s_fsm_d  = FSM_ERR_RD_RESP;
        end else begin
          s_fsm_d = FSM_DECODE;
        end
      end else if (axi4.awvalid && axi4.awready) begin
        s_addr_d  = axi4.awaddr;
        s_write_d = 1'b1;
        s_id_d    = axi4.awid;
        s_len_d   = axi4.awlen;
        if ((axi4.awlen != 8'd0) || (axi4.awburst != `AXI4_BURST_TYPE_INCR) || axi4.awlock) begin
          s_resp_d = `AXI4_RESP_SLAVE_ERROR;
          s_fsm_d  = FSM_ERR_WR_DATA;
        end else begin
          s_fsm_d = FSM_DECODE;
        end
      end
    end
    FSM_DECODE: begin
      if (!s_psel_valid) begin
        s_resp_d = `AXI4_RESP_DECODE_ERROR;
        s_fsm_d  = s_write_q ? FSM_ERR_WR_DATA : FSM_ERR_RD_RESP;
      end else begin
        s_fsm_d = s_write_q ? FSM_WR_DATA : FSM_SETP;
      end
    end
    FSM_WR_DATA: begin
      if (axi4.wvalid && axi4.wready) begin
        s_wdata_d = axi4.wdata;
        s_wstrb_d = axi4.wstrb;
        if (axi4.wlast) begin
          s_fsm_d = FSM_SETP;
        end else begin
          s_resp_d = `AXI4_RESP_SLAVE_ERROR;
          s_fsm_d  = FSM_ERR_WR_DATA;
        end
      end
    end
    FSM_SETP: s_fsm_d = FSM_ENAB;
    FSM_ENAB: begin
      if (s_xfer_ready) begin
        s_resp_d = s_xfer_err ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
        if (s_write_q) begin
          s_fsm_d = FSM_WR_RESP;
        end else begin
          s_rdata_d = s_rd_data;
          s_fsm_d   = FSM_RD_RESP;
        end
      end
    end
    FSM_WR_RESP: begin
      if (axi4.bvalid && axi4.bready) s_fsm_d = FSM_IDLE;
    end
    FSM_RD_RESP: begin
      if (axi4.rvalid && axi4.rready) s_fsm_d = FSM_IDLE;
    end
    FSM_ERR_WR_DATA: begin
      if (axi4.wvalid && axi4.wready) begin
        if ((s_beat_q == s_len_q) || axi4.wlast) begin
          s_fsm_d = FSM_ERR_WR_RESP;
        end else begin
          s_beat_d = s_beat_q + 1'b1;
        end
      end
    end
    FSM_ERR_WR_RESP: begin
      if (axi4.bvalid && axi4.bready) s_fsm_d = FSM_IDLE;
    end
    FSM_ERR_RD_RESP: begin
      if (axi4.rvalid && axi4.rready) begin
        if (s_beat_q == s_len_q) begin
          s_fsm_d = FSM_IDLE;
        end else begin
          s_beat_d = s_beat_q + 1'b1;
        end
      end
    end
    default:  s_fsm_d = FSM_IDLE;
  endcase
end

dffr #(
    .DATA_WIDTH(4)
) u_fsm_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_fsm_d),
    .dat_o  (s_fsm_q)
);
dffr #(
    .DATA_WIDTH(32)
) u_addr_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_addr_d),
    .dat_o  (s_addr_q)
);
dffr #(
    .DATA_WIDTH(32)
) u_wdata_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_wdata_d),
    .dat_o  (s_wdata_q)
);
dffr #(
    .DATA_WIDTH(4)
) u_wstrb_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_wstrb_d),
    .dat_o  (s_wstrb_q)
);
dffr #(
    .DATA_WIDTH(1)
) u_write_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_write_d),
    .dat_o  (s_write_q)
);
dffr #(
    .DATA_WIDTH(1)
) u_id_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_id_d),
    .dat_o  (s_id_q)
);
dffr #(
    .DATA_WIDTH(8)
) u_len_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_len_d),
    .dat_o  (s_len_q)
);
dffr #(
    .DATA_WIDTH(8)
) u_beat_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_beat_d),
    .dat_o  (s_beat_q)
);
dffr #(
    .DATA_WIDTH(32)
) u_rdata_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_rdata_d),
    .dat_o  (s_rdata_q)
);
dffr #(
    .DATA_WIDTH(2)
) u_resp_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  (s_resp_d),
    .dat_o  (s_resp_q)
);
dffr #(
    .DATA_WIDTH(NSLV)
) u_psel_dffr (
    .clk_i  (clk_i),
    .rst_n_i(rst_n_i),
    .dat_i  ((s_fsm_q == FSM_DECODE) ? s_psel_comb : s_psel_q),
    .dat_o  (s_psel_q)
);
