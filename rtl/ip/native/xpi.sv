// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "xpi_define.svh"

interface xpi_if ();
  logic                    sck_o;
  logic [`XPI_NSS_NUM-1:0] nss_o;
  logic [             3:0] io_oe_o;
  logic [             3:0] io_di_i;
  logic [             3:0] io_do_o;
  logic                    irq_o;

  modport dut(
      output sck_o,
      output nss_o,
      output io_oe_o,
      input io_di_i,
      output io_do_o,
      output irq_o
  );
endinterface

module nmi_xpi (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic dma_xfer_done_i,
    output logic dma_tx_stall_o,
    output logic dma_rx_stall_o,
    nmi_if.slave nmi,
    xpi_if.dut  xpi
    // verilog_format: on
);

  // nss
  logic [`XPI_LNS_NUM-1:0] s_xpi_nss;
  // reg mode
  logic [            31:0] s_xpi_mmstad        [0:`XPI_NSS_NUM-1];
  logic [            31:0] s_xpi_mmoffst       [0:`XPI_NSS_NUM-1];
  logic                    s_xpi_mode          [0:`XPI_NSS_NUM-1];
  logic [`XPI_LNS_NUM-1:0] s_xpi_regnss;
  logic [             7:0] s_xpi_clkdiv        [0:`XPI_NSS_NUM-1];
  logic                    s_xpi_rdwr          [0:`XPI_NSS_NUM-1];
  logic                    s_xpi_revdat        [0:`XPI_NSS_NUM-1];
  logic [             7:0] s_xpi_txupb         [0:`XPI_NSS_NUM-1];
  logic [             7:0] s_xpi_txlowb        [0:`XPI_NSS_NUM-1];
  logic [             5:0] s_xpi_rxupb         [0:`XPI_NSS_NUM-1];
  logic [             5:0] s_xpi_rxlowb        [0:`XPI_NSS_NUM-1];
  logic [             1:0] s_xpi_cmdtyp        [0:`XPI_NSS_NUM-1];
  logic [             2:0] s_xpi_cmdlen        [0:`XPI_NSS_NUM-1];
  logic [            31:0] s_xpi_cmddat        [0:`XPI_NSS_NUM-1];
  logic [             1:0] s_xpi_adrtyp        [0:`XPI_NSS_NUM-1];
  logic [             2:0] s_xpi_adrlen        [0:`XPI_NSS_NUM-1];
  logic [            31:0] s_xpi_adrdat        [0:`XPI_NSS_NUM-1];
  logic [             1:0] s_xpi_alttyp        [0:`XPI_NSS_NUM-1];
  logic [             2:0] s_xpi_altlen        [0:`XPI_NSS_NUM-1];
  logic [            31:0] s_xpi_altdat        [0:`XPI_NSS_NUM-1];
  logic [             7:0] s_xpi_tdulen        [0:`XPI_NSS_NUM-1];
  logic [             7:0] s_xpi_rdulen        [0:`XPI_NSS_NUM-1];
  logic [             1:0] s_xpi_dattyp        [0:`XPI_NSS_NUM-1];
  logic [             7:0] s_xpi_datlen        [0:`XPI_NSS_NUM-1];
  logic [             2:0] s_xpi_datbit        [0:`XPI_NSS_NUM-1];
  logic [             7:0] s_xpi_hlvlen        [0:`XPI_NSS_NUM-1];
  // reg mode - fifo
  logic                    s_reg_tx_push_valid;
  logic [            31:0] s_reg_tx_push_data;
  logic                    s_reg_rx_pop_valid;
  // mm mode
  logic                    s_xpi_mm_sel;
  logic                    s_xpi_mm_req;
  logic [`XPI_LNS_NUM-1:0] s_xpi_mm_nss;
  logic                    s_xpi_mm_rd_st;
  logic                    s_xpi_mm_wr_st;
  logic                    s_xpi_mm_rdwr;
  logic [            31:0] s_xpi_mm_addr;
  logic [             2:0] s_xpi_mm_xfer_byte;
  // mm mode - fifo
  logic                    s_mm_tx_push_valid;
  logic [            31:0] s_mm_tx_push_data;
  logic                    s_mm_rx_pop_valid;
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
  assign s_xpi_mm_sel       = nmi.addr[31:28] == `FLASH_START || nmi.addr[31:28] == `QSPI_MEM_START;
  assign u_reg_nmi_if.valid = nmi.valid && (~s_xpi_mm_sel);
  assign u_reg_nmi_if.addr  = nmi.addr;
  assign u_reg_nmi_if.wdata = nmi.wdata;
  assign u_reg_nmi_if.wstrb = nmi.wstrb;

  assign u_mm_nmi_if.valid  = nmi.valid && s_xpi_mm_sel;
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
  assign s_xpi_nss       = s_xpi_mm_sel ? s_xpi_mm_nss : s_xpi_regnss;
  assign s_tx_push_valid = s_xpi_mm_sel ? s_mm_tx_push_valid : s_reg_tx_push_valid;
  assign s_tx_push_data  = s_xpi_mm_sel ? s_mm_tx_push_data  : s_reg_tx_push_data;
  assign s_rx_pop_valid  = s_xpi_mm_sel ? s_mm_rx_pop_valid  : s_reg_rx_pop_valid;
  assign s_xpi_mm_req    = s_xpi_mm_rd_st || s_xpi_mm_wr_st;


  xpi_reg u_xpi_reg (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      // reg
      .xpi_accmd_o    (),
      .xpi_mmstad_o   (s_xpi_mmstad),
      .xpi_mmoffst_o  (s_xpi_mmoffst),
      .xpi_mode_o     (s_xpi_mode),
      .xpi_regnss_o   (s_xpi_regnss),
      .xpi_clkdiv_o   (s_xpi_clkdiv),
      .xpi_rdwr_o     (s_xpi_rdwr),
      .xpi_revdat_o   (s_xpi_revdat),
      .xpi_tx_flush_o (s_tx_flush),
      .xpi_rx_flush_o (s_rx_flush),
      .xpi_cmdtyp_o   (s_xpi_cmdtyp),
      .xpi_cmdlen_o   (s_xpi_cmdlen),
      .xpi_cmddat_o   (s_xpi_cmddat),
      .xpi_adrtyp_o   (s_xpi_adrtyp),
      .xpi_adrlen_o   (s_xpi_adrlen),
      .xpi_adrdat_o   (s_xpi_adrdat),
      .xpi_alttyp_o   (s_xpi_alttyp),
      .xpi_altlen_o   (s_xpi_altlen),
      .xpi_altdat_o   (s_xpi_altdat),
      .xpi_tdulen_o   (s_xpi_tdulen),
      .xpi_rdulen_o   (s_xpi_rdulen),
      .xpi_dattyp_o   (s_xpi_dattyp),
      .xpi_datlen_o   (s_xpi_datlen),
      .xpi_datbit_o   (s_xpi_datbit),
      .xpi_hlvlen_o   (s_xpi_hlvlen),
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


  xpi_mm u_xpi_mm (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .xpi_mmstad_i   (s_xpi_mmstad),
      .xpi_mmoffst_i  (s_xpi_mmoffst),
      .nss_o          (s_xpi_mm_nss),
      .rd_st_o        (s_xpi_mm_rd_st),
      .wr_st_o        (s_xpi_mm_wr_st),
      .rdwr_o         (s_xpi_mm_rdwr),
      .addr_o         (s_xpi_mm_addr),
      .xfer_byte_o    (s_xpi_mm_xfer_byte),
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


  xpi_core u_xpi_core (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .nss_i(s_xpi_nss),
      .mode_i(s_xpi_mode[s_xpi_nss]),
      .clkdiv_i(s_xpi_clkdiv[s_xpi_nss]),
      .rdwr_i(u_mm_nmi_if.valid ? s_xpi_mm_rdwr : s_xpi_rdwr[s_xpi_nss]),
      .revdat_i(s_xpi_revdat[s_xpi_nss]),
      .cmdtyp_i(s_xpi_cmdtyp[s_xpi_nss]),
      .cmdlen_i(s_xpi_cmdlen[s_xpi_nss]),
      .cmddat_i(s_xpi_cmddat[s_xpi_nss]),
      .adrtyp_i(s_xpi_adrtyp[s_xpi_nss]),
      .adrlen_i(s_xpi_adrlen[s_xpi_nss]),
      // HACK:
      .adrdat_i(u_mm_nmi_if.valid ? {s_xpi_mm_addr[23:0], 8'hF0} : s_xpi_adrdat[s_xpi_nss]),
      .tdulen_i(s_xpi_tdulen[s_xpi_nss]),
      .rdulen_i(s_xpi_rdulen[s_xpi_nss]),
      .dattyp_i(s_xpi_dattyp[s_xpi_nss]),
      .datlen_i(s_xpi_datlen[s_xpi_nss]),  // NOTE:
      .datbit_i(u_mm_nmi_if.valid ? s_xpi_mm_xfer_byte : s_xpi_datbit[s_xpi_nss]),
      .hlvlen_i(s_xpi_hlvlen[s_xpi_nss]),
      .tx_data_req_o(s_tx_pop_valid),
      .tx_data_rdy_i(s_tx_pop_ready),
      .tx_data_i(s_tx_pop_data),
      .rx_data_req_o(s_rx_push_valid),
      .rx_data_rdy_i(s_rx_push_ready),
      .rx_data_o(s_rx_push_data),
      .start_i(u_mm_nmi_if.valid ? s_xpi_mm_req : s_reg_xfer_start),
      .done_o(s_xfer_done),
      .tx_elem_num_i(s_tx_elem_num[7:0]),
      .dma_xfer_done_i(dma_xfer_done_i),
      .xpi(xpi)
  );

endmodule
