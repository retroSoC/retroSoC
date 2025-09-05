module spisd_data (
    input  logic        clk_i,
    input  logic        rst_n_i,    
    input  logic        fir_clk_edge_i,
    input  logic        init_done_i,
    output logic [31:0] sec_addr_o,
    output logic        rd_req_o,
    input  logic        rd_data_vld_i,
    input  logic [ 7:0] rd_data_i,
    output logic        wr_req_o,
    input  logic        wr_data_req_i,
    output logic [ 7:0] wr_data_o,
    input  logic        wr_busy_i
);

  reg          sd_init_done_d0;
  reg          sd_init_done_d1;
  reg          wr_busy_d0;
  reg          wr_busy_d1;
  reg   [ 7:0] wr_data_t;
  reg   [ 7:0] rd_comp_data;
  reg   [ 8:0] rd_right_cnt;
  logic        s_pos_init_done;
  logic        s_neg_wr_busy;

  logic        r_wr_req;
  logic        r_rd_req;
  logic [31:0] r_sec_addr;


  assign wr_req_o        = r_wr_req;
  assign rd_req_o        = r_rd_req;
  assign sec_addr_o      = r_sec_addr;


  assign s_pos_init_done = (~sd_init_done_d1) & sd_init_done_d0;
  assign s_neg_wr_busy   = wr_busy_d1 & (~wr_busy_d0);
  assign wr_data_o       = (wr_data_t > 7'd0) ? (wr_data_t - 1'b1) : '0;

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      sd_init_done_d0 <= 1'b0;
      sd_init_done_d1 <= 1'b0;
    end else begin
      if (fir_clk_edge_i) begin
        sd_init_done_d0 <= init_done_i;
        sd_init_done_d1 <= sd_init_done_d0;
      end
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_wr_req   <= 1'b0;
      r_rd_req   <= 1'b0;
      r_sec_addr <= '0;
    end else begin
      if (fir_clk_edge_i) begin
        if (s_pos_init_done) begin
          r_wr_req   <= 1'b1;
          r_sec_addr <= 32'd20000;
        end else if (s_neg_wr_busy) begin
          r_rd_req   <= 1'b1;
          r_sec_addr <= 32'd20000;
        end else begin
          r_wr_req <= 1'b0;
          r_rd_req <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) wr_data_t <= '0;
    else if (fir_clk_edge_i && wr_data_req_i) wr_data_t <= wr_data_t + 1'b1;
  end


  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      wr_busy_d0 <= 1'b0;
      wr_busy_d1 <= 1'b0;
    end else begin
      if (fir_clk_edge_i) begin
        wr_busy_d0 <= wr_busy_i;
        wr_busy_d1 <= wr_busy_d0;
      end
    end
  end

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      rd_comp_data <= '0;
      rd_right_cnt <= '0;
    end else begin
      if (fir_clk_edge_i && rd_data_vld_i) begin
        rd_comp_data <= rd_comp_data + 1'b1;
        if (rd_data_i == rd_comp_data) rd_right_cnt <= rd_right_cnt + 9'd1;
      end
    end
  end

endmodule
