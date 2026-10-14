// =============================================================================
// Module  : sync_2ff
// Purpose : Two-flop synchronizer for a single-bit asynchronous input
//           (e.g. UART RX pin, ADC MISO if sampled asynchronously).
// =============================================================================
module sync_2ff #(
  parameter logic RESET_VAL = 1'b0
) (
  input  logic clk,
  input  logic rst_n,
  input  logic d_async,
  output logic q
);
  (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
  logic [1:0] sh;

  always_ff @(posedge clk) begin
    if (!rst_n) sh <= {2{RESET_VAL}};
    else        sh <= {sh[0], d_async};
  end

  assign q = sh[1];
endmodule
