module piolite_core (
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic           [31:0] pin_inputs_i,
    input  logic           [ 1:0] guard_fault_i,
    input  logic           [ 7:0] guard_fault_code_i[0:1],
    input  logic                  stream_fault_i,
    input  logic                  stream_fault_sm_i,
    input  logic                  dma_tx_push_i,
    input  logic           [31:0] dma_tx_data_i,
    input  logic                  dma_tx_sm_i,
    output logic                  dma_tx_accept_o,
    input  logic                  dma_rx_pop_i,
    input  logic                  dma_rx_sm_i,
    output logic           [31:0] dma_rx_data_o,
    output logic                  dma_rx_accept_o,
`ifdef PIOLITE_FORMAL_TOP
    output logic           [43:0] formal_sm0_o,
`endif
           piolite_if.core        ctrl
);
  logic [ 4:0] s_instruction_addr [0:1];
  logic [15:0] s_instruction_data [0:1];
  logic        s_instruction_valid[0:1];
  logic [ 3:0] s_sm_flag_set      [0:1];
  logic [ 3:0] s_sm_flag_clear    [0:1];
  logic        s_sm_tx_pop        [0:1];
  logic        s_sm_rx_push       [0:1];
  logic [31:0] s_sm_rx_data       [0:1];
  logic [31:0] s_tx_pop_data      [0:1];
  logic [31:0] s_rx_pop_data      [0:1];
  logic        s_tx_push_accept   [0:1];
  logic        s_tx_pop_accept    [0:1];
  logic        s_rx_push_accept   [0:1];
  logic        s_rx_pop_accept    [0:1];
  logic        s_tx_full          [0:1];
  logic        s_tx_empty         [0:1];
  logic        s_rx_full          [0:1];
  logic        s_rx_empty         [0:1];
  logic [31:0] s_flags_d;
  logic [31:0] s_flags_q;
  logic [ 3:0] s_flag_set;
  logic [ 3:0] s_flag_clear;
  logic        s_unused;
`ifdef PIOLITE_FORMAL_TOP
  logic s_sm_formal_commit[0:1];

  assign formal_sm0_o = {
    ctrl.runtime[0].state,
    s_sm_formal_commit[0],
    ctrl.runtime[0].fault_code,
    ctrl.runtime[0].output_oe
  };
`endif
  assign s_unused = ^{s_tx_pop_accept[0], s_tx_pop_accept[1], s_rx_push_accept[0],
      s_rx_push_accept[1], s_tx_full[0], s_tx_full[1], s_rx_empty[0], s_rx_empty[1]};
  assign ctrl.flags = s_flags_q[3:0];
  assign s_flag_set = ctrl.flag_set | s_sm_flag_set[0] | s_sm_flag_set[1];
  assign s_flag_clear = ctrl.flag_clear | s_sm_flag_clear[0] | s_sm_flag_clear[1];
  always_comb begin
    s_flags_d = ctrl.cmd_block_reset ? 32'd0 :
        ((s_flags_q & ~{28'd0, s_flag_clear}) | {28'd0, s_flag_set});
    dma_tx_accept_o = dma_tx_push_i && s_tx_push_accept[dma_tx_sm_i];
    dma_rx_accept_o = dma_rx_pop_i && s_rx_pop_accept[dma_rx_sm_i];
    dma_rx_data_o = s_rx_pop_data[dma_rx_sm_i];
  end

  dffr #(
      .DATA_WIDTH(32)
  ) u_flags (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_flags_d),
      .dat_o  (s_flags_q)
  );

  piolite_imem u_imem (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .clear_valid_i(ctrl.cmd_block_reset),
      .write_i      (ctrl.imem_write),
      .write_addr_i (ctrl.imem_write_addr),
      .write_data_i (ctrl.imem_write_data),
      .sm0_addr_i   (s_instruction_addr[0]),
      .sm0_data_o   (s_instruction_data[0]),
      .sm0_valid_o  (s_instruction_valid[0]),
      .sm1_addr_i   (s_instruction_addr[1]),
      .sm1_data_o   (s_instruction_data[1]),
      .sm1_valid_o  (s_instruction_valid[1]),
      .apb_addr_i   (ctrl.imem_read_addr),
      .apb_data_o   (ctrl.imem_read_data),
      .valid_o      (ctrl.imem_valid)
  );

  for (genvar index = 0; index < 2; index++) begin : gen_sm
    logic        s_external_tx_push;
    logic        s_external_rx_pop;
    logic [31:0] s_external_tx_data;

    assign s_external_tx_push = ctrl.cpu_tx_push[index] ||
        (dma_tx_push_i && (dma_tx_sm_i == index[0]));
    assign s_external_tx_data = (dma_tx_push_i && (dma_tx_sm_i == index[0])) ?
        dma_tx_data_i : ctrl.cpu_tx_data;
    assign s_external_rx_pop = ctrl.cpu_rx_pop[index] ||
        (dma_rx_pop_i && (dma_rx_sm_i == index[0]));
    assign ctrl.cpu_rx_data[index] = s_rx_pop_data[index];

    piolite_sm u_sm (
        .clk_i              (clk_i),
        .rst_n_i            (rst_n_i),
        .cfg_i              (ctrl.cfg[index]),
        .start_i            (ctrl.cmd_start[index]),
        .pause_i            (ctrl.cmd_pause[index]),
        .resume_i           (ctrl.cmd_resume[index]),
        .disable_i          (ctrl.cmd_disable[index]),
        .abort_i            (ctrl.cmd_abort[index]),
        .sm_reset_i         (ctrl.cmd_sm_reset[index]),
        .block_reset_i      (ctrl.cmd_block_reset),
        .event_clear_i      (ctrl.event_clear[index]),
        .guard_fault_i      (guard_fault_i[index]),
        .guard_fault_code_i (guard_fault_code_i[index]),
        .stream_fault_i     (stream_fault_i && (stream_fault_sm_i == index[0])),
        .instruction_i      (s_instruction_data[index]),
        .instruction_valid_i(s_instruction_valid[index]),
        .instruction_addr_o (s_instruction_addr[index]),
        .flags_i            (s_flags_q),
        .pin_inputs_i       (pin_inputs_i),
        .flag_set_o         (s_sm_flag_set[index]),
        .flag_clear_o       (s_sm_flag_clear[index]),
        .tx_empty_i         (s_tx_empty[index]),
        .tx_data_i          (s_tx_pop_data[index]),
        .tx_pop_o           (s_sm_tx_pop[index]),
        .rx_full_i          (s_rx_full[index]),
        .rx_push_o          (s_sm_rx_push[index]),
        .rx_data_o          (s_sm_rx_data[index]),
`ifdef PIOLITE_FORMAL_TOP
        .formal_commit_o    (s_sm_formal_commit[index]),
`endif
        .runtime_o          (ctrl.runtime[index])
    );

    piolite_fifo u_tx_fifo (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .flush_i      (ctrl.cmd_sm_reset[index] || ctrl.cmd_block_reset),
        .push_i       (s_external_tx_push),
        .push_data_i  (s_external_tx_data),
        .pop_i        (s_sm_tx_pop[index]),
        .pop_data_o   (s_tx_pop_data[index]),
        .push_accept_o(s_tx_push_accept[index]),
        .pop_accept_o (s_tx_pop_accept[index]),
        .full_o       (s_tx_full[index]),
        .empty_o      (s_tx_empty[index]),
        .count_o      (ctrl.tx_level[index])
    );

    piolite_fifo u_rx_fifo (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .flush_i      (ctrl.cmd_sm_reset[index] || ctrl.cmd_block_reset),
        .push_i       (s_sm_rx_push[index]),
        .push_data_i  (s_sm_rx_data[index]),
        .pop_i        (s_external_rx_pop),
        .pop_data_o   (s_rx_pop_data[index]),
        .push_accept_o(s_rx_push_accept[index]),
        .pop_accept_o (s_rx_pop_accept[index]),
        .full_o       (s_rx_full[index]),
        .empty_o      (s_rx_empty[index]),
        .count_o      (ctrl.rx_level[index])
    );
  end
endmodule
