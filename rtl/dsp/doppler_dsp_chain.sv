// =============================================================================
// Module  : doppler_dsp_chain
// Purpose : Complete Doppler signal-processing pipeline:
//             ADC code -> DC removal -> Hann window -> 256-pt FFT
//                      -> peak search -> velocity conversion -> telemetry
//           One telemetry record is produced per FFT frame (N samples).
// =============================================================================
module doppler_dsp_chain (
  input  logic                           clk,
  input  logic                           rst_n,

  input  logic                           sample_valid,
  input  logic [neo_pkg::ADC_BITS-1:0]   sample_data,

  output logic                           tlm_valid,
  output logic [15:0]                    tlm_bin,
  output logic [31:0]                    tlm_velocity_mmps,
  output logic [31:0]                    tlm_mag,
  output logic                           tlm_detect,
  output logic [15:0]                    tlm_frame_id,

  output logic                           fft_overrun
);
  import neo_pkg::*;

  // DC removal
  logic                       dc_valid;
  logic signed [DATA_W-1:0]   dc_data;

  dc_blocker u_dc (
    .clk(clk), .rst_n(rst_n),
    .in_valid(sample_valid), .in_data(sample_data),
    .out_valid(dc_valid), .out_data(dc_data)
  );

  // Windowing (address tied to the FFT load counter)
  logic                       win_valid;
  logic signed [DATA_W-1:0]   win_data;
  logic [FFT_LOG2-1:0]        fft_load_idx;

  window_mult u_win (
    .clk(clk), .rst_n(rst_n),
    .in_valid(dc_valid), .in_data(dc_data), .idx(fft_load_idx),
    .out_valid(win_valid), .out_data(win_data)
  );

  // FFT
  logic                       fft_busy;
  logic                       sp_valid, sp_last;
  logic [FFT_LOG2-1:0]        sp_idx;
  logic signed [DATA_W-1:0]   sp_re, sp_im;

  fft_radix2 u_fft (
    .clk(clk), .rst_n(rst_n),
    .in_valid(win_valid), .in_re(win_data), .load_idx(fft_load_idx),
    .busy(fft_busy), .overrun(fft_overrun),
    .out_valid(sp_valid), .out_idx(sp_idx), .out_re(sp_re), .out_im(sp_im),
    .out_last(sp_last)
  );

  // Peak search
  logic                       pk_valid, pk_detect;
  logic [FFT_LOG2-1:0]        pk_bin;
  logic [DATA_W+1:0]          pk_mag;

  peak_detect u_peak (
    .clk(clk), .rst_n(rst_n),
    .in_valid(sp_valid), .in_idx(sp_idx), .in_re(sp_re), .in_im(sp_im),
    .in_last(sp_last),
    .out_valid(pk_valid), .out_bin(pk_bin), .out_mag(pk_mag),
    .out_detect(pk_detect)
  );

  // Physical units
  doppler_calc u_calc (
    .clk(clk), .rst_n(rst_n),
    .in_valid(pk_valid), .in_bin(pk_bin), .in_mag(pk_mag), .in_detect(pk_detect),
    .out_valid(tlm_valid), .out_bin(tlm_bin),
    .out_velocity_mmps(tlm_velocity_mmps), .out_mag(tlm_mag),
    .out_detect(tlm_detect), .out_frame_id(tlm_frame_id)
  );

  // fft_busy kept for debug / future flow-control
  logic unused_ok;
  assign unused_ok = &{1'b0, fft_busy};

endmodule
