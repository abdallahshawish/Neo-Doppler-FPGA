// =============================================================================
// Module  : neo_doppler_top
// Project : NEO Doppler FPGA - space segment payload
// Purpose : Top level.
//
//   Doppler IF --> [ADC SPI] --> [DSP chain] --> [AES-CTR + CRC framer] --> UART TX
//                   (adc_spi_master)  (doppler_dsp_chain)  (secure_tlm_tx)  (uart_tx)
//
// Clock   : single 50 MHz domain; reset is synchronized (reset_sync).
// Security: AES_KEY below is a PLACEHOLDER TEST KEY. For flight / field use,
//           load the key from protected storage (eFuse, BBRAM, secure flash)
//           and increment BOOT_ID in non-volatile memory on every power-up so
//           the CTR nonce never repeats.
// LEDs    : [0] heartbeat  [1] last frame = detect  [2] FFT overrun
//           [3] telemetry frame dropped (UART too slow / busy)
// =============================================================================
module neo_doppler_top #(
  parameter logic [127:0] AES_KEY    = 128'h000102030405060708090a0b0c0d0e0f,
  parameter logic [63:0]  DEVICE_ID  = 64'h4E454F0000000001,
  parameter logic [31:0]  BOOT_ID    = 32'd0,
  // exposed so simulation can shorten the sample period
  parameter int unsigned  SAMPLE_PERIOD_CLKS = neo_pkg::CLK_HZ / neo_pkg::FS_HZ
) (
  input  logic       clk_50m,
  input  logic       rst_n_async,

  // ADC (MCP3201-class, SPI mode 0)
  output logic       adc_sclk,
  output logic       adc_cs_n,
  input  logic       adc_miso,

  // downlink
  output logic       uart_txd,

  output logic [3:0] led
);
  import neo_pkg::*;

  // -------------------------------------------------------------- reset -----
  logic rst_n;
  reset_sync u_rst (.clk(clk_50m), .arst_n(rst_n_async), .srst_n(rst_n));

  // -------------------------------------------------------------- ticks -----
  logic sample_tick, ms_tick;
  tick_gen #(.PERIOD(SAMPLE_PERIOD_CLKS)) u_tick_smp (.clk(clk_50m), .rst_n(rst_n), .tick(sample_tick));
  tick_gen #(.PERIOD(CLK_HZ / 1000))      u_tick_ms  (.clk(clk_50m), .rst_n(rst_n), .tick(ms_tick));

  logic [23:0] timestamp_ms;
  always_ff @(posedge clk_50m) begin
    if (!rst_n)       timestamp_ms <= '0;
    else if (ms_tick) timestamp_ms <= timestamp_ms + 1'b1;
  end

  // ---------------------------------------------------------------- ADC -----
  logic                  miso_s, adc_busy, smp_valid;
  logic [ADC_BITS-1:0]   smp_data;

  sync_2ff u_miso_sync (.clk(clk_50m), .rst_n(rst_n), .d_async(adc_miso), .q(miso_s));

  adc_spi_master u_adc (
    .clk(clk_50m), .rst_n(rst_n),
    .start(sample_tick), .busy(adc_busy),
    .sclk(adc_sclk), .cs_n(adc_cs_n), .miso(miso_s),
    .sample_valid(smp_valid), .sample_data(smp_data)
  );

  // ---------------------------------------------------------------- DSP -----
  logic        tlm_valid, tlm_detect, fft_overrun;
  logic [15:0] tlm_bin, tlm_frame_id;
  logic [31:0] tlm_vel, tlm_mag;

  doppler_dsp_chain u_dsp (
    .clk(clk_50m), .rst_n(rst_n),
    .sample_valid(smp_valid), .sample_data(smp_data),
    .tlm_valid(tlm_valid), .tlm_bin(tlm_bin),
    .tlm_velocity_mmps(tlm_vel), .tlm_mag(tlm_mag),
    .tlm_detect(tlm_detect), .tlm_frame_id(tlm_frame_id),
    .fft_overrun(fft_overrun)
  );

  // ------------------------------------------------------ secure downlink ----
  logic       byte_valid, byte_ready, frame_dropped, tx_busy;
  logic [7:0] byte_data;

  secure_tlm_tx u_tx (
    .clk(clk_50m), .rst_n(rst_n),
    .key(AES_KEY), .device_id(DEVICE_ID), .boot_id(BOOT_ID),
    .tlm_valid(tlm_valid), .tlm_bin(tlm_bin),
    .tlm_velocity_mmps(tlm_vel), .tlm_mag(tlm_mag),
    .tlm_timestamp_ms(timestamp_ms), .tlm_detect(tlm_detect),
    .tlm_frame_id(tlm_frame_id),
    .m_valid(byte_valid), .m_ready(byte_ready), .m_data(byte_data),
    .busy(tx_busy), .frame_dropped(frame_dropped)
  );

  uart_tx u_uart (
    .clk(clk_50m), .rst_n(rst_n),
    .s_valid(byte_valid), .s_ready(byte_ready), .s_data(byte_data),
    .txd(uart_txd)
  );

  // --------------------------------------------------------------- status ---
  logic detect_q;
  always_ff @(posedge clk_50m) begin
    if (!rst_n)         detect_q <= 1'b0;
    else if (tlm_valid) detect_q <= tlm_detect;
  end

  assign led[0] = timestamp_ms[9];       // ~1 Hz heartbeat
  assign led[1] = detect_q;
  assign led[2] = fft_overrun;
  assign led[3] = frame_dropped;

  logic unused_ok;
  assign unused_ok = &{1'b0, adc_busy, tx_busy};

endmodule
