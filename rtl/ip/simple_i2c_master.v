////////////////////////////////////////////////////////////////////
////                                                            ////
////  I2C Master controller Top-level				////
////                                                            ////
////  Modified from original project on OpenCores.		////
////  The top level routine modified to remove wishbone		////
////  interface to match Raven simple interfaces.  For the	////
////  copyright and other original code, see source file	////
////  i2c_master_byte_ctrl.v.					////
////                                                             ////
/////////////////////////////////////////////////////////////////////

module simple_i2c_master (
    input         clk,           // master clock input
    input         resetn,        // synchronous active low reset
    input  [ 2:0] reg_cfg1_we,   // config register 1 write enable (3 bits)
    input  [31:0] reg_cfg1_di,   // config register 1 data input
    output [31:0] reg_cfg1_do,   // config register 1 data output
    input         reg_cfg2_we,   // config register 2 write enable (1 bit)
    input  [31:0] reg_cfg2_di,   // config register 2 data input
    output [31:0] reg_cfg2_do,   // config register 2 data output
    input         reg_dat_we,    // data write enable input (1 bit)
    input         reg_dat_re,    // data read enable input
    input  [31:0] reg_dat_di,    // data input
    output [31:0] reg_dat_do,    // data output
    // I2C signals
    // i2c clock line
    input         scl_pad_i,     // SCL-line input
    output        scl_pad_o,     // SCL-line output (always 1'b0)
    output        scl_padoeb_o,  // SCL-line output enable (active low)
    // i2c data line
    input         sda_pad_i,     // SDA-line input
    output        sda_pad_o,     // SDA-line output (always 1'b0)
    output        sda_padoeb_o,  // SDA-line output enable (active low)
    output        irq_o          // Interrupt for incoming data
);

  // registers (in config register 1)
  reg  [15:0] prer;  // clock prescale register
  reg  [ 7:0] ctr;  // control register

  // registers (in config register 2)
  reg  [ 7:0] cr;  // command register
  wire [ 7:0] sr;  // status register

  // registers (in data register)
  reg  [ 7:0] txr;  // transmit register
  wire [ 7:0] rxr;  // receive register

  // done signal: command completed, clear command register
  wire        done;

  // core enable signal
  wire        core_en;
  wire        ien;

  // status register signals
  wire        irxack;
  reg         rxack;  // received aknowledge from slave
  reg         tip;  // transfer in progress
  reg         irq_flag;  // interrupt pending flag
  wire        i2c_busy;  // bus busy (start signal detected)
  wire        i2c_al;  // i2c bus arbitration lost
  reg         al;  // status register arbitration lost bit

  //
  // module body
  //

  assign reg_cfg1_do = {8'b0, ctr, prer};
  assign reg_cfg2_do = {24'b0, sr};
  assign reg_dat_do  = done ? rxr : ~0;

  // generate registers
  always @(posedge clk) begin
    if (!resetn) begin
      prer <= 16'hffff;
      ctr  <= 8'h0;
      txr  <= 8'h0;
    end else begin
      if (reg_cfg1_we[0]) prer[7:0] <= reg_cfg1_di[7:0];
      if (reg_cfg1_we[1]) prer[15:8] <= reg_cfg1_di[15:8];
      if (reg_cfg1_we[2]) ctr <= reg_cfg1_di[23:16];
      // Upper 8 bits are not used

      // Status register is not writeable
      // Upper 24 bits are not used

      if (reg_dat_we) txr <= reg_dat_di[7:0];
      // Upper 24 bits are not used
    end
  end

  // generate command register (special case)

  always @(posedge clk) begin
    if (!resetn) begin
      cr <= 8'h0;
    end else if (reg_cfg2_we) begin
      if (core_en) cr <= reg_cfg2_di[7:0];
    end else begin
      if (done | i2c_al) cr[7:4] <= 4'h0;  // clear command bits when done
                                           // or when aribitration lost
      cr[2:1] <= 2'b0;  // reserved bits
      cr[0]   <= 1'b0;  // clear IRQ_ACK bit
    end
  end

  // decode command register
  wire sta = cr[7];
  wire sto = cr[6];
  wire rd = cr[5];
  wire wr = cr[4];
  wire ack = cr[3];
  wire iack = cr[0];

  // decode control register
  assign core_en = ctr[7];
  assign ien     = ctr[6];

  // hook up byte controller block
  i2c_master_byte_ctrl byte_controller (
      .clk     (clk),
      .nReset  (resetn),
      .ena     (core_en),
      .clk_cnt (prer),
      .start   (sta),
      .stop    (sto),
      .read    (rd),
      .write   (wr),
      .ack_in  (ack),
      .din     (txr),
      .cmd_ack (done),
      .ack_out (irxack),
      .dout    (rxr),
      .i2c_busy(i2c_busy),
      .i2c_al  (i2c_al),
      .scl_i   (scl_pad_i),
      .scl_o   (scl_pad_o),
      .scl_oen (scl_padoeb_o),
      .sda_i   (sda_pad_i),
      .sda_o   (sda_pad_o),
      .sda_oen (sda_padoeb_o)
  );

  // status register block + interrupt request signal
  always @(posedge clk)
    if (!resetn) begin
      al       <= 1'b0;
      rxack    <= 1'b0;
      tip      <= 1'b0;
      irq_flag <= 1'b0;
    end else begin
      al <= i2c_al | (al & ~sta);
      rxack <= irxack;
      tip <= (rd | wr);
      irq_flag <= (done | i2c_al | irq_flag) & ~iack;  // interrupt request flag is always generated
    end

  // interrupt signal is only generated when IEN
  // (interrupt enable bit) is set
  assign irq_o   = irq_flag && ien;

  // assign status register bits
  assign sr[7]   = rxack;
  assign sr[6]   = i2c_busy;
  assign sr[5]   = al;
  assign sr[4:2] = 3'h0;  // reserved
  assign sr[1]   = tip;
  assign sr[0]   = irq_flag;

endmodule
