// SPI-P2 source-qualified fixed-MMIO credit pacing.
// A reservation is held from DMA admission until terminal response retirement.
module spi_dma_pacing (
    input  logic        clk_i,
    rst_n_i,
    input  logic        enable_i,
    input  logic [31:0] tx_binding_i,
    rx_binding_i,
    input  logic [ 1:0] dma_start_pending_i,
    input  logic [ 3:0] dma_status_i,
    input  logic        dma_error_i,
    input  logic [ 1:0] credit_valid_i,
    credit_retire_i,
    input  logic [ 1:0] credit_commit_i,
    output logic [ 1:0] credit_valid_o,
    credit_retire_o,
    output logic [ 1:0] credit_pending_o,
    output logic [ 3:0] dma_status_o,
    output logic        credit_fault_o,
    busy_o
);
  logic [1:0] s_reserved_d, s_reserved_q;
  logic s_binding_conflict;
  logic s_unused;

  assign s_binding_conflict = tx_binding_i[31] && rx_binding_i[31] &&
      (tx_binding_i[2:0] == rx_binding_i[2:0]);
  assign s_unused = ^{tx_binding_i[30:3], rx_binding_i[30:3]};
  assign credit_valid_o = enable_i ? credit_valid_i & ~s_reserved_q : 2'd0;
  assign credit_retire_o = credit_retire_i;
  assign credit_pending_o = s_reserved_q | credit_valid_o;
  assign dma_status_o = dma_status_i | {credit_pending_o, 2'd0};
  assign busy_o = (dma_status_o != 4'd0) || (dma_start_pending_i != 2'd0) ||
      (credit_pending_o != 2'd0);
  assign credit_fault_o = (!enable_i && ((credit_valid_i != 2'd0) ||
      (credit_commit_i != 2'd0))) || s_binding_conflict || dma_error_i || (s_unused && 1'b0);

  always_comb begin
    s_reserved_d = s_reserved_q;
    s_reserved_d = s_reserved_d & ~credit_retire_i;
    s_reserved_d = s_reserved_d | credit_commit_i;
    if (!enable_i && (credit_retire_i == 2'd0)) s_reserved_d = '0;
  end

  dffr #(
      .DATA_WIDTH(2)
  ) u_reserved (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reserved_d),
      .dat_o  (s_reserved_q)
  );
endmodule
