module apb_master #(
    parameter c_apb_num_slaves = 1
) (
    input                         PCLK,
    input                         PRESETn,
    input                         STREQ,
    input                         SWRT,
    input  [c_apb_num_slaves-1:0] SSEL,
    input  [                31:0] SADDR,
    input  [                31:0] SWDATA,
    input  [                 3:0] WSTRB,
    output [                31:0] SRDATA,
    output [                31:0] PADDR,
    output [c_apb_num_slaves-1:0] PSELx,
    output                        PENABLE,
    output                        PWRITE,
    output [                31:0] PWDATA,
    output [                 3:0] PSTRB,
    input  [c_apb_num_slaves-1:0] PREADY,
    input  [                31:0] PRDATA,
    input  [c_apb_num_slaves-1:0] PSLVERR,
    output [                 1:0] Out_State
);

  localparam Idle = 'd0;
  localparam Setup = 'd1;
  localparam Access = 'd2;

  reg [1:0] state;

  always @(posedge PCLK) begin
    if (!PRESETn) state <= Idle;
    if (state == Idle) begin
      if (STREQ) state <= Setup;
      else state <= Idle;
    end else if (state == Setup) state <= Access;
    else if (state == Access) begin
      if (PREADY && STREQ) state <= Setup;
      else if (PREADY && ~STREQ) state <= Idle;
      else if (~PREADY) state <= Access;
      else state <= Idle;
    end else state <= Idle;

  end

  assign PENABLE   = (state == Access) ? 1'b1 : 1'b0;
  assign PWRITE    = SWRT;
  assign PSELx     = SSEL;
  assign PADDR     = SADDR;
  assign PWDATA    = SWDATA;
  assign SRDATA    = PRDATA;
  assign Out_State = state;
  assign PSTRB     = WSTRB;
endmodule

