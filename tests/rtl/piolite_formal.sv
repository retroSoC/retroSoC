module piolite_formal (
    input wire clk_i
);
  reg         rst_n = 1'b0;
  (* anyseq *)reg         push;
  (* anyseq *)reg         pop;
  (* anyseq *)reg  [31:0] push_data;
  wire [31:0] pop_data;
  wire        push_accept;
  wire        pop_accept;
  wire        full;
  wire        empty;
  wire [ 3:0] count;
  always @(posedge clk_i) rst_n <= 1'b1;

`ifndef PIOLITE_FORMAL_TOP
  piolite_fifo u_fifo (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n),
      .flush_i      (1'b0),
      .push_i       (push),
      .push_data_i  (push_data),
      .pop_i        (pop),
      .pop_data_o   (pop_data),
      .push_accept_o(push_accept),
      .pop_accept_o (pop_accept),
      .full_o       (full),
      .empty_o      (empty),
      .count_o      (count)
  );
  piolite_formal_props u_props (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n),
      .push_i       (push),
      .pop_i        (pop),
      .push_accept_i(push_accept),
      .pop_accept_i (pop_accept),
      .full_i       (full),
      .empty_i      (empty),
      .count_i      (count)
  );
`endif
`ifdef PIOLITE_FORMAL_TOP
  (* anyseq *)reg  [31:0] gpio_input;
  (* anyseq *)reg         guard_loss;
  (* anyseq *)reg         dma_tx_valid;
  (* anyseq *)reg  [31:0] dma_tx_data;
  (* anyseq *)reg  [ 3:0] dma_tx_keep;
  (* anyseq *)reg  [ 3:0] dma_tx_strb;
  (* anyseq *)reg         dma_tx_id;
  (* anyseq *)reg         dma_tx_dest;
  (* anyseq *)reg         dma_tx_user;
  (* anyseq *)reg         dma_tx_last;
  (* anyseq *)reg         dma_rx_ready;
  (* anyseq *)reg  [31:0] paddr;
  (* anyseq *)reg  [31:0] pwdata;
  (* anyseq *)reg         psel;
  (* anyseq *)reg         penable;
  (* anyseq *)reg         pwrite;
  wire [31:0] gpio_value;
  wire [31:0] gpio_oe;
  wire        dma_tx_ready;
  wire        dma_rx_valid;
  wire [31:0] dma_rx_data;
  wire [ 3:0] dma_rx_keep;
  wire [ 3:0] dma_rx_strb;
  wire        dma_rx_last;
  wire        dma_rx_id;
  wire        dma_rx_dest;
  wire        dma_rx_user;
  wire        dma_tx_admit;
  wire        dma_rx_admit;
  wire        irq;
  wire        pready;
  wire [31:0] prdata;
  wire        pslverr;
  wire [43:0] formal_sm0;

  apb4_piolite_block_top u_dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n),
      .clock_hz_i     (32'd24000000),
      .user_select_i  (guard_loss ? 32'd0 : 32'hffff_ffff),
      .user_status_i  (guard_loss ? 32'd0 : 32'hffff_ffff),
      .filter_enable_i(32'd0),
      .gpio_ready_i   (1'b1),
      .gpio_input_i   (gpio_input),
      .gpio_value_o   (gpio_value),
      .gpio_oe_o      (gpio_oe),
      .dma_tx_job_i   (1'b0),
      .dma_rx_job_i   (1'b0),
      .dma_tx_valid_i (dma_tx_valid),
      .dma_tx_ready_o (dma_tx_ready),
      .dma_tx_data_i  (dma_tx_data),
      .dma_tx_keep_i  (dma_tx_keep),
      .dma_tx_strb_i  (dma_tx_strb),
      .dma_tx_id_i    (dma_tx_id),
      .dma_tx_dest_i  (dma_tx_dest),
      .dma_tx_user_i  (dma_tx_user),
      .dma_tx_last_i  (dma_tx_last),
      .dma_rx_valid_o (dma_rx_valid),
      .dma_rx_ready_i (dma_rx_ready),
      .dma_rx_data_o  (dma_rx_data),
      .dma_rx_keep_o  (dma_rx_keep),
      .dma_rx_strb_o  (dma_rx_strb),
      .dma_rx_last_o  (dma_rx_last),
      .dma_rx_id_o    (dma_rx_id),
      .dma_rx_dest_o  (dma_rx_dest),
      .dma_rx_user_o  (dma_rx_user),
      .dma_tx_admit_o (dma_tx_admit),
      .dma_rx_admit_o (dma_rx_admit),
      .irq_o          (irq),
      .paddr_i        (paddr),
      .pprot_i        (3'd0),
      .psel_i         (psel),
      .penable_i      (penable),
      .pwrite_i       (pwrite),
      .pwdata_i       (pwdata),
      .pstrb_i        (pwrite ? 4'hf : 4'd0),
      .pready_o       (pready),
      .prdata_o       (prdata),
      .pslverr_o      (pslverr),
      .formal_sm0_o   (formal_sm0)
  );

  always @(posedge clk_i) begin
    assume (paddr[31:12] == 20'd0 && paddr[11:2] <= 10'hff && paddr[1:0] == 2'd0);
    if (rst_n) begin
      cover (pready);
      cover (formal_sm0[43:41] == 3'd1);
      cover (formal_sm0[40]);
      cover (formal_sm0[43:41] == 3'd4);
      cover (formal_sm0[39:32] != 8'd0);
      cover (formal_sm0[31:0] != 32'd0);
    end
  end
`endif
endmodule
