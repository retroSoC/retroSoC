module ip_mdd_wrapper (
    (* keep *) input  logic        clk_i,
    (* keep *) input  logic        rst_n_i,
    (* keep *) input  logic [ 4:0] sel_i,
    // gpio
    (* keep *) output logic [15:0] gpio_out_o,
    (* keep *) input  logic [15:0] gpio_in_i,
    (* keep *) output logic [15:0] gpio_oeb_o,
    // apb if
    (* keep *) input  logic [31:0] slv_apb_paddr_i,
    (* keep *) input  logic [ 2:0] slv_apb_pprot_i,
    (* keep *) input  logic        slv_apb_psel_i,
    (* keep *) input  logic        slv_apb_penable_i,
    (* keep *) input  logic        slv_apb_pwrite_i,
    (* keep *) input  logic [31:0] slv_apb_pwdata_i,
    (* keep *) input  logic [ 3:0] slv_apb_pstrb_i,
    (* keep *) output logic        slv_apb_pready_o,
    (* keep *) output logic [31:0] slv_apb_prdata_o
);

  logic [31:0] s_slv_0_apb_paddr;
  logic [ 2:0] s_slv_0_apb_pprot;
  logic        s_slv_0_apb_psel;
  logic        s_slv_0_apb_penable;
  logic        s_slv_0_apb_pwrite;
  logic [31:0] s_slv_0_apb_pwdata;
  logic [ 3:0] s_slv_0_apb_pstrb;
  logic        s_slv_0_apb_pready;
  logic [31:0] s_slv_0_apb_prdata;

  logic [31:0] s_slv_user_apb_paddr;
  logic [ 2:0] s_slv_user_apb_pprot;
  logic        s_slv_user_apb_psel;
  logic        s_slv_user_apb_penable;
  logic        s_slv_user_apb_pwrite;
  logic [31:0] s_slv_user_apb_pwdata;
  logic [ 3:0] s_slv_user_apb_pstrb;
  logic        s_slv_user_apb_pready;
  logic [31:0] s_slv_user_apb_prdata;

  // verilog_format: off
  apb4_if       u_archinfo_ip_mdd_apb4_if(clk_i, rst_n_i);
  apb4_archinfo u_apb4_archinfo_ip_mdd(u_archinfo_ip_mdd_apb4_if);
    
  assign u_archinfo_ip_mdd_apb4_if.paddr   = s_slv_0_apb_paddr;
  assign u_archinfo_ip_mdd_apb4_if.pprot   = s_slv_0_apb_pprot;
  assign u_archinfo_ip_mdd_apb4_if.psel    = s_slv_0_apb_psel;
  assign u_archinfo_ip_mdd_apb4_if.penable = s_slv_0_apb_penable;
  assign u_archinfo_ip_mdd_apb4_if.pwrite  = s_slv_0_apb_pwrite;
  assign u_archinfo_ip_mdd_apb4_if.pwdata  = s_slv_0_apb_pwdata;
  assign u_archinfo_ip_mdd_apb4_if.pstrb   = s_slv_0_apb_pstrb;
  assign s_slv_0_apb_pready               = u_archinfo_ip_mdd_apb4_if.pready;
  assign s_slv_0_apb_pslverr              = u_archinfo_ip_mdd_apb4_if.pslverr;
  assign s_slv_0_apb_prdata               = u_archinfo_ip_mdd_apb4_if.prdata;
  // verilog_format: on

  assign slv_apb_pready_o     = sel_i == '0 ? s_slv_0_apb_pready : s_slv_user_apb_pready;
  assign slv_apb_prdata_o     = sel_i == '0 ? s_slv_0_apb_prdata : s_slv_user_apb_prdata;

  assign s_slv_0_apb_paddr   = sel_i == '0 ? slv_apb_paddr_i : '0;
  assign s_slv_0_apb_pprot   = sel_i == '0 ? slv_apb_pprot_i : '0;
  assign s_slv_0_apb_psel    = sel_i == '0 ? slv_apb_psel_i : '0;
  assign s_slv_0_apb_penable = sel_i == '0 ? slv_apb_penable_i : '0;
  assign s_slv_0_apb_pwrite  = sel_i == '0 ? slv_apb_pwrite_i : '0;
  assign s_slv_0_apb_pwdata  = sel_i == '0 ? slv_apb_pwdata_i : '0;
  assign s_slv_0_apb_pstrb   = sel_i == '0 ? slv_apb_pstrb_i : '0;

  assign s_slv_user_apb_paddr   = sel_i != '0 ? slv_apb_paddr_i : '0;
  assign s_slv_user_apb_pprot   = sel_i != '0 ? slv_apb_pprot_i : '0;
  assign s_slv_user_apb_psel    = sel_i != '0 ? slv_apb_psel_i : '0;
  assign s_slv_user_apb_penable = sel_i != '0 ? slv_apb_penable_i : '0;
  assign s_slv_user_apb_pwrite  = sel_i != '0 ? slv_apb_pwrite_i : '0;
  assign s_slv_user_apb_pwdata  = sel_i != '0 ? slv_apb_pwdata_i : '0;
  assign s_slv_user_apb_pstrb   = sel_i != '0 ? slv_apb_pstrb_i : '0;

  user_ip_wrapper u_user_ip_wrapper (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .sel_i            (sel_i),
      .gpio_out_o       (gpio_out_o),
      .gpio_in_i        (gpio_in_i),
      .gpio_oeb_o       (gpio_oeb_o),
      .slv_apb_paddr_i  (s_slv_user_apb_paddr),
      .slv_apb_pprot_i  (s_slv_user_apb_pprot),
      .slv_apb_psel_i   (s_slv_user_apb_psel),
      .slv_apb_penable_i(s_slv_user_apb_penable),
      .slv_apb_pwrite_i (s_slv_user_apb_pwrite),
      .slv_apb_pwdata_i (s_slv_user_apb_pwdata),
      .slv_apb_pstrb_i  (s_slv_user_apb_pstrb),
      .slv_apb_pready_o (s_slv_user_apb_pready),
      .slv_apb_prdata_o (s_slv_user_apb_prdata)
  );


endmodule
