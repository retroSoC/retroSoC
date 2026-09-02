// Functional test model for the site-supplied ICS55 1024 x 32 SRAM macro.
module S55NLLG1PH_X256Y4D32_BW (
    input  logic [31:0] D,
    input  logic        CLK,
    input  logic        CEN,
    input  logic        WEN,
    input  logic [31:0] BWEN,
    input  logic [ 9:0] A,
    output logic [31:0] Q
);
  logic [31:0] s_memory[0:1023];

  always_ff @(posedge CLK) begin
    if (!CEN) begin
      if (!WEN) begin
        for (int bit_index = 0; bit_index < 32; bit_index++) begin
          if (!BWEN[bit_index]) begin
            s_memory[A][bit_index] <= D[bit_index];
          end
        end
      end else begin
        Q <= s_memory[A];
      end
    end
  end
endmodule
