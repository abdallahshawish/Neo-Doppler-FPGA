// =============================================================================
// Testbench : tb_uart_loopback
// Checks    : uart_tx -> uart_rx loopback for a set of corner-case bytes,
//             valid/ready behaviour and absence of framing errors.
//             A fast baud (CLK_HZ/BAUD = 16 clocks) keeps simulation short.
// =============================================================================
`timescale 1ns/1ps
module tb_uart_loopback;
  localparam int CLK_HZ = 1_600_000;
  localparam int BAUD   = 100_000;           // 16 clocks per bit

  logic clk = 0, rst_n = 0;
  logic s_valid = 0, s_ready;
  logic [7:0] s_data;
  logic txd;
  logic m_valid, frame_err;
  logic [7:0] m_data;
  int errors = 0;

  always #5 clk = ~clk;

  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
    .clk(clk), .rst_n(rst_n), .s_valid(s_valid), .s_ready(s_ready),
    .s_data(s_data), .txd(txd));
  uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
    .clk(clk), .rst_n(rst_n), .rxd(txd), .m_valid(m_valid),
    .m_data(m_data), .frame_err(frame_err));

  byte unsigned sent_q[$];
  int rx_count = 0;

  // scoreboard
  always @(posedge clk) if (m_valid) begin
    byte unsigned exp_b;
    exp_b = sent_q.pop_front();
    rx_count++;
    if (m_data !== exp_b || frame_err) begin
      $display("[FAIL] rx %02h expected %02h frame_err=%b", m_data, exp_b, frame_err);
      errors++;
    end
  end

  task automatic send(input byte unsigned b);
    begin
      @(negedge clk);                        // drive away from the active edge
      s_data = b; s_valid = 1'b1;
      sent_q.push_back(b);
      do @(posedge clk); while (!s_ready);   // accepted when valid && ready at an edge
      @(negedge clk);
      s_valid = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);

    send(8'h00); send(8'hFF); send(8'h55); send(8'hAA);
    send(8'hA5); send(8'h5A); send(8'h01); send(8'h80);
    for (int i = 0; i < 32; i++) send(8'(i * 7 + 3));

    // wait for the last byte to arrive
    repeat (16 * 12) @(posedge clk);

    if (rx_count != 40) begin
      $display("[FAIL] received %0d bytes, expected 40", rx_count);
      errors++;
    end
    if (errors == 0) $display("TB_UART: ALL TESTS PASSED (%0d bytes)", rx_count);
    else             $display("TB_UART: %0d FAILURES", errors);
    $finish;
  end
endmodule
