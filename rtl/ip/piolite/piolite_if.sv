interface piolite_if;
  piolite_pkg::sm_config_t         cfg             [0:1];
  piolite_pkg::sm_runtime_t        runtime         [0:1];
  logic                     [ 3:0] tx_level        [0:1];
  logic                     [ 3:0] rx_level        [0:1];
  logic                     [31:0] tx_bind;
  logic                     [31:0] rx_bind;
  logic                     [31:0] imem_valid;
  logic                     [ 3:0] flags;
  logic                     [ 1:0] cmd_start;
  logic                     [ 1:0] cmd_pause;
  logic                     [ 1:0] cmd_resume;
  logic                     [ 1:0] cmd_disable;
  logic                     [ 1:0] cmd_abort;
  logic                     [ 1:0] cmd_sm_reset;
  logic                            cmd_block_reset;
  logic                     [ 3:0] flag_set;
  logic                     [ 3:0] flag_clear;
  logic                     [ 5:0] event_clear     [0:1];
  logic                     [ 1:0] cpu_tx_push;
  logic                     [ 1:0] cpu_rx_pop;
  logic                     [31:0] cpu_tx_data;
  logic                     [31:0] cpu_rx_data     [0:1];
  logic                     [ 1:0] start_guard_ok;
  logic                     [ 1:0] cpu_guard_ok;
  logic                     [15:0] imem_read_data;
  logic                            imem_write;
  logic                     [ 4:0] imem_write_addr;
  logic                     [15:0] imem_write_data;
  logic                     [ 4:0] imem_read_addr;

  modport registers(
      output cfg, tx_bind, rx_bind, cmd_start, cmd_pause, cmd_resume, cmd_disable,
             cmd_abort, cmd_sm_reset, cmd_block_reset, flag_set, flag_clear, event_clear,
             cpu_tx_push, cpu_rx_pop, cpu_tx_data, imem_write, imem_write_addr,
             imem_write_data, imem_read_addr,
      input runtime, tx_level, rx_level, imem_valid, flags, start_guard_ok, cpu_guard_ok,
            imem_read_data, cpu_rx_data
  );
  modport core(
      input cfg, tx_bind, rx_bind, cmd_start, cmd_pause, cmd_resume, cmd_disable, cmd_abort,
            cmd_sm_reset, cmd_block_reset, flag_set, flag_clear, event_clear, cpu_tx_push,
            cpu_rx_pop, cpu_tx_data, imem_write, imem_write_addr, imem_write_data,
            imem_read_addr, start_guard_ok, cpu_guard_ok,
      output runtime, tx_level, rx_level, imem_valid, flags, imem_read_data, cpu_rx_data
  );
endinterface
