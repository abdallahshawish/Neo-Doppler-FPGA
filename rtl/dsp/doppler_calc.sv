// =============================================================================
// Module  : doppler_calc
// Purpose : Converts the winning FFT bin to a radial speed:
//             f_d  = bin * fs / N
//             v    = f_d * c / (2 * f0)           [m/s]
//           Implemented as  v_mm/s = bin * VEL_MMPS_PER_BIN  (constant folded
//           in neo_pkg). Also stamps each result with a spectrum frame id.
// Note    : A single-channel CW sensor gives speed magnitude only; approach vs
//           recede needs an I/Q (quadrature) front-end.
// =============================================================================
module doppler_calc #(
  parameter int unsigned LOG2N = neo_pkg::FFT_LOG2,
  parameter int unsigned MW     = neo_pkg::DATA_W + 2
) (
  input  logic                clk,
  input  logic                rst_n,
  input  logic                in_valid,
  input  logic [LOG2N-1:0]    in_bin,
  input  logic [MW-1:0]       in_mag,
  input  logic                in_detect,

  output logic                out_valid,
  output logic [15:0]         out_bin,
  output logic [31:0]         out_velocity_mmps,
  output logic [31:0]         out_mag,
  output logic                out_detect,
  output logic [15:0]         out_frame_id
);
  localparam logic [63:0] VEL_K64 = neo_pkg::VEL_MMPS_PER_BIN;
  localparam logic [31:0] VEL_K   = VEL_K64[31:0];

  always_ff @(posedge clk) begin
    out_valid <= 1'b0;
    if (!rst_n) begin
      out_bin           <= '0;
      out_velocity_mmps <= '0;
      out_mag           <= '0;
      out_detect        <= 1'b0;
      out_frame_id      <= '0;
    end else if (in_valid) begin
      out_bin           <= 16'(in_bin);
      out_velocity_mmps <= VEL_K * 32'(in_bin);
      out_mag           <= 32'(in_mag);
      out_detect        <= in_detect;
      out_frame_id      <= out_frame_id + 1'b1;
      out_valid         <= 1'b1;
    end
  end
endmodule
