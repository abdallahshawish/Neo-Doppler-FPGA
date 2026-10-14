// =============================================================================
// Module  : fft_radix2
// Purpose : Area-efficient in-place radix-2 DIT FFT, N = 2^LOG2N points,
//           one butterfly engine + one block RAM (re/im packed).
//
//   Input  : real samples, signed Q1.15, one per `in_valid` strobe, written
//            into RAM at bit-reversed addresses (so no reorder stage is needed).
//   Compute: LOG2N stages x N/2 butterflies, 6 clocks per butterfly
//            (RA,RB,RC = read; MUL = 4 multipliers; WA,WB = write-back).
//            Each stage scales by 1/2, so  X_out = FFT(x) / N  (no overflow).
//   Output : bins 0 .. N/2-1 streamed once, `out_last` flags the final bin.
//
// Timing  : N=256 -> 1024 butterflies x 6 = 6144 clocks (~123 us @ 50 MHz).
//           Samples arriving while busy set the sticky `overrun` flag.
// =============================================================================
module fft_radix2 #(
  parameter int unsigned LOG2N = neo_pkg::FFT_LOG2,
  parameter int unsigned DW    = neo_pkg::DATA_W
) (
  input  logic                    clk,
  input  logic                    rst_n,

  // sample input
  input  logic                    in_valid,
  input  logic signed [DW-1:0]    in_re,
  output logic [LOG2N-1:0]        load_idx,     // index the next sample will take

  // status
  output logic                    busy,
  output logic                    overrun,      // sticky

  // half-spectrum output stream
  output logic                    out_valid,
  output logic [LOG2N-1:0]        out_idx,
  output logic signed [DW-1:0]    out_re,
  output logic signed [DW-1:0]    out_im,
  output logic                    out_last
);
  localparam int unsigned N  = 1 << LOG2N;
  localparam int unsigned SW = $clog2(LOG2N + 1);       // stage counter width

  typedef enum logic [3:0] {
    ST_LOAD, ST_RA, ST_RB, ST_RC, ST_MUL, ST_WA, ST_WB, ST_OUT_REQ, ST_OUT_EMIT
  } state_t;
  state_t state;

  // ---------------------------------------------------------------- helpers --
  function automatic logic [LOG2N-1:0] bitrev(input logic [LOG2N-1:0] x);
    for (int i = 0; i < LOG2N; i++) bitrev[i] = x[LOG2N-1-i];
  endfunction

  localparam logic signed [DW+1:0] MAXV =  (1 <<< (DW-1)) - 1;
  localparam logic signed [DW+1:0] MINV = -(1 <<< (DW-1));
  function automatic logic signed [DW-1:0] sat(input logic signed [DW+1:0] v);
    if (v > MAXV)      sat = MAXV[DW-1:0];
    else if (v < MINV) sat = MINV[DW-1:0];
    else               sat = v[DW-1:0];
  endfunction

  // --------------------------------------------------------------- counters --
  logic [LOG2N-2:0] bf_k;            // butterfly index within a stage
  logic [SW-1:0]    stage;           // 1 .. LOG2N
  logic [LOG2N-2:0] out_cnt;

  // ------------------------------------------------------ address generation --
  logic [LOG2N-1:0] k_ext, sh_mask, j, i0, i1, tw_wide;
  logic [SW-1:0]    sh;
  logic [LOG2N-2:0] tw_idx;

  always_comb begin
    k_ext   = {1'b0, bf_k};
    sh      = stage - 1'b1;
    sh_mask = (LOG2N'(1) << sh) - 1'b1;
    j       = k_ext & sh_mask;
    i0      = ((k_ext >> sh) << stage) | j;
    i1      = i0 | (LOG2N'(1) << sh);
    tw_wide = j << (LOG2N - stage);
    tw_idx  = tw_wide[LOG2N-2:0];
  end

  // ------------------------------------------------------------------- RAM ---
  logic                 ram_we;
  logic [LOG2N-1:0]     ram_waddr, ram_raddr;
  logic [2*DW-1:0]      ram_wdata, ram_rdata;

  sdp_ram #(.WIDTH(2*DW), .DEPTH(N)) u_ram (
    .clk(clk), .we(ram_we), .waddr(ram_waddr), .wdata(ram_wdata),
    .raddr(ram_raddr), .rdata(ram_rdata)
  );

  // ------------------------------------------------------------- twiddles ---
  logic signed [15:0] rom_cos, rom_sin;
  twiddle_rom u_tw (.addr(tw_idx), .tw_cos(rom_cos), .tw_sin(rom_sin));

  // -------------------------------------------------------------- datapath ---
  logic signed [DW-1:0] a_re, a_im, b_re, b_im;
  logic signed [15:0]   w_c, w_s;
  logic signed [2*DW-1:0] p_cbr, p_sbi, p_cbi, p_sbr;

  logic signed [2*DW+1:0] sum_r, sum_i;      // 34-bit
  logic signed [DW+1:0]   tr, ti, s0r, s0i, s1r, s1i;
  logic signed [DW-1:0]   x0_re, x0_im, x1_re, x1_im;

  // W = c - j*s ;  t = W*b = (c*br + s*bi) + j(c*bi - s*br)
  always_comb begin
    sum_r = p_cbr + p_sbi;
    sum_i = p_cbi - p_sbr;
    tr    = sum_r >>> 15;
    ti    = sum_i >>> 15;
    s0r   = a_re + tr;
    s0i   = a_im + ti;
    s1r   = a_re - tr;
    s1i   = a_im - ti;
    x0_re = sat(s0r >>> 1);
    x0_im = sat(s0i >>> 1);
    x1_re = sat(s1r >>> 1);
    x1_im = sat(s1i >>> 1);
  end

  // ------------------------------------------------------ memory port muxing --
  always_comb begin
    ram_we    = 1'b0;
    ram_waddr = '0;
    ram_wdata = '0;
    ram_raddr = {1'b0, out_cnt};
    case (state)
      ST_LOAD: begin
        ram_we    = in_valid;
        ram_waddr = bitrev(load_idx);
        ram_wdata = {in_re, {DW{1'b0}}};
      end
      ST_RA:  ram_raddr = i0;
      ST_RB:  ram_raddr = i1;
      ST_WA: begin
        ram_we    = 1'b1;
        ram_waddr = i0;
        ram_wdata = {x0_re, x0_im};
      end
      ST_WB: begin
        ram_we    = 1'b1;
        ram_waddr = i1;
        ram_wdata = {x1_re, x1_im};
      end
      default: ;
    endcase
  end

  // ----------------------------------------------------------------- FSM ----
  assign busy = (state != ST_LOAD);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state    <= ST_LOAD;
      load_idx <= '0;
      bf_k     <= '0;
      stage    <= SW'(1);
      out_cnt  <= '0;
      overrun  <= 1'b0;
      a_re <= '0; a_im <= '0; b_re <= '0; b_im <= '0;
      w_c  <= '0; w_s  <= '0;
      p_cbr <= '0; p_sbi <= '0; p_cbi <= '0; p_sbr <= '0;
    end else begin
      if (in_valid && state != ST_LOAD) overrun <= 1'b1;

      case (state)
        ST_LOAD: begin
          if (in_valid) begin
            if (load_idx == LOG2N'(N - 1)) begin
              load_idx <= '0;
              bf_k     <= '0;
              stage    <= SW'(1);
              state    <= ST_RA;
            end else begin
              load_idx <= load_idx + 1'b1;
            end
          end
        end

        ST_RA: state <= ST_RB;

        ST_RB: begin                       // RAM now presents x[i0]
          a_re  <= ram_rdata[2*DW-1:DW];
          a_im  <= ram_rdata[DW-1:0];
          state <= ST_RC;
        end

        ST_RC: begin                       // RAM now presents x[i1]
          b_re  <= ram_rdata[2*DW-1:DW];
          b_im  <= ram_rdata[DW-1:0];
          w_c   <= rom_cos;
          w_s   <= rom_sin;
          state <= ST_MUL;
        end

        ST_MUL: begin
          p_cbr <= w_c * b_re;
          p_sbi <= w_s * b_im;
          p_cbi <= w_c * b_im;
          p_sbr <= w_s * b_re;
          state <= ST_WA;
        end

        ST_WA: state <= ST_WB;

        ST_WB: begin
          if (bf_k == (LOG2N-1)'(N/2 - 1)) begin
            bf_k <= '0;
            if (stage == SW'(LOG2N)) begin
              out_cnt <= '0;
              state   <= ST_OUT_REQ;
            end else begin
              stage <= stage + 1'b1;
              state <= ST_RA;
            end
          end else begin
            bf_k  <= bf_k + 1'b1;
            state <= ST_RA;
          end
        end

        ST_OUT_REQ: state <= ST_OUT_EMIT;

        ST_OUT_EMIT: begin
          if (out_cnt == (LOG2N-1)'(N/2 - 1)) begin
            state <= ST_LOAD;
          end else begin
            out_cnt <= out_cnt + 1'b1;
            state   <= ST_OUT_REQ;
          end
        end

        default: state <= ST_LOAD;
      endcase
    end
  end

  // Output stream (combinational from RAM read register)
  assign out_valid = (state == ST_OUT_EMIT);
  assign out_idx   = {1'b0, out_cnt};
  assign out_re    = ram_rdata[2*DW-1:DW];
  assign out_im    = ram_rdata[DW-1:0];
  assign out_last  = out_valid && (out_cnt == (LOG2N-1)'(N/2 - 1));

endmodule
