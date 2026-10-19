interface spi_ctrl_if;
  spi_pkg::configuration_t       cfg;
  spi_pkg::status_t              stat;
  logic                    [8:0] cmd;
  logic cmd_err, session_writable, segment_writable;
  logic tx_push, rx_pop, tx_ready, rx_ready;
  logic [31:0] tx_data, rx_data;
  logic [5:0] events;
  logic clear_events, clear_bindings;
  modport registers(
      output cfg, cmd, tx_push, rx_pop, tx_data,
      input stat, cmd_err, session_writable, segment_writable,
                    tx_ready, rx_ready, rx_data, events, clear_events, clear_bindings
  );
  modport core(
      input cfg, cmd, tx_push, rx_pop, tx_data,
      output stat, cmd_err, session_writable, segment_writable,
               tx_ready, rx_ready, rx_data, events, clear_events, clear_bindings
  );
endinterface
