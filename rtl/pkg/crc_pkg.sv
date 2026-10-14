// =============================================================================
// Package : crc_pkg
// Purpose : CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection,
//           no final XOR). Check value for "123456789" is 0x29B1.
//           Used for frame-integrity detection (error detection, NOT security).
// =============================================================================
`ifndef CRC_PKG_SV
`define CRC_PKG_SV

package crc_pkg;

  localparam logic [15:0] CRC16_INIT = 16'hFFFF;

  // Bitwise update by one byte (unrolled by synthesis into an XOR network).
  function automatic logic [15:0] crc16_update(input logic [15:0] crc,
                                               input logic [7:0]  data);
    logic [15:0] c;
    c = crc ^ {data, 8'h00};
    for (int i = 0; i < 8; i++)
      c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
    return c;
  endfunction

endpackage : crc_pkg

`endif
