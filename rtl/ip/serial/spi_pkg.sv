package spi_pkg;
  typedef enum logic [3:0] {
    Disabled = 4'd0,
    Idle     = 4'd1,
    Armed    = 4'd2,
    Setup    = 4'd3,
    Shift    = 4'd4,
    Hold     = 4'd5,
    Held     = 4'd6,
    Gap      = 4'd7,
    Closing  = 4'd8
  } wire_state_e;
  typedef struct packed {
    logic [4:0]  session;
    logic [15:0] divider,    setup_cycles, hold_cycles, inactive_cycles;
    logic [3:0]  segment;
    logic [31:0] frames;
    logic [15:0] dummy;
    logic [31:0] tx_binding, rx_binding;
    logic [11:0] watermarks;
  } configuration_t;
  typedef struct packed {
    logic [31:0] status,   levels,     fault,      fault_frame, frames,    words;
    logic [31:0] tx_words, rx_words,   rx_removed, tx_stalls,   rx_stalls;
    logic [31:0] pins,     ready_pins, payload;
  } status_t;
endpackage
