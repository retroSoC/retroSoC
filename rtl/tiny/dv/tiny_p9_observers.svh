// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
// Verification-only session counters. Count actual FIFO handshakes, including
// PIO pops. They are neither hardware registers nor a worst-case rate bound.
integer p9_accepted_words = 0;
integer p9_delivered_words = 0;
integer p9_fifo_high_water = 0;
integer p9_stall_run = 0;
integer p9_backpressure = 0;
integer p9_ifetch_completions = 0;
integer p9_xpi_completions = 0;
integer p9_last_progress = 0;
bit     p9_reported = 0;
// sv2v lowers packed structs to plain vectors with identical bit layout, so
// the Icarus flow sees only the vector form of these DUT structs. Slice the
// packed views directly; identical bit ranges work in the Verilator view.
localparam int P9_REQ_STATE_LO = 73;  // tiny_cpu_mem request_t state[2:0]
localparam int P9_REQ_STATE_HI = 75;
localparam int P9_REQ_ADDR_LO = 41;  // request_t addr[31:0]
localparam int P9_REQ_ADDR_HI = 72;
localparam int P9_REQ_DATA_LO = 9;  // request_t data[31:0]
localparam int P9_REQ_DATA_HI = 40;
localparam int P9_REQ_WRITE = 5;  // request_t write
localparam int P9_SLOW_STATE_LO = 102;  // tiny_cpu_mem slow_t state[1:0]
localparam int P9_SLOW_STATE_HI = 103;
localparam int P9_SLOW_OWNER = 101;  // slow_t owner
localparam int P9_SLOW_WRITE = 100;  // slow_t write
localparam int P9_SLOW_ADDR_LO = 64;  // slow_t addr[31:0]
localparam int P9_SLOW_ADDR_HI = 95;
localparam int P9_CDC_STATE_LO = 110;  // tiny_apb_async_bridge src_t/dst_t state[1:0]
localparam int P9_CDC_STATE_HI = 111;
`include "tiny_p9_monitor.svh"
always @(posedge u_dut.u_soc.u_dvp.s_pclk_sel) begin
  if ($test$plusargs(
          "tiny_p9_camera"
      ) && u_dut.u_soc.u_dvp.s_pclk_rst_n && u_dut.u_soc.u_dvp.s_core_push_valid &&
          u_dut.u_soc.u_dvp.s_fifo_src_ready) begin
    p9_accepted_words = p9_accepted_words + 1;
    if (p9_accepted_words - p9_delivered_words > p9_fifo_high_water)
      p9_fifo_high_water = p9_accepted_words - p9_delivered_words;
  end
end

// Opt-in diagnostic only. These observers never drive the design and do not
// enable the serial UART character observer selected by tiny_p9_progress.
bit p9_diag_enabled = 0;
bit p9_diag_camera_started = 0;
bit p9_diag_pin15_seen = 0;
bit p9_diag_ended = 0;
integer p9_diag_file = 0;
string p9_diag_path;
string p9_diag_uart_line = "";
longint unsigned p9_diag_ref_cycles = 0;
longint unsigned p9_diag_sys_cycles = 0;
longint unsigned p9_diag_core_cycles = 0;
longint unsigned p9_diag_gpio_cycles = 0;
longint unsigned p9_diag_uart_cycles = 0;
longint unsigned p9_diag_pin15_cycle = 0;
longint unsigned p9_diag_uart_pushes = 0;
longint unsigned p9_diag_uart_pops = 0;
longint unsigned p9_diag_xpi_apb_requests = 0;
longint unsigned p9_diag_xpi_apb_responses = 0;
longint unsigned p9_diag_xpi_apb_wait = 0;
longint unsigned p9_diag_post_pin15_cycles = 100000;
bit p9_diag_xpi_apb_pending = 0;

// Endpoint numbers: 0=GPIO SYS, 1=GPIO leaf, 2=UART SYS, 3=UART leaf.
wire [3:0] p9_diag_apb_clk = {
  u_dut.u_soc.s_uart0_clk, u_dut.u_soc.s_exec_clk, u_dut.u_soc.s_gpio_clk, u_dut.u_soc.s_exec_clk
};
wire [3:0] p9_diag_apb_reset = {
  u_dut.u_soc.s_uart0_rst_n,
  u_dut.u_soc.s_fabric_rst_n,
  u_dut.u_soc.s_gpio_rst_n,
  u_dut.u_soc.s_fabric_rst_n
};
wire [3:0] p9_diag_apb_sel = {
  u_dut.u_soc.u_uart0_apb4_if.psel,
  u_dut.u_soc.u_uart0_sys_apb4_if.psel,
  u_dut.u_soc.u_gpio_apb4_if.psel,
  u_dut.u_soc.u_gpio_sys_apb4_if.psel
};
wire [3:0] p9_diag_apb_enable = {
  u_dut.u_soc.u_uart0_apb4_if.penable,
  u_dut.u_soc.u_uart0_sys_apb4_if.penable,
  u_dut.u_soc.u_gpio_apb4_if.penable,
  u_dut.u_soc.u_gpio_sys_apb4_if.penable
};
wire [3:0] p9_diag_apb_ready = {
  u_dut.u_soc.u_uart0_apb4_if.pready,
  u_dut.u_soc.u_uart0_sys_apb4_if.pready,
  u_dut.u_soc.u_gpio_apb4_if.pready,
  u_dut.u_soc.u_gpio_sys_apb4_if.pready
};
wire [3:0] p9_diag_apb_error = {
  u_dut.u_soc.u_uart0_apb4_if.pslverr,
  u_dut.u_soc.u_uart0_sys_apb4_if.pslverr,
  u_dut.u_soc.u_gpio_apb4_if.pslverr,
  u_dut.u_soc.u_gpio_sys_apb4_if.pslverr
};
wire [3:0] p9_diag_apb_write = {
  u_dut.u_soc.u_uart0_apb4_if.pwrite,
  u_dut.u_soc.u_uart0_sys_apb4_if.pwrite,
  u_dut.u_soc.u_gpio_apb4_if.pwrite,
  u_dut.u_soc.u_gpio_sys_apb4_if.pwrite
};
wire [3:0][31:0] p9_diag_apb_addr = {
  u_dut.u_soc.u_uart0_apb4_if.paddr,
  u_dut.u_soc.u_uart0_sys_apb4_if.paddr,
  u_dut.u_soc.u_gpio_apb4_if.paddr,
  u_dut.u_soc.u_gpio_sys_apb4_if.paddr
};
wire [3:0][31:0] p9_diag_apb_wdata = {
  u_dut.u_soc.u_uart0_apb4_if.pwdata,
  u_dut.u_soc.u_uart0_sys_apb4_if.pwdata,
  u_dut.u_soc.u_gpio_apb4_if.pwdata,
  u_dut.u_soc.u_gpio_sys_apb4_if.pwdata
};
wire [3:0][31:0] p9_diag_apb_rdata = {
  u_dut.u_soc.u_uart0_apb4_if.prdata,
  u_dut.u_soc.u_uart0_sys_apb4_if.prdata,
  u_dut.u_soc.u_gpio_apb4_if.prdata,
  u_dut.u_soc.u_gpio_sys_apb4_if.prdata
};
wire [3:0][3:0] p9_diag_apb_strb = {
  u_dut.u_soc.u_uart0_apb4_if.pstrb,
  u_dut.u_soc.u_uart0_sys_apb4_if.pstrb,
  u_dut.u_soc.u_gpio_apb4_if.pstrb,
  u_dut.u_soc.u_gpio_sys_apb4_if.pstrb
};

initial begin
  p9_diag_enabled = $test$plusargs("tiny_p9_diag");
  if (p9_diag_enabled) begin
    if ($test$plusargs("tiny_p9_diag_long")) p9_diag_post_pin15_cycles = 2000000;
    if ($test$plusargs("tiny_p9_progress"))
      $fatal(1, "P9_DIAG_ERROR diagnostic and legacy UART progress are mutually exclusive");
    if (!$value$plusargs("tiny_p9_diag_log=%s", p9_diag_path))
      $fatal(1, "P9_DIAG_ERROR missing diagnostic log path");
    p9_diag_file = $fopen(p9_diag_path, "w");
    if (p9_diag_file == 0) $fatal(1, "P9_DIAG_ERROR cannot open diagnostic log");
    $fdisplay(
        p9_diag_file,
        "P9_DIAG_BEGIN version=1 time_unit=ns ref_interval=10000 post_pin15=%0d cycle_limit=5000000",
        p9_diag_post_pin15_cycles);
    $fflush(p9_diag_file);
    $display("P9_DIAG_BEGIN passive GPIO/UART diagnostic only");
  end
end

// The XPI controller is clocked in the memory domain, so keep this endpoint
// separate from the SYS/PCLK APB vector above. This is passive diagnostic data
// only; it does not alter APB handshakes or the controller state.
always @(posedge u_dut.u_soc.s_backend_mem_clk) begin
  if (p9_diag_enabled && p9_diag_file != 0) begin
    if (!u_dut.u_soc.s_xpi_rst_n) begin
      p9_diag_xpi_apb_pending = 0;
      p9_diag_xpi_apb_wait    = 0;
    end else if (u_dut.u_soc.u_xpi_apb4_if.psel && u_dut.u_soc.u_xpi_apb4_if.penable) begin
      if (!p9_diag_xpi_apb_pending) begin
        p9_diag_xpi_apb_pending = 1;
        p9_diag_xpi_apb_requests++;
        p9_diag_xpi_apb_wait = 0;
        if (p9_diag_camera_started)
          $fdisplay(
              p9_diag_file,
              "P9_DIAG_XPI_APB_REQ time_ns=%0.3f ref=%0d seq=%0d addr=%h write=%b wdata=%h strb=%h",
              $realtime,
              p9_diag_ref_cycles,
              p9_diag_xpi_apb_requests,
              u_dut.u_soc.u_xpi_apb4_if.paddr,
              u_dut.u_soc.u_xpi_apb4_if.pwrite,
              u_dut.u_soc.u_xpi_apb4_if.pwdata,
              u_dut.u_soc.u_xpi_apb4_if.pstrb
          );
      end
      if (u_dut.u_soc.u_xpi_apb4_if.pready) begin
        p9_diag_xpi_apb_responses++;
        if (p9_diag_camera_started)
          $fdisplay(
              p9_diag_file,
              "P9_DIAG_XPI_APB_RESP time_ns=%0.3f ref=%0d seq=%0d wait=%0d error=%b rdata=%h",
              $realtime,
              p9_diag_ref_cycles,
              p9_diag_xpi_apb_requests,
              p9_diag_xpi_apb_wait,
              u_dut.u_soc.u_xpi_apb4_if.pslverr,
              u_dut.u_soc.u_xpi_apb4_if.prdata
          );
        p9_diag_xpi_apb_pending = 0;
        p9_diag_xpi_apb_wait    = 0;
      end else p9_diag_xpi_apb_wait++;
    end
  end
end

task automatic p9_diag_finish(input string reason);
  p9_diag_ended = 1;
  $fdisplay(p9_diag_file, "P9_DIAG_END reason=%s ref=%0d pin15=%0d pin15_ref=%0d", reason,
            p9_diag_ref_cycles, p9_diag_pin15_seen, p9_diag_pin15_cycle);
  $fflush(p9_diag_file);
  $fclose(p9_diag_file);
  p9_diag_file = 0;
  $display("P9_DIAG_END reason=%s ref=%0d diagnostic_only=1", reason, p9_diag_ref_cycles);
  $finish;
endtask

always @(posedge u_dut.u_soc.u_cpu.s_cpu_clk) if (p9_diag_enabled) p9_diag_core_cycles++;
always @(posedge u_dut.u_soc.s_gpio_clk) if (p9_diag_enabled) p9_diag_gpio_cycles++;
always @(posedge u_dut.u_soc.s_exec_clk) if (p9_diag_enabled) p9_diag_sys_cycles++;
always @(posedge u_dut.u_soc.s_uart0_clk) begin
  if (p9_diag_enabled && p9_diag_file != 0) begin
    p9_diag_uart_cycles++;
    if (u_dut.u_soc.s_uart0_rst_n) begin
      if (u_dut.u_soc.u_uart0.s_tx_data_pop) p9_diag_uart_pops++;
      if (u_dut.u_soc.u_uart0.u_uart_reg.s_tx_push && !u_dut.u_soc.u_uart0.s_loopback) begin
        p9_diag_uart_pushes++;
        if (u_dut.u_soc.u_uart0_apb4_if.pwdata[7:0] == 8'd10) begin
          if (p9_diag_uart_line == "P9_STAGE CAMERA_PINS_START") p9_diag_camera_started = 1;
          if (p9_diag_uart_line == "P9_STAGE CAMERA_PIN pin=15" && !p9_diag_pin15_seen) begin
            p9_diag_pin15_seen  = 1;
            p9_diag_pin15_cycle = p9_diag_ref_cycles;
          end
          $fdisplay(p9_diag_file, "P9_DIAG_UART time_ns=%0.3f ref=%0d line=%s", $realtime,
                    p9_diag_ref_cycles, p9_diag_uart_line);
          $fflush(p9_diag_file);
          p9_diag_uart_line = "";
        end else if (u_dut.u_soc.u_uart0_apb4_if.pwdata[7:0] != 8'd13) begin
          if (p9_diag_uart_line.len() >= 256)
            $fatal(1, "P9_DIAG_ERROR diagnostic UART line exceeded 256 bytes");
          p9_diag_uart_line = {
            p9_diag_uart_line, $sformatf("%c", u_dut.u_soc.u_uart0_apb4_if.pwdata[7:0])
          };
        end
      end
    end
  end
end

for (genvar port_index = 0; port_index < 2; port_index++) begin : gen_p9_diag_cpu
  longint unsigned requests = 0, responses = 0, wait_cycles = 0;
  logic [31:0] last_response_addr = 0;
  always @(posedge u_dut.u_soc.s_exec_clk) begin
    if (p9_diag_enabled && u_dut.u_soc.s_core_rst_n) begin
      if (u_dut.u_soc.u_cpu_ahbl_if[port_index].hready &&
          u_dut.u_soc.u_cpu_ahbl_if[port_index].htrans[1])
        requests++;
      // s_terminal retires the saved request; HREADY/HTRANS alone accepts
      // an address and must not be mislabeled as instruction retirement.
      if (u_dut.u_soc.u_cpu_mem.s_terminal[port_index]) begin
        responses++;
        last_response_addr = u_dut.u_soc.u_cpu_mem.s_req_q[port_index][P9_REQ_ADDR_HI:P9_REQ_ADDR_LO];
        wait_cycles = 0;
      end else if (u_dut.u_soc.u_cpu_mem.s_req_q[port_index][P9_REQ_STATE_HI:P9_REQ_STATE_LO] != 0)
        wait_cycles++;
      else wait_cycles = 0;
    end else wait_cycles = 0;
  end
  always @(negedge s_clk) begin
    if (p9_diag_enabled && p9_diag_file != 0 && p9_diag_ref_cycles % 10000 == 0) begin
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_CPU time_ns=%0.3f ref=%0d port=%0d requests=%0d responses=%0d wait=%0d addr=%h write=%b trans=%b ready=%b resp=%b state=%0d saved_addr=%h saved_data=%h saved_write=%b last_response_addr=%h",
          $realtime, p9_diag_ref_cycles, port_index, requests, responses, wait_cycles,
          u_dut.u_soc.u_cpu_ahbl_if[port_index].haddr, u_dut.u_soc.u_cpu_ahbl_if[port_index].hwrite,
          u_dut.u_soc.u_cpu_ahbl_if[port_index].htrans,
          u_dut.u_soc.u_cpu_ahbl_if[port_index].hready, u_dut.u_soc.u_cpu_ahbl_if[port_index].hresp,
          u_dut.u_soc.u_cpu_mem.s_req_q[port_index][P9_REQ_STATE_HI:P9_REQ_STATE_LO],
          u_dut.u_soc.u_cpu_mem.s_req_q[port_index][P9_REQ_ADDR_HI:P9_REQ_ADDR_LO],
          u_dut.u_soc.u_cpu_mem.s_req_q[port_index][P9_REQ_DATA_HI:P9_REQ_DATA_LO],
          u_dut.u_soc.u_cpu_mem.s_req_q[port_index][P9_REQ_WRITE], last_response_addr);
      $fflush(p9_diag_file);
    end
  end
end

for (genvar endpoint = 0; endpoint < 4; endpoint++) begin : gen_p9_diag_apb
  bit pending = 0;
  longint unsigned requests = 0, responses = 0, wait_cycles = 0;
  always @(posedge p9_diag_apb_clk[endpoint]) begin
    if (p9_diag_enabled && p9_diag_file != 0) begin
      if (!p9_diag_apb_reset[endpoint]) begin
        if (pending && p9_diag_camera_started)
          $fdisplay(
              p9_diag_file,
              "P9_DIAG_APB_RESET time_ns=%0.3f endpoint=%0d seq=%0d",
              $realtime,
              endpoint,
              requests
          );
        pending     = 0;
        wait_cycles = 0;
      end else if (p9_diag_apb_sel[endpoint] && p9_diag_apb_enable[endpoint]) begin
        if (!pending) begin
          pending = 1;
          requests++;
          wait_cycles = 0;
          if (p9_diag_camera_started)
            $fdisplay(
                p9_diag_file,
                "P9_DIAG_APB_REQ time_ns=%0.3f endpoint=%0d seq=%0d addr=%h write=%b wdata=%h strb=%h",
                $realtime,
                endpoint,
                requests,
                p9_diag_apb_addr[endpoint],
                p9_diag_apb_write[endpoint],
                p9_diag_apb_wdata[endpoint],
                p9_diag_apb_strb[endpoint]
            );
        end
        if (p9_diag_apb_ready[endpoint]) begin
          responses++;
          if (p9_diag_camera_started)
            $fdisplay(
                p9_diag_file,
                "P9_DIAG_APB_RESP time_ns=%0.3f endpoint=%0d seq=%0d wait=%0d error=%b rdata=%h",
                $realtime,
                endpoint,
                requests,
                wait_cycles,
                p9_diag_apb_error[endpoint],
                p9_diag_apb_rdata[endpoint]
            );
          pending     = 0;
          wait_cycles = 0;
        end else wait_cycles++;
      end
    end
  end
  always @(negedge s_clk) begin
    if (p9_diag_enabled && p9_diag_file != 0 && p9_diag_ref_cycles % 10000 == 0) begin
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_APB time_ns=%0.3f ref=%0d endpoint=%0d reset=%b pending=%b requests=%0d responses=%0d wait=%0d sel=%b enable=%b ready=%b error=%b addr=%h write=%b wdata=%h rdata=%h",
          $realtime, p9_diag_ref_cycles, endpoint, p9_diag_apb_reset[endpoint], pending, requests,
          responses, wait_cycles, p9_diag_apb_sel[endpoint], p9_diag_apb_enable[endpoint],
          p9_diag_apb_ready[endpoint], p9_diag_apb_error[endpoint], p9_diag_apb_addr[endpoint],
          p9_diag_apb_write[endpoint], p9_diag_apb_wdata[endpoint], p9_diag_apb_rdata[endpoint]);
      $fflush(p9_diag_file);
    end
  end
end

always @(posedge s_clk) if (p9_diag_enabled) p9_diag_ref_cycles++;
// Sample a half REF cycle after the edge counters and native endpoint events.
always @(negedge s_clk) begin
  if (p9_diag_enabled && p9_diag_file != 0 && !p9_diag_ended) begin
    if (p9_diag_ref_cycles % 10000 == 0) begin
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_CLOCK time_ns=%0.3f ref=%0d sys=%0d core=%0d gpio=%0d uart=%0d boot=%b core_reset=%b fabric_reset=%b gated=%h disabled=%h clock_block=%b periph_block=%b",
          $realtime, p9_diag_ref_cycles, p9_diag_sys_cycles, p9_diag_core_cycles,
          p9_diag_gpio_cycles, p9_diag_uart_cycles, u_dut.u_soc.s_boot_release_q,
          u_dut.u_soc.s_core_rst_n, u_dut.u_soc.s_fabric_rst_n, u_dut.u_soc.s_actual_gate,
          u_dut.u_soc.s_disabled_sys, u_dut.u_soc.s_clock_block, u_dut.u_soc.s_periph_block);
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_SLOW time_ns=%0.3f ref=%0d owner=%b state=%0d addr=%h write=%b ahb_trans=%b ahb_ready=%b ahb_resp=%b aw=%b/%b w=%b/%b b=%b/%b bresp=%b ar=%b/%b r=%b/%b rresp=%b",
          $realtime, p9_diag_ref_cycles, u_dut.u_soc.u_cpu_mem.s_slow_q[P9_SLOW_OWNER],
          u_dut.u_soc.u_cpu_mem.s_slow_q[P9_SLOW_STATE_HI:P9_SLOW_STATE_LO],
          u_dut.u_soc.u_cpu_mem.s_slow_q[P9_SLOW_ADDR_HI:P9_SLOW_ADDR_LO],
          u_dut.u_soc.u_cpu_mem.s_slow_q[P9_SLOW_WRITE],
          u_dut.u_soc.u_cpu_mem.u_slow_ahbl_if.htrans, u_dut.u_soc.u_cpu_mem.u_slow_ahbl_if.hready,
          u_dut.u_soc.u_cpu_mem.u_slow_ahbl_if.hresp, u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.awvalid,
          u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.awready,
          u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.wvalid, u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.wready,
          u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.bvalid, u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.bready,
          u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.bresp, u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.arvalid,
          u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.arready, u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.rvalid,
          u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.rready, u_dut.u_soc.u_cpu_mem.u_slow_axi4_if.rresp);
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_CDC time_ns=%0.3f ref=%0d gpio_src=%0d gpio_dst=%0d gpio_link=%b/%b gpio_ready=%b uart_src=%0d uart_dst=%0d uart_link=%b/%b uart_ready=%b",
          $realtime, p9_diag_ref_cycles,
          u_dut.u_soc.u_gpio_cfg_cdc.s_src_q[P9_CDC_STATE_HI:P9_CDC_STATE_LO],
          u_dut.u_soc.u_gpio_cfg_cdc.s_dst_q[P9_CDC_STATE_HI:P9_CDC_STATE_LO],
          u_dut.u_soc.u_gpio_cfg_cdc.s_link_src_rst_n, u_dut.u_soc.u_gpio_cfg_cdc.s_link_dst_rst_n,
          u_dut.u_soc.s_apb_cdc_ready[0],
          u_dut.u_soc.u_uart0_cfg_cdc.s_src_q[P9_CDC_STATE_HI:P9_CDC_STATE_LO],
          u_dut.u_soc.u_uart0_cfg_cdc.s_dst_q[P9_CDC_STATE_HI:P9_CDC_STATE_LO],
          u_dut.u_soc.u_uart0_cfg_cdc.s_link_src_rst_n,
          u_dut.u_soc.u_uart0_cfg_cdc.s_link_dst_rst_n, u_dut.u_soc.s_apb_cdc_ready[1]);
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_TX time_ns=%0.3f ref=%0d pushes=%0d pops=%0d count=%0d full=%b enable=%b config_valid=%b busy=%b pop=%b flow_blocked=%b baud_int=%0d baud_frac=%0d",
          $realtime, p9_diag_ref_cycles, p9_diag_uart_pushes, p9_diag_uart_pops,
          u_dut.u_soc.u_uart0.u_uart_reg.s_tx_count, u_dut.u_soc.u_uart0.u_uart_reg.s_tx_full,
          u_dut.u_soc.u_uart0.s_tx_en, u_dut.u_soc.u_uart0.u_uart_reg.s_config_valid,
          u_dut.u_soc.u_uart0.s_tx_busy, u_dut.u_soc.u_uart0.s_tx_data_pop,
          u_dut.u_soc.u_uart0.s_tx_flow_blocked, u_dut.u_soc.u_uart0.s_baud_int,
          u_dut.u_soc.u_uart0.s_baud_frac);
      $fdisplay(
          p9_diag_file,
          "P9_DIAG_XPI time_ns=%0.3f ref=%0d apb_pending=%b apb_req=%0d apb_resp=%0d apb_wait=%0d controller=%b mm_busy=%b indirect_busy=%b core_busy=%b owner=%0d tx_count=%0d rx_count=%0d core_start=%b core_done=%b core_err=%b err_event=%b err_code=%0d err_addr=%h",
          $realtime, p9_diag_ref_cycles, p9_diag_xpi_apb_pending, p9_diag_xpi_apb_requests,
          p9_diag_xpi_apb_responses, p9_diag_xpi_apb_wait, u_dut.u_soc.u_xpi.s_controller_en,
          u_dut.u_soc.u_xpi.s_mm_busy, u_dut.u_soc.u_xpi.s_indirect_busy,
          u_dut.u_soc.u_xpi.s_core_busy, u_dut.u_soc.u_xpi.s_owner_q,
          u_dut.u_soc.u_xpi.s_tx_fifo_count, u_dut.u_soc.u_xpi.s_rx_fifo_count,
          u_dut.u_soc.u_xpi.s_core_start, u_dut.u_soc.u_xpi.s_core_done,
          u_dut.u_soc.u_xpi.s_core_err, u_dut.u_soc.u_xpi.s_err_event,
          u_dut.u_soc.u_xpi.s_err_code, u_dut.u_soc.u_xpi.s_err_addr);
      if ((u_dut.u_soc.u_sram.gen_group[0].u_group.s_addr[0] == 32'h30002a4c) ||
          (u_dut.u_soc.u_sram.gen_group[0].u_group.s_read_pending_q &&
           (u_dut.u_soc.u_sram.gen_group[0].u_group.s_read_owner_q == 0))) begin
        $fdisplay(
            p9_diag_file,
            "P9_DIAG_SRAM time_ns=%0.3f ref=%0d addr=%h req=%b ready=%b grant=%b issue=%b pending=%b owner=%0d bank=%0d bank_sel=%b rsp_valid=%b rsp_ready=%b rdata=%h bank_data=%h",
            $realtime, p9_diag_ref_cycles, u_dut.u_soc.u_sram.gen_group[0].u_group.s_addr[0],
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_req[0],
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_grant[0],
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_grant[0],
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_issue,
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_read_pending_q,
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_read_owner_q,
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_read_bank_q,
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_bank_select[2],
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_rsp_valid_q[0],
            u_dut.u_soc.u_cpu_mem.s_req_q[0][P9_REQ_STATE_HI:P9_REQ_STATE_LO] == 3,
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_rsp_data_q[0],
            u_dut.u_soc.u_sram.gen_group[0].u_group.s_bank_data[2]);
      end
      $fflush(p9_diag_file);
    end
    if (p9_diag_pin15_seen && p9_diag_ref_cycles - p9_diag_pin15_cycle >= p9_diag_post_pin15_cycles)
      p9_diag_finish("post_pin15");
    else if (p9_diag_ref_cycles >= 5000000) p9_diag_finish("cycle_limit");
  end
end
always @(posedge u_dut.u_soc.s_dvp_clk) begin
  if ($test$plusargs("tiny_p9_camera") && u_dut.u_soc.s_dvp_rst_n) begin
    if (u_dut.u_soc.u_dvp.s_fifo_dst_valid && u_dut.u_soc.u_dvp.s_fifo_dst_ready)
      p9_delivered_words = p9_delivered_words + 1;
    if (u_dut.u_soc.u_dvp.s_fifo_dst_valid && !u_dut.u_soc.u_dvp.s_fifo_dst_ready) begin
      p9_stall_run = p9_stall_run + 1;
      if (p9_stall_run > p9_backpressure) p9_backpressure = p9_stall_run;
    end else p9_stall_run = 0;
  end
end
always @(posedge s_clk) begin
  if (u_dut.u_soc.u_cpu_ahbl_if[0].hready && u_dut.u_soc.u_cpu_ahbl_if[0].htrans[1]) begin
    p9_ifetch_completions = p9_ifetch_completions + 1;
    p9_last_progress      = s_cycles;
  end
  if (u_dut.u_soc.u_xpi_mem_axi4_if.rvalid && u_dut.u_soc.u_xpi_mem_axi4_if.rready) begin
    p9_xpi_completions = p9_xpi_completions + 1;
    p9_last_progress   = s_cycles;
  end
  if ($test$plusargs("tiny_p9_progress") && s_cycles % 10000 == 0)
    $display(
        "P9_BOOT_PROGRESS cycle=%0d ifetch_address=%h ifetch_completed=%0d xpi_beats=%0d last_progress=%0d",
        s_cycles,
        u_dut.u_soc.u_cpu_ahbl_if[0].haddr,
        p9_ifetch_completions,
        p9_xpi_completions,
        p9_last_progress
    );
  if ($test$plusargs("tiny_p9_camera") && u_dut.s_test_done && !p9_reported) begin
    p9_reported = 1;
    $display(
        "P9_OBSERVATION version=1 accepted_words=%0d delivered_words=%0d fifo_high_water=%0d backpressure=%0d pixel_half_ns=%0d",
        p9_accepted_words, p9_delivered_words, p9_fifo_high_water, p9_backpressure,
        u_dvp_camera.pixel_half_ns);
  end
end
