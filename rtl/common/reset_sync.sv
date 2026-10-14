// =============================================================================
// Module  : reset_sync
// Purpose : Asynchronous-assert / synchronous-de-assert reset synchronizer.
//           Prevents metastability on reset release and guarantees that every
//           flop in the clock domain leaves reset on the same clock edge.
// =============================================================================
module reset_sync #(
  parameter int unsigned STAGES = 2
) (
  input  logic clk,
  input  logic arst_n,   // asynchronous, active-low (board button / PLL lock)
  output logic srst_n    // synchronized, active-low
);
  (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
  logic [STAGES-1:0] sh;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) sh <= '0;
    else         sh <= {sh[STAGES-2:0], 1'b1};
  end

  assign srst_n = sh[STAGES-1];
endmodule
