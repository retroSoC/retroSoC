module tiny_r2_p4_formal (
    input logic clk_i,
    input logic rst_n_i
);
  logic s_started_q = 1'b0;
  (* anyseq *) logic [2:0] s_valid, s_ready, s_write;
  tiny_sram_port_if u_ports[3] ();
  always_ff @(posedge clk_i) begin
    s_started_q <= 1'b1;
    assume (rst_n_i == s_started_q);
  end
  for (genvar client = 0; client < 3; client++) begin : gen_client
    logic [2:0] s_outstanding_q = '0;
    wire        s_accept = u_ports[client].req_valid && u_ports[client].req_ready;
    wire        s_complete = u_ports[client].rsp_valid && u_ports[client].rsp_ready;
    always_ff @(posedge clk_i) begin
      if (!rst_n_i) s_outstanding_q <= '0;
      else begin
        case ({
          s_accept, s_complete
        })
          2'b10: s_outstanding_q <= s_outstanding_q + 3'd1;
          2'b01: s_outstanding_q <= s_outstanding_q - 3'd1;
          default: begin
          end
        endcase
        assert (s_outstanding_q <= ((client == 2) ? 3'd2 : 3'd1));
        assert (!u_ports[client].rsp_valid || (s_outstanding_q != 3'd0));
      end
    end
    assign u_ports[client].req_valid = s_valid[client];
    assign u_ports[client].rsp_ready = s_ready[client];
    assign u_ports[client].write     = s_write[client];
    assign u_ports[client].addr      = 32'h30000000 + 32'(client) * 32'h1000;
    assign u_ports[client].wdata     = 32'(client);
    assign u_ports[client].wstrb     = 4'hf;
  end
  tiny_sram_group u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ports  (u_ports)
  );
endmodule

// Abstract only the macro payload: arbitration, storage reservation, response
// capture and all control logic are the production group implementation.
module tc_sram_1024x32 (
    input  logic        clk_i,
    cs_i,
    input  logic [ 9:0] addr_i,
    input  logic [31:0] data_i,
    input  logic [ 3:0] mask_i,
    input  logic        wren_i,
    output logic [31:0] data_o
);
  (* anyseq *) logic [31:0] s_value;
  assign data_o = s_value;
endmodule
