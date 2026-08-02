// Functional ICS55 IO models for Verilator only.
//
// The native model uses transistor primitives, transmission gates, and drive
// strengths that Verilator does not support. These models retain the logical
// behavior used by the SoC wrappers without replacing native-cell instances in
// other flows.

`timescale 1ns / 1ps

// The native PDK module names and analog drive controls are fixed interfaces.
// They do not affect the digital behavior represented by these models.
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSED */
module P65_1233_PWE (
    input  logic E,
    input  logic XIN,
    output logic XOUT,
    output logic XC
);

  assign XOUT = ~(E & XIN);
  assign XC   = E & XIN;

endmodule

module P65_1233_PBMUX (
    output logic C,
    inout  wire  A,
    inout  wire  PAD,
    input  logic IE,
    input  logic CS,
    input  logic I,
    input  logic OE,
    input  logic OD,
    input  logic PU,
    input  logic PD,
    input  logic DS0,
    input  logic DS1
);

  assign PAD = OE ? (OD ? (I ? 1'bz : 1'b0) : I) : 1'bz;
  assign PAD = PU ? 1'b1 : 1'bz;
  assign PAD = PD ? 1'b0 : 1'bz;
  assign A   = PAD;
  assign C   = IE ? PAD : 1'b0;

endmodule
/* verilator lint_on UNUSED */
/* verilator lint_on DECLFILENAME */
