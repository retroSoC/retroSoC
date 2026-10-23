module spi_formal_props (
    input wire clk_i,
    rst_n_i,
    active_i,
    done_i,
    abort_i,
    sck_i,
    cpol_i
);
  reg       past_valid = 0;
  reg [4:0] closing_cycles = 0;
  always @(posedge clk_i) begin
    past_valid <= rst_n_i;
    if (!rst_n_i || !active_i || !abort_i) closing_cycles <= 0;
    else closing_cycles <= closing_cycles + 1;
    if (rst_n_i && past_valid) begin
      assert (!done_i || (active_i && !abort_i));
      assert (closing_cycles <= 10);
      if (!active_i && !$past(active_i)) assert (sck_i == cpol_i);
      cover (done_i);
      cover ($past(active_i && abort_i) && !active_i);
    end
  end
endmodule
