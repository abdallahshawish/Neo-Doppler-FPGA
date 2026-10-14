// =============================================================================
// Testbench : tb_dsp_chain
// Checks    : full DSP pipeline (DC removal, window, FFT, peak, velocity) with
//             synthetic ADC codes: a bin-centred tone must be detected at the
//             right bin and speed; a flat (no-signal) frame must not trigger.
//             Expected values match scripts/ref_model.py (VEL_MMPS_PER_BIN=111).
// =============================================================================
`timescale 1ns/1ps
module tb_dsp_chain;
  import neo_pkg::*;

  logic clk = 0, rst_n = 0;
  always #10 clk = ~clk;

  logic                 sample_valid = 0;
  logic [ADC_BITS-1:0]  sample_data  = '0;
  logic                 tlm_valid, tlm_detect, fft_overrun;
  logic [15:0]          tlm_bin, tlm_frame_id;
  logic [31:0]          tlm_vel, tlm_mag;
  int errors = 0;

  doppler_dsp_chain dut (
    .clk(clk), .rst_n(rst_n),
    .sample_valid(sample_valid), .sample_data(sample_data),
    .tlm_valid(tlm_valid), .tlm_bin(tlm_bin),
    .tlm_velocity_mmps(tlm_vel), .tlm_mag(tlm_mag),
    .tlm_detect(tlm_detect), .tlm_frame_id(tlm_frame_id),
    .fft_overrun(fft_overrun)
  );

  // capture the telemetry pulse
  logic        got_tlm;
  logic [15:0] c_bin;
  logic [31:0] c_vel, c_mag;
  logic        c_det;
  always @(posedge clk) if (tlm_valid) begin
    got_tlm <= 1'b1; c_bin <= tlm_bin; c_vel <= tlm_vel;
    c_mag <= tlm_mag; c_det <= tlm_detect;
  end

  // feed one frame; tone_bin < 0 => constant (no signal)
  task automatic run_frame(input int tone_bin, input int amp);
    real v;
    int  code;
    begin
      got_tlm = 1'b0;
      for (int n = 0; n < FFT_N; n++) begin
        if (tone_bin < 0) code = 2048;
        else begin
          v    = 2048.0 + amp * $sin(2.0 * 3.14159265358979 * tone_bin * n / FFT_N);
          code = $rtoi(v + 0.5);
        end
        @(negedge clk);
        sample_data  = code[ADC_BITS-1:0];
        sample_valid = 1'b1;
        @(negedge clk);
        sample_valid = 1'b0;
        repeat (10) @(negedge clk);          // inter-sample gap (> pipeline depth)
      end
      begin : wait_result
        int t = 0;
        while (!got_tlm && t < 20000) begin @(posedge clk); t++; end
      end
      repeat (5) @(posedge clk);
    end
  endtask

  task automatic expect_tone(input int tone_bin);
    begin
      run_frame(tone_bin, 1000);
      if (!got_tlm)                       begin $display("[FAIL] no telemetry for tone %0d", tone_bin); errors++; end
      else if (c_bin !== tone_bin[15:0])  begin $display("[FAIL] tone %0d -> bin %0d", tone_bin, c_bin); errors++; end
      else if (c_vel !== tone_bin * 111)  begin $display("[FAIL] tone %0d -> v=%0d mm/s", tone_bin, c_vel); errors++; end
      else if (!c_det)                    begin $display("[FAIL] tone %0d not detected (mag %0d)", tone_bin, c_mag); errors++; end
      else $display("[PASS] tone bin %0d -> bin %0d, v = %0d mm/s, mag %0d, detect %0b",
                    tone_bin, c_bin, c_vel, c_mag, c_det);
    end
  endtask

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    expect_tone(40);
    expect_tone(17);

    run_frame(-1, 0);
    if (!got_tlm || c_det !== 1'b0) begin
      $display("[FAIL] flat frame produced detect=%0b", c_det); errors++;
    end else $display("[PASS] flat frame -> no detection");

    if (fft_overrun) begin $display("[FAIL] FFT overrun flagged"); errors++; end

    if (errors == 0) $display("TB_DSP_CHAIN: ALL TESTS PASSED");
    else             $display("TB_DSP_CHAIN: %0d FAILURES", errors);
    $finish;
  end
endmodule
