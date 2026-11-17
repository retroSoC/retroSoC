// verilog_syntax: parse-as-module-body
axi4_stream_if piolite_tx_axis (
    .aclk   (clk_i),
    .aresetn(rst_n_i)
);
axi4_stream_if piolite_rx_axis (
    .aclk   (clk_i),
    .aresetn(rst_n_i)
);
assign piolite_tx_axis.tready = 1'b0;
assign piolite_rx_axis.tvalid = 1'b0;
assign piolite_rx_axis.tdata  = '0;
assign piolite_rx_axis.tkeep  = '0;
assign piolite_rx_axis.tstrb  = '0;
assign piolite_rx_axis.tlast  = 1'b0;
assign piolite_rx_axis.tid    = '0;
assign piolite_rx_axis.tdest  = '0;
assign piolite_rx_axis.tuser  = '0;
