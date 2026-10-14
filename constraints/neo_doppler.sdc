# =============================================================================
# neo_doppler.sdc - timing constraints (Intel Quartus TimeQuest / Vivado XDC
# compatible subset). Adjust port names / board delays to your hardware.
# =============================================================================

# 50 MHz system clock
create_clock -name clk_50m -period 20.000 [get_ports clk_50m]
derive_clock_uncertainty

# Asynchronous inputs: reset button and ADC data are re-synchronized in RTL.
set_false_path -from [get_ports rst_n_async]
set_false_path -from [get_ports adc_miso]

# Outputs are slow (SPI 1 MHz, UART 115200) - no meaningful I/O timing.
set_false_path -to [get_ports {adc_sclk adc_cs_n uart_txd led[*]}]

# Synchronizer flops: do not time the first stage of reset_sync / sync_2ff.
# (Quartus recognises them via the SYNCHRONIZER_IDENTIFICATION attribute,
#  Vivado via ASYNC_REG.)
