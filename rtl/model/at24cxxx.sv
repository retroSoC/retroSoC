`timescale 1ns / 10 ps


// AT24C Device Family
// Note: Compiler directives are used to adapt the model to a particular
// device of the family.
// Note: Choose VERBOSE 0 to suppress troubleshooting messages.

// Dates of Revisions:

// m.d. ciletti 03/05/03
// m.d. ciletti 04/28/2006
// m.d. ciletti 05/30/2008
// B. Morgan 7/23/2008
// m.d. ciletti 7/26/2008
// B. Schoendube 9/19/2014
// C. Tomlinson 02/17/2020 AT24C64C 1.8V to 5.5V 400kHz max

// Summary of Revisions
// Pre-2008 Modified to handle the following device functionality:

// (1) Detects toggling of SDA under SCL = 1 and cancels the START condition
// if the sequence ends with a STOP condition.

// (2) Detects and recovers from a random START condition, i.e. if a start
// condition appears anywhere in the data transmission the machine resets
// itself to begin receiving a device address byte.

// (3) Detects a sequence of 9 clocks with SDA held high and resets the
// machine to await a START condition. The address register of the machine
// is not affected by the reset operation.

// (4) Corrects an occurrence of an incorrect device label for the
// AT24C1024 device.

// (5) Includes address code for the P bits (had been removed for testing)

// 05/30/2008 Modified to deal with infinite loop upon time out for page
// write.


// 05/30/2008 Modified to provide additional documentation.

// 7/23/2008 Added 24C512B 1.8v 400khz and 2.5v 1Mhz timing sets.

// 7/26/2008 Modified to handle protocol violation with WP (write protection)
// and provide additional documentation.
// Required reset of Valid_Address_flag.
// Corrected code entries for AT24C512B.

// 9/19/2014 added device types AT24C64E and AT24C32E
// Corrected possible bus access error when not selected
// Corrected tSUSTO timing checks
// Change timing callouts to be consistent
// Added timing checks for AT24C32E and AT24C64E

// AT24C64E was not developed, removing AT24C64E references C.Tomlinson 01/08/2020

////////////////////////////////////////////////////////////////////////////
//                            DEVICE SELECTION
////////////////////////////////////////////////////////////////////////////

`define WANT_VERBOSE 0

// Slave address formats
// 1M 1010_0_A1_P0_R/W
// 512K 1010_0_A1_A0_R/W
// 256K 1010_0_A1_A0_R/W
// 128K 1010_0_A1_A0_R/W
// 64K 1010_A2_A1_A0_R/W
// 32K 1010_A2_A2_A0_R/W
// 16K 1010_P2_P1_P0_R/W
// 8K 1010_A2_P1_P0_R/W
// 4K 1010_A2_A1_P0_R/W
// 2K 1010_A2_A1_A0_R/W
// 1K 1010_A2_A1_A0_R/W

// To configure the model, edit the comments of the compiler
// directives as specfifed below :

// (1) remove // from the `define line of the selected device  (REQUIRED)
// (2) remove // to select timing parameters  (OPTIONAL)
// (3) set the SLAVE_ADDRESS (REQUIRED)
// (Arbitrary addresses are used below for testing)
// Be sure that the test bench is adapted to the particular model
// No further action needed.


// `define AT24C64D

//`define AT24C1024
//`define AT24C512B
// define AT24C512
//`define AT24C256
//`define AT24C128

//`define AT24C64A
//`define AT24C32A
//`define AT24C16A
//`define AT24C08A
`define AT24C04A
//`define AT24C02A
//`define AT24C01A

//`define AT24C64
//`define AT24C32
//`define AT24C08
// `define AT24C04
// `define AT24C02

//`define AT34C02

// Options for timing parameters

//`define WANT_AT24C1024__4_5__5_5V_TIMING

//using existing 1024 400kHz timing set for AT24C32E C.Tomlinson 01/08/2020
// `define WANT_AT24C1024__2_7__5_5V_TIMING

//`define WANT_AT24C_01A_02_04_08_16__2_7__2_5__1_8_V_TIMING
// `define WANT_AT24C_01A_02_04_08_16__5_V_TIMING

// `define WANT_AT24C_02A_04A_08A_16A__1_8_V_TIMING
// `define WANT_AT24C_02A_04A_08A__2_5V__2_7V_TIMING
//`define WANT_AT24C_16A__2_5V_TIMING
`define WANT_AT24C_02A_04A_08A_16A__5V_TIMING

//`define WANT_AT24C512B__1_8V_TIMING
//`define WANT_AT24C512B__2_5V_TIMING
//`define WANT_AT24C512__1_8_V_TIMING
//`define WANT_AT24C512__2_7V_TIMING
//`define WANT_AT24C512__5V_TIMING

//`define WANT_AT24C128_256__1_8_V_TIMING
//`define WANT_AT24C128_256__2_5V_TIMING
//`define WANT_AT24C128_256__5V_TIMING
//`define WANT_AT34C02__1_8_V_TIMING
//`define WANT_AT34C02__2_7__5_0_V_TIMING

`ifdef AT24C1024
module  AT24C1024 (SDA, SCL, WP);
`endif
`ifdef AT24C512B

module  AT24C512B (SDA, SCL, WP);
`endif
`ifdef AT24C512

module  AT24C512 (SDA, SCL, WP);
`endif
`ifdef AT24C256

module  AT24C256 (SDA, SCL, WP);
`endif
`ifdef AT24C128

module  AT24C128 (SDA, SCL, WP);
`endif
`ifdef AT24C64B

module  AT24C64B (SDA, SCL, WP); //cjt 10_25_2021 added B
`endif
`ifdef AT24C64D

module  AT24C64D (SDA, SCL, WP); //cjt 10_25_2021 added D
`endif
`ifdef AT24C32D

module  AT24C32 (SDA, SCL, WP);
`endif
`ifdef AT24C64A

module  AT24C64 (SDA, SCL, WP);
`endif
`ifdef AT24C32A

module  AT24C32 (SDA, SCL, WP);
`endif
`ifdef AT24C16A

module  AT24C16A (SDA, SCL, WP);
`endif
`ifdef AT24C08A

module  AT24C08A (SDA, SCL, WP);
`endif
`ifdef AT24C04A

module  AT24C04 (SDA, SCL, WP);
`endif
`ifdef AT24C02A

module  AT24C02A (SDA, SCL, WP);
`endif
`ifdef AT24C01A

module  AT24C01A (SDA, SCL, WP);
`endif
`ifdef AT24C64

module  AT24C64 (SDA, SCL, WP);
`endif
`ifdef AT24C32

module  AT24C32 (SDA, SCL, WP);
`endif
`ifdef AT24C16

module  AT24C16 (SDA, SCL, WP);
`endif
`ifdef AT24C08

module  AT24C08 (SDA, SCL, WP);
`endif
`ifdef AT24C04

module  AT24C04 (SDA, SCL, WP);
`endif
`ifdef AT24C02

module  AT24C02 (SDA, SCL, WP);
`endif
`ifdef AT34C02

module  AT34C02 (SDA, SCL, WP);
`endif

inout SDA;      // Bi-directional serial data
input SCL;      // Serial clock
input WP;      // Write protection



/////////////////////////////////////////////////////////////////////////////
////////////////////////////// DEVICE CONFIGURATION  ///////////////////////
// Slave address formats
// 1M 1010_0_A1_P0_R/W
// 512K 1010_0_A1_A0_R/W
// 256K 1010_0_A1_A0_R/W
// 128K 1010_0_A1_A0_R/W
// 64K 1010_A2_A1_A0_R/W
// 32K 1010_A2_A2_A0_R/W
// 16K 1010_P1_P1_P0_R/W
// 8K 1010_A2_P1_P0_R/W
// 4K 1010_A2_A1_P0_R/W
// 2K 1010_A2_A1_A0_R/W
// 1K 1010_A2_A1_A0_R/W

// The following parameters configure the device.

// The A2_A1_A0 of the slave addresses are arbitrary for the
// purpose of testing the model.  A testbench must send the indicated
// device address, together with the appropriate memory address bits
// P2_P1_P0, as needed.

//AT24C1024, 512 pages at 256 bytes/page, 17 address bits
`ifdef AT24C1024

parameter MEM_SIZE = 131072;
parameter ADDR_SIZE = 17;
parameter WORD_ADDR_SIZE = 8;
parameter SLAVE_ADDRESS = 6'b1010_00; // Testbench provides P0 and R/W bits
`endif

// AT24C512B, 512 pages at 128 bytes/page, 16 address bits
`ifdef AT24C512B

parameter MEM_SIZE = 65536;
parameter ADDR_SIZE = 16;
parameter WORD_ADDR_SIZE = 7;
parameter SLAVE_ADDRESS = 7'b1010_011; // Testbench provides R/W bit
`endif


// AT24C512, 512 pages at 128 bytes/page, 16 address bits
`ifdef AT24C512

parameter MEM_SIZE = 65536;
parameter ADDR_SIZE = 16;
parameter WORD_ADDR_SIZE = 7;
parameter SLAVE_ADDRESS = 7'b1010_011; // Testbench provides R/W bit
`endif

// AT24C256, 512 pages at 64 bytes/page, 15 address bits
`ifdef AT24C256

parameter MEM_SIZE = 32768;
parameter ADDR_SIZE = 15;
parameter WORD_ADDR_SIZE = 6;
parameter SLAVE_ADDRESS = 7'b1010_011; // Testbench provides R/W bit
`endif

// AT24C128, 256 pages at 64 bytes/page, 14 address bits
`ifdef AT24C128

parameter MEM_SIZE = 16384;
parameter ADDR_SIZE = 14;
parameter WORD_ADDR_SIZE = 6;
parameter SLAVE_ADDRESS = 7'b1010_011; // Testbench provides R/W bit
`endif

// AT24C64, 256 pages at 32 bytes/page, 13 address bits
`ifdef AT24C64

parameter MEM_SIZE = 8192;
parameter ADDR_SIZE = 13;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_111; // Testbench provides R/W bit
`endif

// AT24C64A, 256 pages at 32 bytes/page, 13 address bits
`ifdef AT24C64A

parameter MEM_SIZE = 8192;
parameter ADDR_SIZE = 13;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_111; // Testbench provides R/W bit
`endif

// AT24C64B, 256 pages at 32 bytes/page, 13 address bits
`ifdef AT24C64B

parameter MEM_SIZE = 8192;
parameter ADDR_SIZE = 13;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_111; // Testbench provides R/W bit
`endif

// AT24C64C, 256 pages at 32 bytes/page, 13 address bits
`ifdef AT24C64C

parameter MEM_SIZE = 8192;
parameter ADDR_SIZE = 13;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_111; // Testbench provides R/W bit
`endif

// AT24C64D, 256 pages at 32 bytes/page, 13 address bits
`ifdef AT24C64D

parameter MEM_SIZE = 8192;
parameter ADDR_SIZE = 13;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_111; // Testbench provides R/W bit
`endif

// AT24C32, 128 pages at 32 bytes/page, 12 address bits
`ifdef AT24C32

parameter MEM_SIZE = 4096;
parameter ADDR_SIZE = 12;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_101; // Testbench provides R/W bit
`endif

// AT24C32D, 128 pages at 32 bytes/page, 12 address bits
`ifdef AT24C32D

parameter MEM_SIZE = 4096;
parameter ADDR_SIZE = 12;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_101; // Testbench provides R/W bit
`endif

// AT24C32A, 128 pages at 32 bytes/page, 12 address bits
`ifdef AT24C32A

parameter MEM_SIZE = 4096;
parameter ADDR_SIZE = 12;
parameter WORD_ADDR_SIZE = 5;
parameter SLAVE_ADDRESS = 7'b1010_101; // Testbench provides R/W bit
`endif

// AT24C16, 128 pages at 16 bytes/page, 11 address bits
`ifdef AT24C16

parameter MEM_SIZE = 2048;
parameter ADDR_SIZE = 11;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 4'b1010; // Testbench provides P2_P1_P0_R/W bits
`endif

// AT24C16A, 128 pages at 16 bytes/page, 11 address bits
`ifdef AT24C16A

parameter MEM_SIZE = 2048;
parameter ADDR_SIZE = 11;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 4'b1010; // Testbench provides P2_P1_P0_R/W bits
`endif

// AT24C08, 64 pages at 16 bytes/page, 10 address bits
`ifdef AT24C08

parameter MEM_SIZE = 1024;
parameter ADDR_SIZE = 10;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 5'b1010_0; // Testbench provides P1_P0_R/W bits

`endif
// AT24C08A, 64 pages at 16 bytes/page, 10 address bits
`ifdef AT24C08A

parameter MEM_SIZE = 1024;
parameter ADDR_SIZE = 10;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 5'b1010_0; // Testbench provides P1_P0_R/W bits
`endif

// AT24C04, 32 pages at 16 bytes/page, 9 address bits
`ifdef AT24C04

parameter MEM_SIZE = 512;
parameter ADDR_SIZE = 9;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 6'b1010_00; // Testbench provides P0_R/W bits
`endif

// AT24C04A, 32 pages at 16 bytes/page, 9 address bits
`ifdef AT24C04A

parameter MEM_SIZE = 512;
parameter ADDR_SIZE = 9;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 6'b1010_00; // Testbench provides P0_R/W bits
`endif

// AT24C02, 32 pages at 8 bytes/page, 8 address bits
`ifdef AT24C02

parameter MEM_SIZE = 256;
parameter ADDR_SIZE = 8;
parameter WORD_ADDR_SIZE = 3;
parameter SLAVE_ADDRESS = 7'b1010_100; // Testbench provides R/W bit
`endif

// AT24C02A, 32 pages at 8 bytes/page, 8 address bits
`ifdef AT24C02A

parameter MEM_SIZE = 256;
parameter ADDR_SIZE = 8;
parameter WORD_ADDR_SIZE = 3;
parameter SLAVE_ADDRESS = 7'b1010_100; // Testbench provides R/W bit
`endif

// AT24C01A, 16 page at 8 bytes/page, 7 address bits
`ifdef AT24C01A

parameter MEM_SIZE = 128;
parameter ADDR_SIZE = 7;
parameter WORD_ADDR_SIZE = 3;
parameter SLAVE_ADDRESS = 7'b1010_110; // Testbench provides R/W bits
`endif

// AT34C02, 16 pages at 16 bytes/page, 8 address bits
`ifdef AT34C02

parameter MEM_SIZE = 256;
parameter ADDR_SIZE = 8;
parameter WORD_ADDR_SIZE = 4;
parameter SLAVE_ADDRESS = 7'b1010_100; // Testbench provides R/W bit
`endif

// Device Parameters for internal decoding

// AT24C1024, 512 pages at 256 bytes/page, 17 address bits
parameter MEM_SIZE_1MEG_BIT = 131072;
parameter ADDR_SIZE_1M_BIT = 17;
parameter WORD_ADDR_SIZE_1M_BIT = 8;

// AT24C512B, 512 pages at 128 bytes/page, 16 address bits
parameter MEM_SIZE_500K_BIT = 65536;
parameter ADDR_SIZE_500K_BIT = 16;
parameter WORD_ADDR_SIZE_500K_BIT = 7;

// Removed to avoid redefinition error at compilation
// AT24C512, 512 pages at 128 bytes/page, 16 address bits
// parameter MEM_SIZE_500K_BIT = 65536;
// parameter ADDR_SIZE_500K_BIT = 16;
// parameter WORD_ADDR_SIZE_500K_BIT = 7;

// AT24C256, 512 pages at 64 bytes, 15 address bits
parameter MEM_SIZE_256K_BIT = 32768;
parameter ADDR_SIZE_256K_BIT = 15;
parameter WORD_ADDR_SIZE_256K_BIT = 6;

// AT24C128, 256 pages at 64 bytes, 14 address bits
parameter MEM_SIZE_128K_BIT = 16384;
parameter ADDR_SIZE_128K_BIT = 14;
parameter WORD_ADDR_SIZE_128K_BIT = 6;

// AT24C64, AT24C64A, AT24C64B, AT24C64C, AT24C64D 256 pages at 32 bytes, 13 address bits
parameter MEM_SIZE_64K_BIT = 8192;
parameter ADDR_SIZE_64K_BIT = 13;
parameter WORD_ADDR_SIZE_64K_BIT = 5;

// AT24C32, AT24C32A, AT24C32D 128 pages at 32 bytes/page, 12 address bits
parameter MEM_SIZE_32K_BIT = 4096;
parameter ADDR_SIZE_32K_BIT = 12;
parameter WORD_ADDR_SIZE_32K_BIT = 5;

// AT24C16, AT24C16A, 128 pages at 16 bytes/page, 11 address bits
parameter MEM_SIZE_16K_BIT = 2048;
parameter ADDR_SIZE_16K_BIT = 11;
parameter WORD_ADDR_SIZE_16K_BIT = 4;

// AT24C08, AT24C08A, 64 pages at 16 bytes/page, 10 address bits
parameter MEM_SIZE_8K_BIT = 1024;
parameter ADDR_SIZE_8K_BIT = 10;
parameter WORD_ADDR_SIZE_8K_BIT = 4;

// AT24C04, AT24C04A, 32 pages at 16 bytes/page, 9 address bits

parameter MEM_SIZE_4K_BIT = 512;

parameter ADDR_SIZE_4K_BIT = 9;
parameter WORD_ADDR_SIZE_4K_BIT = 4;

// AT24C02, AT24C02A 32 pages at 8 bytes/page, 8 address bits
parameter MEM_SIZE_2K_BIT = 256;
parameter ADDR_SIZE_2K_BIT = 8;
parameter WORD_ADDR_SIZE_2K_BIT = 3;

// AT24C01A, 16 pages at 8 bytes/page, 7 ADDRESS bits
parameter MEM_SIZE_1K_BIT = 128;
parameter ADDR_SIZE_1K_BIT = 7;
parameter WORD_ADDR_SIZE_1K_BIT = 3;

// AT34C02, 16 pages at 16 bytes/page, 8 address bits
//parameter MEM_SIZE_2K_BIT = 256;
//parameter ADDR_SIZE_2K_BIT = 8;
parameter WORD_ADDR_SIZE_AT34C02_2K_BIT = 4;

parameter BYTE_SIZE = 8;

// parameter POWER_UP_DELAY = 50000;    // For testing CJT 06_22_2020
parameter VERBOSE = `WANT_VERBOSE;  // Enable $display statements
// parameter TIMEOUT_FOR_WRITE = 5_000_000; // 5 ms
parameter TIMEOUT_FOR_WRITE = 5_000;        // For testing
// parameter TIMEOUT_FOR_WRITE = 0;        // For testing
//***************************************************************************
//***************************************************************************
//                           Write Protection (Externally applied signal)
//***************************************************************************
//***************************************************************************

// WP = 0 if not protected
// WP = 1 if protected

//***************************************************************************
//***************************************************************************
//                           Registers and Memory
//***************************************************************************
//***************************************************************************

reg [(ADDR_SIZE - 1):0]   addr_reg ;      // address register
reg [(BYTE_SIZE - 1):0]  memory[(MEM_SIZE-1):0] ;    //Device memory
reg [BYTE_SIZE-1: 0]   S_Byte_Shft_Reg;
reg [6: 0]    Device_Address;  // Maximum of 7 bits
reg load_address_bit, M_ACK;

reg ld_S_Byte_Shft_Reg;
reg ld_addr_reg_MSB_byte;
reg ld_addr_reg_LSB_byte;
reg shift_in;
reg shift_out;

parameter      SEND = 1, RECEIVE = 0;
parameter  [31:0]   SENDING = "send";
parameter  [31:0]   RECEIVING = "recv";
reg   [2:0]    state_recv, next_state_recv;
reg   [2:0]    state_send, next_state_send;
wire      SDA_out;
reg       S_send_rcvb;
reg       Addr_Done;
reg       S_ACK; // Active-high 3-state
// control of SDA_out

reg Valid_Address_flag;   // Detects valid device address from master
reg NO_ACK_flag;    // Flag indicating No_ACK from master
reg Time_Out_flag;   // Time out flag
reg Exec_Page_Write_flag;  // Execute page write flag
reg Exec_Seq_Read_flag;   // Execute sequential read flag
reg RUN_flag;    // Asserts after power-up
reg Exec_Random_Read_flag;
reg Write_flag;
wire [BYTE_SIZE-1: 0] mem_byte = memory[addr_reg]; // For debug of READ
reg First_START_flag;
reg [8:0] Protocol_Recovery_reg;
reg Device_Address_Active;              //Indicates when the device address field is active

event STOP_condition;
event START_condition;
event START_trigger;
event incr_addr_reg;  // increments the memory address
event incr_word_addr;  // increments the page address
reg S_START;   // Flag set on falling edge of SCL for
// a valid start condition. Cleared on
// the next rising edge of SCL
reg S_STOP;

`ifdef AT34C02

reg AT34C02_SWP_reg;
reg AT34C02_SWP_enabled;
`endif

//************************************************************************
//************************// Slave bus controls  *************************
//************************************************************************

triand SDA_int = (S_send_rcvb == SEND)?
       ((S_ACK == 0)? SDA_out: 1'b0): 1'bz;
tri   SDA = RUN_flag ? SDA_int: 1'bz;
tri   SDA_in = (S_send_rcvb == RECEIVE)? SDA : 1'bz;

wire [31:0] receiver = (S_send_rcvb == SEND)?
     SENDING : ((S_send_rcvb == RECEIVE)) ?
     RECEIVING : 32'bx;   // For ASCII display

//************************************************************************

//************************ Memory Initialization *************************
//************************************************************************

integer k;
initial
    for (k = 0; k <= MEM_SIZE-1; k = k+1)
        memory[k] = {BYTE_SIZE {1'b1}};

//************************************************************************
//*************************** Address Register Controls ******************
//************************************************************************

always @(posedge SCL)
    if (ld_addr_reg_MSB_byte == 1)
    begin
`ifdef AT24C1024
        addr_reg[ADDR_SIZE-2: 8] <= S_Byte_Shft_Reg;  // Fixed 214C1024

`endif
    `ifdef AT24C512

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C512B       // 7/26/2008

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C256

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C128

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C64

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C64A

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif

`ifdef AT24C64B

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif

`ifdef AT24C64C

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif

`ifdef AT24C64D

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif

`ifdef AT24C32

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C32A

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif
    `ifdef AT24C32E

        addr_reg[ADDR_SIZE-1: 8] <= S_Byte_Shft_Reg;
`endif

    end
    else if (ld_addr_reg_LSB_byte == 1)
    case (MEM_SIZE)


        MEM_SIZE_1K_BIT:
            addr_reg[6:0] <= S_Byte_Shft_Reg[6: 0];
        default:
            addr_reg[7:0] <= S_Byte_Shft_Reg[7: 0];
    endcase

always @(incr_word_addr) // Increment address within a page after WRITE
    addr_reg[WORD_ADDR_SIZE -1: 0] <= addr_reg[WORD_ADDR_SIZE -1: 0] +1;

always @(incr_addr_reg) // Increment address within mem space after READ
    addr_reg <= addr_reg + 1;

//*************************************************************************
//**************************     Shift Register    ************************
//*************************************************************************

assign SDA_out = S_Byte_Shft_Reg[BYTE_SIZE-1] ? 1'bz : 1'b0;

always @(posedge SCL)
    if ((shift_in == 1) && (!Time_Out_flag))
        S_Byte_Shft_Reg <= {S_Byte_Shft_Reg [BYTE_SIZE-2:0], SDA_in };

always @ (negedge SCL)
    if (shift_out == 1)
        S_Byte_Shft_Reg <= S_Byte_Shft_Reg << 1;

    else if (ld_S_Byte_Shft_Reg == 1)
        S_Byte_Shft_Reg <= memory[addr_reg];



//*************************************************************************
//*********************   Protocol Recovery Register **********************
//*************************************************************************

always @(posedge SCL)
begin     // Simplified 7/26/2008
    if ({Protocol_Recovery_reg [7:0], SDA_in} == 9'b1_1111_1111)
    begin
        $display("Protocol Recovery initiated");
        Recover_from_Protocol_Interupt;
        disable Data_Transmission.Outer_Block.Inner_Block;

    end
end


//************************************************************************
//*********************** Read/Write State Machine ***********************
//************************************************************************
//************************      Power-Up         *************************
//************************************************************************

initial
begin    // Power-Up Initialization
`ifdef  AT34C02
    AT34C02_SWP_reg = 0;  // one-time programmable
    AT34C02_SWP_enabled = 0; // one-time programmable
`endif

    Power_up_initialization;
    if (VERBOSE)
        $display("Begin Power Up Sequence");
    if (VERBOSE)
        $display ("Waiting for START_condition");
    S_send_rcvb = RECEIVE;
end // Power-Up Initialization

//************************************************************************
//********************* S_START and S_STOP conditions ********************
//************************************************************************

// Start trigger allows latency between start condition and falling edge
// of SCL. If stop occurs in this interval the machine ignores the start
// condition and awaits a subsequent start condition.

// START Condition Detection

always @ (negedge SDA_in)
    if(SCL == 1)
    begin
        if (VERBOSE)
            $display("START condition detected", $time);
        S_STOP = 0;
        S_START = 1;
        -> START_condition;  // Start condition event

        if (VERBOSE)
            $display ("Got START condtion event");

        @(STOP_condition or negedge SCL)
         if (SCL == 0)
         begin
             if (VERBOSE)
                 $display ("First negedge of SCL after START", $time);
             Valid_Address_flag = 0;
             if(VERBOSE)
                 $display("START event triggered");
             -> START_trigger;  // Start trigger event
             @ (posedge SCL) S_START = 0; // Waits until cycle ends
         end
         else
         begin  // STOP condition detected under same clock
             if (VERBOSE)
                 $display ("STOP under same clock as START");
             S_START = 0;
             S_STOP = 1;
         end
     end


 // STOP Condition Detection

 always @ (posedge SDA_in)   // Stop condition
     if(SCL == 1)
     begin
         // S_START = 0;  04/24/2006
         S_STOP = 1;

         if (VERBOSE)
             $display ("STOP condition", $time);
         -> STOP_condition;
         Valid_Address_flag = 0;
         ld_S_Byte_Shft_Reg = 0;
         shift_in = 0;
         shift_out = 0;
     end



 //************************************************************************
 //***   Data_Tranmission:   Response to START_trigger event   ************
 //************************************************************************

 // Note: START_trigger is synched to a drop in SCL after start condition
 // to deal with possibility of multiple drops of SDA under the clock
 // before the falling edge of the clock.  (05/30/2008)



 always @ (START_trigger)
 begin: Data_Transmission //04/24/2006
     First_START_flag = 1;
     if (VERBOSE)
         $display("******************* Data Transmission Triggered by start", $time);

     forever
     begin: Outer_Block

         // Check for power up enabled
         if (VERBOSE && (!RUN_flag))
         begin
             $display ("MACHINE NOT POWERED UP");
             disable Data_Transmission;
         end

         // Check for time-out condition
         if (RUN_flag && (Time_Out_flag))
         begin
             if (VERBOSE)
                 $display("Time_Out_flag Asserted - Skip START condition");
             if (VERBOSE)
                 $display($realtime);
             disable Data_Transmission;  // 05/30/3008 Prevent inf loop
             //disable Outer_Block;   // 05/30/3008 Prevent inf loop
         end

         else
         begin: Inner_Block

             Recover_from_Protocol_Interupt; // Clear flags and variables as needed
             if (VERBOSE)
                 $display("Valid Start Condition - Begin Data_Transmission", $time);
             if (VERBOSE)
                 $display("Getting Device Address Byte", $time);

             Get_a_Byte;  // Reads 8 bits of data on (rising edge of SCL)
             if(VERBOSE)
                 $display("Byte received:  %H ",S_Byte_Shft_Reg, $time);
             @ (negedge SCL)  // First drop in SCL after byte is read
               shift_in = 0;
             NO_ACK_flag = 0;
             if (Device_Address_Active)
                 Check_for_Valid_Upper_Bits_of_Device_Address;
             if (Valid_Address_flag)
             begin:  Got_Address_Match
                 if (VERBOSE)
                     $display ("Device Address_Match Found", $time);
                 case (S_Byte_Shft_Reg[0])  // LSB = 0 for write, 1 for read

                     0:
                         Write_or_Dummy_Write_with_Random_Read;
                     1:
                         Current_Address_and_Sequential_Read;
                 endcase
                 if (VERBOSE)
                     $display ("S_Byte_Shft_Reg[0] = ", S_Byte_Shft_Reg[0]);
             end  // Got_Address_Match
             else if (VERBOSE)
                 $display("Invalid device address", $time);

         end // Inner_Block
     end // Outer_Block
 end // Data_Transmission

 //***********************
 //*** enable device address active
 //*************************
 always @ (START_trigger)
 begin
     Device_Address_Active = 1;  // Only active during first byte after start. BS 09/19/2014
     repeat (8)
         @ (posedge SCL);


     @(negedge SCL)
      #1 Device_Address_Active = 0;  // Delay to insure signal persists after needed
 end


 // modified 04/24/2006 to detect stop under same clock as start and
 // ignore the start condition.

 //************************************************************************
 //***     Data_Tranmission:   Response to STOP condition      ************
 //************************************************************************

 always @ (STOP_condition)
 begin: STOP_Block
     if (S_START ==1)
     begin
         S_START = 0;
         S_STOP = 1;
         disable STOP_Block;
     end
     else
     begin

         if (VERBOSE)
             $display ("****************** SLAVE STOP condition detected");

         S_START = 0;
         S_STOP = 1;
         Valid_Address_flag = 0;
         Exec_Seq_Read_flag = 0;
         Exec_Random_Read_flag = 0;

`ifdef AT34C02 // Special tratment for AT34C02

         if ((AT34C02_SWP_enabled == 0) && (AT34C02_SWP_reg == 1))
         begin
             AT34C02_SWP_enabled = 1;
             Exec_Page_Write_flag = 1;
         end
`endif

         if (Exec_Page_Write_flag)
         begin  // 2-11-2003
             if (VERBOSE)
                 $display ("Time:", $realtime);
             if (VERBOSE)
                 $display ("STOP DETECTED - TIME OUT FOR PAGE WRITE");

             disable Data_Transmission;
             Time_Out_flag = 1;
             Exec_Page_Write_flag = 0;
             #TIMEOUT_FOR_WRITE Time_Out_flag = 0;
             shift_in = 0;
         end
         else
         begin
             if (VERBOSE)
                 $display ("STOP CONDITION WITHOUT PAGE WRITE", $time);
             if (VERBOSE)
                 $display ("END DATA TRANSMISSION");
             disable Data_Transmission;
         end
     end
 end

 // Watchdog for random START

 always @ (negedge SCL)
 begin: Watch_for_Random_START_trigger
     if(S_START && First_START_flag)
     begin

         if(VERBOSE)
             $display(">>> Detected random START protocol interupt", $time);

         disable Data_Transmission.Outer_Block.Inner_Block;
     end
 end

 task Get_a_Byte; // Reads data on 8 rising edges of SCL
     begin
         NO_ACK_flag = 0;
         shift_in = 1;
         repeat (8)
         begin
             @ (posedge SCL)
               if (VERBOSE)
                   $display ("Within Get_a_Byte");
             if(VERBOSE)
                 $display("Bit received: %H", S_Byte_Shft_Reg[0]);
         end
     end
 endtask

 task Check_for_Valid_Upper_Bits_of_Device_Address;
     begin
         Valid_Address_flag = 0;  // 7/26/2008
         if (VERBOSE)
             $display ("Checking for valid upper bits of device address", $time);
`ifdef AT24C1024

         Device_Address = S_Byte_Shft_Reg[7: 2];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C1024");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C1024");
         end
`endif
`ifdef AT24C512B
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C512B");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C512B");
         end
`endif

`ifdef AT24C512
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C512");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C512");
         end
`endif
`ifdef AT24C256
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C256");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C256");
         end
`endif
`ifdef AT24C128
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C128");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C128");
         end
`endif

`ifdef AT24C64
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C64");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C64");
         end
`endif
`ifdef AT24C64A
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C64A");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C64A");
         end
`endif

`ifdef AT24C64B
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C64B");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C64B");
         end
`endif

`ifdef AT24C64C
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C64C");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C64C");
         end
`endif

`ifdef AT24C64D
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C64D");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C64D");
         end
`endif

`ifdef AT24C32
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C32");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C32");
         end
`endif
`ifdef AT24C32E
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C32E");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C32E");
         end
`endif
`ifdef AT24C32A
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C32A");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C32A");
         end
`endif
`ifdef AT24C16
         Device_Address = S_Byte_Shft_Reg[7: 4];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C16");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C16");
         end
`endif
`ifdef AT24C16A
         Device_Address = S_Byte_Shft_Reg[7: 4];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C16A");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C16A");

         end
`endif
`ifdef AT24C08
         Device_Address = {2'b0, S_Byte_Shft_Reg[7: 3]};
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C08");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);

             $display ("Valid device address not detected for AT24C08");
         end
`endif

`ifdef AT24C08A
         Device_Address = {2'b0, S_Byte_Shft_Reg[7: 3]};
         if (VERBOSE)
             $display ("SLAVE_ADDRESS =", SLAVE_ADDRESS);
         if (VERBOSE)
             $display ("Device_Address =", Device_Address);

         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C08A");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C08A");
         end
`endif
`ifdef AT24C04
         Device_Address = S_Byte_Shft_Reg[7: 2];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C04");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C04");
         end
`endif
`ifdef AT24C04A
         Device_Address = S_Byte_Shft_Reg[7: 2];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C04A");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C04A");
         end
`endif
`ifdef AT24C02
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C02");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C02");
         end
`endif
`ifdef AT24C02A
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C02A");
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C02A");
         end
`endif
`ifdef AT24C01A
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT24C01A", $time);
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT24C01", $time);
         end
`endif

`ifdef AT34C02
         Device_Address = S_Byte_Shft_Reg[7: 1];
         if (Device_Address == SLAVE_ADDRESS)
         begin
             if (VERBOSE)
                 $display ("Valid device address for AT34C02");
             Valid_Address_flag = 1;
         end
         else if ((Device_Address == {4'b0110, SLAVE_ADDRESS[3:1]})
                  && (AT34C02_SWP_reg == 0))
         begin
             if (VERBOSE)
                 $display ("Device will be programmed for software write protection");
             AT34C02_SWP_reg = 1;
             Valid_Address_flag = 1;
         end
         else if (VERBOSE)
         begin
             $display ($realtime);
             $display ("Valid device address not detected for AT34C02");
         end

`endif //  `ifdef AT34C02

     end
 endtask



 task Write_or_Dummy_Write_with_Random_Read;
     begin: Wrapper
         if (VERBOSE)
             $display ("Write or Dummy Write with Random Read", $time);
         if (VERBOSE)
             $display("******************* Check for Dummy Write Sequence");

         Get_Lower_Device_Address_Bits_and_ACK_to_Master;

         if (VERBOSE)
             $display("Device address bits are loaded");
         if(VERBOSE)
             $display("addr_reg holds %H",addr_reg);
         Get_Word_Address_Bytes;
         if(VERBOSE)
             $display("addr_reg holds %H",addr_reg);
         shift_in = 1; // Prep for read of data word (gets MSB)

         if (VERBOSE)
             $display("Wait for First clock after ACK following address bytes");

         @ (posedge SCL)  // Can't get START condition until after this clock
           begin: Byte_or_Page_Write
               if (VERBOSE)
                   $display("Byte_or_Page_Write Sequence initiated", $time);
               if (VERBOSE)
                   $display("Checking for WRITE PROTECTION");
               if (WP == 1)
               begin: WP_Detection
                   if (VERBOSE)
                       $display ("************************");
                   if (VERBOSE)
                       $display ("Invalid Attempt to Write");
                   if (VERBOSE)
                       $display ("Chip is write-protected");
                   if (VERBOSE)
                       $display ("************************");
                   disable Data_Transmission;  // 7/26/2008
               end // WP_Detection

               else
               begin: Write_Sequence
                   if (VERBOSE)
                       $display("Beginning a WRITE sequence", $time);
                   Get_Remainder_of_Byte;
                   if(VERBOSE)
                       $display("S_Byte_Shft_Reg holds %H",S_Byte_Shft_Reg);
                   if(VERBOSE)
                       $display ("addr_reg holds %H",addr_reg);
                   ACK_and_Write_a_Byte;
                   if (VERBOSE)
                       $display("Increment the address register", $time);
                   Execute_Page_Write;
                   if (VERBOSE)
                       $display ("*********************************************");
                   if (VERBOSE)
                       $display ("********************** TIMEOUT FOR PAGE WRITE");
                   if (VERBOSE)
                       $display ("*********************************************");
               end // Write_Sequence
           end // Byte_or_Page_Write
       end   // Wrapper
   endtask


   task ACK_and_Write_a_Byte;
`ifdef AT34C02

       if ((AT34C02_SWP_reg == 1) && (AT34C02_SWP_enabled == 0))
       begin
           if(VERBOSE)
               $display("ACKing and writing a byte", $time);
           @ (negedge SCL);
           S_ACK = 1;
           shift_in = 0;
           S_send_rcvb = SEND;

           @ (posedge SCL)
             @ (negedge SCL)
             begin
                 S_ACK = 0;
                 shift_in = 1;
                 S_send_rcvb = RECEIVE;
             end
             else if ((AT34C02_SWP_enabled && (addr_reg > 127))||(AT34C02_SWP_reg == 0))
             begin
                 @ (negedge SCL)
                   S_ACK = 1;
                 shift_in = 0;
                 S_send_rcvb = SEND;
                 Write_flag = 1;
                 @ (posedge SCL)
                   memory[addr_reg] <= S_Byte_Shft_Reg;
                 @ (negedge SCL)
                   S_ACK = 0;
                 shift_in = 1;
                 S_send_rcvb = RECEIVE;
                 Write_flag = 0;
                 -> incr_word_addr;

             end

`else
       begin // not AT34C02
           @ (negedge SCL) S_ACK = 1;
           shift_in = 0;
           S_send_rcvb = SEND;

           Write_flag = 1;
           @ (posedge SCL) memory[addr_reg] <= S_Byte_Shft_Reg;
           @ (negedge SCL) S_ACK = 0;
           shift_in = 1;
           S_send_rcvb = RECEIVE;
           Write_flag = 0;
           -> incr_word_addr;
       end
`endif
         endtask

         task Get_Remainder_of_Byte;
             begin
                 if (VERBOSE)
                     $display("Getting remainder of byte");
                 repeat (7)
                 begin
                     @ (posedge SCL)
                       if(VERBOSE)
                           $display("Clock tick - Data bit loaded into S_Byte_Shift_Reg");
                     if(VERBOSE)
                         $display("Ready to write - data word has been loaded into shift register", $time);
                 end
             end  // repeat
         endtask


         task Get_Lower_Device_Address_Bits_and_ACK_to_Master;
             begin  // Called on first drop of SCL after byte of data is read
                 if (VERBOSE)
                     $display("Getting lower device address bits and ACK to Master", $time);

`ifdef AT24C1024

                 addr_reg[ADDR_SIZE-1] = S_Byte_Shft_Reg[1];  //Grab P0
`endif
  `ifdef AT24C16

                 addr_reg[ADDR_SIZE-1:ADDR_SIZE-3 ] = S_Byte_Shft_Reg[3:1];
`endif
  `ifdef AT24C16A

                 addr_reg[ADDR_SIZE-1:ADDR_SIZE-3 ] = S_Byte_Shft_Reg[3:1];
`endif
  `ifdef AT24C08

                 addr_reg[ADDR_SIZE-1:ADDR_SIZE-2] = S_Byte_Shft_Reg[2:1];
`endif
  `ifdef AT24C08A

                 addr_reg[ADDR_SIZE-1:ADDR_SIZE-2] = S_Byte_Shft_Reg[2:1];
`endif
  `ifdef AT24C04

                 addr_reg[ADDR_SIZE-1] = S_Byte_Shft_Reg[1];
`endif
  `ifdef AT24C04A

                 addr_reg[ADDR_SIZE-1] = S_Byte_Shft_Reg[1];
`endif

                 S_send_rcvb = SEND;
                 S_ACK = 1;  // Send ACK on first drop of SCL after byte of data
                 @(negedge SCL)
                  S_ACK = 0;
                 shift_in = 1; // Ends ACK on second drop of SCL
                 S_send_rcvb = RECEIVE;
             end
         endtask

         task Get_Word_Address_Bytes;
             begin
                 if(VERBOSE)
                     $display("Get_Word_Address_Bytes");
                 case (MEM_SIZE)
                     MEM_SIZE_1MEG_BIT,
                     MEM_SIZE_500K_BIT,
                     MEM_SIZE_256K_BIT,
                     MEM_SIZE_128K_BIT,
                     MEM_SIZE_64K_BIT,
                     MEM_SIZE_32K_BIT:
                     begin
                         Get_MSB_Byte_and_ACK;
                         shift_in = 1;
                         Get_LSB_Byte_and_ACK;
                     end
                     default:
                     begin
                         Get_LSB_Byte_and_ACK;
                     end
                 endcase
             end
         endtask

         task Begin_a_Read_Sequence;
             begin
                 if (VERBOSE)
                     $display("Beginning a READ sequence", $time);
                 @ (negedge SCL)
                   shift_in = 0;
                 NO_ACK_flag = 0;
                 if (Device_Address_Active)
                     Check_for_Valid_Upper_Bits_of_Device_Address;
                 if (Valid_Address_flag)
                 begin:  Address_Match
                     if (VERBOSE)
                         $display ("Upper_Bits_of_Device_Address_Match");

                     case (S_Byte_Shft_Reg[0])
                         0:
                         begin
                             Write_or_Dummy_Write_with_Random_Read;// Should not occur
                             if (VERBOSE)
                                 $display ("********* ERROR *****");
                         end
                         1:
                             Current_Address_and_Sequential_Read; // Read after dummy write
                     endcase
                 end  // Address_Match
             end
         endtask


         ///////////////////////////////////////////////////////////////////////////////
         ///////////////////////////////////////////////////////////////////////////////
         task Execute_Page_Write;   // Added 1-27-2003
             begin
                 if (VERBOSE)
                     $display("time:", $realtime);
                 if (VERBOSE)
                     $display("*********************************************");
                 if (VERBOSE)
                     $display("*********************************************");
                 if (VERBOSE)
                     $display("********* Execute_Page_Write is Writing Bytes");
                 if (VERBOSE)
                     $display("*********************************************");
                 if (VERBOSE)
                     $display("*********************************************");
                 if (VERBOSE)
                     $display("************************************", $time);
`ifdef AT34C02 begin

                 if ((AT34C02_SWP_enabled && (addr_reg > 127))||(AT34C02_SWP_reg == 0))
                 begin
                     shift_in = 1;
                     Exec_Page_Write_flag = 1;
                     forever
                     begin: Writing_Bytes
                         repeat (BYTE_SIZE) @ (posedge SCL);
                         ACK_and_Write_a_Byte;
                         addr_reg[WORD_ADDR_SIZE-1: 0] <= addr_reg[WORD_ADDR_SIZE-1:0] +1;
                     end // Writing_Bytes
                 end

`else // Not AT34C02
                 shift_in = 1;
                 Exec_Page_Write_flag = 1;
                 forever
                 begin: Writing_Bytes
                     repeat (BYTE_SIZE) @ (posedge SCL);
                     ACK_and_Write_a_Byte;
                     addr_reg[WORD_ADDR_SIZE-1: 0] <= addr_reg[WORD_ADDR_SIZE-1:0] +1;
                 end // Writing_Bytes
`endif

             end
         endtask

         task Current_Address_and_Sequential_Read;
             begin

                 if (VERBOSE)
                     $display("Beginning Current_Address_and_Sequential_Read", $time);
                 Load_Slave_Shift_Register_and_Send_ACK;
                 @(posedge SCL)
                  ld_S_Byte_Shft_Reg = 0;
                 shift_out = 1;
                 @(negedge SCL)
                  forever
                  begin: Current_or_Sequential_Read
                      Exec_Seq_Read_flag = 1;
                      repeat (6) @ (negedge SCL);
                      @ (posedge SCL) shift_out = 0;
                      @ (negedge SCL) // Have sent ACK and 8 bits to master
                        S_send_rcvb = RECEIVE;
                      ->incr_addr_reg;
                      @ (posedge SCL)
                        if (SDA_in > 0)
                        begin :Got_NO_ACK_from_Master
                            NO_ACK_So_Wait_for_STOP_Condition;
                            if (VERBOSE)
                                $display ("Got no ACK from Master - Disable Data Transmission", $time);
                            Exec_Seq_Read_flag = 0;
                            disable Data_Transmission;
                        end //Got_No_ACK_from_Master
                        else
                        begin: Got_ACK_from_Master  //  bit was 0

                            ld_S_Byte_Shft_Reg = 1;

                            Got_ACK_so_prepare_to_send;
                        end // Got_ACK_from_Master
                    end // Current _or_Sequential_Read
                end

            endtask

            task Load_Slave_Shift_Register_and_Send_ACK;  // Modified for protocol interupt
                begin
                    S_send_rcvb = SEND;
                    S_ACK = 1;                             // Send ACK to master
                    @(posedge SCL)
                     ld_S_Byte_Shft_Reg = 1;
                    @ (negedge SCL)
                      if(S_START)
                      begin
                          if(VERBOSE)
                              $display("Protocol interupted by START", $time);
                          disable Data_Transmission.Outer_Block.Inner_Block;
                      end
                      S_ACK = 0;
                end
            endtask

            task Got_ACK_so_prepare_to_send;  //Modified for protocol interupt
                begin
                    if (VERBOSE)
                        $display ("got ACK from master");
                    @ (negedge SCL)
                      if(S_START)
                      begin
                          if(VERBOSE)
                              $display("Protocol interupted by START", $time);
                          disable Data_Transmission.Outer_Block.Inner_Block;
                      end
                      S_send_rcvb = SEND;
                    @ (posedge SCL);
                    ld_S_Byte_Shft_Reg = 0;
                    shift_out = 1;
                    @ (negedge SCL)
                      if(S_START)
                      begin
                          if(VERBOSE)
                              $display("Protocol interupted by START", $time);
                          disable Data_Transmission.Outer_Block.Inner_Block;
                      end

                  end
              endtask

              task NO_ACK_So_Wait_for_STOP_Condition; // Modified for protocol interupt
                  begin
                      NO_ACK_flag = 1;
                      if (VERBOSE)
                          $display ("Got_NO_ACK_from_Master ", $time);
                      ld_S_Byte_Shft_Reg = 0;
                      @ (STOP_condition)
                        NO_ACK_flag = 0;
                      S_START = 0; // 04/24/2006
                      S_STOP = 1; // 04/24/2006
                  end
              endtask

              task Get_MSB_Byte_and_ACK;  // Modified for protocol interupt
                  begin
                      if (VERBOSE)
                          $display("Get_MSB_Byte_and_ACK", $time);
                      Get_a_Byte;
                      @ (negedge SCL)
                        shift_in = 0;
                      ld_addr_reg_MSB_byte = 1; // Set to load on next up edge of SCL
                      S_send_rcvb = SEND;
                      S_ACK = 1;     // Send ACK to master
                      @ (negedge SCL)
                        if (VERBOSE)
                            $display ("Loading MSB address byte", $time);
                      ld_addr_reg_MSB_byte = 0;

                      S_send_rcvb = RECEIVE;
                      S_ACK = 0;
                  end
              endtask

              task Get_LSB_Byte_and_ACK;  //Modified for protocol interupt
                  begin
                      if (VERBOSE)
                          $display("Get_LSB_Byte_and_ACK", $time);
                      //shift_in = 1;
                      Get_a_Byte;
                      @ (negedge SCL);
                      shift_in = 0;
                      ld_addr_reg_LSB_byte = 1;
                      S_send_rcvb = SEND;
                      S_ACK = 1;                      // Send ACK to master
                      @ (negedge SCL)
                        if (VERBOSE)
                            $display("Loading LSB address byte", $time);
                      ld_addr_reg_LSB_byte = 0;
                      S_send_rcvb = RECEIVE;
                      S_ACK = 0;
                  end
              endtask

              task Power_up_initialization;
                  begin
                      RUN_flag = 0;
                      addr_reg = 0;
                      S_Byte_Shft_Reg = 0;
                      Protocol_Recovery_reg = 0;

                      ld_S_Byte_Shft_Reg = 0;
                      ld_addr_reg_MSB_byte = 0;
                      ld_addr_reg_LSB_byte = 0;
                      shift_in = 0;
                      shift_out = 0;
                      S_ACK = 0;
                      NO_ACK_flag = 0;
                      Time_Out_flag = 0;
                      Exec_Page_Write_flag = 0;

                      Exec_Seq_Read_flag = 0;
                      Exec_Random_Read_flag = 0;
                      Write_flag = 0;
                      First_START_flag = 0;

                      S_START = 0;
                      S_STOP = 0;
                      Device_Address_Active = 0;

                      //  #POWER_UP_DELAY if (VERBOSE) $display ("Power_up_Initialization"); CJT 06_22_2020
                      RUN_flag = 1;

                  end
              endtask

              task Recover_from_Protocol_Interupt;
                  begin
                      Valid_Address_flag = 0;
                      ld_S_Byte_Shft_Reg = 0;
                      ld_addr_reg_MSB_byte = 0;
                      ld_addr_reg_LSB_byte = 0;
                      S_Byte_Shft_Reg = 0;
                      shift_in = 0;
                      shift_out = 0;
                      S_ACK = 0;
                      NO_ACK_flag = 0;
                      Exec_Page_Write_flag = 0;
                      Exec_Seq_Read_flag = 0;
                      Exec_Random_Read_flag = 0;
                      Write_flag = 0;
                      S_START = 0;
                      S_STOP = 0;
                      S_send_rcvb = RECEIVE;
                  end
              endtask




              //***************************************************************************
              //***************************************************************************
              //                      Timing Parameters and Checks AT24C1024
              //***************************************************************************
              //***************************************************************************
              // Set up conditions for when to measure stop timing
              wire en_st_stp_timing = RUN_flag && SCL && RECEIVE;

       /*     __________________________________________________                    *
       *     | Symbol  |  Voltage   |  Min   |  Max  |  Units |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     |  fSCL   |  4.5 - 5.5 |   0    |  1000 |   kHz  |                    *
       *     |         |  2.7 - 5.5 |   0    |  400  |        |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     |  tLOW   |  4.5 - 5.5 |   0.6  |   0   |   us   |                    *
       *     |         |  2.7 - 5.5 |   1.3  |   0   |        |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     |  tHIGH  |  4.5 - 5.5 |   0.4  |   0   |   us   |                    *
       *     |         |  2.7 - 5.5 |   1.0  |   0   |        |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     | tHDSTA  |  4.5 - 5.5 |   0.25 |       |   us   |                    *
       *     |         |  2.7 - 5.5 |   0.6  |       |        |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     | tSUSTA  |  4.5 - 5.5 |   0.25 |       |   us   |                    *
       *     |         |  2.7 - 5.5 |   0.6  |       |        |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     | tHDDAT  |            |        |   0   |   ns   |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     | tSUDAT  |            |        |   100 |   ns   |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     |  tSUSTO |  4.5 - 5.5 |   0.25 |       |   us   |                    *
       *     |         |  2.7 - 5.5 |   0.6  |       |        |                    *
       *     |---------|------------|--------|-------|--------|                    *
       *     |  tDH    |            |   50   |       |   ns   |                    *
       *      ------------------------------------------------                     *
       *                                                                           *
       ****************************************************************************/

`ifdef WANT_AT24C1024__4_5__5_5V_TIMING

       specify
           specparam tLOW    = 400;
           specparam tHIGH   = 400;
           specparam tHDSTA  = 250;
           specparam tSUSTA  = 250;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 250;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C1024__2_7__5_5V_TIMING

       specify
           specparam tLOW    = 1300;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;


           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

       //***************************************************************************

       //***************************************************************************
       //                Timing Parameters and Checks AT24C01A/02/04/08/16
       //***************************************************************************
       //***************************************************************************
       /*    -----------------------------------------------------
       *     |               Voltage     |    Voltage     |       |
       *     |          2.7-,2.5-, 1.8 V |    5 V         |       |
       *     |---------|---------|-------|--------|-------|-------|
       *     | Symbol  |   Min   |  Max  |  Min   | Max   | Units |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  fSCL   |    0    |  100  |        | 400   |  kHz  |
       *     |---------|---------|-------|-------_|-------|-------|
       *     |  tLOW   |    4.7  |   0   |   1.2  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tHIGH  |    4    |   0   |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tHDSTA  |    4    |       |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tSUSTA  |    4.7  |       |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tHDDAT  |     0   |       |   0    |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tSUDAT  |    200  |       |   100  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tSUSTO |    4.7  |       |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tDH    |     100 |       |   50   |       |   ns  |
       *      ----------------------------------------------------                                                                               *

       ****************************************************************************/



`ifdef WANT_AT24C_01A_02_04_08_16__5_V_TIMING

       specify
           specparam tLOW    = 1200;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;

           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C_01A_02_04_08_16__2_7__2_5__1_8_V_TIMING

       specify
           specparam tLOW    = 1200;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif



       //***************************************************************************
       //***************************************************************************
       //                      Timing Parameters and Checks
       //                          AT24C02A/04A/08A/16A
       //***************************************************************************
       //***************************************************************************
       //    -----------------------------------------------------------------
       //   |         |AT24C02A/04A |AT24C02A/04A |   AT24C16A  |AT24C02A/04A |
       //   |         |AT24C08A/16A |AT24C08A     |             |AT24C08A/16A |
       //   |-----------------------------------------------------------------
       //   |         |   Voltage   |   Voltage   |             |             |
       //   |         |   1.8V      | 2.5V, 2.7V  |     2.5V    |     5.0V    |
       //   |---------|------|------|------|------|------|------|--------------------|
       //   | Symbol  | Min  | Max  | Min  | Max  | Min  | Max  | Min  | Max  |Units |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   |  fSCL   |      | 100  |      | 100  |      | 400  |      | 400  | kHz  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   |  tLOW   |  4.7 |      | 4.7  |      | 1.3  |      | 1.2  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   |  tHIGH  |  4.0 |      | 4.0  |      | 0.6  |      | 0.6  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   | tHDSTA  |  4.0 |      | 4.0  |      | 0.6  |      | 0.6  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   | tSUSTA  |  4.7 |      | 4.7  |      | 0.6  |      | 0.6  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   | tHDDAT  |   0  |      |  0   |      | 0    |      | 0    |      |  us  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   | tSUDAT  |  200 |      | 200  |      | 100  |      | 100  |      |  ns  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   |  tSUSTO |  4.7 |      | 4.7  |      | 0.6  |      | 0.6  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|------|------|
       //   |  tDH    |  100 |      | 100  |      | 100  |      | 50   |      |  ns  |
       //    ------------------------------------------------------------------------|


`ifdef WANT_AT24C_02A_04A_08A_16A__1_8_V_TIMING

       specify
           specparam tLOW    = 4700;
           specparam tHIGH   = 4000;
           specparam tHDSTA  = 4000;
           specparam tSUSTA  = 4700;

           specparam tHDDAT  = 0;
           specparam tSUDAT  = 200;
           specparam tSUSTO  = 4700;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);


           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C_02A_04A_08A__2_5V__2_7V_TIMING

       specify
           specparam tLOW    = 4700;
           specparam tHIGH   = 4000;
           specparam tHDSTA  = 4000;
           specparam tSUSTA  = 4700;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 200;
           specparam tSUSTO  = 4700;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths

           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C_16A__2_5V_TIMING

       specify
           specparam tLOW    = 1300;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif


`ifdef WANT_AT24C_02A_04A_08A_16A__5V_TIMING

       specify
           specparam tLOW    = 1200;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif



       //***************************************************************************
       //***************************************************************************
       //                      Timing Parameters and Checks
       //                               AT24C512B
       //***************************************************************************
       //***************************************************************************
       //   |----------------------------------------------------
       //   |         |   Voltage   |      Voltage       |
       //   |         |    1.8V     |    2.5V / 5.0 V    |
       //   |---------|------|------|------|------|------|
       //   | Symbol  | Min  | Max  | Min  | Max  |Units |
       //   |---------|------|------|------|------|------|
       //   |  fSCL   |      | 400  |      | 1000 | kHz  |
       //   |---------|------|------|------|------|------|
       //   |  tLOW   | 1.3  |      | 0.4  |      |  us  |
       //   |---------|------|------|------|------|------|
       //   |  tHIGH  | 0.6  |      | 0.4  |      |  us  |
       //   |---------|------|------|------|------|------|
       //   | tHDSTA  | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|
       //   | tSUSTA  | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|
       //   | tHDDAT  |   0  |      | 0    |      |  us  |
       //   |---------|------|------|------|------|------|
       //   | tSUDAT  | 100  |      | 100  |      |  ns  |
       //   |---------|------|------|------|------|------|
       //   |  tSUSTO | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|
       //   |  tDH    |  50  |      | 50   |      |  ns  |
       //    --------------------------------------------|

`ifdef WANT_AT24C512B__1_8V_TIMING

       specify
           specparam tLOW    = 400;
           specparam tHIGH   = 400;
           specparam tHDSTA  = 250;
           specparam tSUSTA  = 250;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C512B__2_5V_TIMING

       specify
           specparam tLOW    = 400;
           specparam tHIGH   = 400;
           specparam tHDSTA  = 250;
           specparam tSUSTA  = 250;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 250;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif



       //***************************************************************************
       //***************************************************************************
       //                      Timing Parameters and Checks
       //                               AT24C512
       //***************************************************************************
       //***************************************************************************
       //   |----------------------------------------------------
       //   |         |   Voltage   |   Voltage   |  Voltage    |
       //   |         |   1.8V      |    2.7V     |     5.0 V   |
       //   |---------|------|------|------|------|------|------|------|
       //   | Symbol  | Min  | Max  | Min  | Max  | Min  | Max  |Units |
       //   |---------|------|------|------|------|------|------|------|
       //   |  fSCL   |      | 100  |      | 100  |      | 400  | kHz  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tLOW   |  4.7 |      | 1.3  |      | 0.4  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tHIGH  |  4.0 |      | 1.0  |      | 0.4  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tHDSTA  |  4.0 |      | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tSUSTA  |  4.7 |      | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tHDDAT  |   0  |      |  0   |      | 0    |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tSUDAT  |  200 |      | 100  |      | 100  |      |  ns  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tSUSTO |  4.7 |      | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tDH    |  100 |      | 50   |      | 50   |      |  ns  |
       //    ----------------------------------------------------------|

`ifdef WANT_AT24C512__1_8_V_TIMING

       specify
           specparam tLOW    = 4700;
           specparam tHIGH   = 4000;
           specparam tHDSTA  = 4000;
           specparam tSUSTA  = 4700;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 200;
           specparam tSUSTO  = 4700;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C512__2_7V_TIMING

       specify
           specparam tLOW    = 400;
           specparam tHIGH   = 400;
           specparam tHDSTA  = 250;
           specparam tSUSTA  = 250;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C512__5V_TIMING

       specify
           specparam tLOW    = 1300;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 250;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

       //////////////////

       //***************************************************************************
       //***************************************************************************
       //                      Timing Parameters and Checks
       //                               AT24C128_256
       //***************************************************************************
       //***************************************************************************
       //   |---------------------------------------------------
       //   |         |   Voltage   |   Voltage   |  Voltage    |
       //   |         |   1.8V      |    2.5V     |     5.0 V   |
       //   |---------|------|------|------|------|------|------|------|
       //   | Symbol  | Min  | Max  | Min  | Max  | Min  | Max  |Units |
       //   |---------|------|------|------|------|------|------|------|
       //   |  fSCL   |      | 100  |      | 400  |      | 1000 | kHz  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tLOW   |  4.7 |      | 1.3  |      | 0.4  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tHIGH  |  4.0 |      | 0.6  |      | 0.4  |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tHDSTA  |  4.0 |      | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tSUSTA  |  4.7 |      | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tHDDAT  |   0  |      |  0   |      | 0    |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   | tSUDAT  |  200 |      | 100  |      | 100  |      |  ns  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tSUSTO |  4.7 |      | 0.6  |      | 0.25 |      |  us  |
       //   |---------|------|------|------|------|------|------|------|
       //   |  tDH    |  100 |      | 50   |      | 50   |      |  ns  |
       //    ----------------------------------------------------------|


`ifdef WANT_AT24C128_256__1_8_V_TIMING

       specify
           specparam tLOW    = 4700;
           specparam tHIGH   = 4000;
           specparam tHDSTA  = 4000;
           specparam tSUSTA  = 4700;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 200;
           specparam tSUSTO  = 4700;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C128_256__2_5V_TIMING

       specify
           specparam tLOW    = 1300;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif

`ifdef WANT_AT24C128_256__5V_TIMING

       specify
           specparam tLOW    = 400;

           specparam tHIGH   = 400;
           specparam tHDSTA  = 250;
           specparam tSUSTA  = 250;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 250;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif


       //***************************************************************************
       //***************************************************************************
       //                Timing Parameters and Checks AT34C02
       //***************************************************************************
       //***************************************************************************

       /*    -----------------------------------------------------
       *     |               Voltage     |    Voltage     |       |
       *     |                 1.8 V     |    2.7, 5 V    |       |
       *     |---------|---------|-------|--------|-------|-------|
       *     | Symbol  |   Min   |  Max  |  Min   | Max   | Units |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  fSCL   |    0    |  100  |        | 400   |  kHz  |
       *     |---------|---------|-------|-------_|-------|-------|
       *     |  tLOW   |    4.7  |   0   |   1.2  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tHIGH  |    4    |   0   |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tHDSTA  |    4    |       |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tSUSTA  |    4.7  |       |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tHDDAT  |     0   |       |   0    |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tSUDAT  |    200  |       |   100  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tSUSTO |    4.7  |       |   0.6  |       |   us  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tDH    |     100 |       |   50   |       |   ns  |
       *      ----------------------------------------------------
       *
       ****************************************************************************/

`ifdef WANT_AT34C02__2_7__5_0_V_TIMING

       specify
           specparam tLOW    = 1200;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif


`ifdef WANT_AT34C02__1_8_V_TIMING

       specify
           specparam tLOW    = 4700;
           specparam tHIGH   = 4000;
           specparam tHDSTA  = 4000;
           specparam tSUSTA  = 4700;

           specparam tHDDAT  = 0;
           specparam tSUDAT  = 200;
           specparam tSUSTO  = 4700;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif //  `ifdef WANT_AT34C02__1_8_V_TIMING

       //***************************************************************************
       //***************************************************************************
       //                Timing Parameters and Checks AT34C32/64
       //***************************************************************************
       //***************************************************************************

       /*    -----------------------------------------------------
       *     |               Voltage     |    Voltage     |       |
       *     |                 1.7 V     |    2.5, 3.6 V  |       |
       *     |---------|---------|-------|--------|-------|-------|
       *     | Symbol  |   Min   |  Max  |  Min   | Max   | Units |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  fSCL   |    0    |  400  |        |1000   |  kHz  |
       *     |---------|---------|-------|-------_|-------|-------|
       *     |  tLOW   |   1300  |   0   |   500  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tHIGH  |   600   |   0   |   400  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tHDSTA  |   600   |       |   250  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tSUSTA  |   600   |       |   250  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tHDDAT  |     0   |       |   0    |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     | tSUDAT  |    100  |       |   100  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tSUSTO |    600  |       |   250  |       |   ns  |
       *     |---------|---------|-------|--------|-------|-------|
       *     |  tDH    |     100 |       |   50   |       |   ns  |
       *      ----------------------------------------------------                                                                               *
       ****************************************************************************/

`ifdef WANT_AT34C32__1_7_V_TIMING

       specify
           specparam tLOW    = 1300;
           specparam tHIGH   = 600;
           specparam tHDSTA  = 600;
           specparam tSUSTA  = 600;
           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 600;
           specparam tDH     = 100;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif


`ifdef WANT_AT34C32__2_5_V_TIMING

       specify
           specparam tLOW    = 500;
           specparam tHIGH   = 400;
           specparam tHDSTA  = 250;
           specparam tSUSTA  = 2500;

           specparam tHDDAT  = 0;
           specparam tSUDAT  = 100;
           specparam tSUSTO  = 250;
           specparam tDH     = 50;

           $width(posedge SCL, tHIGH);             // SCL pulsewidths
           $width(negedge SCL, tLOW);

           $hold(negedge SDA, negedge SCL, tHDSTA);  // START hold time  cjt 02_27_2020
           $setup(posedge SCL, negedge SDA &&& en_st_stp_timing, tSUSTA); // START setup time  cjt 02_27_2020


           $hold(negedge SCL, SDA, tHDDAT);  // Data_in hold time
           $setup(SDA, posedge SCL, tSUDAT);  // Data_in setup time

           $setup(posedge SCL, posedge SDA &&& en_st_stp_timing, tSUSTO); // STOP setup time cjt 02_27_2020
       endspecify
`endif //  `ifdef WANT_AT34C32__2_5_V_TIMING


       endmodule