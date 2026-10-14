// =============================================================================
// Module  : tick_gen
// Purpose : Periodic single-cycle strobe every PERIOD clock cycles.
//           Used for the ADC sample tick (FS_HZ) and the 1 ms timestamp tick.
// =============================================================================
module tick_gen #(
  parameter int unsigned PERIOD = 25_000
) (
  input  logic clk,
  input  logic rst_n,
  output logic tick
);
  localparam int unsigned CW = (PERIOD > 1) ? $clog2(PERIOD) : 1;
  logic [CW-1:0] cnt;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt  <= '0;
      tick <= 1'b0;
    end else if (cnt == CW'(PERIOD - 1)) begin
      cnt  <= '0;
      tick <= 1'b1;
    end else begin
      cnt  <= cnt + 1'b1;
      tick <= 1'b0;
    end
  end
endmodule
