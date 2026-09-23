`timescale 1ns / 1ps

module apu_kws_sram_client_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        req_i = 1'b0;
  logic        write_i = 1'b1;
  logic [16:0] addr_i = 17'd0;
  logic [31:0] data_i = 32'd0;
  logic [ 3:0] strb_i = 4'd0;
  logic ready_o, valid_o, access_err_o;
  logic [31:0]       data_o;
  logic [15:0][14:0] model_addr_i = '0;
  logic [15:0][ 7:0] model_data_o;
  logic              scratch_clear_i = 1'b0;
  logic [19:0][15:0] scratch_read_addr_i = '0;
  logic [19:0][31:0] scratch_read_data_o;
  logic [ 5:0]       scratch_write_valid_i = 6'd0;
  logic [ 5:0][15:0] scratch_write_addr_i = '0;
  logic [ 5:0][31:0] scratch_write_data_i = '0;
  logic [ 5:0][ 3:0] scratch_write_strb_i = '0;
  logic              scratch_access_err_o;
  logic              codec_req_i = 1'b0;
  logic [16:0]       codec_addr_i = 17'd0;
  logic codec_ready_o, codec_valid_o, codec_access_err_o;
  logic [31:0] codec_data_o;

  always #5 clk_i = ~clk_i;

  apu_kws_sram_client u_kws_sram_client (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .req_i                (req_i),
      .write_i              (write_i),
      .addr_i               (addr_i),
      .data_i               (data_i),
      .strb_i               (strb_i),
      .ready_o              (ready_o),
      .data_o               (data_o),
      .valid_o              (valid_o),
      .access_err_o         (access_err_o),
      .model_addr_i         (model_addr_i),
      .model_data_o         (model_data_o),
      .scratch_clear_i      (scratch_clear_i),
      .scratch_read_addr_i  (scratch_read_addr_i),
      .scratch_read_data_o  (scratch_read_data_o),
      .scratch_write_valid_i(scratch_write_valid_i),
      .scratch_write_addr_i (scratch_write_addr_i),
      .scratch_write_data_i (scratch_write_data_i),
      .scratch_write_strb_i (scratch_write_strb_i),
      .scratch_access_err_o (scratch_access_err_o)
  );

  apu_local_sram u_local_sram (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .image_valid_i     (1'b1),
      .table_bytes_i     (16'd0),
      .epoch_clear_i     (1'b0),
      .loader_active_i   (1'b0),
      .loader_req_i      (1'b0),
      .loader_addr_i     (17'd0),
      .loader_data_i     (32'd0),
      .loader_strb_i     (4'd0),
      .loader_ready_o    (),
      .codec_req_i       (codec_req_i),
      .codec_write_i     (1'b0),
      .codec_addr_i      (codec_addr_i),
      .codec_data_i      (32'd0),
      .codec_strb_i      (4'd0),
      .codec_ready_o     (codec_ready_o),
      .codec_data_o      (codec_data_o),
      .codec_valid_o     (codec_valid_o),
      .codec_access_err_o(codec_access_err_o)
  );

  task automatic write_model(input logic [16:0] address_i, input logic [31:0] value_i);
    begin
      @(negedge clk_i);
      req_i  = 1'b1;
      addr_i = address_i;
      data_i = value_i;
      strb_i = 4'hf;
      if (!ready_o) $fatal(1, "model client did not accept a bounded write");
      @(negedge clk_i);
      req_i  = 1'b0;
      strb_i = 4'd0;
    end
  endtask

  task automatic write_scratch(input logic [15:0] address_i, input logic [31:0] value_i,
                               input logic [3:0] strobe_i);
    begin
      @(negedge clk_i);
      scratch_write_valid_i[0] = 1'b1;
      scratch_write_addr_i[0]  = address_i;
      scratch_write_data_i[0]  = value_i;
      scratch_write_strb_i[0]  = strobe_i;
      @(negedge clk_i);
      scratch_write_valid_i[0] = 1'b0;
      scratch_write_strb_i[0]  = 4'd0;
      scratch_read_addr_i[0]   = address_i;
      #1;
      if (scratch_read_data_o[0] != value_i) begin
        $fatal(1, "scratch layout write mismatch at %04x", address_i);
      end
    end
  endtask

  task automatic reject_codec_address(input logic [16:0] address_i);
    begin
      @(negedge clk_i);
      codec_req_i  = 1'b1;
      codec_addr_i = address_i;
      #1;
      if (!codec_ready_o || !codec_access_err_o) begin
        $fatal(1, "codec accessed reserved KWS bank at %05x", address_i);
      end
      @(negedge clk_i);
      codec_req_i = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(negedge clk_i);
    rst_n_i = 1'b1;

    write_model(`APB4_APU__LOCAL_KWS_BASE, 32'h4433_2211);
    model_addr_i[0] = 15'd0;
    model_addr_i[1] = 15'd1;
    model_addr_i[2] = 15'd2;
    model_addr_i[3] = 15'd3;
    #1;
    if ({model_data_o[3], model_data_o[2], model_data_o[1], model_data_o[0]} != 32'h4433_2211) begin
      $fatal(1, "banks10..17 model readback mismatch");
    end
    write_model(17'h1_0000, 32'h8877_6655);
    write_model(`APB4_APU__LOCAL_KWS_BASE + `RETROSOC_APU_KWS__MODEL_BYTES - 4, 32'hccbb_aa99);
    model_addr_i[0] = 15'h6000;
    model_addr_i[1] = 15'h6001;
    model_addr_i[2] = 15'h6002;
    model_addr_i[3] = 15'h6003;
    model_addr_i[4] = 15'h7ffc;
    model_addr_i[5] = 15'h7ffd;
    model_addr_i[6] = 15'h7ffe;
    model_addr_i[7] = 15'h7fff;
    #1;
    if ({model_data_o[3], model_data_o[2], model_data_o[1], model_data_o[0]} != 32'h8877_6655) begin
      $fatal(1, "APUM model address crossing 0x10000 did not map to bank16");
    end
    if ({model_data_o[7], model_data_o[6], model_data_o[5], model_data_o[4]} != 32'hccbb_aa99) begin
      $fatal(1, "APUM final word did not map to bank17");
    end

    write_scratch(`RETROSOC_APU_KWS__SCRATCH_A_BASE, 32'h0102_0304, 4'hf);
    write_scratch(`RETROSOC_APU_KWS__SCRATCH_B_BASE, 32'h1112_1314, 4'hf);
    write_scratch(`RETROSOC_APU_KWS__SCRATCH_MFCC_BASE, 32'h2122_2324, 4'hf);
    write_scratch(`RETROSOC_APU_KWS__SCRATCH_MEL_BASE, 32'h3132_3334, 4'hf);
    write_scratch(`RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE, 32'h4142_4344, 4'hf);
    write_scratch(`RETROSOC_APU_KWS__SCRATCH_INGRESS_BASE, 32'h5152_5354, 4'hf);
    write_scratch(`RETROSOC_APU_KWS__SCRATCH_PEAK_BASE, 32'h6162_6364, 4'hf);
    write_scratch(16'h7ffc, 32'h7172_7374, 4'hf);

    model_addr_i[0] = 15'd0;
    #1;
    if (model_data_o[0] != 8'h11) $fatal(1, "scratch write corrupted APUM storage");

    @(negedge clk_i);
    req_i  = 1'b1;
    addr_i = `RETROSOC_APU_KWS__SCRATCH_LOCAL_BASE;
    #1;
    if (!access_err_o) $fatal(1, "model loader escaped banks10..17");
    @(negedge clk_i);
    req_i = 1'b0;
    @(negedge clk_i);

    scratch_write_addr_i[0]  = 16'h8000;
    scratch_write_valid_i[0] = 1'b1;
    #1;
    if (!scratch_access_err_o) $fatal(1, "scratch range overflow was accepted");
    @(negedge clk_i);
    scratch_write_valid_i[0] = 1'b0;

    write_scratch(`RETROSOC_APU_KWS__SCRATCH_FIR_BASE, 32'h0000_1234, 4'hf);
    @(negedge clk_i);
    scratch_clear_i = 1'b1;
    @(negedge clk_i);
    scratch_clear_i        = 1'b0;
    scratch_read_addr_i[0] = `RETROSOC_APU_KWS__SCRATCH_FIR_BASE;
    #1;
    if (scratch_read_data_o[0] != 32'd0) $fatal(1, "FIR lifecycle clear exposed stale data");
    scratch_read_addr_i[0] = `RETROSOC_APU_KWS__SCRATCH_A_BASE;
    #1;
    if (scratch_read_data_o[0] != 32'h0102_0304) begin
      $fatal(1, "history clear corrupted non-history scratch");
    end

    reject_codec_address(`APB4_APU__LOCAL_KWS_BASE);
    reject_codec_address(`RETROSOC_APU_KWS__SCRATCH_LOCAL_BASE);

    $display("PASS: APU P7 banks10..25 model/scratch SRAM isolation");
    $finish;
  end

  logic s_unused;
  assign s_unused = valid_o ^ ^data_o ^ codec_valid_o ^ ^codec_data_o;
endmodule
