// =============================================================================
// Module  : secure_tlm_tx
// Purpose : Turns a telemetry record into an encrypted, CRC-protected frame
//           and streams it byte-by-byte to a UART (or any valid/ready sink).
//
//   Encryption : AES-128 in CTR mode.
//        keystream = AES_K( {device_id[63:0], boot_id[31:0], frame_ctr[31:0]} )
//        ciphertext = plaintext(16 B) XOR keystream
//     CTR needs no padding, no block alignment and only the forward cipher.
//     SECURITY RULE: (boot_id, frame_ctr) must NEVER repeat under one key.
//     Feed `boot_id` from non-volatile storage (increment on every power-up).
//
//   Wire frame (28 bytes, all multi-byte fields big-endian):
//     [0..1]   A5 5A                 sync
//     [2..5]   boot_id               \  nonce, sent in clear (not secret)
//     [6..9]   frame_ctr             /
//     [10..25] ciphertext (16 B)
//     [26..27] CRC-16/CCITT-FALSE over bytes [2..25]
//
//   Telemetry plaintext (16 B):
//     bin[15:0] | velocity_mmps[31:0] | mag[31:0] | timestamp_ms[23:0] |
//     flags[7:0] (bit0 = detect) | frame_id[15:0]
//
//   Note: CRC detects corruption only. For tamper-proof (authenticated) links
//   upgrade to AES-GCM or add an AES-CMAC tag.
// =============================================================================
module secure_tlm_tx (
  input  logic         clk,
  input  logic         rst_n,

  // configuration (static while running)
  input  logic [127:0] key,
  input  logic [63:0]  device_id,
  input  logic [31:0]  boot_id,

  // telemetry in
  input  logic         tlm_valid,
  input  logic [15:0]  tlm_bin,
  input  logic [31:0]  tlm_velocity_mmps,
  input  logic [31:0]  tlm_mag,
  input  logic [23:0]  tlm_timestamp_ms,
  input  logic         tlm_detect,
  input  logic [15:0]  tlm_frame_id,

  // byte stream out (valid/ready)
  output logic         m_valid,
  input  logic         m_ready,
  output logic [7:0]   m_data,

  // status
  output logic         busy,
  output logic         frame_dropped      // sticky: record arrived while busy
);
  import crc_pkg::*;

  localparam int unsigned FB     = neo_pkg::FRAME_BYTES;   // 28
  localparam int unsigned BODY_B = FB - 2;                 // bytes before CRC

  typedef enum logic [1:0] {S_IDLE, S_AES, S_SEND} state_t;
  state_t state;

  logic [127:0] plaintext, cipher;
  logic [31:0]  frame_ctr;
  logic [BODY_B*8-1:0] body;      // sync .. ciphertext, byte0 = MSB
  logic [4:0]   idx;
  logic [15:0]  crc;

  // ---- AES core ---------------------------------------------------------------
  logic         aes_start, aes_busy, aes_done;
  logic [127:0] aes_out;

  aes128_core u_aes (
    .clk(clk), .rst_n(rst_n),
    .start(aes_start), .key(key),
    .block_in({device_id, boot_id, frame_ctr}),
    .busy(aes_busy), .done(aes_done), .block_out(aes_out)
  );

  // ---- output byte mux -------------------------------------------------------
  logic [7:0] body_byte;
  assign body_byte = body[(BODY_B-1-idx)*8 +: 8];

  always_comb begin
    if (idx < 5'(BODY_B))       m_data = body_byte;
    else if (idx == 5'(BODY_B)) m_data = crc[15:8];
    else                        m_data = crc[7:0];
  end

  assign m_valid = (state == S_SEND);
  assign busy    = (state != S_IDLE);

  // ---- control FSM ---------------------------------------------------------
  always_ff @(posedge clk) begin
    aes_start <= 1'b0;
    if (!rst_n) begin
      state         <= S_IDLE;
      frame_ctr     <= '0;
      idx           <= '0;
      crc           <= crc_pkg::CRC16_INIT;
      plaintext     <= '0;
      cipher        <= '0;
      body          <= '0;
      frame_dropped <= 1'b0;
    end else begin
      if (tlm_valid && state != S_IDLE) frame_dropped <= 1'b1;

      case (state)
        S_IDLE: begin
          if (tlm_valid) begin
            plaintext <= {tlm_bin, tlm_velocity_mmps, tlm_mag, tlm_timestamp_ms,
                          7'b0, tlm_detect, tlm_frame_id};
            aes_start <= 1'b1;
            state     <= S_AES;
          end
        end

        S_AES: begin
          if (aes_done) begin
            cipher <= plaintext ^ aes_out;
            body   <= {neo_pkg::SYNC0, neo_pkg::SYNC1, boot_id, frame_ctr,
                       plaintext ^ aes_out};
            idx    <= '0;
            crc    <= crc_pkg::CRC16_INIT;
            state  <= S_SEND;
          end
        end

        S_SEND: begin
          if (m_ready) begin
            if (idx >= 5'd2 && idx < 5'(BODY_B))
              crc <= crc16_update(crc, m_data);
            if (idx == 5'(FB - 1)) begin
              frame_ctr <= frame_ctr + 1'b1;
              state     <= S_IDLE;
            end else begin
              idx <= idx + 1'b1;
            end
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // aes_busy only used for assertions / debug
  logic unused_ok;
  assign unused_ok = &{1'b0, aes_busy, cipher};

endmodule
