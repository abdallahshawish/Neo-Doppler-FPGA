// =============================================================================
// Module  : window_mult
// Purpose : Multiplies each sample by the Hann window coefficient selected by
//           `idx` (driven by the FFT's load counter so window and FFT can never
//           lose alignment). Output = (sample * w) >>> 15, 1 clock latency.
// =============================================================================
module window_mult #(
  parameter int unsigned DATA_W = neo_pkg::DATA_W,
  parameter int unsigned LOG2N  = neo_pkg::FFT_LOG2
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      in_valid,
  input  logic signed [DATA_W-1:0]  in_data,
  input  logic [LOG2N-1:0]          idx,        // sample position in the frame
  output logic                      out_valid,
  output logic signed [DATA_W-1:0]  out_data
);
  logic [15:0]               win;
  logic signed [DATA_W+16:0] prod;     // signed(16) x unsigned(16) -> 33 bit

  window_rom u_rom (.addr(idx), .win(win));

  assign prod = in_data * $signed({1'b0, win});

  always_ff @(posedge clk) begin
    out_valid <= 1'b0;
    if (!rst_n) begin
      out_data <= '0;
    end else if (in_valid) begin
      out_data  <= prod >>> 15;
      out_valid <= 1'b1;
    end
  end
endmodule
