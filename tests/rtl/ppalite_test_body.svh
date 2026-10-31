logic clk_i = 1'b0;
always #5 clk_i = ~clk_i;
logic            rst_n_i = 1'b0;
logic   [  31:0] clock_hz_i = 32'd24000000;
logic            route_idle_i = 1'b1;
logic            source_ready_i = 1'b1;
logic            source_quiet_i = 1'b1;
logic            source_done_i = 1'b0;
logic            source_stopped_i = 1'b1;
logic   [  31:0] source_sequence_i = 32'd0;
logic   [  31:0] source_words_i = 32'd0;
logic   [  31:0] source_geometry_i = 32'd0;
logic   [   7:0] source_err_i = 8'd0;
logic            transport_ready_i = 1'b1;
logic            transport_idle_i = 1'b1;
logic            transport_done_i = 1'b0;
logic   [   7:0] transport_err_i = 8'd0;
logic            in_valid;
logic            in_ready;
logic   [  31:0] in_data;
logic   [   3:0] in_keep;
logic   [   3:0] in_strb;
logic            in_id;
logic            in_dest;
logic            in_user;
logic            in_last;
logic            out_valid;
logic            out_ready;
logic   [  31:0] out_data;
logic   [   3:0] out_keep;
logic   [   3:0] out_strb;
logic            out_last;
logic            out_id;
logic            out_dest;
logic            out_user;
logic            irq_o;
logic   [  31:0] stream_input_count;
logic   [  31:0] stream_output_count;
logic   [  31:0] vector_mem                [0:65535];
logic   [  31:0] external_sequence;
reg     [4095:0] vector_path;
integer          vector_count;
integer          vector_base;
integer          input_count;
integer          output_count;
integer          vector_index;

apb4_if u_apb (
    .pclk   (clk_i),
    .presetn(rst_n_i)
);
`ifndef PPALITE_DUT
`define PPALITE_DUT apb4_ppalite
`endif
/* verilator lint_off PINCONNECTEMPTY */
`PPALITE_DUT u_dut (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .clock_hz_i         (clock_hz_i),
    .route_idle_i       (route_idle_i),
    .route_i            (1'b0),
    .route_change_i     (1'b0),
    .route_write_o      (),                   // P1 retains its internal route selector.
    .route_value_o      (),
    .processing_format_o(),
    .capture_state_o    (),
    .capture_arm_o      (),
    .capture_close_o    (),
    .processor_idle_o   (),
    .source_ready_i     (source_ready_i),
    .source_quiet_i     (source_quiet_i),
    .source_done_i      (source_done_i),
    .source_stopped_i   (source_stopped_i),
    .source_sequence_i  (source_sequence_i),
    .source_words_i     (source_words_i),
    .source_geometry_i  (source_geometry_i),
    .source_err_i       (source_err_i),
    .source_config_err_i(1'b0),
    .source_stats_err_i (1'b0),
    .transport_ready_i  (transport_ready_i),
    .transport_idle_i   (transport_idle_i),
    .transport_done_i   (transport_done_i),
    .transport_err_i    (transport_err_i),
    .in_valid_i         (in_valid),
    .in_ready_o         (in_ready),
    .in_data_i          (in_data),
    .in_keep_i          (in_keep),
    .in_strb_i          (in_strb),
    .in_id_i            (in_id),
    .in_dest_i          (in_dest),
    .in_user_i          (in_user),
    .in_last_i          (in_last),
    .out_valid_o        (out_valid),
    .out_ready_i        (out_ready),
    .out_data_o         (out_data),
    .out_keep_o         (out_keep),
    .out_strb_o         (out_strb),
    .out_last_o         (out_last),
    .out_id_o           (out_id),
    .out_dest_o         (out_dest),
    .out_user_o         (out_user),
    .irq_o              (irq_o),
`ifdef PPALITE_SCALAR_APB
    .paddr_i            (u_apb.paddr),
    .pprot_i            (u_apb.pprot),
    .psel_i             (u_apb.psel),
    .penable_i          (u_apb.penable),
    .pwrite_i           (u_apb.pwrite),
    .pwdata_i           (u_apb.pwdata),
    .pstrb_i            (u_apb.pstrb),
    .pready_o           (u_apb.pready),
    .prdata_o           (u_apb.prdata),
    .pslverr_o          (u_apb.pslverr)
`else
    .apb4               (u_apb)
`endif
);
/* verilator lint_on PINCONNECTEMPTY */

ppalite_stream_bfm u_stream_bfm (
    .clk_i            (clk_i),
    .rst_n_i          (rst_n_i),
    .in_valid_o       (in_valid),
    .in_ready_i       (in_ready),
    .in_data_o        (in_data),
    .in_keep_o        (in_keep),
    .in_strb_o        (in_strb),
    .in_id_o          (in_id),
    .in_dest_o        (in_dest),
    .in_user_o        (in_user),
    .in_last_o        (in_last),
    .out_valid_i      (out_valid),
    .out_ready_o      (out_ready),
    .out_data_i       (out_data),
    .out_keep_i       (out_keep),
    .out_strb_i       (out_strb),
    .out_last_i       (out_last),
    .out_id_i         (out_id),
    .out_dest_i       (out_dest),
    .out_user_i       (out_user),
    .input_accepted_o (stream_input_count),
    .output_accepted_o(stream_output_count)
);

task automatic access (input logic write_access, input logic [11:0] offset, input logic [31:0] data,
                       input logic [3:0] strobe, input logic err_expected,
                       output logic [31:0] result_data);
  @(negedge clk_i);
  u_apb.psel    = 1'b1;
  u_apb.penable = 1'b0;
  u_apb.pwrite  = write_access;
  u_apb.paddr   = {20'd0, offset};
  u_apb.pwdata  = data;
  u_apb.pstrb   = strobe;
  u_apb.pprot   = 3'd0;
  @(negedge clk_i);
  u_apb.penable = 1'b1;
  for (integer timeout_cycles = 0; !u_apb.pready; timeout_cycles++) begin
    if (timeout_cycles == 3) $fatal(1, "PPALITE APB response exceeded bound");
    @(negedge clk_i);
  end
  if (u_apb.pslverr !== err_expected)
    $fatal(1, "PPALITE APB offset=%h err=%b expected=%b", offset, u_apb.pslverr, err_expected);
  result_data = u_apb.prdata;
  @(posedge clk_i);
  @(negedge clk_i);
  u_apb.psel    = 1'b0;
  u_apb.penable = 1'b0;
  @(negedge clk_i);
endtask

task automatic wr(input logic [11:0] offset, input logic [31:0] data, input logic err);
  logic [31:0] unused_data;
  if ($test$plusargs("PPALITE_TRACE") && (TestKind == 2))
    $display("PPALITE_APB_WRITE offset=%h data=%h expected_err=%b", offset, data, err);
  access (1'b1, offset, data, 4'hf, err, unused_data);
endtask

task automatic rd(input logic [11:0] offset, output logic [31:0] data);
  access (1'b0, offset, 32'd0, 4'd0, 1'b0, data);
endtask

task automatic check_reg(input logic [11:0] offset, input logic [31:0] expected_data);
  logic [31:0] observed;
  rd(offset, observed);
  if (observed !== expected_data)
    $fatal(1, "PPALITE register %h got=%h expected=%h", offset, observed, expected_data);
endtask

task automatic reset_dut;
  rst_n_i           = 1'b0;
  route_idle_i      = 1'b1;
  source_ready_i    = 1'b1;
  source_quiet_i    = 1'b1;
  source_done_i     = 1'b0;
  source_stopped_i  = 1'b1;
  source_err_i      = 8'd0;
  source_words_i    = 32'd0;
  source_geometry_i = 32'd0;
  source_sequence_i = external_sequence;
  transport_ready_i = 1'b1;
  transport_idle_i  = 1'b1;
  transport_done_i  = 1'b0;
  transport_err_i   = 8'd0;
  u_apb.psel        = 1'b0;
  u_apb.penable     = 1'b0;
  u_apb.pwrite      = 1'b0;
  u_apb.paddr       = 32'd0;
  u_apb.pwdata      = 32'd0;
  u_apb.pstrb       = 4'd0;
  u_apb.pprot       = 3'd0;
  u_stream_bfm.reset_bfm();
  repeat (3) @(negedge clk_i);
  rst_n_i = 1'b1;
  repeat (3) @(negedge clk_i);
endtask

task automatic configure_vector(input integer base);
  source_geometry_i = vector_mem[base+1];
  source_words_i    = 32'd0;
  wr(12'h014, 32'd1, 1'b0);
  wr(12'h020, vector_mem[base+0], 1'b0);
  wr(12'h024, vector_mem[base+1], 1'b0);
  wr(12'h028, vector_mem[base+2], 1'b0);
  wr(12'h030, 32'd0, 1'b0);
  wr(12'h034, 32'hffff_ffff, 1'b0);
  wr(12'h018, 32'd1, 1'b0);
  check_reg(12'h038, vector_mem[base+3]);
  check_reg(12'h03c, vector_mem[base+4]);
  check_reg(12'h040, vector_mem[base+5]);
  check_reg(12'h044, vector_mem[base+6]);
  check_reg(12'h048, vector_mem[base+7]);
  check_reg(12'h04c, vector_mem[base+8]);
  check_reg(12'h098, vector_mem[base+0]);
  check_reg(12'h09c, vector_mem[base+1]);
endtask

task automatic run_vectors;
  if (!$value$plusargs("PPALITE_VECTORS=%s", vector_path))
    $fatal(1, "PPALITE vector file plusarg is required");
  $readmemh(vector_path, vector_mem);
  vector_count = vector_mem[0];
  if (vector_count !== 97) $fatal(1, "PPALITE incomplete vector corpus");
  vector_base = 1;
  for (vector_index = 0; vector_index < vector_count; vector_index++) begin
    $display("PPALITE_P1_VECTOR %0d", vector_index);
    reset_dut();
    configure_vector(vector_base);
    input_count  = vector_mem[vector_base+9];
    output_count = vector_mem[vector_base+10];
    fork
      begin
        for (integer index = 0; index < input_count; index++) begin
          u_stream_bfm.send_word(
              vector_mem[vector_base+12+index*5], vector_mem[vector_base+13+index*5][3:0],
              vector_mem[vector_base+14+index*5][3:0], vector_mem[vector_base+15+index*5][0],
              vector_mem[vector_base+16+index*5][0], 1'b0,
              (TestKind == 1) ? ((index * 7 + vector_index * 3) % 5) : 0);
        end
      end
      begin
        for (integer index = 0; index < output_count; index++) begin
          u_stream_bfm.expect_word(vector_mem[vector_base+12+input_count*5+index*5],
                                   vector_mem[vector_base+15+input_count*5+index*5][0],
                                   vector_mem[vector_base+16+input_count*5+index*5][0],
                                   (TestKind == 1) ? ((index * 11 + vector_index) % 7) : 0, 10000);
        end
      end
    join
    repeat (6) @(negedge clk_i);
    check_reg(12'h058, input_count);
    check_reg(12'h05c, vector_mem[vector_base+1][15:0] * vector_mem[vector_base+1][31:16]);
    check_reg(12'h060, {16'd0, vector_mem[vector_base+1][31:16]});
    check_reg(12'h064, vector_mem[vector_base+3][15:0] * vector_mem[vector_base+3][31:16]);
    check_reg(12'h068, output_count);
    check_reg(12'h06c, {16'd0, vector_mem[vector_base+3][31:16]});
    check_reg(12'h088, 32'd0);
    rd(12'h01c, vector_mem[60000]);
    if ((vector_mem[60000] & 32'h0000_071f) !== 32'h0000_0704)
      $fatal(1, "PPALITE VERIFY/input/pipe/owner status missing: %h", vector_mem[60000]);
    source_words_i    = input_count;
    source_sequence_i = external_sequence + 32'd1;
    source_done_i     = 1'b1;
    transport_done_i  = 1'b1;
    @(negedge clk_i);
    source_done_i = 1'b0;
    @(negedge clk_i);
    wr(12'h018, 32'd2, 1'b0);
    rd(12'h01c, vector_mem[60000]);
    if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
      $fatal(1, "PPALITE COMPLETE/result status missing: %h", vector_mem[60000]);
    check_reg(12'h054, external_sequence + 32'd1);
    wr(12'h018, 32'd4, 1'b0);
    rd(12'h01c, vector_mem[60000]);
    if ((vector_mem[60000] & 32'h0000_2107) !== 32'h0000_2000)
      $fatal(1, "PPALITE RELEASE did not retain result/drop owner: %h", vector_mem[60000]);
    external_sequence = external_sequence + 32'd1;
    vector_base       = vector_base + 12 + 5 * (input_count + output_count);
  end
endtask

task automatic run_apb;
  logic [31:0] observed;
  reset_dut();
  check_reg(12'h000, 32'h5050_414c);
  check_reg(12'h004, 32'h0001_0000);
  check_reg(12'h008, 32'h0000_00ff);
  check_reg(12'h00c, 32'h0020_0802);
  check_reg(12'h010, 32'd24000000);
  check_reg(12'h02c, 32'h0001_0b02);
  for (integer offset = 0; offset <= 32'h09c; offset += 4) begin
    if (offset !== 32'h018) rd(offset[11:0], observed);
  end
  access (1'b0, 12'h018, 32'd0, 4'd0, 1'b1, observed);
  access (1'b1, 12'h002, 32'd0, 4'hf, 1'b1, observed);
  access (1'b1, 12'h020, 32'd0, 4'h3, 1'b1, observed);
  access (1'b1, 12'h0a0, 32'd0, 4'hf, 1'b1, observed);
  wr(12'h000, 32'd0, 1'b1);
  wr(12'h020, 32'h0000_0008, 1'b1);
  wr(12'h020, 32'h0000_0010, 1'b1);
  wr(12'h024, 32'd0, 1'b1);
  wr(12'h028, 32'h0000_0003, 1'b1);
  check_reg(12'h020, 32'd0);
  check_reg(12'h024, 32'd0);
  check_reg(12'h028, 32'd0);
  for (integer offset = 32'h038; offset <= 32'h04c; offset += 4) check_reg(offset[11:0], 32'd0);
  wr(12'h018, 32'd1, 1'b1);
  wr(12'h014, 32'd1, 1'b0);
  wr(12'h020, 32'h0000_0002, 1'b0);
  wr(12'h024, 32'h0003_0005, 1'b0);
  source_geometry_i = 32'h0003_0005;
  wr(12'h028, 32'h0000_0105, 1'b0);
  wr(12'h030, 32'd2, 1'b1);
  wr(12'h030, 32'hffff_fffc, 1'b0);
  wr(12'h034, 32'd8, 1'b0);
  wr(12'h018, 32'd1, 1'b1);
  wr(12'h030, 32'd0, 1'b0);
  wr(12'h034, 32'd7, 1'b0);
  wr(12'h018, 32'd1, 1'b1);
  check_reg(12'h050, 32'd0);
  check_reg(12'h038, 32'd0);
  wr(12'h034, 32'd8, 1'b0);
  wr(12'h018, 32'd1, 1'b0);
  check_reg(12'h050, 32'd1);
  check_reg(12'h038, 32'h0002_0002);
  check_reg(12'h03c, 32'd4);
  check_reg(12'h040, 32'd4);
  check_reg(12'h044, 32'd8);
  check_reg(12'h048, 32'd8);
  check_reg(12'h04c, 32'd2);
  wr(12'h020, 32'd0, 1'b1);
  wr(12'h024, 32'h0003_0005, 1'b1);
  wr(12'h018, 32'd3, 1'b1);
  wr(12'h018, 32'd8, 1'b0);
  check_reg(12'h088, 32'd7);
  wr(12'h018, 32'd8, 1'b0);
  source_err_i = 8'd1;
  wr(12'h018, 32'h10, 1'b0);
  check_reg(12'h050, 32'd1);
  check_reg(12'h088, 32'd0);
  check_reg(12'h07c, 32'd0);
  wr(12'h018, 32'd1, 1'b1);
  source_err_i = 8'd0;
  wr(12'h018, 32'd8, 1'b1);
  wr(12'h018, 32'h20, 1'b1);
  wr(12'h014, 32'd0, 1'b0);
  wr(12'h080, 32'h1f, 1'b0);
  wr(12'h018, 32'h20, 1'b0);
  check_reg(12'h020, 32'd0);
  check_reg(12'h024, 32'd0);
  check_reg(12'h050, 32'd0);
  check_reg(12'h080, 32'd0);
  wr(12'h080, 32'h1f, 1'b0);
  check_reg(12'h080, 32'h1f);
  wr(12'h080, 32'h20, 1'b1);
  $display("PPALITE_P1_COVER PPL-V04 checked-layout-capacity-and-atomic-ARM");
  $display("PPALITE_P1_COVER PPL-V15 csr-access-errors-lifecycle-and-parity");
endtask

task automatic setup_negative(input logic [31:0] size);
  reset_dut();
  external_sequence = 32'd0;
  source_sequence_i = 32'd0;
  source_geometry_i = size;
  wr(12'h014, 32'd1, 1'b0);
  wr(12'h020, 32'd0, 1'b0);
  wr(12'h024, size, 1'b0);
  wr(12'h028, 32'd0, 1'b0);
  wr(12'h030, 32'd0, 1'b0);
  wr(12'h034, 32'hffff_ffff, 1'b0);
  wr(12'h018, 32'd1, 1'b0);
endtask

task automatic expect_close(input logic [7:0] code);
  repeat (3) @(negedge clk_i);
  rd(12'h088, vector_mem[60000]);
  rd(12'h090, vector_mem[60001]);
  rd(12'h094, vector_mem[60002]);
  $display("PPALITE_CLOSE first=%h source=%h dma=%h expected=%h", vector_mem[60000],
           vector_mem[60001], vector_mem[60002], code);
  check_reg(12'h088, {24'd0, code});
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000][2:0] !== 3'd6) || !vector_mem[60000][8])
    $fatal(1, "PPALITE fault did not retain CLOSING owner");
  if (in_ready) $fatal(1, "PPALITE fault left input admission enabled");
endtask

task automatic pulse_source_done(input logic [31:0] words, input logic [31:0] seq);
  source_words_i    = words;
  source_sequence_i = seq;
  source_done_i     = 1'b1;
  @(negedge clk_i);
  source_done_i = 1'b0;
endtask

task automatic send_four_by_two;
  u_stream_bfm.send_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 0);
  u_stream_bfm.send_word(32'h06050407, 4'hf, 4'hf, 1'b0, 1'b1, 1'b0, 0);
  u_stream_bfm.send_word(32'h0a09080b, 4'hf, 4'hf, 1'b0, 1'b0, 1'b0, 0);
  u_stream_bfm.send_word(32'h0e0d0c0f, 4'hf, 4'hf, 1'b0, 1'b1, 1'b0, 0);
endtask

task automatic run_negative_matrix;
  for (integer kind = 0; kind < 6; kind++) begin
    setup_negative(32'h0001_0004);
    case (kind)
      0:       u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'hf, 1'b0, 1'b0, 1'b0, 1'b0);
      1:       u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b1, 1'b0, 1'b0);
      2:       u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'h3, 1'b1, 1'b0, 1'b0, 1'b0);
      3:       u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b1, 1'b0);
      4:       u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 1'b1);
      default: u_stream_bfm.reject_word(32'h02030001, 4'h3, 4'h3, 1'b1, 1'b0, 1'b0, 1'b0);
    endcase
    expect_close(8'd3);
  end
  setup_negative(32'h0001_0004);
  u_stream_bfm.send_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 0);
  u_stream_bfm.reject_word(32'h06050407, 4'hf, 4'hf, 1'b1, 1'b1, 1'b0, 1'b0);
  expect_close(8'd3);
  setup_negative(32'h0001_0004);
  u_stream_bfm.send_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 0);
  u_stream_bfm.reject_word(32'h06050407, 4'hf, 4'hf, 1'b0, 1'b0, 1'b0, 1'b0);
  expect_close(8'd3);
  $display("PPALITE_P1_COVER PPL-V05 malformed-sof-eol-keep-strb-id-dest");

  setup_negative(32'h0002_0004);
  pulse_source_done(32'd0, 32'd1);
  expect_close(8'd4);
  setup_negative(32'h0002_0004);
  u_stream_bfm.send_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 0);
  u_stream_bfm.send_word(32'h06050407, 4'hf, 4'hf, 1'b0, 1'b1, 1'b0, 0);
  pulse_source_done(32'd2, 32'd1);
  expect_close(8'd4);
  setup_negative(32'h0002_0004);
  send_four_by_two();
  pulse_source_done(32'd3, 32'd1);
  expect_close(8'd4);
  setup_negative(32'h0002_0004);
  send_four_by_two();
  pulse_source_done(32'd4, 32'd1);
  pulse_source_done(32'd4, 32'd1);
  expect_close(8'd4);
  setup_negative(32'h0001_0001);
  @(negedge clk_i);
  u_stream_bfm.drive_word(32'h02030001, 4'h3, 4'h3, 1'b1, 1'b1, 1'b0, 1'b0);
  pulse_source_done(32'd1, 32'd2);
  if (in_ready) $fatal(1, "PPALITE wrong-sequence final beat was admitted");
  u_stream_bfm.clear_word();
  expect_close(8'd4);
  $display("PPALITE_P1_COVER PPL-V05 source-done-short-count-and-duplicate-faults");

  setup_negative(32'h0002_0004);
  source_err_i = 8'd1;
  u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 1'b0);
  expect_close(8'd1);
  setup_negative(32'h0002_0004);
  transport_err_i = 8'd1;
  u_stream_bfm.reject_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 1'b0);
  expect_close(8'd6);
endtask

task automatic send_single_valid;
  setup_negative(32'h0001_0001);
  u_stream_bfm.send_word(32'h02030001, 4'h3, 4'h3, 1'b1, 1'b1, 1'b0, 0);
  u_stream_bfm.expect_word(32'h0000_0001, 1'b1, 1'b1, 0, 100);
  repeat (6) @(negedge clk_i);
endtask

task automatic complete_single_frame;
  send_single_valid();
  pulse_source_done(32'd1, 32'd1);
  transport_done_i = 1'b1;
  repeat (2) @(negedge clk_i);
  wr(12'h018, 32'd2, 1'b0);
  check_reg(12'h054, 32'd1);
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
    $fatal(1, "PPALITE complete predicate failed");
endtask

task automatic run_lifecycle_races;
  send_single_valid();
  source_words_i    = 32'd1;
  source_sequence_i = 32'd1;
  source_done_i     = 1'b0;
  repeat (3) @(negedge clk_i);
  rd(12'h01c, vector_mem[60000]);
  if (vector_mem[60000][11]) $fatal(1, "PPALITE SOURCE_DONE set without an event");
  wr(12'h018, 32'd2, 1'b1);
  pulse_source_done(32'd1, 32'd1);
  transport_done_i = 1'b1;
  repeat (2) @(negedge clk_i);
  wr(12'h018, 32'd2, 1'b0);
  wr(12'h018, 32'd4, 1'b0);
  $display("PPALITE_P1_COVER PPL-V05 source-done-requires-event");

  send_single_valid();
  pulse_source_done(32'd1, 32'd1);
  transport_done_i = 1'b1;
  repeat (2) @(negedge clk_i);
  source_err_i = 8'd1;
  wr(12'h018, 32'd2, 1'b1);
  expect_close(8'd1);
  check_reg(12'h07c, 32'h0000_0005);
  wr(12'h018, 32'h10, 1'b0);
  check_reg(12'h07c, 32'd0);
  wr(12'h018, 32'd1, 1'b1);
  source_err_i = 8'd0;
  $display("PPALITE_P1_COVER PPL-V05 late-source-error-and-finalize-race");

  complete_single_frame();
  source_err_i = 8'd1;
  wr(12'h018, 32'd4, 1'b1);
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
    $fatal(1, "PPALITE RELEASE/error dropped ownership or result");
  source_err_i      = 8'd0;
  source_geometry_i = 32'h0001_0002;
  wr(12'h018, 32'd4, 1'b1);
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
    $fatal(1, "PPALITE RELEASE/geometry dropped ownership or result");
  source_geometry_i = 32'h0001_0001;
  wr(12'h018, 32'd4, 1'b0);
  $display("PPALITE_P1_COVER PPL-V15 finalize-release-live-error-atomicity");

  complete_single_frame();
  source_words_i    = 32'd1;
  source_sequence_i = 32'd2;
  source_done_i     = 1'b0;
  wr(12'h018, 32'd4, 1'b1);
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
    $fatal(1, "PPALITE advanced source sequence released ownership");
  wr(12'h018, 32'd8, 1'b0);
  wr(12'h018, 32'h10, 1'b0);

  complete_single_frame();
  source_words_i    = 32'd1;
  source_sequence_i = 32'd1;
  source_done_i     = 1'b1;
  wr(12'h018, 32'd4, 1'b1);
  source_done_i = 1'b0;
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
    $fatal(1, "PPALITE active completion event released ownership");
  wr(12'h018, 32'd8, 1'b0);
  wr(12'h018, 32'h10, 1'b0);

  complete_single_frame();
  source_words_i = 32'd2;
  source_done_i  = 1'b0;
  wr(12'h018, 32'd4, 1'b1);
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2707) !== 32'h0000_2705)
    $fatal(1, "PPALITE source word mismatch released ownership");
  wr(12'h018, 32'd8, 1'b0);
  wr(12'h018, 32'h10, 1'b0);
  $display("PPALITE_P1_COVER PPL-V15 release-source-statistics");

  setup_negative(32'h0001_0001);
  u_stream_bfm.send_word(32'h02030001, 4'h3, 4'h3, 1'b1, 1'b1, 1'b0, 0);
  while (!out_valid) @(negedge clk_i);
  if (out_data !== 32'h0000_0001) $fatal(1, "PPALITE unexpected held output");
  wr(12'h018, 32'd8, 1'b0);
  if (!out_valid || (out_data !== 32'h0000_0001)) $fatal(1, "PPALITE ABORT withdrew held output");
  wr(12'h07c, 32'h10, 1'b0);
  check_reg(12'h07c, 32'h0000_0018);
  source_err_i = 8'd1;
  u_stream_bfm.expect_word(32'h0000_0001, 1'b1, 1'b1, 0, 100);
  wr(12'h018, 32'h10, 1'b0);
  check_reg(12'h050, 32'd1);
  check_reg(12'h07c, 32'd0);
  wr(12'h018, 32'd1, 1'b1);
  source_err_i = 8'd0;
  $display("PPALITE_P1_COVER PPL-V15 abort-held-output-drain-and-w1c");

  setup_negative(32'h0001_0040);
  for (integer index = 0; index < 10; index++) begin
    u_stream_bfm.send_word(32'h02030001, 4'hf, 4'hf, (index == 0), 1'b0, 1'b0, 0);
  end
  check_reg(12'h078, 32'h0000_8082);
  wr(12'h018, 32'd8, 1'b0);
  if (!out_valid) $fatal(1, "PPALITE full FIFO output disappeared on ABORT");
  u_stream_bfm.drain_output(100);
  wr(12'h018, 32'h10, 1'b0);
  check_reg(12'h050, 32'd1);
  check_reg(12'h078, 32'd0);
  $display("PPALITE_P1_COVER PPL-V15 abort-queued-input-cleanup-and-fifo-fields");

`ifndef PPALITE_SCALAR_APB
  setup_negative(32'h0001_0001);
  force u_dut.u_core.s_output_err_q = 8'd5;
  pulse_source_done(32'd1, 32'd2);
  release u_dut.u_core.s_output_err_q;
  expect_close(8'd4);
  $display("PPALITE_P1_COVER PPL-V15 simultaneous-code4-code5-priority");
`endif

  send_single_valid();
  pulse_source_done(32'd1, 32'd1);
  transport_done_i = 1'b1;
  repeat (2) @(negedge clk_i);
  fork
    u_stream_bfm.hold_extra_word(32'h04050607);
    wr(12'h018, 32'd2, 1'b1);
  join
  expect_close(8'd4);
  check_reg(12'h07c, 32'h0000_0005);
  wr(12'h018, 32'h10, 1'b0);

  complete_single_frame();
  @(negedge clk_i);
  u_stream_bfm.drive_word(32'h04050607, 4'hf, 4'hf, 1'b0, 1'b1, 1'b0, 1'b0);
  @(negedge clk_i);
  wr(12'h018, 32'd4, 1'b1);
  u_stream_bfm.clear_word();
  rd(12'h01c, vector_mem[60000]);
  if ((vector_mem[60000] & 32'h0000_2107) !== 32'h0000_2105)
    $fatal(1, "PPALITE excess RELEASE race dropped ownership");
  wr(12'h018, 32'd8, 1'b0);
  wr(12'h018, 32'h10, 1'b0);
  $display("PPALITE_P1_COVER PPL-V05 finalize-release-excess-race");

  $display("PPALITE_STAGE partial-start");
  reset_dut();
  source_geometry_i = 32'h0001_0004;
  wr(12'h014, 32'd1, 1'b0);
  wr(12'h020, 32'h0000_0012, 1'b0);
  wr(12'h024, 32'h0001_0004, 1'b0);
  wr(12'h028, 32'd0, 1'b0);
  wr(12'h030, 32'd0, 1'b0);
  wr(12'h034, 32'hffff_ffff, 1'b0);
  wr(12'h018, 32'd1, 1'b0);
  u_stream_bfm.drive_word(32'h02030001, 4'hf, 4'hf, 1'b1, 1'b0, 1'b0, 1'b0);
  @(negedge clk_i);
  u_stream_bfm.clear_word();
  repeat (2) @(negedge clk_i);
  if (out_valid) $fatal(1, "PPALITE partial row unexpectedly produced output");
  $display("PPALITE_STAGE partial-abort");
  wr(12'h018, 32'd8, 1'b0);
  $display("PPALITE_STAGE partial-recover");
  wr(12'h018, 32'h10, 1'b0);
  check_reg(12'h050, 32'd1);
  wr(12'h018, 32'd1, 1'b0);
  check_reg(12'h050, 32'd2);
  wr(12'h018, 32'd8, 1'b0);
  wr(12'h018, 32'h10, 1'b0);
  $display("PPALITE_P1_COVER PPL-V15 partial-packer-abort-recovery");

  $display("PPALITE_STAGE stale-arm-start");
  complete_single_frame();
  wr(12'h018, 32'd4, 1'b0);
  u_stream_bfm.hold_extra_word(32'h04050607);
  repeat (2) @(negedge clk_i);
  wr(12'h018, 32'd1, 1'b0);
  check_reg(12'h050, 32'd2);
  u_stream_bfm.send_word(32'h02030001, 4'h3, 4'h3, 1'b1, 1'b1, 1'b0, 0);
  u_stream_bfm.expect_word(32'h0000_0001, 1'b1, 1'b1, 0, 100);
  $display("PPALITE_P1_COVER PPL-V15 idle-excess-then-legal-arm");
  $display("PPALITE_P1_COVER PPL-V15 recover-reset-irq-and-clean-arm-epoch");
endtask

task automatic run_detection_edge_races;
  $display("PPALITE_STAGE detection-start");
  setup_negative(32'h0006_0003);
  for (integer index = 0; index < 10; index++) begin
    $display("PPALITE_STAGE detection-send %0d", index);
    u_stream_bfm.send_word(32'h02030001, index[0] ? 4'h3 : 4'hf, index[0] ? 4'h3 : 4'hf,
                           (index == 0), index[0], 1'b0, 0);
  end
  $display("PPALITE_STAGE detection-reject");
  rd(12'h05c, vector_mem[60000]);
  rd(12'h068, vector_mem[60001]);
  u_stream_bfm.reject_word(32'h04050607, 4'hf, 4'h3, 1'b0, 1'b0, 1'b0, 1'b0);
  check_reg(12'h05c, vector_mem[60000]);
  check_reg(12'h068, vector_mem[60001]);
  expect_close(8'd3);
  $display("PPALITE_P1_COVER PPL-V05 detection-edge-framing-no-transform");

  setup_negative(32'h0001_0004);
  @(negedge clk_i);
  u_stream_bfm.drive_word(32'h02030001, 4'hf, 4'h3, 1'b1, 1'b0, 1'b0, 1'b0);
  transport_err_i = 8'd1;
  @(negedge clk_i);
  u_stream_bfm.clear_word();
  expect_close(8'd3);
  transport_err_i = 8'd0;
  $display("PPALITE_P1_COVER PPL-V05 live-framing-priority-over-dma");

`ifndef PPALITE_SCALAR_APB
  setup_negative(32'h0001_0001);
  force u_dut.u_core.s_output_live_err = 8'd5;
  transport_err_i = 8'd1;
  repeat (2) @(negedge clk_i);
  release u_dut.u_core.s_output_live_err;
  expect_close(8'd5);
  transport_err_i = 8'd0;
  $display("PPALITE_P1_COVER PPL-V05 live-output-priority-over-dma");
`endif
endtask

task automatic run_stream_errs;
  reset_dut();
  source_geometry_i = 32'h0001_0001;
  wr(12'h014, 32'd1, 1'b0);
  wr(12'h020, 32'd0, 1'b0);
  wr(12'h024, 32'h0001_0001, 1'b0);
  wr(12'h028, 32'd0, 1'b0);
  wr(12'h030, 32'd0, 1'b0);
  wr(12'h034, 32'hffff_ffff, 1'b0);
  wr(12'h018, 32'd1, 1'b0);
  u_stream_bfm.send_word(32'h02030001, 4'h3, 4'h3, 1'b1, 1'b1, 1'b0, 0);
  u_stream_bfm.expect_word(32'h0000_0001, 1'b1, 1'b1, 0, 100);
  u_stream_bfm.hold_extra_word(32'h04050607);
  repeat (3) @(negedge clk_i);
  check_reg(12'h088, 32'd4);
  check_reg(12'h058, 32'd1);
  if (out_valid) $fatal(1, "PPALITE post-quota input generated output");
  $display("PPALITE_P1_COVER PPL-V05 excess-valid-while-input-ready-low");
endtask

initial begin
  external_sequence = 32'd0;
  if ((TestKind == 0) || (TestKind == 1)) begin
    run_vectors();
    if (TestKind == 0) begin
      $display("PPALITE_P1_COVER PPL-V01 scalar-pixel-format-matrix");
      $display("PPALITE_P1_COVER PPL-V02 step-phase-and-geometry-matrix");
      $display("PPALITE_P1_COVER PPL-V03 dvp-byte-lane-and-row-padding");
      $display("PPALITE_P1_COVER PPL-V06 dropped-rows-and-post-output-input-drain");
    end else begin
      $display("PPALITE_P1_COVER PPL-V07 randomized-gaps-backpressure-and-stability");
      run_stream_errs();
      run_negative_matrix();
      run_lifecycle_races();
      run_detection_edge_races();
    end
  end else begin
    run_apb();
  end
  $display("PPALITE_P1_PASS %s", TestName);
  $finish;
end

initial begin
  #50000000;
  $fatal(1, "PPALITE test timeout");
end
