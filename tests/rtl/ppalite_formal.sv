module ppalite_formal (
    input wire clk_i
);
  reg rst_n = 1'b0;
  always @(posedge clk_i) rst_n <= 1'b1;
`ifndef PPALITE_FORMAL_TOP
  (* anyseq *)reg         push;
  (* anyseq *)reg         pop;
  (* anyseq *)reg         flush;
  (* anyseq *)reg  [31:0] push_data;
  wire [31:0] pop_data;
  wire        full;
  wire        empty;
  wire [ 3:0] count;
  ppalite_fifo #(
      .DataWidth  (32),
      .BufferDepth(8)
  ) u_fifo (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n),
      .flush_i    (flush),
      .push_i     (push),
      .push_data_i(push_data),
      .pop_i      (pop),
      .pop_data_o (pop_data),
      .full_o     (full),
      .empty_o    (empty),
      .count_o    (count)
  );
  ppalite_formal_props u_props (
      .clk_i  (clk_i),
      .rst_n_i(rst_n),
      .flush_i(flush),
      .push_i (push),
      .pop_i  (pop),
      .full_i (full),
      .empty_i(empty),
      .count_i(count)
  );
`else
  (* anyseq *)reg  [31:0] source_sequence;
  (* anyseq *)reg  [31:0] source_words;
  (* anyseq *)reg  [31:0] source_geometry;
  (* anyseq *)reg  [ 7:0] source_err;
  (* anyseq *)reg         source_done;
  (* anyseq *)reg         source_quiet;
  (* anyseq *)reg         source_stopped;
  (* anyseq *)reg         transport_done;
  (* anyseq *)reg         transport_idle;
  (* anyseq *)reg  [ 7:0] transport_err;
  (* anyseq *)reg         in_valid;
  (* anyseq *)reg  [31:0] in_data;
  (* anyseq *)reg  [ 3:0] in_keep;
  (* anyseq *)reg  [ 3:0] in_strb;
  (* anyseq *)reg         in_id;
  (* anyseq *)reg         in_dest;
  (* anyseq *)reg         in_user;
  (* anyseq *)reg         in_last;
  (* anyseq *)reg         out_ready;
  (* anyseq *)reg  [31:0] paddr;
  (* anyseq *)reg         psel;
  (* anyseq *)reg         penable;
  (* anyseq *)reg         pwrite;
  (* anyseq *)reg  [31:0] pwdata;
  wire        in_ready;
  wire        out_valid;
  wire [31:0] out_data;
  wire [ 3:0] out_keep;
  wire [ 3:0] out_strb;
  wire        out_last;
  wire        out_id;
  wire        out_dest;
  wire        out_user;
  wire        irq;
  wire        pready;
  wire [31:0] prdata;
  wire        pslverr;
  wire [ 2:0] formal_state;
  wire [ 7:0] formal_core_err;

  apb4_ppalite_block_top u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n),
      .clock_hz_i       (32'd24000000),
      .route_idle_i     (1'b1),
      .source_ready_i   (1'b1),
      .source_quiet_i   (source_quiet),
      .source_done_i    (source_done),
      .source_stopped_i (source_stopped),
      .source_sequence_i(source_sequence),
      .source_words_i   (source_words),
      .source_geometry_i(source_geometry),
      .source_err_i     (source_err),
      .transport_ready_i(1'b1),
      .transport_idle_i (transport_idle),
      .transport_done_i (transport_done),
      .transport_err_i  (transport_err),
      .in_valid_i       (in_valid),
      .in_ready_o       (in_ready),
      .in_data_i        (in_data),
      .in_keep_i        (in_keep),
      .in_strb_i        (in_strb),
      .in_id_i          (in_id),
      .in_dest_i        (in_dest),
      .in_user_i        (in_user),
      .in_last_i        (in_last),
      .out_valid_o      (out_valid),
      .out_ready_i      (out_ready),
      .out_data_o       (out_data),
      .out_keep_o       (out_keep),
      .out_strb_o       (out_strb),
      .out_last_o       (out_last),
      .out_id_o         (out_id),
      .out_dest_o       (out_dest),
      .out_user_o       (out_user),
      .formal_state_o   (formal_state),
      .formal_core_err_o(formal_core_err),
      .irq_o            (irq),
      .paddr_i          (paddr),
      .pprot_i          (3'd0),
      .psel_i           (psel),
      .penable_i        (penable),
      .pwrite_i         (pwrite),
      .pwdata_i         (pwdata),
      .pstrb_i          (pwrite ? 4'hf : 4'd0),
      .pready_o         (pready),
      .prdata_o         (prdata),
      .pslverr_o        (pslverr)
  );
  always @(posedge clk_i) begin
    assume ((paddr[11:8] == 4'd0) && (paddr[7:0] <= 8'h9c) && (paddr[1:0] == 2'd0));
    if (rst_n) begin
      cover (pready);
      cover (formal_state == 3'd1);
      cover (out_valid);
      cover (formal_core_err != 8'd0);
    end
  end
`endif
endmodule
