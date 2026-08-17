// Shared AXI4-to-APB4 decoder state for both APB4 islands.
localparam logic [3:0] FSM_IDLE = 4'd0;
localparam logic [3:0] FSM_DECODE = 4'd1;
localparam logic [3:0] FSM_WR_DATA = 4'd2;
localparam logic [3:0] FSM_SETP = 4'd3;
localparam logic [3:0] FSM_ENAB = 4'd4;
localparam logic [3:0] FSM_WR_RESP = 4'd5;
localparam logic [3:0] FSM_RD_RESP = 4'd6;
localparam logic [3:0] FSM_ERR_WR_DATA = 4'd7;
localparam logic [3:0] FSM_ERR_WR_RESP = 4'd8;
localparam logic [3:0] FSM_ERR_RD_RESP = 4'd9;

logic [3:0] s_fsm_d, s_fsm_q;
logic [31:0] s_addr_d, s_addr_q, s_decode_addr;
logic [31:0] s_wdata_d, s_wdata_q;
logic [3:0] s_wstrb_d, s_wstrb_q;
logic s_write_d, s_write_q;
logic s_id_d, s_id_q;
logic [7:0] s_len_d, s_len_q;
logic [7:0] s_beat_d, s_beat_q;
logic [31:0] s_rdata_d, s_rdata_q;
logic [1:0] s_resp_d, s_resp_q;
logic [31:0] s_rd_data;
logic s_xfer_valid, s_xfer_ready, s_xfer_err;
logic s_psel_valid;

