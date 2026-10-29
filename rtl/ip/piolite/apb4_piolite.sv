module apb4_piolite (
    input  logic                clk_i,
    input  logic                rst_n_i,
    input  logic         [31:0] clock_hz_i,
    input  logic         [31:0] user_select_i,
    input  logic         [31:0] user_status_i,
    input  logic         [31:0] filter_enable_i,
    input  logic                gpio_ready_i,
    input  logic         [31:0] gpio_input_i,
    output logic         [31:0] gpio_value_o,
    output logic         [31:0] gpio_oe_o,
    input  logic                dma_tx_job_i,
    input  logic                dma_rx_job_i,
    input  logic                dma_tx_valid_i,
    output logic                dma_tx_ready_o,
    input  logic         [31:0] dma_tx_data_i,
    input  logic         [ 3:0] dma_tx_keep_i,
    input  logic         [ 3:0] dma_tx_strb_i,
    input  logic                dma_tx_id_i,
    input  logic                dma_tx_dest_i,
    input  logic                dma_tx_user_i,
    input  logic                dma_tx_last_i,
    output logic                dma_rx_valid_o,
    input  logic                dma_rx_ready_i,
    output logic         [31:0] dma_rx_data_o,
    output logic         [ 3:0] dma_rx_keep_o,
    output logic         [ 3:0] dma_rx_strb_o,
    output logic                dma_rx_last_o,
    output logic                dma_rx_id_o,
    output logic                dma_rx_dest_o,
    output logic                dma_rx_user_o,
    output logic                dma_tx_admit_o,
    output logic                dma_rx_admit_o,
    output logic                irq_o,
`ifdef PIOLITE_FORMAL_TOP
    output logic         [43:0] formal_sm0_o,
`endif
           apb4_if.slave        apb4
);
  piolite_if u_ctrl ();
  logic [ 1:0] s_guard_fault;
  logic [ 7:0] s_guard_fault_code [0:1];
  logic [ 1:0] s_session_live;
  logic        s_stream_fault;
  logic        s_stream_fault_sm;
  logic        s_dma_tx_push;
  logic [31:0] s_dma_tx_fifo_data;
  logic        s_dma_tx_sm;
  logic        s_dma_tx_accept;
  logic        s_dma_rx_pop;
  logic        s_dma_rx_sm;
  logic [31:0] s_dma_rx_fifo_data;
  logic        s_dma_rx_accept;
  logic        s_tx_held;
  logic        s_rx_held;
  logic        s_tx_closing;
  logic        s_rx_closing;

  always_comb begin
    for (integer index = 0; index < 2; index++) begin
      s_session_live[index] = (u_ctrl.runtime[index].state != piolite_pkg::Disabled) ||
          (u_ctrl.tx_level[index] != 4'd0) || (u_ctrl.rx_level[index] != 4'd0) ||
          (u_ctrl.tx_bind[31] && (u_ctrl.tx_bind[0] == index[0])) ||
          (u_ctrl.rx_bind[31] && (u_ctrl.rx_bind[0] == index[0])) ||
          (u_ctrl.tx_bind[31] && (u_ctrl.tx_bind[0] == index[0]) &&
           (dma_tx_job_i || s_tx_held)) ||
          (u_ctrl.rx_bind[31] && (u_ctrl.rx_bind[0] == index[0]) &&
           (dma_rx_job_i || s_rx_held));
    end
    dma_tx_admit_o = u_ctrl.tx_bind[31] && !s_tx_closing && !s_guard_fault[u_ctrl.tx_bind[0]];
    dma_rx_admit_o = u_ctrl.rx_bind[31] && !s_rx_closing && !s_guard_fault[u_ctrl.rx_bind[0]];
  end

  piolite_gpio_guard u_gpio_guard (
      .cfg_i           (u_ctrl.cfg),
      .runtime_i       (u_ctrl.runtime),
      .session_live_i  (s_session_live),
      .user_select_i   (user_select_i),
      .user_status_i   (user_status_i),
      .filter_enable_i (filter_enable_i),
      .gpio_ready_i    (gpio_ready_i),
      .start_guard_ok_o(u_ctrl.start_guard_ok),
      .cpu_guard_ok_o  (u_ctrl.cpu_guard_ok),
      .fault_valid_o   (s_guard_fault),
      .fault_code_o    (s_guard_fault_code),
      .gpio_value_o    (gpio_value_o),
      .gpio_oe_o       (gpio_oe_o)
  );

  piolite_dma_adapter u_dma_adapter (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .block_reset_i       (u_ctrl.cmd_block_reset),
      .sm_reset_i          (u_ctrl.cmd_sm_reset),
      .runtime_i           (u_ctrl.runtime),
      .tx_bind_i           (u_ctrl.tx_bind),
      .rx_bind_i           (u_ctrl.rx_bind),
      .guard_fault_i       (s_guard_fault),
      .rx_level_i          (u_ctrl.rx_level),
      .tx_valid_i          (dma_tx_valid_i),
      .tx_ready_o          (dma_tx_ready_o),
      .tx_data_i           (dma_tx_data_i),
      .tx_keep_i           (dma_tx_keep_i),
      .tx_strb_i           (dma_tx_strb_i),
      .tx_id_i             (dma_tx_id_i),
      .tx_dest_i           (dma_tx_dest_i),
      .tx_user_i           (dma_tx_user_i),
      .tx_last_i           (dma_tx_last_i),
      .tx_fifo_push_o      (s_dma_tx_push),
      .tx_fifo_data_o      (s_dma_tx_fifo_data),
      .tx_fifo_sm_o        (s_dma_tx_sm),
      .tx_fifo_accept_i    (s_dma_tx_accept),
      .rx_fifo_pop_o       (s_dma_rx_pop),
      .rx_fifo_sm_o        (s_dma_rx_sm),
      .rx_fifo_data_i      (s_dma_rx_fifo_data),
      .rx_fifo_accept_i    (s_dma_rx_accept),
      .rx_valid_o          (dma_rx_valid_o),
      .rx_ready_i          (dma_rx_ready_i),
      .rx_data_o           (dma_rx_data_o),
      .rx_keep_o           (dma_rx_keep_o),
      .rx_strb_o           (dma_rx_strb_o),
      .rx_last_o           (dma_rx_last_o),
      .rx_id_o             (dma_rx_id_o),
      .rx_dest_o           (dma_rx_dest_o),
      .rx_user_o           (dma_rx_user_o),
      .tx_held_o           (s_tx_held),
      .rx_held_o           (s_rx_held),
      .tx_closing_o        (s_tx_closing),
      .rx_closing_o        (s_rx_closing),
      .stream_fault_valid_o(s_stream_fault),
      .stream_fault_sm_o   (s_stream_fault_sm)
  );

  piolite_core u_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .pin_inputs_i      (gpio_input_i),
      .guard_fault_i     (s_guard_fault),
      .guard_fault_code_i(s_guard_fault_code),
      .stream_fault_i    (s_stream_fault),
      .stream_fault_sm_i (s_stream_fault_sm),
      .dma_tx_push_i     (s_dma_tx_push),
      .dma_tx_data_i     (s_dma_tx_fifo_data),
      .dma_tx_sm_i       (s_dma_tx_sm),
      .dma_tx_accept_o   (s_dma_tx_accept),
      .dma_rx_pop_i      (s_dma_rx_pop),
      .dma_rx_sm_i       (s_dma_rx_sm),
      .dma_rx_data_o     (s_dma_rx_fifo_data),
      .dma_rx_accept_o   (s_dma_rx_accept),
`ifdef PIOLITE_FORMAL_TOP
      .formal_sm0_o      (formal_sm0_o),
`endif
      .ctrl              (u_ctrl)
  );

  piolite_reg u_reg (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .clock_hz_i   (clock_hz_i),
      .user_select_i(user_select_i),
      .tx_job_i     (dma_tx_job_i),
      .rx_job_i     (dma_rx_job_i),
      .tx_held_i    (s_tx_held),
      .rx_held_i    (s_rx_held),
      .tx_closing_i (s_tx_closing),
      .rx_closing_i (s_rx_closing),
      .irq_o        (irq_o),
      .apb4         (apb4),
      .ctrl         (u_ctrl)
  );
`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      assert ((u_ctrl.runtime[0].output_oe & u_ctrl.runtime[1].output_oe) == 32'd0);
      for (integer index = 0; index < 2; index++) begin
        if (u_ctrl.runtime[index].state == piolite_pkg::Closing) begin
          assert (u_ctrl.runtime[index].output_oe == 32'd0);
          assert (!u_ctrl.cpu_tx_push[index] && !u_ctrl.cpu_rx_pop[index]);
        end
      end
    end
  end
`endif
endmodule
