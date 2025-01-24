//-------------------------------------
// SPI controller for ravenna (PicoSoC)
//-------------------------------------
// Written by Tim Edwards
// efabless, inc. January 3, 2018
// updated April 8, 2019
//-------------------------------------

// `include "spi_slave.v"

//-----------------------------------------------------------
// This is a standalone slave SPI for the raven chip that is
// intended to be independent of the picosoc and independent
// of all IP blocks except the power-on-reset.  This SPI has
// register outputs controlling the functions that critically
// affect operation of the picosoc and so cannot be accessed
// from the picosoc itself.  This includes the PLL enables
// and trim, and the crystal oscillator enable.  It also has
// a general reset for the picosoc, an IRQ input, a bypass for
// the entire crystal oscillator and PLL chain, the
// manufacturer and product IDs and product revision number.
// To be independent of the 1.8V regulator, the slave SPI is
// synthesized with the 3V digital library and runs off of
// the 3V supply.
//
// April 2019 update for the Ravenna chip includes additional
// logic to override the enables and direction on every
// digital bidirectional pad.  Also defines a mode for
// pass-through access to the flash SPI, which forces the
// processor into a reset state.  The housekeeping SPI command
// word is then followed by a flash SPI command of any length.
// The end of the flash SPI command (rising CSB) is also the
// end of the housekeeping SPI command, and it returns to its
// normal start state.  This pass-through method avoids the
// need to use a separate FTDI channel for flash programming.
// A dual channel FTDI could then have the second channel used
// for UART communication.
//-----------------------------------------------------------

//------------------------------------------------------------
// Picochip defined registers:
// Register 0:  SPI status and control (unused & reserved)
// Register 1h: Mask revision (= 0) (readonly)
// Register 1l and 2:  Manufacturer ID (0x456) (readonly)
// Register 3:  Product ID (= 3) (readonly)
//
// Register 4:  PLL enables and trim (7 bits)
// Register 5:  PLL bypass (1 bit)
// Register 6:  IRQ (1 bit)
// Register 7:  reset (1 bit)
// Register 8:  trap (1 bit) (readonly)
// Register 9:  crystal and regulator enables (2 bits)
// Register a:  NVRAM test mode (4 bits)
//------------------------------------------------------------

module ravenna_spi (
    RST,
    SCK,
    SDI,
    CSB,
    SDO,
    sdo_enb,
    xtal_ena,
    reg_ena,
    pll_vco_ena,
    pll_cp_ena,
    pll_bias_ena,
    pll_trim,
    pll_bypass,
    pll_vco_in,
    tm_nvcp,
    irq,
    reset,
    trap,
    pass_thru_reset,
    pass_thru_sck,
    pass_thru_csb,
    pass_thru_sdi,
    pass_thru_sdo,
    mfgr_id,
    prod_id,
    mask_rev_in,
    mask_rev
);

  input RST;
  input SCK;
  input SDI;
  input CSB;
  output SDO;
  output sdo_enb;
  output xtal_ena;
  output reg_ena;
  output pll_vco_ena;
  output pll_vco_in;
  output pll_cp_ena;
  output pll_bias_ena;
  output [3:0] pll_trim;
  output pll_bypass;
  output [3:0] tm_nvcp;
  output irq;
  output reset;
  input trap;
  output pass_thru_reset;
  output pass_thru_sck;
  output pass_thru_csb;
  output pass_thru_sdi;
  input pass_thru_sdo;
  input [3:0] mask_rev_in;  // metal programmed
  output [11:0] mfgr_id;
  output [7:0] prod_id;
  output [3:0] mask_rev;

  reg        xtal_ena;
  reg        reg_ena;
  reg  [3:0] pll_trim;
  reg        pll_vco_ena;
  reg        pll_cp_ena;
  reg        pll_bias_ena;
  reg        pll_bypass;
  reg  [3:0] tm_nvcp;
  reg        irq;
  reg        reset_reg;

  wire [7:0] odata;
  wire [7:0] idata;
  wire [7:0] iaddr;

  wire       trap;
  wire       rdstb;
  wire       wrstb;
  wire       pass_thru;  // Pass-through mode detected by spi_slave.
  wire       pass_thru_delay;
  wire       isdo;
  wire       reset;

  // Pass-through mode:  When spi_slave detects the pass-through
  // command, the processor is held in reset, CSB to the flash is
  // held low until CSB to ravenna_spi is raised, terminating the
  // pass-through operation;  and signals SCK, SDI, and SDO are
  // mirrored directly to/from the flash QSPI pins.

  assign pass_thru_csb = ~pass_thru_delay;
  assign pass_thru_sck = pass_thru ? SCK : 1'b0;
  assign pass_thru_sdi = pass_thru ? SDI : 1'b0;
  assign SDO           = pass_thru ? pass_thru_sdo : isdo;
  assign reset         = pass_thru_reset ? 1'b1 : reset_reg;

  // Instantiate the SPI slave module

  spi_slave U1 (
      .reset          (RST),
      .SCK            (SCK),
      .SDI            (SDI),
      .CSB            (CSB),
      .SDO            (isdo),
      .sdoenb         (sdo_enb),
      .idata          (odata),
      .odata          (idata),
      .oaddr          (iaddr),
      .rdstb          (rdstb),
      .wrstb          (wrstb),
      .pass_thru      (pass_thru),
      .pass_thru_delay(pass_thru_delay),
      .pass_thru_reset(pass_thru_reset)
  );

  wire [11:0] mfgr_id;
  wire [ 7:0] prod_id;
  wire [ 3:0] mask_rev;
  wire        pll_vco_in;

  assign mfgr_id = 12'h456;  // Hard-coded
  assign prod_id = 8'h03;  // Hard-coded
  assign mask_rev = mask_rev_in;  // Copy in to out.

  // pll_vco_in is raised when the VCO is enabled and the charge
  // pump is disabled.  This combination indicates that the VCO
  // is free-running and frequency is controlled by the voltage
  // at VCO_IN.  This signal drives a multiplexer to connect
  // VCO_IN to COMP_INP when on, or ground when off.

  assign pll_vco_in = pll_vco_ena & ~pll_cp_ena;

  // Send register contents to odata on SPI read command
  // All values are 1-4 bits and no shadow registers are required.

  assign odata = (iaddr == 8'h00) ? 8'h00 :  // SPI status (fixed)
      (iaddr == 8'h01) ? {mask_rev, mfgr_id[11:8]} :  // Mask rev (metal programmed)
      (iaddr == 8'h02) ? mfgr_id[7:0] :  // Manufacturer ID (fixed)
      (iaddr == 8'h03) ? prod_id :  // Product ID (fixed)
      (iaddr == 8'h04) ? {1'b0, pll_trim, pll_cp_ena, pll_vco_ena, pll_bias_ena} :
	(iaddr == 8'h05) ? {7'b0000000, pll_bypass} :
	(iaddr == 8'h06) ? {7'b0000000, irq} :
	(iaddr == 8'h07) ? {7'b0000000, reset} :
	(iaddr == 8'h08) ? {7'b0000000, trap} :
	(iaddr == 8'h09) ? {6'b000000, reg_ena, xtal_ena} :
	(iaddr == 8'h0a) ? {4'b0000, tm_nvcp} :	// NVRAM test mode
      8'h00;  // Default

  // Register mapping and I/O to slave module

  always @(posedge SCK or posedge RST) begin
    if (RST == 1'b1) begin
      pll_trim     <= 4'b0000;
      xtal_ena     <= 1'b1;
      reg_ena      <= 1'b1;
      pll_vco_ena  <= 1'b1;
      pll_cp_ena   <= 1'b1;
      pll_bias_ena <= 1'b1;
      pll_bypass   <= 1'b0;
      tm_nvcp      <= 4'h0;
      irq          <= 1'b0;
      reset_reg    <= 1'b0;
    end else if (wrstb == 1'b1) begin
      case (iaddr)
        8'h04: begin
          pll_trim     <= idata[6:3];
          pll_cp_ena   <= idata[2];
          pll_vco_ena  <= idata[1];
          pll_bias_ena <= idata[0];
        end
        8'h05: begin
          pll_bypass <= idata[0];
        end
        8'h06: begin
          irq <= idata[0];
        end
        8'h07: begin
          reset_reg <= idata[0];
        end
        // Register 8 is read-only
        8'h09: begin
          reg_ena  <= idata[1];
          xtal_ena <= idata[0];
        end
        8'h0a: begin
          tm_nvcp <= idata[3:0];
        end
      endcase  // (iaddr)
    end
  end
endmodule  // raven_spi
