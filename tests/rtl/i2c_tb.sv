`timescale 1ns / 1ps

`include "ribp_i2c_define.svh"

module i2c_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic dma_tx_stall;
  logic dma_rx_stall;
  logic slave_scl_low = 1'b0;
  logic slave_sda_low = 1'b0;
  logic scl_line;
  logic sda_line;
  ribp_if ribp ();
  i2c_if i2c ();

  always #5 clk_i = ~clk_i;

  assign scl_line  = (i2c.scl_oe_o || slave_scl_low) ? 1'b0 : 1'b1;
  assign sda_line  = (i2c.sda_oe_o || slave_sda_low) ? 1'b0 : 1'b1;
  assign i2c.scl_i = scl_line;
  assign i2c.sda_i = sda_line;

  ribp_i2c u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(dma_tx_stall),
      .dma_rx_stall_o(dma_rx_stall),
      .ribp          (ribp),
      .i2c           (i2c)
  );

  task automatic ribp_write(input logic [31:0] address, input logic [31:0] data,
                            input logic expected_error);
    begin
      @(negedge clk_i);
      ribp.addr  = address;
      ribp.wdata = data;
      ribp.wstrb = 4'hF;
      ribp.valid = 1'b1;
      while (!ribp.ready) begin
        @(posedge clk_i);
        #1;
      end
      if (ribp.resp_err !== expected_error) begin
        $fatal(1, "I2C write %h error=%b expected=%b", address, ribp.resp_err, expected_error);
      end
      @(negedge clk_i);
      ribp.valid = 1'b0;
      ribp.wstrb = '0;
    end
  endtask

  task automatic ribp_read(input logic [31:0] address, input logic expected_error,
                           output logic [31:0] data);
    begin
      @(negedge clk_i);
      ribp.addr  = address;
      ribp.wdata = '0;
      ribp.wstrb = '0;
      ribp.valid = 1'b1;
      while (!ribp.ready) begin
        @(posedge clk_i);
        #1;
      end
      if (ribp.resp_err !== expected_error) begin
        $fatal(1, "I2C read %h error=%b expected=%b", address, ribp.resp_err, expected_error);
      end
      data = ribp.rdata;
      @(negedge clk_i);
      ribp.valid = 1'b0;
    end
  endtask

  task automatic wait_start;
    begin
      @(negedge sda_line);
      while (!scl_line) begin
        @(negedge sda_line);
      end
    end
  endtask

  task automatic receive_byte(output logic [7:0] data, input integer stretch_cycles);
    integer bit_index;
    begin
      for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
        @(posedge scl_line);
        data[bit_index] = sda_line;
      end
      @(negedge scl_line);
      slave_sda_low = 1'b1;
      if (stretch_cycles != 0) begin
        slave_scl_low = 1'b1;
        repeat (stretch_cycles) @(posedge clk_i);
        slave_scl_low = 1'b0;
      end
      @(posedge scl_line);
      @(negedge scl_line);
      slave_sda_low = 1'b0;
    end
  endtask

  task automatic send_byte(input logic [7:0] data, output logic nack);
    integer bit_index;
    begin
      for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
        slave_sda_low = !data[bit_index];
        @(posedge scl_line);
        @(negedge scl_line);
      end
      slave_sda_low = 1'b0;
      @(posedge scl_line);
      nack = sda_line;
      @(negedge scl_line);
    end
  endtask

  task automatic wait_done;
    logic   [31:0] value;
    logic   [31:0] error_value;
    logic   [31:0] status_value;
    integer        attempts;
    begin
      value = '0;
      for (attempts = 0; attempts < 4000; attempts = attempts + 1) begin
        ribp_read(`RIBP_I2C_INTR_STATE, 1'b0, value);
        if (value[`I2C_INTR_DONE]) begin
          attempts = 4000;
        end
      end
      if (!value[`I2C_INTR_DONE]) begin
        ribp_read(`RIBP_I2C_ERROR_STATUS, 1'b0, error_value);
        ribp_read(`RIBP_I2C_STATUS, 1'b0, status_value);
        $fatal(1, "I2C transaction did not complete: error=%h status=%h fsm=%0d", error_value,
               status_value, u_dut.u_i2c_core.s_fsm_q);
      end
      ribp_write(`RIBP_I2C_INTR_STATE, 32'hFF, 1'b0);
    end
  endtask

  task automatic clear_state;
    begin
      ribp_write(`RIBP_I2C_ERROR_STATUS, 32'h7FF, 1'b0);
      ribp_write(`RIBP_I2C_INTR_STATE, 32'hFF, 1'b0);
      ribp_write(`RIBP_I2C_COMMAND, 32'hC, 1'b0);
    end
  endtask

  initial begin
    logic   [31:0] value;
    logic   [ 7:0] byte_value;
    logic          nack;
    integer        pulse_count;

    ribp.valid = 1'b0;
    ribp.addr  = '0;
    ribp.wdata = '0;
    ribp.wstrb = '0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (4) @(posedge clk_i);

    ribp_read(`RIBP_I2C_IP_VERSION, 1'b0, value);
    if (value != 32'h0002_0000) $fatal(1, "I2C version mismatch");
    ribp_read(`RIBP_I2C_CAPABILITY, 1'b0, value);
    if (value != 32'h007F_1010) $fatal(1, "I2C capability mismatch: %h", value);
    ribp_read(32'h2, 1'b1, value);

    ribp_write(`RIBP_I2C_SCL_TIMING, 32'h0008_0008, 1'b0);
    ribp_write(`RIBP_I2C_START_TIMING, 32'h0002_0002, 1'b0);
    ribp_write(`RIBP_I2C_DATA_TIMING, 32'h0001_0000, 1'b0);
    ribp_write(`RIBP_I2C_STOP_TIMING, 32'h0002_0002, 1'b0);
    ribp_write(`RIBP_I2C_FILTER, 0, 1'b0);
    ribp_write(`RIBP_I2C_STRETCH_TIMEOUT, 200, 1'b0);
    ribp_write(`RIBP_I2C_BUS_IDLE_TIMEOUT, 200, 1'b0);
    ribp_write(`RIBP_I2C_COMMAND_TIMEOUT, 2000, 1'b0);
    ribp_write(`RIBP_I2C_TARGET_ADDR, 7'h50, 1'b0);
    ribp_write(`RIBP_I2C_CTRL, 1, 1'b0);

    fork
      begin
        wait_start();
        receive_byte(byte_value, 0);
        if (byte_value != 8'hA0) $fatal(1, "write address mismatch: %h", byte_value);
        receive_byte(byte_value, 0);
        if (byte_value != 8'hA5) $fatal(1, "write data mismatch: %h", byte_value);
      end
      begin
        ribp_write(`RIBP_I2C_DATA_CMD, 32'h4A5, 1'b0);
        wait_done();
      end
    join

    clear_state();
    ribp_write(`RIBP_I2C_TARGET_ADDR, 32'h0000_06AA, 1'b0);
    fork
      begin
        wait_start();
        receive_byte(byte_value, 0);
        if (byte_value != 8'hF4) $fatal(1, "10-bit write header mismatch: %h", byte_value);
        receive_byte(byte_value, 0);
        if (byte_value != 8'hAA) $fatal(1, "10-bit low address mismatch: %h", byte_value);
        wait_start();
        receive_byte(byte_value, 0);
        if (byte_value != 8'hF5) $fatal(1, "10-bit read header mismatch: %h", byte_value);
        send_byte(8'hC3, nack);
        if (!nack) $fatal(1, "final 10-bit read byte was not NACKed");
      end
      begin
        ribp_write(`RIBP_I2C_DATA_CMD, 32'hD00, 1'b0);
        wait_done();
        ribp_read(`RIBP_I2C_RXDATA, 1'b0, value);
        if (value[7:0] != 8'hC3) $fatal(1, "10-bit read data mismatch: %h", value);
      end
    join

    clear_state();
    ribp_write(`RIBP_I2C_TARGET_ADDR, 7'h50, 1'b0);
    fork
      begin
        wait_start();
        receive_byte(byte_value, 0);
        if (byte_value != 8'hA0) $fatal(1, "combined write address mismatch");
        receive_byte(byte_value, 0);
        if (byte_value != 8'h12) $fatal(1, "combined register byte mismatch");
        wait_start();
        receive_byte(byte_value, 0);
        if (byte_value != 8'hA1) $fatal(1, "combined read address mismatch");
        send_byte(8'h5A, nack);
        if (!nack) $fatal(1, "final read byte was not NACKed");
      end
      begin
        ribp_write(`RIBP_I2C_DATA_CMD, 32'h012, 1'b0);
        ribp_write(`RIBP_I2C_DATA_CMD, 32'hF00, 1'b0);
        wait_done();
        ribp_read(`RIBP_I2C_RXDATA, 1'b0, value);
        if (value[7:0] != 8'h5A) $fatal(1, "read data mismatch: %h", value);
      end
    join

    clear_state();
    fork
      begin
        wait_start();
        receive_byte(byte_value, 12);
        receive_byte(byte_value, 0);
      end
      begin
        ribp_write(`RIBP_I2C_DATA_CMD, 32'h45C, 1'b0);
        wait_done();
      end
    join

    clear_state();
    ribp_write(`RIBP_I2C_TARGET_ADDR, 7'h51, 1'b0);
    ribp_write(`RIBP_I2C_DATA_CMD, 32'h455, 1'b0);
    repeat (300) @(posedge clk_i);
    ribp_read(`RIBP_I2C_ERROR_STATUS, 1'b0, value);
    if (!value[`I2C_ERROR_ADDR_NACK]) $fatal(1, "address NACK was not reported");

    clear_state();
    ribp_write(`RIBP_I2C_TARGET_ADDR, 7'h7F, 1'b0);
    fork
      begin
        wait_start();
        @(negedge scl_line);
        #1 slave_sda_low = 1'b1;
        @(posedge scl_line);
        repeat (4) @(posedge clk_i);
        slave_sda_low = 1'b0;
      end
      begin
        ribp_write(`RIBP_I2C_DATA_CMD, 32'h400, 1'b0);
      end
    join
    repeat (20) @(posedge clk_i);
    ribp_read(`RIBP_I2C_ERROR_STATUS, 1'b0, value);
    if (!value[`I2C_ERROR_ARB_LOST]) $fatal(1, "arbitration loss was not reported");

    clear_state();
    slave_sda_low = 1'b1;
    fork
      begin
        pulse_count = 0;
        while (pulse_count < 9) begin
          @(posedge scl_line);
          pulse_count = pulse_count + 1;
        end
        slave_sda_low = 1'b0;
      end
      begin
        ribp_write(`RIBP_I2C_COMMAND, 32'h2, 1'b0);
      end
    join
    repeat (80) @(posedge clk_i);
    ribp_read(`RIBP_I2C_INTR_STATE, 1'b0, value);
    if (!value[`I2C_INTR_RECOVERY_DONE] || (pulse_count != 9)) begin
      $fatal(1, "bus recovery failed: intr=%h pulses=%0d", value, pulse_count);
    end

    if (i2c.scl_o !== 1'b0 || i2c.sda_o !== 1'b0) begin
      $fatal(1, "I2C pads are not open-drain constants");
    end
    $display("I2C V2 transfer, error, stretch, arbitration, and recovery test passed");
    $finish;
  end

  initial begin
    repeat (50000) @(posedge clk_i);
    $fatal(1, "I2C test timeout");
  end

endmodule
