module user_mstr_wrapper (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 4:0] sel_i,
    output logic        core_valid_o,
    output logic [31:0] core_addr_o,
    output logic [31:0] core_wdata_o,
    output logic [ 3:0] core_wstrb_o,
    input  logic [31:0] core_rdata_i,
    input  logic        core_ready_i,
    input  logic [31:0] irq_i
);

  logic        s_user_1_core_valid;
  logic [31:0] s_user_1_core_addr;
  logic [31:0] s_user_1_core_wdata;
  logic [ 3:0] s_user_1_core_wstrb;
  logic [31:0] s_user_1_core_rdata;
  logic        s_user_1_core_ready;
  logic [31:0] s_user_1_irq;

  logic        s_user_2_core_valid;
  logic [31:0] s_user_2_core_addr;
  logic [31:0] s_user_2_core_wdata;
  logic [ 3:0] s_user_2_core_wstrb;
  logic [31:0] s_user_2_core_rdata;
  logic        s_user_2_core_ready;
  logic [31:0] s_user_2_irq;

  logic        s_user_3_core_valid;
  logic [31:0] s_user_3_core_addr;
  logic [31:0] s_user_3_core_wdata;
  logic [ 3:0] s_user_3_core_wstrb;
  logic [31:0] s_user_3_core_rdata;
  logic        s_user_3_core_ready;
  logic [31:0] s_user_3_irq;

  logic        s_user_4_core_valid;
  logic [31:0] s_user_4_core_addr;
  logic [31:0] s_user_4_core_wdata;
  logic [ 3:0] s_user_4_core_wstrb;
  logic [31:0] s_user_4_core_rdata;
  logic        s_user_4_core_ready;
  logic [31:0] s_user_4_irq;


  always_comb begin
    core_valid_o        = '0;
    core_addr_o         = '0;
    core_wdata_o        = '0;
    core_wstrb_o        = '0;
    s_user_1_core_rdata = '0;
    s_user_1_core_ready = '0;
    s_user_1_irq        = '0;
    s_user_2_core_rdata = '0;
    s_user_2_core_ready = '0;
    s_user_2_irq        = '0;
    s_user_3_core_rdata = '0;
    s_user_3_core_ready = '0;
    s_user_3_irq        = '0;
    s_user_4_core_rdata = '0;
    s_user_4_core_ready = '0;
    s_user_4_irq        = '0;
    unique case (sel_i)
      5'd1: begin
        core_valid_o        = s_user_1_core_valid;
        core_addr_o         = s_user_1_core_addr;
        core_wdata_o        = s_user_1_core_wdata;
        core_wstrb_o        = s_user_1_core_wstrb;
        s_user_1_core_rdata = core_rdata_i;
        s_user_1_core_ready = core_ready_i;
        s_user_1_irq        = irq_i;
      end
      5'd2: begin
        core_valid_o        = s_user_2_core_valid;
        core_addr_o         = s_user_2_core_addr;
        core_wdata_o        = s_user_2_core_wdata;
        core_wstrb_o        = s_user_2_core_wstrb;
        s_user_2_core_rdata = core_rdata_i;
        s_user_2_core_ready = core_ready_i;
        s_user_2_irq        = irq_i;
      end
      5'd3: begin
        core_valid_o        = s_user_3_core_valid;
        core_addr_o         = s_user_3_core_addr;
        core_wdata_o        = s_user_3_core_wdata;
        core_wstrb_o        = s_user_3_core_wstrb;
        s_user_3_core_rdata = core_rdata_i;
        s_user_3_core_ready = core_ready_i;
        s_user_3_irq        = irq_i;
      end
      5'd4: begin
        core_valid_o        = s_user_4_core_valid;
        core_addr_o         = s_user_4_core_addr;
        core_wdata_o        = s_user_4_core_wdata;
        core_wstrb_o        = s_user_4_core_wstrb;
        s_user_4_core_rdata = core_rdata_i;
        s_user_4_core_ready = core_ready_i;
        s_user_4_irq        = irq_i;
      end
      default: begin
        core_valid_o        = '0;
        core_addr_o         = '0;
        core_wdata_o        = '0;
        core_wstrb_o        = '0;
        s_user_1_core_rdata = '0;
        s_user_1_core_ready = '0;
        s_user_1_irq        = '0;
        s_user_2_core_rdata = '0;
        s_user_2_core_ready = '0;
        s_user_2_irq        = '0;
        s_user_3_core_rdata = '0;
        s_user_3_core_ready = '0;
        s_user_3_irq        = '0;
        s_user_4_core_rdata = '0;
        s_user_4_core_ready = '0;
        s_user_4_irq        = '0;
      end
    endcase
  end


  user_mstr_design_1 u_user_mstr_design_1 (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .core_valid_o(s_user_1_core_valid),
      .core_addr_o (s_user_1_core_addr),
      .core_wdata_o(s_user_1_core_wdata),
      .core_wstrb_o(s_user_1_core_wstrb),
      .core_rdata_i(s_user_1_core_rdata),
      .core_ready_i(s_user_1_core_ready),
      .irq_i       (s_user_1_irq)
  );

  user_mstr_design_2 u_user_mstr_design_2 (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .core_valid_o(s_user_2_core_valid),
      .core_addr_o (s_user_2_core_addr),
      .core_wdata_o(s_user_2_core_wdata),
      .core_wstrb_o(s_user_2_core_wstrb),
      .core_rdata_i(s_user_2_core_rdata),
      .core_ready_i(s_user_2_core_ready),
      .irq_i       (s_user_2_irq)
  );

  user_mstr_design_3 u_user_mstr_design_3 (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .core_valid_o(s_user_3_core_valid),
      .core_addr_o (s_user_3_core_addr),
      .core_wdata_o(s_user_3_core_wdata),
      .core_wstrb_o(s_user_3_core_wstrb),
      .core_rdata_i(s_user_3_core_rdata),
      .core_ready_i(s_user_3_core_ready),
      .irq_i       (s_user_3_irq)
  );

  user_mstr_design_4 u_user_mstr_design_4 (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .core_valid_o(s_user_4_core_valid),
      .core_addr_o (s_user_4_core_addr),
      .core_wdata_o(s_user_4_core_wdata),
      .core_wstrb_o(s_user_4_core_wstrb),
      .core_rdata_i(s_user_4_core_rdata),
      .core_ready_i(s_user_4_core_ready),
      .irq_i       (s_user_4_irq)
  );
endmodule
