module ppalite_stream_bfm (
    input  logic        clk_i,
    input  logic        rst_n_i,
    output logic        in_valid_o,
    input  logic        in_ready_i,
    output logic [31:0] in_data_o,
    output logic [ 3:0] in_keep_o,
    output logic [ 3:0] in_strb_o,
    output logic        in_id_o,
    output logic        in_dest_o,
    output logic        in_user_o,
    output logic        in_last_o,
    input  logic        out_valid_i,
    output logic        out_ready_o,
    input  logic [31:0] out_data_i,
    input  logic [ 3:0] out_keep_i,
    input  logic [ 3:0] out_strb_i,
    input  logic        out_last_i,
    input  logic        out_id_i,
    input  logic        out_dest_i,
    input  logic        out_user_i,
    output logic [31:0] input_accepted_o,
    output logic [31:0] output_accepted_o
);
  logic        s_stalled_q;
  logic [43:0] s_output_q;

  function automatic logic sidebands_valid(input logic [3:0] keep, input logic [3:0] strb,
                                           input logic identity, input logic destination);
    sidebands_valid = ({keep, strb, identity, destination} === {4'hf, 4'hf, 2'b00});
  endfunction

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_stalled_q       <= 1'b0;
      s_output_q        <= 44'd0;
      input_accepted_o  <= 32'd0;
      output_accepted_o <= 32'd0;
    end else begin
      if ($test$plusargs("PPALITE_TRACE") && out_valid_i)
        $display(
            "PPALITE_BFM t=%0t data=%h sof=%b last=%b ready=%b",
            $time,
            out_data_i,
            out_user_i,
            out_last_i,
            out_ready_o
        );
      if (in_valid_o && in_ready_i) input_accepted_o <= input_accepted_o + 32'd1;
      if (out_valid_i && out_ready_o) output_accepted_o <= output_accepted_o + 32'd1;
      if (s_stalled_q && (!out_valid_i ||
          ({out_data_i, out_keep_i, out_strb_i, out_last_i, out_id_i, out_dest_i,
            out_user_i} !== s_output_q))) begin
        $fatal(1, "PPALITE output changed under backpressure");
      end
      if (out_valid_i && !sidebands_valid(out_keep_i, out_strb_i, out_id_i, out_dest_i)) begin
        $fatal(1, "PPALITE output constant sideband violation");
      end
      s_stalled_q <= out_valid_i && !out_ready_o;
      s_output_q <= {
        out_data_i, out_keep_i, out_strb_i, out_last_i, out_id_i, out_dest_i, out_user_i
      };
    end
  end

  task automatic reset_bfm;
    in_valid_o  = 1'b0;
    in_data_o   = 32'd0;
    in_keep_o   = 4'hf;
    in_strb_o   = 4'hf;
    in_id_o     = 1'b0;
    in_dest_o   = 1'b0;
    in_user_o   = 1'b0;
    in_last_o   = 1'b0;
    out_ready_o = 1'b0;
  endtask

  task automatic drive_word(input logic [31:0] data, input logic [3:0] keep, input logic [3:0] strb,
                            input logic sof, input logic last, input logic identity,
                            input logic destination);
    in_data_o  = data;
    in_keep_o  = keep;
    in_strb_o  = strb;
    in_user_o  = sof;
    in_last_o  = last;
    in_id_o    = identity;
    in_dest_o  = destination;
    in_valid_o = 1'b1;
  endtask

  task automatic clear_word;
    in_valid_o = 1'b0;
    in_user_o  = 1'b0;
    in_last_o  = 1'b0;
    in_id_o    = 1'b0;
    in_dest_o  = 1'b0;
  endtask

  task automatic send_word(input logic [31:0] data, input logic [3:0] keep, input logic [3:0] strb,
                           input logic sof, input logic last, input logic identity,
                           input integer gap);
    repeat (gap) @(negedge clk_i);
    @(negedge clk_i);
    in_data_o  = data;
    in_keep_o  = keep;
    in_strb_o  = strb;
    in_user_o  = sof;
    in_last_o  = last;
    in_id_o    = identity;
    in_dest_o  = 1'b0;
    in_valid_o = 1'b1;
    if ($test$plusargs("PPALITE_TRACE"))
      $display(
          "PPALITE_SEND data=%h keep=%h sof=%b last=%b ready=%b", data, keep, sof, last, in_ready_i
      );
    do @(posedge clk_i); while (!in_ready_i);
    @(negedge clk_i);
    in_valid_o = 1'b0;
    in_user_o  = 1'b0;
    in_last_o  = 1'b0;
    in_id_o    = 1'b0;
  endtask

  task automatic reject_word(input logic [31:0] data, input logic [3:0] keep,
                             input logic [3:0] strb, input logic sof, input logic last,
                             input logic identity, input logic destination);
    @(negedge clk_i);
    in_data_o  = data;
    in_keep_o  = keep;
    in_strb_o  = strb;
    in_user_o  = sof;
    in_last_o  = last;
    in_id_o    = identity;
    in_dest_o  = destination;
    in_valid_o = 1'b1;
    repeat (2) begin
      @(negedge clk_i);
      if (in_ready_i) $fatal(1, "PPALITE malformed input was admitted");
    end
    in_valid_o = 1'b0;
    in_user_o  = 1'b0;
    in_last_o  = 1'b0;
    in_id_o    = 1'b0;
    in_dest_o  = 1'b0;
  endtask

  task automatic expect_word(input logic [31:0] data, input logic sof, input logic last,
                             input integer stall_cycles, input integer timeout_cycles);
    integer cycles;
    logic   observed;
    cycles      = 0;
    observed    = 1'b0;
    out_ready_o = 1'b0;
    while (!observed && (cycles < timeout_cycles)) begin
      @(negedge clk_i);
      cycles++;
      if (out_valid_i) begin
        if ((out_data_i !== data) || (out_user_i !== sof) || (out_last_i !== last)) begin
          $fatal(1, "PPALITE output got=%h/%b/%b expected=%h/%b/%b", out_data_i, out_user_i,
                 out_last_i, data, sof, last);
        end
        observed = 1'b1;
      end
    end
    if (!observed) $fatal(1, "PPALITE output timeout");
    repeat (stall_cycles) @(negedge clk_i);
    out_ready_o = 1'b1;
    @(negedge clk_i);
    out_ready_o = 1'b0;
  endtask

  task automatic drain_output(input integer timeout_cycles);
    integer cycles;
    cycles      = 0;
    out_ready_o = 1'b1;
    while (out_valid_i && (cycles < timeout_cycles)) begin
      @(negedge clk_i);
      cycles++;
    end
    if (out_valid_i) $fatal(1, "PPALITE output drain timeout");
    out_ready_o = 1'b0;
  endtask

  task automatic hold_extra_word(input logic [31:0] data);
    @(negedge clk_i);
    in_data_o  = data;
    in_keep_o  = 4'hf;
    in_strb_o  = 4'hf;
    in_user_o  = 1'b0;
    in_last_o  = 1'b1;
    in_valid_o = 1'b1;
    repeat (3) @(negedge clk_i);
    if (in_ready_i) $fatal(1, "PPALITE accepted post-quota input");
    in_valid_o = 1'b0;
  endtask
endmodule
