
module address_decoder #(
    parameter                             c_apb_num_slaves = 1,
    parameter [32*c_apb_num_slaves-1 : 0] memory_regions1  = 0,
    parameter [32*c_apb_num_slaves-1 : 0] memory_regions2  = 64
) (
    input  [                31:0] input_address,
    output [c_apb_num_slaves-1:0] slave_sel

);

  genvar i;
  /*
generate
	for(i=0;i<c_apb_num_slaves;i=i+1) assign SSEL[i] = (captured_addr >= memory_regions1[i]) & ((state == Access)|(state == Setup)) & (captured_addr <= memory_regions2[i]) ;
endgenerate
*/

  generate
    for (i = 32; i <= c_apb_num_slaves * 32; i = i + 32) begin
      assign slave_sel[(i-32)/32] = (input_address >= memory_regions1[i-1:(i-32)]) & (input_address <= memory_regions2[i-1:(i-32)]) ;
    end
  endgenerate


endmodule
