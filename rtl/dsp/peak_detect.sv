// =============================================================================
// Module  : peak_detect
// Purpose : Finds the strongest spectral line in the half-spectrum stream.
//           Magnitude estimate: |re| + |im|  (monotonic, multiplier-free).
//           Bins below MIN_BIN (DC and very-low-frequency drift) are ignored.
//           On the last bin, emits one result pulse with the winning bin,
//           its magnitude and a threshold-based `detect` decision.
// =============================================================================
module peak_detect #(
  parameter int unsigned LOG2N   = neo_pkg::FFT_LOG2,
  parameter int unsigned DW      = neo_pkg::DATA_W,
  parameter int unsigned MIN_BIN = neo_pkg::PEAK_MIN_BIN,
  parameter int unsigned THRESH  = neo_pkg::PEAK_THRESH
) (
  input  logic                    clk,
  input  logic                    rst_n,
  // spectrum stream
  input  logic                    in_valid,
  input  logic [LOG2N-1:0]        in_idx,
  input  logic signed [DW-1:0]    in_re,
  input  logic signed [DW-1:0]    in_im,
  input  logic                    in_last,
  // result (1-cycle pulse)
  output logic                    out_valid,
  output logic [LOG2N-1:0]        out_bin,
  output logic [DW+1:0]           out_mag,
  output logic                    out_detect
);
  localparam int unsigned MW = DW + 2;

  logic [DW:0]  abs_re, abs_im;
  logic [MW-1:0] mag;
  logic [MW-1:0] best_mag;
  logic [LOG2N-1:0] best_bin;
  logic better;
  logic [MW-1:0]    fin_mag;
  logic [LOG2N-1:0] fin_bin;

  always_comb begin
    abs_re = in_re[DW-1] ? (~{in_re[DW-1], in_re} + 1'b1) : {1'b0, in_re};
    abs_im = in_im[DW-1] ? (~{in_im[DW-1], in_im} + 1'b1) : {1'b0, in_im};
    mag    = MW'(abs_re) + MW'(abs_im);
    better = (in_idx >= LOG2N'(MIN_BIN)) && (mag > best_mag);
    fin_mag = better ? mag    : best_mag;
    fin_bin = better ? in_idx : best_bin;
  end

  always_ff @(posedge clk) begin
    out_valid <= 1'b0;
    if (!rst_n) begin
      best_mag   <= '0;
      best_bin   <= '0;
      out_bin    <= '0;
      out_mag    <= '0;
      out_detect <= 1'b0;
    end else if (in_valid) begin
      if (in_idx == '0) begin                 // new spectrum
        best_mag <= '0;
        best_bin <= '0;
      end else begin
        best_mag <= fin_mag;
        best_bin <= fin_bin;
      end
      if (in_last) begin
        out_bin    <= fin_bin;
        out_mag    <= fin_mag;
        out_detect <= (fin_mag >= MW'(THRESH));
        out_valid  <= 1'b1;
      end
    end
  end
endmodule
