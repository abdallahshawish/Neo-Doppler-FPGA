// =============================================================================
// Module  : sdp_ram
// Purpose : Simple dual-port RAM (1 write port, 1 read port, single clock,
//           synchronous read). Written in the canonical style that infers
//           block RAM in Intel Quartus, AMD Vivado and Lattice Radiant.
//           Read-during-write to the same address returns OLD data.
// =============================================================================
module sdp_ram #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned DEPTH = 256
) (
  input  logic                     clk,
  input  logic                     we,
  input  logic [$clog2(DEPTH)-1:0] waddr,
  input  logic [WIDTH-1:0]         wdata,
  input  logic [$clog2(DEPTH)-1:0] raddr,
  output logic [WIDTH-1:0]         rdata
);
  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
