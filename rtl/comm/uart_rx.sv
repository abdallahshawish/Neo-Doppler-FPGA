// =============================================================================
// Module  : uart_rx
// Purpose : UART receiver, 8N1, LSB first. Input is synchronized internally,
//           start bit is validated at mid-bit, data sampled at bit centres.
//           `m_valid` pulses for one clock per received byte; `frame_err`
//           is high with m_valid when the stop bit was not high.
// =============================================================================
module uart_rx #(
  parameter int unsigned CLK_HZ = neo_pkg::CLK_HZ,
  parameter int unsigned BAUD   = neo_pkg::BAUD
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       rxd,            // asynchronous pin
  output logic       m_valid,
  output logic [7:0] m_data,
  output logic       frame_err
);
  localparam int unsigned CLKS = CLK_HZ / BAUD;
  localparam int unsigned HALF = CLKS / 2;
  localparam int unsigned CW   = (CLKS > 1) ? $clog2(CLKS) : 1;

  typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
  state_t        state;
  logic [CW-1:0] cnt;
  logic [2:0]    bit_idx;
  logic [7:0]    shreg;
  logic          rx_s;

  sync_2ff #(.RESET_VAL(1'b1)) u_sync (
    .clk(clk), .rst_n(rst_n), .d_async(rxd), .q(rx_s)
  );

  always_ff @(posedge clk) begin
    m_valid <= 1'b0;
    if (!rst_n) begin
      state     <= S_IDLE;
      cnt       <= '0;
      bit_idx   <= '0;
      shreg     <= '0;
      m_data    <= '0;
      frame_err <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          cnt <= '0;
          if (!rx_s) state <= S_START;
        end

        S_START: begin                          // move to centre of start bit
          if (cnt == CW'(HALF - 1)) begin
            cnt <= '0;
            if (!rx_s) begin
              bit_idx <= '0;
              state   <= S_DATA;
            end else begin
              state <= S_IDLE;                  // glitch
            end
          end else cnt <= cnt + 1'b1;
        end

        S_DATA: begin
          if (cnt == CW'(CLKS - 1)) begin
            cnt   <= '0;
            shreg <= {rx_s, shreg[7:1]};
            if (bit_idx == 3'd7) state <= S_STOP;
            else bit_idx <= bit_idx + 1'b1;
          end else cnt <= cnt + 1'b1;
        end

        S_STOP: begin
          if (cnt == CW'(CLKS - 1)) begin
            cnt       <= '0;
            m_data    <= shreg;
            frame_err <= !rx_s;
            m_valid   <= 1'b1;
            state     <= S_IDLE;
          end else cnt <= cnt + 1'b1;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
