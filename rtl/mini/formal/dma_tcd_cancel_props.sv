module dma_tcd_cancel_formal;
  (* gclk *)reg        clk_i;
  wire       rst_n_i;
  wire [3:0] start_i;
  wire [3:0] abort_i;
  wire [3:0] aborted;
  wire       tcd_mode;
  wire       tcd_read_owner_valid;
  wire       tcd_parse;
  wire       tcd_loaded;
  wire       tcd_fetch_pending;
  wire       tcd_abort;

  dma_formal_design u_design (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .start_i             (start_i),
      .abort_i             (abort_i),
      .aborted             (aborted),
      .tcd_mode            (tcd_mode),
      .tcd_read_owner_valid(tcd_read_owner_valid),
      .tcd_parse           (tcd_parse),
      .tcd_loaded          (tcd_loaded),
      .tcd_fetch_pending   (tcd_fetch_pending),
      .tcd_abort           (tcd_abort)
  );

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assume (tcd_mode);
      if (tcd_abort) begin
        assert (!tcd_loaded);
        assert (!tcd_fetch_pending);
      end
      cover (tcd_fetch_pending && abort_i[0]);
      cover (aborted[0] && !start_i[0]);
    end
  end
endmodule
