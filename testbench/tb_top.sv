module tb_top;
    logic clock_i;
    logic reset_ni;
    logic    uart_rx;
    logic    uart_tx;
   // logic [`SPI_SS_NB-1:0] ss_o;
    logic                  sclk_o;
    logic                  sd_o;
    logic                  sd_i;
    logic cio_jtag_tck;
    logic cio_jtag_tdi;
    logic cio_jtag_tdo;
    logic cio_jtag_tms;
    logic cio_jtag_trst_n;
    logic [19:0] gpio_i;
    logic [19:0] gpio_o;

    initial begin
		  reset_ni = 1'b0;
		  clock_i = 1'b0;
		  #2000;
		  reset_ni = 1'b1;
    end
 
    always #12.5 clock_i <= (clock_i === 1'b0);
 
  azadi_soc_top #(
  ) top_verilator(
    .clk_i(clock_i),
    .rst_ni(reset_ni),
    .gpio_i(gpio_i),
    .gpio_o(gpio_o),
    .uart_tx(uart_tx),
    .uart_rx(uart_rx),
  // jtag interface
    .jtag_tck_i(cio_jtag_tck),
    .jtag_tms_i(cio_jtag_tms),
    .jtag_trst_ni(cio_jtag_trst_n),
    .jtag_tdi_i(cio_jtag_tdi),
    .jtag_tdo_o(cio_jtag_tdo),
  // spi interface
    .ss_o        (),
    .sclk_o      (sclk_o),
    .sd_o        (sd_o),
    .sd_i        (sd_i)
  );
endmodule
