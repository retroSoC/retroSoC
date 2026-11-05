module ppalite_decimator (
    input  logic [ 2:0] format_i,
    input  logic        gray8_i,
    input  logic        rgb_swap_i,
    input  logic        output_byte_swap_i,
    input  logic [ 1:0] step_x_i,
    input  logic [ 1:0] step_y_i,
    input  logic [ 1:0] phase_x_i,
    input  logic [ 1:0] phase_y_i,
    input  logic [15:0] x_i,
    input  logic [15:0] y_i,
    input  logic [15:0] pixel_i,
    output logic        sel_o,
    output logic        line_sel_o,
    output logic [15:0] sample_o
);
  logic [15:0] s_x_delta;
  logic [15:0] s_y_delta;
  logic [15:0] s_x_mask;
  logic [15:0] s_y_mask;
  logic [15:0] s_rgb;
  logic [ 7:0] s_y;
  logic [15:0] s_converted;

  always_comb begin
    s_x_mask = (step_x_i == 2'd0) ? 16'd0 : ((step_x_i == 2'd1) ? 16'd1 : 16'd3);
    s_y_mask = (step_y_i == 2'd0) ? 16'd0 : ((step_y_i == 2'd1) ? 16'd1 : 16'd3);
    s_x_delta = x_i - {14'd0, phase_x_i};
    s_y_delta = y_i - {14'd0, phase_y_i};
    sel_o = (x_i >= {14'd0, phase_x_i}) && (y_i >= {14'd0, phase_y_i}) &&
        ((s_x_delta & s_x_mask) == 16'd0) && ((s_y_delta & s_y_mask) == 16'd0);
    line_sel_o = (y_i >= {14'd0, phase_y_i}) && ((s_y_delta & s_y_mask) == 16'd0);

    case (format_i)
      3'd0:    s_rgb = pixel_i;
      3'd1:    s_rgb = {pixel_i[7:0], pixel_i[15:8]};
      default: s_rgb = 16'd0;
    endcase
    case (format_i)
      3'd2, 3'd4: s_y = pixel_i[15:8];
      default:    s_y = pixel_i[7:0];
    endcase
    if (rgb_swap_i) s_rgb = {s_rgb[4:0], s_rgb[10:5], s_rgb[15:11]};
    if (gray8_i) begin
      s_converted = {8'd0, s_y};
    end else if (format_i >= 3'd2) begin
      s_converted = {s_y[7:3], s_y[7:2], s_y[7:3]};
    end else begin
      s_converted = s_rgb;
    end
    sample_o = (!gray8_i && output_byte_swap_i) ? {s_converted[7:0], s_converted[15:8]} :
        s_converted;
  end
endmodule
