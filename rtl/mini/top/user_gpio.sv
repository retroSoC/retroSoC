`include "mdd_config.svh"

interface user_gpio_if ();
  logic [`USER_GPIO_NUM-1:0] gpio_out;
  logic [`USER_GPIO_NUM-1:0] gpio_in;
  logic [`USER_GPIO_NUM-1:0] gpio_oen;

  modport dut(output gpio_out, input gpio_in, output gpio_oen);
endinterface
