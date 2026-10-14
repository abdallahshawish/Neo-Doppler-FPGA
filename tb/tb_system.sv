// =============================================================================
// Testbench : tb_system   (end-to-end)
// Flow      : behavioural MCP3201 ADC model (Doppler tone) -> neo_doppler_top
//             -> UART -> uart_rx -> frame parser -> CRC check -> AES-CTR
//             decryption (reusing the RTL AES core) -> field check.
// Speed     : SAMPLE_PERIOD_CLKS is shortened to 8000 clocks; one frame still
//             needs 256 conversions (~2 M clocks), so expect a few minutes in
//             iverilog and seconds in ModelSim/Questa/Vivado xsim.
// =============================================================================
`timescale 1ns/1ps
module tb_system;
  import neo_pkg::*;
  import crc_pkg::*;

  localparam int TONE_BIN = 40;
  localparam int AMP      = 1000;

  localparam logic [127:0] KEY = 128'h000102030405060708090a0b0c0d0e0f;
  localparam logic [63:0]  DEV = 64'h4E454F0000000001;
  localparam logic [31:0]  BOOT = 32'h00000007;

  logic clk = 0, rst_n = 0;
  always #10 clk = ~clk;

  logic adc_sclk, adc_cs_n, adc_miso, uart_txd;
  logic [3:0] led;
  int errors = 0;

  neo_doppler_top #(.AES_KEY(KEY), .DEVICE_ID(DEV), .BOOT_ID(BOOT),
                    .SAMPLE_PERIOD_CLKS(8000)) dut (
    .clk_50m(clk), .rst_n_async(rst_n),
    .adc_sclk(adc_sclk), .adc_cs_n(adc_cs_n), .adc_miso(adc_miso),
    .uart_txd(uart_txd), .led(led)
  );

  // -------------------------------------------------- MCP3201 behavioural model
  int          conv_n = 0;
  logic [11:0] code;
  int          k;

  function automatic logic [11:0] gen_code(input int n);
    real v;
    begin
      v = 2048.0 + AMP * $sin(2.0 * 3.14159265358979 * TONE_BIN * n / FFT_N);
      gen_code = 12'($rtoi(v + 0.5));
    end
  endfunction

  initial adc_miso = 1'b0;
  always @(negedge adc_cs_n) begin
    code    = gen_code(conv_n);
    conv_n  = conv_n + 1;
    k       = 0;
    adc_miso <= 1'b0;
  end
  always @(posedge adc_sclk) begin
    k = k + 1;                         // k-th rising edge just happened
    // value to present for rising edge k+1: 2 lead bits (0), then B11..B0
    if (k + 1 <= ADC_LEAD_CLKS)                 adc_miso <= 1'b0;
    else if (k + 1 <= ADC_LEAD_CLKS + ADC_BITS) adc_miso <= code[ADC_BITS - 1 - (k + 1 - ADC_LEAD_CLKS - 1)];
    else                                        adc_miso <= 1'b0;
  end

  // ------------------------------------------------------- ground-side UART RX
  logic       rx_valid, rx_ferr;
  logic [7:0] rx_byte;
  uart_rx u_gs_rx (.clk(clk), .rst_n(rst_n), .rxd(uart_txd),
                   .m_valid(rx_valid), .m_data(rx_byte), .frame_err(rx_ferr));

  // ---------------------------------------- ground-side keystream (RTL AES core)
  logic         ks_start = 0, ks_busy, ks_done;
  logic [127:0] ks_block, ks_out;
  aes128_core u_gs_aes (.clk(clk), .rst_n(rst_n), .start(ks_start), .key(KEY),
                        .block_in(ks_block), .busy(ks_busy), .done(ks_done),
                        .block_out(ks_out));

  // ------------------------------------------------------------ frame parser
  logic [7:0] fr [0:FRAME_BYTES-1];
  int         fr_n = 0;
  bit         frame_ready = 0;

  always @(posedge clk) if (rx_valid) begin
    if (rx_ferr) begin $display("[FAIL] UART framing error"); errors++; end
    if (fr_n == 0 && rx_byte != SYNC0) begin
      // hunt for sync
    end else if (fr_n == 1 && rx_byte != SYNC1) begin
      fr_n <= 0;
    end else begin
      fr[fr_n] <= rx_byte;
      if (fr_n == FRAME_BYTES - 1) begin fr_n <= 0; frame_ready <= 1; end
      else fr_n <= fr_n + 1;
    end
  end

  // ------------------------------------------------------------------- checks
  initial begin
    repeat (6) @(posedge clk);
    rst_n = 1;

    wait (frame_ready);
    @(posedge clk);

    // CRC
    begin
      logic [15:0] c, rx_crc;
      c = CRC16_INIT;
      for (int i = 2; i < FRAME_BYTES - 2; i++) c = crc16_update(c, fr[i]);
      rx_crc = {fr[FRAME_BYTES-2], fr[FRAME_BYTES-1]};
      if (c !== rx_crc) begin $display("[FAIL] CRC: computed %04h, received %04h", c, rx_crc); errors++; end
      else $display("[PASS] CRC-16 valid (%04h)", c);
    end

    // nonce fields
    begin
      logic [31:0] boot_rx, ctr_rx;
      boot_rx = {fr[2], fr[3], fr[4], fr[5]};
      ctr_rx  = {fr[6], fr[7], fr[8], fr[9]};
      if (boot_rx !== BOOT || ctr_rx !== 32'd0) begin
        $display("[FAIL] nonce boot=%08h ctr=%08h", boot_rx, ctr_rx); errors++;
      end else $display("[PASS] nonce fields boot_id=%08h frame_ctr=%08h", boot_rx, ctr_rx);
      ks_block = {DEV, boot_rx, ctr_rx};
    end

    // decrypt (CTR): plaintext = cipher XOR AES_K(nonce_block)
    @(negedge clk); ks_start = 1;
    @(negedge clk); ks_start = 0;
    wait (ks_done);
    @(posedge clk);
    begin
      logic [127:0] cipher, pt;
      logic [15:0]  p_bin;
      logic [31:0]  p_vel, p_mag;
      logic [23:0]  p_ts;
      logic [7:0]   p_flags;
      for (int i = 0; i < 16; i++) cipher[127 - 8*i -: 8] = fr[10 + i];
      pt = cipher ^ ks_out;
      {p_bin, p_vel, p_mag, p_ts, p_flags} = pt[127:16];
      $display("       telemetry: bin=%0d  v=%0d mm/s  mag=%0d  t=%0d ms  detect=%0b  frame_id=%0d",
               p_bin, p_vel, p_mag, p_ts, p_flags[0], pt[15:0]);
      if (p_bin !== TONE_BIN[15:0])          begin $display("[FAIL] bin %0d != %0d", p_bin, TONE_BIN); errors++; end
      else if (p_vel !== TONE_BIN * VEL_MMPS_PER_BIN[31:0]) begin $display("[FAIL] velocity %0d", p_vel); errors++; end
      else if (!p_flags[0])                  begin $display("[FAIL] detect flag not set"); errors++; end
      else $display("[PASS] decrypted telemetry correct (tone bin %0d detected)", TONE_BIN);
    end

    if (led[2]) begin $display("[FAIL] FFT overrun LED set"); errors++; end

    if (errors == 0) $display("TB_SYSTEM: ALL TESTS PASSED");
    else             $display("TB_SYSTEM: %0d FAILURES", errors);
    $finish;
  end

  // watchdog
  initial begin
    #(64'd400_000_000);   // 400 ms sim time  (= 20 M clocks)
    $display("TB_SYSTEM: TIMEOUT");
    $finish;
  end
endmodule
