module user_ip_wrapper (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 4:0] sel_i,
    output logic [15:0] gpio_out_o,
    input  logic [15:0] gpio_in_i,
    output logic [15:0] gpio_oeb_o,
    input  logic [31:0] slv_apb_paddr_i,
    input  logic [ 2:0] slv_apb_pprot_i,
    input  logic        slv_apb_psel_i,
    input  logic        slv_apb_penable_i,
    input  logic        slv_apb_pwrite_i,
    input  logic [31:0] slv_apb_pwdata_i,
    input  logic [ 3:0] slv_apb_pstrb_i,
    output logic        slv_apb_pready_o,
    output logic [31:0] slv_apb_prdata_o
);

  logic [15:0] s_user_1_gpio_out;
  logic [15:0] s_user_1_gpio_in;
  logic [15:0] s_user_1_gpio_oeb;
  logic [31:0] s_user_1_apb_paddr;
  logic [ 2:0] s_user_1_apb_pprot;
  logic        s_user_1_apb_psel;
  logic        s_user_1_apb_penable;
  logic        s_user_1_apb_pwrite;
  logic [31:0] s_user_1_apb_pwdata;
  logic [ 3:0] s_user_1_apb_pstrb;
  logic        s_user_1_apb_pready;
  logic [31:0] s_user_1_apb_prdata;

  logic [15:0] s_user_2_gpio_out;
  logic [15:0] s_user_2_gpio_in;
  logic [15:0] s_user_2_gpio_oeb;
  logic [31:0] s_user_2_apb_paddr;
  logic [ 2:0] s_user_2_apb_pprot;
  logic        s_user_2_apb_psel;
  logic        s_user_2_apb_penable;
  logic        s_user_2_apb_pwrite;
  logic [31:0] s_user_2_apb_pwdata;
  logic [ 3:0] s_user_2_apb_pstrb;
  logic        s_user_2_apb_pready;
  logic [31:0] s_user_2_apb_prdata;


  always_comb begin
    gpio_out_o           = '0;
    gpio_oeb_o           = '1;
    slv_apb_pready_o     = '0;
    slv_apb_prdata_o     = '0;
    s_user_1_gpio_in     = '0;
    s_user_1_apb_paddr   = '0;
    s_user_1_apb_pprot   = '0;
    s_user_1_apb_psel    = '0;
    s_user_1_apb_penable = '0;
    s_user_1_apb_pwrite  = '0;
    s_user_1_apb_pwdata  = '0;
    s_user_1_apb_pstrb   = '0;
    s_user_2_gpio_in     = '0;
    s_user_2_apb_paddr   = '0;
    s_user_2_apb_pprot   = '0;
    s_user_2_apb_psel    = '0;
    s_user_2_apb_penable = '0;
    s_user_2_apb_pwrite  = '0;
    s_user_2_apb_pwdata  = '0;
    s_user_2_apb_pstrb   = '0;
    unique case (sel_i)
      5'd1: begin
        gpio_out_o           = s_user_1_gpio_out;
        gpio_oeb_o           = s_user_1_gpio_oeb;
        slv_apb_pready_o     = s_user_1_apb_pready;
        slv_apb_prdata_o     = s_user_1_apb_prdata;
        s_user_1_gpio_in     = gpio_in_i;
        s_user_1_apb_paddr   = slv_apb_paddr_i;
        s_user_1_apb_pprot   = slv_apb_pprot_i;
        s_user_1_apb_psel    = slv_apb_psel_i;
        s_user_1_apb_penable = slv_apb_penable_i;
        s_user_1_apb_pwrite  = slv_apb_pwrite_i;
        s_user_1_apb_pwdata  = slv_apb_pwdata_i;
        s_user_1_apb_pstrb   = slv_apb_pstrb_i;
      end
      5'd2: begin
        gpio_out_o           = s_user_2_gpio_out;
        gpio_oeb_o           = s_user_2_gpio_oeb;
        slv_apb_pready_o     = s_user_2_apb_pready;
        slv_apb_prdata_o     = s_user_2_apb_prdata;
        s_user_2_gpio_in     = gpio_in_i;
        s_user_2_apb_paddr   = slv_apb_paddr_i;
        s_user_2_apb_pprot   = slv_apb_pprot_i;
        s_user_2_apb_psel    = slv_apb_psel_i;
        s_user_2_apb_penable = slv_apb_penable_i;
        s_user_2_apb_pwrite  = slv_apb_pwrite_i;
        s_user_2_apb_pwdata  = slv_apb_pwdata_i;
        s_user_2_apb_pstrb   = slv_apb_pstrb_i;
      end
      default: begin
        gpio_out_o           = '0;
        gpio_oeb_o           = '1;
        slv_apb_pready_o     = '0;
        slv_apb_prdata_o     = '0;
        s_user_1_gpio_in     = '0;
        s_user_1_apb_paddr   = '0;
        s_user_1_apb_pprot   = '0;
        s_user_1_apb_psel    = '0;
        s_user_1_apb_penable = '0;
        s_user_1_apb_pwrite  = '0;
        s_user_1_apb_pwdata  = '0;
        s_user_1_apb_pstrb   = '0;
        s_user_2_gpio_in     = '0;
        s_user_2_apb_paddr   = '0;
        s_user_2_apb_pprot   = '0;
        s_user_2_apb_psel    = '0;
        s_user_2_apb_penable = '0;
        s_user_2_apb_pwrite  = '0;
        s_user_2_apb_pwdata  = '0;
        s_user_2_apb_pstrb   = '0;
      end
    endcase
  end

  user_ip_design_1 u_user_ip_design_1 (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .gpio_out_o   (s_user_1_gpio_out),
      .gpio_in_i    (s_user_1_gpio_in),
      .gpio_oeb_o   (s_user_1_gpio_oeb),
      .apb_paddr_i  (s_user_1_apb_paddr),
      .apb_pprot_i  (s_user_1_apb_pprot),
      .apb_psel_i   (s_user_1_apb_psel),
      .apb_penable_i(s_user_1_apb_penable),
      .apb_pwrite_i (s_user_1_apb_pwrite),
      .apb_pwdata_i (s_user_1_apb_pwdata),
      .apb_pstrb_i  (s_user_1_apb_pstrb),
      .apb_pready_o (s_user_1_apb_pready),
      .apb_prdata_o (s_user_1_apb_prdata)
  );

  user_ip_design_2 u_user_ip_design_2 (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .gpio_out_o   (s_user_2_gpio_out),
      .gpio_in_i    (s_user_2_gpio_in),
      .gpio_oeb_o   (s_user_2_gpio_oeb),
      .apb_paddr_i  (s_user_2_apb_paddr),
      .apb_pprot_i  (s_user_2_apb_pprot),
      .apb_psel_i   (s_user_2_apb_psel),
      .apb_penable_i(s_user_2_apb_penable),
      .apb_pwrite_i (s_user_2_apb_pwrite),
      .apb_pwdata_i (s_user_2_apb_pwdata),
      .apb_pstrb_i  (s_user_2_apb_pstrb),
      .apb_pready_o (s_user_2_apb_pready),
      .apb_prdata_o (s_user_2_apb_prdata)
  );

endmodule
