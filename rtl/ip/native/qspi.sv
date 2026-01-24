// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "qspi_define.svh"

interface qspi_if ();
  logic                     spi_sck_o;
  logic [`QSPI_NSS_NUM-1:0] spi_nss_o;
  logic [              3:0] spi_io_en_o;
  logic [              3:0] spi_io_in_i;
  logic [              3:0] spi_io_out_o;
  logic                     irq_o;

  modport dut(
      output spi_sck_o,
      output spi_nss_o,
      output spi_io_en_o,
      input spi_io_in_i,
      output spi_io_out_o,
      output irq_o
  );

  // verilog_format: off
  modport tb(
      input spi_sck_o,
      input spi_nss_o,
      input spi_io_en_o,
      output spi_io_in_i,
      input spi_io_out_o,
      input irq_o
  );
  // verilog_format: on
endinterface

module nmi_qspi (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic dma_xfer_done_i,
    output logic dma_tx_stall_o,
    output logic dma_rx_stall_o,
    nmi_if.slave nmi,
    qspi_if.dut  qspi
    // verilog_format: on
);

  // nss
  logic [`QSPI_LNS_NUM-1:0] s_qspi_nss;
  // reg mode
  logic [             31:0] s_qspi_mmstad       [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_mmoffst      [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_mode         [0:`QSPI_NSS_NUM-1];
  logic [`QSPI_LNS_NUM-1:0] s_qspi_regnss;
  logic [              7:0] s_qspi_clkdiv       [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_rdwr         [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_revdat       [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_txupb        [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_txlowb       [0:`QSPI_NSS_NUM-1];
  logic [              5:0] s_qspi_rxupb        [0:`QSPI_NSS_NUM-1];
  logic [              5:0] s_qspi_rxlowb       [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_cmdtyp       [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_cmdlen       [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_cmddat       [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_adrtyp       [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_adrlen       [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_adrdat       [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_alttyp       [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_altlen       [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_altdat       [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_tdulen       [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_rdulen       [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_dattyp       [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_datlen       [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_datbit       [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_hlvlen       [0:`QSPI_NSS_NUM-1];
  // reg mode - fifo
  logic                     s_reg_tx_push_valid;
  logic [             31:0] s_reg_tx_push_data;
  logic                     s_reg_rx_pop_valid;
  // mm mode
  logic                     s_qspi_mm_sel;
  logic                     s_qspi_mm_req;
  logic [`QSPI_LNS_NUM-1:0] s_qspi_mm_nss;
  logic                     s_qspi_mm_rd_st;
  logic                     s_qspi_mm_wr_st;
  logic                     s_qspi_mm_rdwr;
  logic [             31:0] s_qspi_mm_addr;
  logic [              2:0] s_qspi_mm_xfer_byte;
  // mm mode - fifo
  logic                     s_mm_tx_push_valid;
  logic [             31:0] s_mm_tx_push_data;
  logic                     s_mm_rx_pop_valid;
  // tx fifo
  logic s_tx_push_valid, s_tx_push_ready;
  logic s_tx_pop_valid, s_tx_pop_ready;
  logic s_tx_empty, s_tx_full, s_tx_flush;
  logic [31:0] s_tx_push_data, s_tx_pop_data;
  logic [8:0] s_tx_elem_num;
  // rx fifo
  logic s_rx_push_valid, s_rx_push_ready;
  logic s_rx_pop_valid, s_rx_pop_ready;
  logic s_rx_empty, s_rx_full, s_rx_flush;
  logic [31:0] s_rx_push_data, s_rx_pop_data;
  logic [6:0] s_rx_elem_num;
  // ctrl
  logic s_reg_xfer_start, s_xfer_done;
  // interface
  nmi_if u_reg_nmi_if ();
  nmi_if u_mm_nmi_if ();


  // nmi mux
  assign s_qspi_mm_sel      = nmi.addr[31:28] == `FLASH_START || nmi.addr[31:28] == `QSPI_MEM_START;
  assign u_reg_nmi_if.valid = nmi.valid && (~s_qspi_mm_sel);
  assign u_reg_nmi_if.addr  = nmi.addr;
  assign u_reg_nmi_if.wdata = nmi.wdata;
  assign u_reg_nmi_if.wstrb = nmi.wstrb;

  assign u_mm_nmi_if.valid  = nmi.valid && s_qspi_mm_sel;
  assign u_mm_nmi_if.addr   = nmi.addr;
  assign u_mm_nmi_if.wdata  = nmi.wdata;
  assign u_mm_nmi_if.wstrb  = nmi.wstrb;

  // verilog_format: off
  assign nmi.ready = (u_reg_nmi_if.valid & u_reg_nmi_if.ready) |
                     (u_mm_nmi_if.valid  & u_mm_nmi_if.ready);

  assign nmi.rdata = ({32{(u_reg_nmi_if.valid & u_reg_nmi_if.ready)}} & u_reg_nmi_if.rdata) |
                     ({32{(u_mm_nmi_if.valid  & u_mm_nmi_if.ready)}}  & u_mm_nmi_if.rdata);
  // verilog_format: on

  // reg/mm mode nss
  assign s_qspi_nss      = s_qspi_mm_sel ? s_qspi_mm_nss : s_qspi_regnss;
  assign s_tx_push_valid = s_qspi_mm_sel ? s_mm_tx_push_valid : s_reg_tx_push_valid;
  assign s_tx_push_data  = s_qspi_mm_sel ? s_mm_tx_push_data  : s_reg_tx_push_data;
  assign s_rx_pop_valid  = s_qspi_mm_sel ? s_mm_rx_pop_valid  : s_reg_rx_pop_valid;
  assign s_qspi_mm_req   = s_qspi_mm_rd_st || s_qspi_mm_wr_st;


  qspi_reg u_qspi_reg (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      // reg
      .qspi_accmd_o   (),
      .qspi_mmstad_o  (s_qspi_mmstad),
      .qspi_mmoffst_o (s_qspi_mmoffst),
      .qspi_mode_o    (s_qspi_mode),
      .qspi_regnss_o  (s_qspi_regnss),
      .qspi_clkdiv_o  (s_qspi_clkdiv),
      .qspi_rdwr_o    (s_qspi_rdwr),
      .qspi_revdat_o  (s_qspi_revdat),
      .qspi_tx_flush_o(s_tx_flush),
      .qspi_rx_flush_o(s_rx_flush),
      .qspi_cmdtyp_o  (s_qspi_cmdtyp),
      .qspi_cmdlen_o  (s_qspi_cmdlen),
      .qspi_cmddat_o  (s_qspi_cmddat),
      .qspi_adrtyp_o  (s_qspi_adrtyp),
      .qspi_adrlen_o  (s_qspi_adrlen),
      .qspi_adrdat_o  (s_qspi_adrdat),
      .qspi_alttyp_o  (s_qspi_alttyp),
      .qspi_altlen_o  (s_qspi_altlen),
      .qspi_altdat_o  (s_qspi_altdat),
      .qspi_tdulen_o  (s_qspi_tdulen),
      .qspi_rdulen_o  (s_qspi_rdulen),
      .qspi_dattyp_o  (s_qspi_dattyp),
      .qspi_datlen_o  (s_qspi_datlen),
      .qspi_datbit_o  (s_qspi_datbit),
      .qspi_hlvlen_o  (s_qspi_hlvlen),
      // tx fifo
      .tx_push_valid_o(s_reg_tx_push_valid),
      .tx_push_data_o (s_reg_tx_push_data),
      .tx_full_i      (s_tx_full),
      .tx_empty_i     (s_tx_empty),
      .tx_elem_num_i  (s_tx_elem_num),
      // rx fifo
      .rx_pop_valid_o (s_reg_rx_pop_valid),
      .rx_pop_data_i  (s_rx_pop_data),
      .rx_full_i      (s_rx_full),
      .rx_empty_i     (s_rx_empty),
      .rx_elem_num_i  (s_rx_elem_num),
      // ctrl
      .xfer_start_o   (s_reg_xfer_start),
      .xfer_done_i    (s_xfer_done),
      // dma
      .dma_tx_stall_o (dma_tx_stall_o),
      .dma_rx_stall_o (dma_rx_stall_o),
      .nmi            (u_reg_nmi_if)
  );


  qspi_mm u_qspi_mm (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .qspi_mmstad_i  (s_qspi_mmstad),
      .qspi_mmoffst_i (s_qspi_mmoffst),
      .nss_o          (s_qspi_mm_nss),
      .rd_st_o        (s_qspi_mm_rd_st),
      .wr_st_o        (s_qspi_mm_wr_st),
      .rdwr_o         (s_qspi_mm_rdwr),
      .addr_o         (s_qspi_mm_addr),
      .xfer_byte_o    (s_qspi_mm_xfer_byte),
      // tx fifo
      .tx_push_valid_o(s_mm_tx_push_valid),
      .tx_push_data_o (s_mm_tx_push_data),
      .tx_push_ready_i(s_tx_push_ready),
      // rx fifo
      .rx_pop_valid_o (s_mm_rx_pop_valid),
      .rx_pop_data_i  (s_rx_pop_data),
      .rx_pop_ready_i (s_rx_pop_ready),
      // ctrl
      .xfer_done_i    (s_xfer_done),
      .nmi            (u_mm_nmi_if)
  );



  assign s_tx_push_ready = ~s_tx_full;
  assign s_tx_pop_ready  = ~s_tx_empty;
  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(256)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_tx_flush),
      .push_i (s_tx_push_valid),
      .full_o (s_tx_full),
      .dat_i  (s_tx_push_data),
      .pop_i  (s_tx_pop_valid),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data),
      .cnt_o  (s_tx_elem_num)
  );

  // rx fifo
  assign s_rx_push_ready = ~s_rx_full;
  assign s_rx_pop_ready  = ~s_rx_empty;
  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(64)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_rx_flush),
      .push_i (s_rx_push_valid),
      .full_o (s_rx_full),
      .dat_i  (s_rx_push_data),
      .pop_i  (s_rx_pop_valid),
      .empty_o(s_rx_empty),
      .dat_o  (s_rx_pop_data),
      .cnt_o  (s_rx_elem_num)
  );


  qspi_core u_qspi_core (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .nss_i(s_qspi_nss),
      .mode_i(s_qspi_mode[s_qspi_nss]),
      .clkdiv_i(s_qspi_clkdiv[s_qspi_nss]),
      .rdwr_i(u_mm_nmi_if.valid ? s_qspi_mm_rdwr : s_qspi_rdwr[s_qspi_nss]),
      .revdat_i(s_qspi_revdat[s_qspi_nss]),
      .cmdtyp_i(s_qspi_cmdtyp[s_qspi_nss]),
      .cmdlen_i(s_qspi_cmdlen[s_qspi_nss]),
      .cmddat_i(s_qspi_cmddat[s_qspi_nss]),
      .adrtyp_i(s_qspi_adrtyp[s_qspi_nss]),
      .adrlen_i(s_qspi_adrlen[s_qspi_nss]),
      // HACK:
      .adrdat_i(u_mm_nmi_if.valid ? {s_qspi_mm_addr[23:0], 8'hF0} : s_qspi_adrdat[s_qspi_nss]),
      .tdulen_i(s_qspi_tdulen[s_qspi_nss]),
      .rdulen_i(s_qspi_rdulen[s_qspi_nss]),
      .dattyp_i(s_qspi_dattyp[s_qspi_nss]),
      .datlen_i(s_qspi_datlen[s_qspi_nss]),  // NOTE:
      .datbit_i(u_mm_nmi_if.valid ? s_qspi_mm_xfer_byte : s_qspi_datbit[s_qspi_nss]),
      .hlvlen_i(s_qspi_hlvlen[s_qspi_nss]),
      .tx_data_req_o(s_tx_pop_valid),
      .tx_data_rdy_i(s_tx_pop_ready),
      .tx_data_i(s_tx_pop_data),
      .rx_data_req_o(s_rx_push_valid),
      .rx_data_rdy_i(s_rx_push_ready),
      .rx_data_o(s_rx_push_data),
      .start_i(u_mm_nmi_if.valid ? s_qspi_mm_req : s_reg_xfer_start),
      .done_o(s_xfer_done),
      .tx_elem_num_i(s_tx_elem_num[7:0]),
      .dma_xfer_done_i(dma_xfer_done_i),
      .qspi(qspi)
  );

endmodule
