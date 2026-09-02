// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

`include "axi4_define.svh"

module jpeg_dma #(
    parameter int unsigned AddrWidth     = 32,
    parameter int unsigned DataWidth     = 64,
    parameter int unsigned MaxBurstBeats = 16
) (
    // verilog_format: off -- preserve read, write, status, and AXI interface columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  abort_i,
    input  logic                  quiesce_i,
    input  logic                  read_start_i,
    input  logic [AddrWidth-1:0]  read_addr_i,
    input  logic [31:0]           read_line_bytes_i,
    input  logic [31:0]           read_stride_i,
    input  logic [15:0]           read_lines_i,
    output logic                  read_busy_o,
    output logic                  read_done_o,
    axi4_stream_if.source         read_axis,
    input  logic                  write_start_i,
    input  logic [AddrWidth-1:0]  write_addr_i,
    input  logic [31:0]           write_line_bytes_i,
    input  logic [31:0]           write_stride_i,
    input  logic [15:0]           write_lines_i,
    output logic                  write_busy_o,
    output logic                  write_done_o,
    axi4_stream_if.sink           write_axis,
    output logic                  error_o,
    output logic                  error_read_o,
    output logic [ 1:0]           error_resp_o,
    output logic [AddrWidth-1:0]  error_addr_o,
    output logic [31:0]           read_bytes_o,
    output logic [31:0]           write_bytes_o,
    output logic [31:0]           read_stall_o,
    output logic [31:0]           write_stall_o,
    axi4_if.master                axi4
    // verilog_format: on
);
  localparam int unsigned BeatBytes = DataWidth / 8;
  localparam int unsigned StrobeWidth = DataWidth / 8;

  typedef enum logic [1:0] {
    ReadIdle,
    ReadStart,
    ReadData
  } read_state_e;

  typedef enum logic [1:0] {
    WriteIdle,
    WriteStart,
    WriteData,
    WriteResponse
  } write_state_e;

  read_state_e                    s_read_state_d;
  read_state_e                    s_read_state_q;
  logic         [            1:0] s_read_state_bits_q;
  write_state_e                   s_write_state_d;
  write_state_e                   s_write_state_q;
  logic         [            1:0] s_write_state_bits_q;
  logic         [  AddrWidth-1:0] s_read_line_base_d;
  logic         [  AddrWidth-1:0] s_read_line_base_q;
  logic         [  AddrWidth-1:0] s_read_addr_d;
  logic         [  AddrWidth-1:0] s_read_addr_q;
  logic         [           31:0] s_read_line_bytes_d;
  logic         [           31:0] s_read_line_bytes_q;
  logic         [           31:0] s_read_remaining_d;
  logic         [           31:0] s_read_remaining_q;
  logic         [           31:0] s_read_stride_d;
  logic         [           31:0] s_read_stride_q;
  logic         [           15:0] s_read_lines_d;
  logic         [           15:0] s_read_lines_q;
  logic                           s_read_first_d;
  logic                           s_read_first_q;
  logic                           s_read_abort_d;
  logic                           s_read_abort_q;
  logic                           s_read_done_d;
  logic                           s_read_done_q;
  logic         [  AddrWidth-1:0] s_write_line_base_d;
  logic         [  AddrWidth-1:0] s_write_line_base_q;
  logic         [  AddrWidth-1:0] s_write_addr_d;
  logic         [  AddrWidth-1:0] s_write_addr_q;
  logic         [           31:0] s_write_line_bytes_d;
  logic         [           31:0] s_write_line_bytes_q;
  logic         [           31:0] s_write_remaining_d;
  logic         [           31:0] s_write_remaining_q;
  logic         [           31:0] s_write_stride_d;
  logic         [           31:0] s_write_stride_q;
  logic         [           15:0] s_write_lines_d;
  logic         [           15:0] s_write_lines_q;
  logic         [            4:0] s_write_burst_beats_d;
  logic         [            4:0] s_write_burst_beats_q;
  logic                           s_write_abort_d;
  logic                           s_write_abort_q;
  logic                           s_write_done_d;
  logic                           s_write_done_q;
  logic                           s_err_d;
  logic                           s_err_q;
  logic                           s_err_read_d;
  logic                           s_err_read_q;
  logic         [            1:0] s_err_resp_d;
  logic         [            1:0] s_err_resp_q;
  logic         [  AddrWidth-1:0] s_err_addr_d;
  logic         [  AddrWidth-1:0] s_err_addr_q;
  logic         [           31:0] s_read_bytes_d;
  logic         [           31:0] s_read_bytes_q;
  logic         [           31:0] s_write_bytes_d;
  logic         [           31:0] s_write_bytes_q;
  logic         [           31:0] s_read_stall_d;
  logic         [           31:0] s_read_stall_q;
  logic         [           31:0] s_write_stall_d;
  logic         [           31:0] s_write_stall_q;

  logic                           s_read_start_valid;
  logic                           s_read_start_ready;
  logic         [            4:0] s_read_beats;
  logic                           s_read_master_busy;
  logic                           s_read_beat_valid;
  logic                           s_read_beat_ready;
  logic         [  DataWidth-1:0] s_read_data;
  logic         [            1:0] s_read_resp;
  logic                           s_read_last;
  logic                           s_read_expected_last;
  logic                           s_read_id_err;
  logic                           s_read_master_done;
  logic                           s_write_start_valid;
  logic                           s_write_start_ready;
  logic         [            4:0] s_write_beats;
  logic                           s_write_master_busy;
  logic                           s_write_data_valid;
  logic                           s_write_data_ready;
  logic         [  DataWidth-1:0] s_write_data;
  logic         [StrobeWidth-1:0] s_write_strobe;
  logic                           s_write_master_done;
  logic         [            1:0] s_write_resp;
  logic                           s_write_id_err;
  logic         [StrobeWidth-1:0] s_read_keep;
  logic         [StrobeWidth-1:0] s_write_expected_keep;
  logic         [           31:0] s_read_beat_bytes;
  logic         [           31:0] s_write_beat_bytes;
  logic                           s_read_fault;
  logic                           s_write_fault;
  logic                           s_write_payload_fault;

  function automatic logic [4:0] choose_burst(input logic [11:0] addr_low_i,
                                              input logic [31:0] bytes_i);
    logic [31:0] s_beats_needed;
    logic [31:0] s_boundary_beats;
    logic [31:0] s_selected;
    begin
      s_beats_needed   = (bytes_i + BeatBytes - 1) / BeatBytes;
      s_boundary_beats = (32'd4096 - {20'd0, addr_low_i}) / BeatBytes;
      s_selected       = s_beats_needed;
      if (s_selected > MaxBurstBeats) begin
        s_selected = MaxBurstBeats;
      end
      if (s_selected > s_boundary_beats) begin
        s_selected = s_boundary_beats;
      end
      if (s_selected == 32'd0) begin
        s_selected = 32'd1;
      end
      return s_selected[4:0];
    end
  endfunction

  function automatic logic [StrobeWidth-1:0] byte_mask(input logic [31:0] bytes_i);
    logic [StrobeWidth:0] s_mask;
    begin
      if (bytes_i >= BeatBytes) begin
        return '1;
      end
      s_mask = ({{StrobeWidth{1'b0}}, 1'b1} << bytes_i) - 1'b1;
      return s_mask[StrobeWidth-1:0];
    end
  endfunction

  function automatic logic [31:0] saturating_increment(input logic [31:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_read_state_q = read_state_e'(s_read_state_bits_q);
  assign s_write_state_q = write_state_e'(s_write_state_bits_q);
  assign s_read_beats = choose_burst(s_read_addr_q[11:0], s_read_remaining_q);
  assign s_write_beats = choose_burst(s_write_addr_q[11:0], s_write_remaining_q);
  assign s_read_beat_bytes = (s_read_remaining_q >= BeatBytes) ? BeatBytes : s_read_remaining_q;
  assign s_write_beat_bytes = (s_write_remaining_q >= BeatBytes) ? BeatBytes : s_write_remaining_q;
  assign s_read_keep = byte_mask(s_read_beat_bytes);
  assign s_write_expected_keep = byte_mask(s_write_beat_bytes);

  assign s_read_start_valid = (s_read_state_q == ReadStart) && !s_read_abort_q;
  assign s_read_beat_ready = (s_read_state_q == ReadData) &&
                             (s_read_abort_q || s_err_q || read_axis.tready);
  assign read_axis.tdata = s_read_data;
  assign read_axis.tkeep = s_read_keep;
  assign read_axis.tstrb = s_read_keep;
  assign read_axis.tlast = s_read_remaining_q <= BeatBytes;
  assign read_axis.tid = '0;
  assign read_axis.tdest = '0;
  assign read_axis.tuser = s_read_first_q;
  assign read_axis.tvalid = (s_read_state_q == ReadData) && s_read_beat_valid &&
                            !s_read_abort_q && !s_err_q && !s_read_fault;
  assign s_read_fault = s_read_beat_valid &&
                        ((s_read_resp != `AXI4_RESP_OKAY) || s_read_id_err ||
                         (s_read_last != s_read_expected_last));

  assign s_write_start_valid = (s_write_state_q == WriteStart) && !s_write_abort_q;
  assign s_write_payload_fault = (write_axis.tkeep != s_write_expected_keep) ||
                                 (write_axis.tstrb != s_write_expected_keep) ||
                                 (write_axis.tlast != (s_write_remaining_q <= BeatBytes));
  assign s_write_data_valid = (s_write_state_q == WriteData) &&
                              (s_write_abort_q || s_err_q || write_axis.tvalid);
  assign s_write_data = (s_write_abort_q || s_err_q || s_write_payload_fault) ?
                            '0 : write_axis.tdata;
  assign s_write_strobe = (s_write_abort_q || s_err_q || s_write_payload_fault) ?
                              '0 : write_axis.tkeep;
  assign write_axis.tready = (s_write_state_q == WriteData) && s_write_data_ready &&
                             !s_write_abort_q && !s_err_q;
  assign s_write_fault = s_write_master_done &&
                         ((s_write_resp != `AXI4_RESP_OKAY) || s_write_id_err);

  assign read_busy_o = (s_read_state_q != ReadIdle) || s_read_master_busy;
  assign write_busy_o = (s_write_state_q != WriteIdle) || s_write_master_busy;
  assign read_done_o = s_read_done_q;
  assign write_done_o = s_write_done_q;
  assign error_o = s_err_q;
  assign error_read_o = s_err_read_q;
  assign error_resp_o = s_err_resp_q;
  assign error_addr_o = s_err_addr_q;
  assign read_bytes_o = s_read_bytes_q;
  assign write_bytes_o = s_write_bytes_q;
  assign read_stall_o = s_read_stall_q;
  assign write_stall_o = s_write_stall_q;

  always_comb begin
    s_read_state_d      = s_read_state_q;
    s_read_line_base_d  = s_read_line_base_q;
    s_read_addr_d       = s_read_addr_q;
    s_read_line_bytes_d = s_read_line_bytes_q;
    s_read_remaining_d  = s_read_remaining_q;
    s_read_stride_d     = s_read_stride_q;
    s_read_lines_d      = s_read_lines_q;
    s_read_first_d      = s_read_first_q;
    s_read_abort_d      = s_read_abort_q;
    s_read_done_d       = 1'b0;

    if (abort_i && (s_read_state_q != ReadIdle)) begin
      s_read_abort_d = 1'b1;
    end
    unique case (s_read_state_q)
      ReadIdle: begin
        s_read_abort_d = 1'b0;
        if (read_start_i && !quiesce_i) begin
          if ((read_line_bytes_i == 32'd0) || (read_lines_i == 16'd0) || (read_addr_i[$clog2(
                  BeatBytes
              )-1:0] != '0) || (read_stride_i < read_line_bytes_i)) begin
            s_read_done_d = 1'b1;
          end else begin
            s_read_line_base_d  = read_addr_i;
            s_read_addr_d       = read_addr_i;
            s_read_line_bytes_d = read_line_bytes_i;
            s_read_remaining_d  = read_line_bytes_i;
            s_read_stride_d     = read_stride_i;
            s_read_lines_d      = read_lines_i;
            s_read_first_d      = 1'b1;
            s_read_state_d      = ReadStart;
          end
        end
      end
      ReadStart: begin
        if (s_read_start_valid && s_read_start_ready) begin
          s_read_state_d = ReadData;
        end
      end
      ReadData: begin
        if (s_read_beat_valid && s_read_beat_ready) begin
          s_read_addr_d      = s_read_addr_q + s_read_beat_bytes;
          s_read_remaining_d = s_read_remaining_q - s_read_beat_bytes;
          s_read_first_d     = 1'b0;
          if (s_read_last) begin
            if (s_read_abort_q || s_read_fault || s_err_q) begin
              s_read_done_d  = 1'b1;
              s_read_state_d = ReadIdle;
            end else if (s_read_remaining_q <= BeatBytes) begin
              if (s_read_lines_q == 16'd1) begin
                s_read_done_d  = 1'b1;
                s_read_state_d = ReadIdle;
              end else begin
                s_read_line_base_d = s_read_line_base_q + s_read_stride_q;
                s_read_addr_d      = s_read_line_base_q + s_read_stride_q;
                s_read_remaining_d = s_read_line_bytes_q;
                s_read_lines_d     = s_read_lines_q - 1'b1;
                s_read_state_d     = ReadStart;
              end
            end else begin
              s_read_state_d = ReadStart;
            end
          end
        end
      end
      default: s_read_state_d = ReadIdle;
    endcase
  end

  always_comb begin
    s_write_state_d       = s_write_state_q;
    s_write_line_base_d   = s_write_line_base_q;
    s_write_addr_d        = s_write_addr_q;
    s_write_line_bytes_d  = s_write_line_bytes_q;
    s_write_remaining_d   = s_write_remaining_q;
    s_write_stride_d      = s_write_stride_q;
    s_write_lines_d       = s_write_lines_q;
    s_write_burst_beats_d = s_write_burst_beats_q;
    s_write_abort_d       = s_write_abort_q;
    s_write_done_d        = 1'b0;

    if (abort_i && (s_write_state_q != WriteIdle)) begin
      s_write_abort_d = 1'b1;
    end
    unique case (s_write_state_q)
      WriteIdle: begin
        s_write_abort_d = 1'b0;
        if (write_start_i && !quiesce_i) begin
          if ((write_line_bytes_i == 32'd0) || (write_lines_i == 16'd0) || (write_addr_i[$clog2(
                  BeatBytes
              )-1:0] != '0) || (write_stride_i < write_line_bytes_i)) begin
            s_write_done_d = 1'b1;
          end else begin
            s_write_line_base_d  = write_addr_i;
            s_write_addr_d       = write_addr_i;
            s_write_line_bytes_d = write_line_bytes_i;
            s_write_remaining_d  = write_line_bytes_i;
            s_write_stride_d     = write_stride_i;
            s_write_lines_d      = write_lines_i;
            s_write_state_d      = WriteStart;
          end
        end
      end
      WriteStart: begin
        if (s_write_start_valid && s_write_start_ready) begin
          s_write_burst_beats_d = s_write_beats;
          s_write_state_d       = WriteData;
        end
      end
      WriteData: begin
        if (s_write_data_valid && s_write_data_ready) begin
          s_write_addr_d      = s_write_addr_q + s_write_beat_bytes;
          s_write_remaining_d = s_write_remaining_q - s_write_beat_bytes;
          if (s_write_burst_beats_q == 5'd1) begin
            s_write_state_d = WriteResponse;
          end else begin
            s_write_burst_beats_d = s_write_burst_beats_q - 1'b1;
          end
        end
      end
      WriteResponse: begin
        if (s_write_master_done) begin
          if (s_write_abort_q || s_write_fault || s_err_q) begin
            s_write_done_d  = 1'b1;
            s_write_state_d = WriteIdle;
          end else if (s_write_remaining_q == 32'd0) begin
            if (s_write_lines_q == 16'd1) begin
              s_write_done_d  = 1'b1;
              s_write_state_d = WriteIdle;
            end else begin
              s_write_line_base_d = s_write_line_base_q + s_write_stride_q;
              s_write_addr_d      = s_write_line_base_q + s_write_stride_q;
              s_write_remaining_d = s_write_line_bytes_q;
              s_write_lines_d     = s_write_lines_q - 1'b1;
              s_write_state_d     = WriteStart;
            end
          end else begin
            s_write_state_d = WriteStart;
          end
        end
      end
      default: s_write_state_d = WriteIdle;
    endcase
  end

  always_comb begin
    s_err_d         = s_err_q;
    s_err_read_d    = s_err_read_q;
    s_err_resp_d    = s_err_resp_q;
    s_err_addr_d    = s_err_addr_q;
    s_read_bytes_d  = s_read_bytes_q;
    s_write_bytes_d = s_write_bytes_q;
    s_read_stall_d  = s_read_stall_q;
    s_write_stall_d = s_write_stall_q;
    if ((read_start_i || write_start_i) && !read_busy_o && !write_busy_o) begin
      s_err_d         = 1'b0;
      s_err_read_d    = 1'b0;
      s_err_resp_d    = `AXI4_RESP_OKAY;
      s_err_addr_d    = '0;
      s_read_bytes_d  = 32'd0;
      s_write_bytes_d = 32'd0;
      s_read_stall_d  = 32'd0;
      s_write_stall_d = 32'd0;
    end
    if (read_axis.tvalid && !read_axis.tready) begin
      s_read_stall_d = saturating_increment(s_read_stall_q);
    end
    if (write_axis.tvalid && !write_axis.tready) begin
      s_write_stall_d = saturating_increment(s_write_stall_q);
    end
    if (s_read_beat_valid && s_read_beat_ready && !s_read_fault && !s_read_abort_q) begin
      s_read_bytes_d = s_read_bytes_q + s_read_beat_bytes;
    end
    if (s_write_data_valid && s_write_data_ready && !s_write_payload_fault &&
        !s_write_abort_q) begin
      s_write_bytes_d = s_write_bytes_q + s_write_beat_bytes;
    end
    if (!s_err_q && s_read_fault) begin
      s_err_d      = 1'b1;
      s_err_read_d = 1'b1;
      s_err_resp_d = s_read_resp;
      s_err_addr_d = s_read_addr_q;
    end else if (!s_err_q && (s_write_fault ||
                              ((s_write_state_q == WriteData) && write_axis.tvalid &&
                               s_write_data_ready && s_write_payload_fault))) begin
      s_err_d      = 1'b1;
      s_err_read_d = 1'b0;
      s_err_resp_d = s_write_fault ? s_write_resp : `AXI4_RESP_SLAVE_ERROR;
      s_err_addr_d = s_write_addr_q;
    end else if (!s_err_q && abort_i && (read_busy_o || write_busy_o)) begin
      s_err_d      = 1'b1;
      s_err_read_d = read_busy_o;
      s_err_resp_d = `AXI4_RESP_OKAY;
      s_err_addr_d = read_busy_o ? s_read_addr_q : s_write_addr_q;
    end
  end

  dma_axi4_master #(
      .AddrWidth    (AddrWidth),
      .DataWidth    (DataWidth),
      .MaxBurstBeats(MaxBurstBeats)
  ) u_axi4_master (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .read_start_valid_i  (s_read_start_valid),
      .read_start_ready_o  (s_read_start_ready),
      .read_addr_i         (s_read_addr_q),
      .read_beats_i        (s_read_beats),
      .read_fixed_i        (1'b0),
      .read_busy_o         (s_read_master_busy),
      .read_beat_valid_o   (s_read_beat_valid),
      .read_beat_ready_i   (s_read_beat_ready),
      .read_data_o         (s_read_data),
      .read_resp_o         (s_read_resp),
      .read_last_o         (s_read_last),
      .read_expected_last_o(s_read_expected_last),
      .read_id_error_o     (s_read_id_err),
      .read_done_o         (s_read_master_done),
      .write_start_valid_i (s_write_start_valid),
      .write_start_ready_o (s_write_start_ready),
      .write_addr_i        (s_write_addr_q),
      .write_beats_i       (s_write_beats),
      .write_fixed_i       (1'b0),
      .write_busy_o        (s_write_master_busy),
      .write_data_valid_i  (s_write_data_valid),
      .write_data_ready_o  (s_write_data_ready),
      .write_data_i        (s_write_data),
      .write_strb_i        (s_write_strobe),
      .write_done_o        (s_write_master_done),
      .write_resp_o        (s_write_resp),
      .write_id_error_o    (s_write_id_err),
      .axi4                (axi4)
  );

  dffr #(
      .DATA_WIDTH(2)
  ) u_read_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_state_d),
      .dat_o  (s_read_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_write_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_state_d),
      .dat_o  (s_write_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(AddrWidth)
  ) u_read_line_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_line_base_d),
      .dat_o  (s_read_line_base_q)
  );
  dffr #(
      .DATA_WIDTH(AddrWidth)
  ) u_read_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_addr_d),
      .dat_o  (s_read_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_line_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_line_bytes_d),
      .dat_o  (s_read_line_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_remaining_d),
      .dat_o  (s_read_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_stride_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_stride_d),
      .dat_o  (s_read_stride_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_read_lines_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_lines_d),
      .dat_o  (s_read_lines_q)
  );
  dffr u_read_first_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_first_d),
      .dat_o  (s_read_first_q)
  );
  dffr u_read_abort_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_abort_d),
      .dat_o  (s_read_abort_q)
  );
  dffr u_read_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_done_d),
      .dat_o  (s_read_done_q)
  );
  dffr #(
      .DATA_WIDTH(AddrWidth)
  ) u_write_line_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_line_base_d),
      .dat_o  (s_write_line_base_q)
  );
  dffr #(
      .DATA_WIDTH(AddrWidth)
  ) u_write_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_addr_d),
      .dat_o  (s_write_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_line_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_line_bytes_d),
      .dat_o  (s_write_line_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_remaining_d),
      .dat_o  (s_write_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_stride_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_stride_d),
      .dat_o  (s_write_stride_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_write_lines_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_lines_d),
      .dat_o  (s_write_lines_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_write_burst_beats_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_burst_beats_d),
      .dat_o  (s_write_burst_beats_q)
  );
  dffr u_write_abort_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_abort_d),
      .dat_o  (s_write_abort_q)
  );
  dffr u_write_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_done_d),
      .dat_o  (s_write_done_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr u_err_read_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_read_d),
      .dat_o  (s_err_read_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_err_resp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_resp_d),
      .dat_o  (s_err_resp_q)
  );
  dffr #(
      .DATA_WIDTH(AddrWidth)
  ) u_err_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_addr_d),
      .dat_o  (s_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_bytes_d),
      .dat_o  (s_read_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_bytes_d),
      .dat_o  (s_write_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_stall_d),
      .dat_o  (s_read_stall_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_stall_d),
      .dat_o  (s_write_stall_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth != 32) || (DataWidth != 64) || (MaxBurstBeats < 1) || (MaxBurstBeats > 16)) begin
      $fatal(1, "jpeg_dma: unsupported AXI geometry");
    end
  end
`endif
endmodule
