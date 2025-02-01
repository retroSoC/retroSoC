
module flop #(parameter width = 1) (
    input  wire               clk,
    input  wire               rst,
    input  wire [width-1 : 0] d,
    output reg  [width-1 : 0] q
);

always@(posedge clk or negedge rst) begin
    if(!rst)
        q <= 'b0;
    else
        q <= d;
end

endmodule