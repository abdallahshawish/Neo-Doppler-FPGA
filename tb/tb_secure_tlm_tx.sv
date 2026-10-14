// =============================================================================
// Testbench : tb_secure_tlm_tx
// Checks    : the 28-byte encrypted frame produced by secure_tlm_tx is
//             byte-identical to the golden frame from scripts/ref_model.py
//             (AES-128-CTR + CRC-16). Also checks frame counter increment on
//             a second frame (nonce must change) and the dropped-frame flag.
// =============================================================================
`timescale 1ns/1ps
module tb_secure_tlm_tx;
  `include "golden_frame.svh"

  logic clk = 0, rst_n = 0;
  always #10 clk = ~clk;

  logic         tlm_valid = 0;
  logic         m_valid, m_ready = 1;
  logic [7:0]   m_data;
  logic         busy, frame_dropped;
  int errors = 0;

  secure_tlm_tx dut (
    .clk(clk), .rst_n(rst_n),
    .key(G_KEY), .device_id(G_DEVICE_ID), .boot_id(G_BOOT_ID),
    .tlm_valid(tlm_valid), .tlm_bin(G_BIN),
    .tlm_velocity_mmps(G_VEL_MMPS), .tlm_mag(G_MAG),
    .tlm_timestamp_ms(G_TS_MS), .tlm_detect(G_DETECT),
    .tlm_frame_id(G_FRAME_ID),
    .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
    .busy(busy), .frame_dropped(frame_dropped)
  );

  logic [7:0] rx [0:27];
  int rx_n;

  // random back-pressure: the sink accepts a byte ~75 % of the clocks
  always @(negedge clk) m_ready <= (($urandom % 4) != 0);

  // collect bytes
  always @(posedge clk) begin
    if (m_valid && m_ready) begin
      rx[rx_n] <= m_data;
      rx_n     <= rx_n + 1;
    end
  end

  task automatic fire_record;
    begin
      @(negedge clk); tlm_valid = 1;
      @(negedge clk); tlm_valid = 0;
    end
  endtask

  task automatic wait_frame;
    int t;
    begin
      t = 0;
      while (rx_n < 28 && t < 5000) begin @(posedge clk); t++; end
      repeat (4) @(posedge clk);
    end
  endtask

  initial begin
    rx_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (3) @(posedge clk);

    // ---- frame 0 : must match the golden frame ---------------------------------
    fire_record();
    wait_frame();
    begin
      logic [223:0] got;
      for (int i = 0; i < 28; i++) got[223 - 8*i -: 8] = rx[i];
      if (got !== G_FRAME) begin
        $display("[FAIL] frame mismatch\n  got      %056h\n  expected %056h", got, G_FRAME);
        errors++;
      end else
        $display("[PASS] frame 0 matches golden vector: %056h", got);
    end

    // ---- frame 1 : counter must increment, ciphertext must change ---------------
    rx_n = 0;
    fire_record();
    wait_frame();
    if (rx[9] !== 8'h01) begin
      $display("[FAIL] frame counter byte = %02h, expected 01", rx[9]);
      errors++;
    end else
      $display("[PASS] frame 1 carries incremented counter");
    if (rx[10] === G_FRAME[143:136] && rx[11] === G_FRAME[135:128] &&
        rx[12] === G_FRAME[127:120] && rx[13] === G_FRAME[119:112]) begin
      $display("[FAIL] ciphertext did not change between frames (nonce reuse!)");
      errors++;
    end else
      $display("[PASS] ciphertext differs between frames");

    // ---- back-to-back record while busy must raise frame_dropped ---------------
    rx_n = 0;
    fire_record();
    repeat (20) @(posedge clk);
    fire_record();                              // arrives while still transmitting
    wait_frame();
    if (!frame_dropped) begin
      $display("[FAIL] frame_dropped not set");
      errors++;
    end else
      $display("[PASS] frame_dropped flagged for overlapping record");

    if (errors == 0) $display("TB_SECURE_TLM_TX: ALL TESTS PASSED");
    else             $display("TB_SECURE_TLM_TX: %0d FAILURES", errors);
    $finish;
  end
endmodule
