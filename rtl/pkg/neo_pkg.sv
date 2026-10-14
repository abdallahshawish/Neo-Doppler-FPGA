// =============================================================================
// Package : neo_pkg
// Project : NEO Doppler FPGA - space-to-ground meteoroid monitoring payload
// Purpose : Single source of truth for system-level parameters and the
//           telemetry/frame format shared by RTL, testbenches and the ground
//           station (scripts/ground_station.py).
// =============================================================================
`ifndef NEO_PKG_SV
`define NEO_PKG_SV

package neo_pkg;

  // ------------------------------------------------------------- Clocking ---
  localparam int unsigned CLK_HZ     = 50_000_000;   // system clock
  localparam int unsigned FS_HZ      = 2_000;        // Doppler IF sample rate
  localparam int unsigned BAUD       = 115_200;      // UART baud rate

  // ------------------------------------------------------------------ ADC ---
  localparam int unsigned ADC_BITS      = 12;        // MCP3201-class SPI ADC
  localparam int unsigned ADC_LEAD_CLKS = 2;         // sample + null-bit clocks
  localparam int unsigned SCLK_HZ       = 1_000_000; // SPI clock (<= ADC max)

  // ------------------------------------------------------------------ DSP ---
  localparam int unsigned DATA_W    = 16;            // fixed-point datapath, Q1.15
  localparam int unsigned FFT_LOG2  = 8;
  localparam int unsigned FFT_N     = 1 << FFT_LOG2; // 256-point FFT
  localparam int unsigned DC_SHIFT  = 6;             // DC tracker time constant 2^6

  // Peak detection
  localparam int unsigned PEAK_MIN_BIN = 2;          // ignore DC / very low bins
  localparam int unsigned PEAK_THRESH  = 200;        // |re|+|im| detection threshold

  // --------------------------------------------------------- Doppler physics --
  // f_d = 2 * v * f0 / c   ->   v = f_d * c / (2 * f0)
  localparam logic [63:0] F0_HZ  = 64'd10_525_000_000; // HB100-class 10.525 GHz
  localparam logic [63:0] C_MPS  = 64'd299_792_458;
  // velocity step per FFT bin in mm/s:  (fs/N) * c / (2 f0) * 1000
  localparam logic [63:0] VEL_MMPS_PER_BIN =
      (64'd1000 * FS_HZ * C_MPS) / (64'd2 * F0_HZ * FFT_N);

  // ----------------------------------------------------------- Frame format --
  // Wire frame (28 bytes):
  //   [0..1]   0xA5 0x5A  sync
  //   [2..5]   boot_id    (CTR nonce part 1, clear)
  //   [6..9]   frame_ctr  (CTR nonce part 2, clear)
  //   [10..25] ciphertext = AES128-CTR( plaintext telemetry, 16 bytes )
  //   [26..27] CRC-16/CCITT-FALSE over bytes [2..25] (big-endian)
  localparam logic [7:0] SYNC0       = 8'hA5;
  localparam logic [7:0] SYNC1       = 8'h5A;
  localparam int unsigned FRAME_BYTES = 28;

  // Telemetry plaintext (16 bytes, big-endian fields, byte 0 = MSB of block):
  //   [0..1]   peak_bin         [2..5]  velocity_mmps (unsigned)
  //   [6..9]   peak_mag         [10..12] timestamp_ms (24-bit, wraps)
  //   [13]     flags (bit0 = detect)       [14..15] spectrum_frame_id
  localparam int unsigned FLAG_DETECT = 0;

endpackage : neo_pkg

`endif
