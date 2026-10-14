// =============================================================================
// Module  : dc_blocker
// Purpose : Converts unsigned ADC codes to signed Q1.15 samples and removes the
//           DC offset with a first-order tracking filter:
//             avg += (x - avg) / 2^SHIFT ;   y = x - avg
//           The tracker is primed with the first sample to avoid a start-up
//           transient. Output is left-aligned to use the full DATA_W range.
// Latency : 1 clock.
// =============================================================================
module dc_blocker #(
  parameter int unsigned IN_BITS  = neo_pkg::ADC_BITS,
  parameter int unsigned DATA_W   = neo_pkg::DATA_W,
  parameter int unsigned SHIFT    = neo_pkg::DC_SHIFT
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      in_valid,
  input  logic [IN_BITS-1:0]        in_data,    // unsigned ADC code
  output logic                      out_valid,
  output logic signed [DATA_W-1:0]  out_data
);
  localparam int unsigned XW        = IN_BITS + 1;              // centered sample
  localparam int unsigned AW        = XW + SHIFT;               // tracker width
  localparam int unsigned OUT_SHIFT = DATA_W - XW;              // left align

  logic signed [XW-1:0] x;
  logic signed [AW-1:0] avg_fx;
  logic                 primed;
  logic signed [XW-1:0] avg_int;
  logic signed [XW-1:0] y;

  // x = code - mid-scale  (range -2^(B-1) .. 2^(B-1)-1, 13-bit signed container)
  assign x       = $signed({1'b0, in_data}) - $signed(XW'(1 << (IN_BITS - 1)));
  assign avg_int = avg_fx >>> SHIFT;
  assign y       = x - avg_int;

  always_ff @(posedge clk) begin
    out_valid <= 1'b0;
    if (!rst_n) begin
      avg_fx   <= '0;
      primed   <= 1'b0;
      out_data <= '0;
    end else if (in_valid) begin
      if (!primed) begin
        avg_fx <= AW'(x) <<< SHIFT;
        primed <= 1'b1;
      end else begin
        avg_fx <= avg_fx + AW'(x) - AW'(avg_int);
      end
      out_data  <= DATA_W'(y) <<< OUT_SHIFT;
      out_valid <= 1'b1;
    end
  end
endmodule
