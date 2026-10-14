// =============================================================================
// Module  : uart_tx
// Purpose : UART transmitter, 8N1, LSB first. Valid/ready byte interface:
//           a byte is accepted when s_valid && s_ready.
// =============================================================================
module uart_tx #(
  parameter int unsigned CLK_HZ = neo_pkg::CLK_HZ,
  parameter int unsigned BAUD   = neo_pkg::BAUD
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       s_valid,
  output logic       s_ready,
  input  logic [7:0] s_data,
  output logic       txd
);
  localparam int unsigned CLKS = CLK_HZ / BAUD;
  localparam int unsigned CW   = (CLKS > 1) ? $clog2(CLKS) : 1;

  logic [9:0]    sh;        // {stop, data[7:0], start}
  logic [3:0]    bit_idx;
  logic [CW-1:0] cnt;
  logic          busy;

  assign s_ready = !busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy    <= 1'b0;
      txd     <= 1'b1;
      sh      <= '1;
      bit_idx <= '0;
      cnt     <= '0;
    end else if (!busy) begin
      txd <= 1'b1;
      if (s_valid) begin
        sh      <= {1'b1, s_data, 1'b0};
        txd     <= 1'b0;                  // start bit
        busy    <= 1'b1;
        bit_idx <= '0;
        cnt     <= '0;
      end
    end else begin
      if (cnt == CW'(CLKS - 1)) begin
        cnt <= '0;
        if (bit_idx == 4'd9) begin        // stop bit finished
          busy <= 1'b0;
          txd  <= 1'b1;
        end else begin
          bit_idx <= bit_idx + 1'b1;
          txd     <= sh[bit_idx + 1'b1];
        end
      end else begin
        cnt <= cnt + 1'b1;
      end
    end
  end
endmodule
