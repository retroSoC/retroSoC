interface ppalite_if;
  logic [ 5:0] cfg;
  logic [31:0] input_size;
  logic [11:0] sampling;
  logic [31:0] output_size;
  logic [31:0] row_bytes;
  logic [31:0] stride_bytes;
  logic [31:0] valid_bytes;
  logic [31:0] transport_bytes;
  logic [31:0] expected_words;
  logic [ 5:0] cmd;
  logic [ 2:0] state;
  logic        close;
  logic        started;
  logic        input_done;
  logic        excess;
  logic [31:0] excess_position;
  logic        local_idle;
  logic        pipe_done;
  logic [31:0] input_words;
  logic [31:0] input_pixels;
  logic [31:0] input_lines;
  logic [31:0] sel_pixels;
  logic [31:0] output_words;
  logic [31:0] output_lines;
  logic [31:0] input_stall_cycles;
  logic [31:0] output_stall_cycles;
  logic        output_stall_event;
  logic [ 1:0] input_level;
  logic [ 3:0] output_level;
  logic [ 3:0] output_high_water;
  logic [ 7:0] core_err;
  logic [31:0] err_position;

  modport registers(
      output cfg, input_size, sampling, output_size, row_bytes,
             stride_bytes, valid_bytes, transport_bytes, expected_words, cmd, state, close,
      input started, input_done, excess, excess_position, local_idle,
            pipe_done, input_words, input_pixels, input_lines, sel_pixels, output_words,
            output_lines, input_stall_cycles, output_stall_cycles, output_stall_event, input_level,
            output_level, output_high_water, core_err, err_position
  );
  modport core(
      input cfg, input_size, sampling, output_size, row_bytes,
            stride_bytes, valid_bytes, transport_bytes, expected_words, cmd, state, close,
      output started, input_done, excess, excess_position, local_idle,
             pipe_done, input_words,
             input_pixels, input_lines, sel_pixels, output_words, output_lines,
             input_stall_cycles, output_stall_cycles, output_stall_event, input_level,
             output_level, output_high_water, core_err, err_position
  );
endinterface
