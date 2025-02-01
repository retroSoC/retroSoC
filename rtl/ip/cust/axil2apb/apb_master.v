module apb_master
	#(parameter c_apb_num_slaves = 1)
	( PCLK,PRESETn,
	  STREQ,SWRT,SSEL,SADDR,SWDATA,WSTRB,SRDATA,
	  PADDR,PSELx,PENABLE,PWRITE,PWDATA,PSTRB,
	  PREADY,PRDATA,PSLVERR,
	  m_apb_prdata2,m_apb_prdata3,m_apb_prdata4,m_apb_prdata5,m_apb_prdata6,m_apb_prdata7,
	  m_apb_prdata8,m_apb_prdata9,m_apb_prdata10,m_apb_prdata11,m_apb_prdata12,m_apb_prdata13,
	  m_apb_prdata14,m_apb_prdata15,m_apb_prdata16,
	  Out_State
	);


input       			   PCLK;
input       			   PRESETn;

input	     			   STREQ;
input	     			   SWRT;
input[c_apb_num_slaves-1:0] 	   SSEL;
input[31:0]  			   SADDR;
input[31:0]  			   SWDATA;
input[3:0]                         WSTRB;
output[31:0] 			   SRDATA;

output[31:0] 			   PADDR;
// output[2:0]  			   PPROT;
output[c_apb_num_slaves-1:0] 	   PSELx;
output	     			   PENABLE;
output       			   PWRITE;
output[31:0] 			   PWDATA;
output[3:0]  			   PSTRB;

input[c_apb_num_slaves-1:0] 	   PREADY;
input[31:0]  			   PRDATA;
input[31:0] 			   m_apb_prdata2;
input[31:0] 			   m_apb_prdata3;
input[31:0] 			   m_apb_prdata4;
input[31:0] 			   m_apb_prdata5;
input[31:0] 			   m_apb_prdata6;
input[31:0] 			   m_apb_prdata7;
input[31:0] 			   m_apb_prdata8;
input[31:0] 			   m_apb_prdata9;
input[31:0] 			   m_apb_prdata10;
input[31:0] 			   m_apb_prdata11;
input[31:0] 			   m_apb_prdata12;
input[31:0] 			   m_apb_prdata13;
input[31:0] 			   m_apb_prdata14;
input[31:0] 			   m_apb_prdata15;
input[31:0] 			   m_apb_prdata16;
input[c_apb_num_slaves-1:0]        PSLVERR;

output[1:0]  			   Out_State;

parameter Idle   = 'd 0;
parameter Setup  = 'd 1;
parameter Access = 'd 2;

reg[1:0]  state;

always @ (posedge PCLK)
begin
	if (!PRESETn)
	state <= Idle;
	if (state == Idle)
	begin
		if (STREQ)
		  state <= Setup;
		else
		  state <= Idle;
	end
	else if (state == Setup)
		state <= Access;
	else if (state == Access)
	begin
		if (PREADY && STREQ)
		  state <= Setup;
		else if (PREADY && ~STREQ)
		  state <= Idle;
		else if (~PREADY)
		  state <= Access;
		else
		  state <= Idle;   
	end
	else state <= Idle;

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

