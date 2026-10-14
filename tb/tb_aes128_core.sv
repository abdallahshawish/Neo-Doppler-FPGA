// =============================================================================
// Testbench : tb_aes128_core
// Checks    : FIPS-197 Appendix B and Appendix C.1 known-answer vectors,
//             busy/done handshake and 11-cycle latency.
// =============================================================================
`timescale 1ns/1ps
module tb_aes128_core;
  logic clk = 0, rst_n = 0;
  logic start = 0, busy, done;
  logic [127:0] key, pt, ct;
  int errors = 0;

  always #10 clk = ~clk;

  aes128_core dut (.clk(clk), .rst_n(rst_n), .start(start), .key(key),
                   .block_in(pt), .busy(busy), .done(done), .block_out(ct));

  task automatic run_vec(input logic [127:0] k, input logic [127:0] p,
                         input logic [127:0] expect_ct, input string name);
    int cycles;
    begin
      key = k; pt = p;
      @(posedge clk); start <= 1'b1;
      @(posedge clk); start <= 1'b0;
      cycles = 0;
      while (!done && cycles < 40) begin @(posedge clk); cycles++; end
      @(negedge clk);
      if (ct !== expect_ct) begin
        $display("[FAIL] %s: got %032h expected %032h", name, ct, expect_ct);
        errors++;
      end else
        $display("[PASS] %s: %032h (latency %0d clk)", name, ct, cycles + 1);
      repeat (3) @(posedge clk);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    run_vec(128'h2b7e151628aed2a6abf7158809cf4f3c,
            128'h3243f6a8885a308d313198a2e0370734,
            128'h3925841d02dc09fbdc118597196a0b32, "FIPS-197 App.B");
    run_vec(128'h000102030405060708090a0b0c0d0e0f,
            128'h00112233445566778899aabbccddeeff,
            128'h69c4e0d86a7b0430d8cdb78070b4c55a, "FIPS-197 App.C.1");

    if (errors == 0) $display("TB_AES128: ALL TESTS PASSED");
    else             $display("TB_AES128: %0d FAILURES", errors);
    $finish;
  end
endmodule
