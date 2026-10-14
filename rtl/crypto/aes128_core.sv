// =============================================================================
// Module  : aes128_core
// Purpose : AES-128 block ENCRYPTION (FIPS-197), iterative architecture:
//           one round per clock, on-the-fly key expansion (no key RAM).
//           Latency 11 clocks (1 initial AddRoundKey + 10 rounds).
//           Area is small enough for low-cost FPGAs; throughput ~ 128 bit /
//           11 clk  (about 580 Mbit/s @ 50 MHz) - far above the telemetry need.
//
// Use      : the telemetry link runs it in CTR mode (see secure_tlm_tx), which
//           only needs the forward cipher - decryption hardware is not needed.
// Verified : tb/tb_aes128_core.sv against FIPS-197 Appendix B and C.1 vectors.
// =============================================================================
module aes128_core (
  input  logic         clk,
  input  logic         rst_n,

  input  logic         start,          // 1-cycle strobe, ignored while busy
  input  logic [127:0] key,            // sampled on `start`
  input  logic [127:0] block_in,       // sampled on `start`

  output logic         busy,
  output logic         done,           // 1-cycle strobe, block_out valid
  output logic [127:0] block_out       // held until next operation completes
);
  import aes_pkg::*;

  logic [127:0] st, rk, nrk;
  logic [3:0]   round;

  always_comb nrk = next_round_key(rk, round);

  always_ff @(posedge clk) begin
    done <= 1'b0;
    if (!rst_n) begin
      busy      <= 1'b0;
      st        <= '0;
      rk        <= '0;
      round     <= 4'd1;
      block_out <= '0;
    end else if (!busy) begin
      if (start) begin
        st    <= block_in ^ key;          // initial AddRoundKey
        rk    <= key;
        round <= 4'd1;
        busy  <= 1'b1;
      end
    end else begin
      if (round == 4'd10) begin           // final round: no MixColumns
        block_out <= shift_rows(sub_bytes(st)) ^ nrk;
        done      <= 1'b1;
        busy      <= 1'b0;
      end else begin
        st    <= mix_columns(shift_rows(sub_bytes(st))) ^ nrk;
        rk    <= nrk;
        round <= round + 1'b1;
      end
    end
  end
endmodule
