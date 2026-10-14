// =============================================================================
// Module  : adc_spi_master
// Purpose : SPI mode-0 master for MCP3201-class 12-bit ADCs.
//           One conversion per `start` pulse:
//             CS low -> LEAD_CLKS clocks (sample + null bit) -> BITS data
//             bits MSB-first (MISO sampled on SCLK rising edge) -> CS high.
//           `sample_valid` pulses for one clock when `sample_data` is ready.
// Adapt    : change BITS / LEAD_CLKS for other serial ADCs.
// =============================================================================
module adc_spi_master #(
  parameter int unsigned CLK_HZ    = neo_pkg::CLK_HZ,
  parameter int unsigned SCLK_HZ   = neo_pkg::SCLK_HZ,
  parameter int unsigned BITS      = neo_pkg::ADC_BITS,
  parameter int unsigned LEAD_CLKS = neo_pkg::ADC_LEAD_CLKS
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start,         // 1-cycle strobe (sample tick)
  output logic                 busy,
  // SPI pins
  output logic                 sclk,
  output logic                 cs_n,
  input  logic                 miso,          // already synchronized
  // result
  output logic                 sample_valid,
  output logic [BITS-1:0]      sample_data
);
  localparam int unsigned HALF  = CLK_HZ / (2 * SCLK_HZ);
  localparam int unsigned TOTAL = LEAD_CLKS + BITS;
  localparam int unsigned DW    = (HALF > 1) ? $clog2(HALF) : 1;
  localparam int unsigned EW    = $clog2(TOTAL + 1) + 1;

  typedef enum logic [1:0] {S_IDLE, S_RUN, S_END} state_t;
  state_t          state;
  logic [DW-1:0]   div;
  logic [EW-1:0]   edges;       // rising edges generated so far
  logic [BITS-1:0] shreg;

  assign busy = (state != S_IDLE);

  always_ff @(posedge clk) begin
    sample_valid <= 1'b0;
    if (!rst_n) begin
      state <= S_IDLE;
      sclk  <= 1'b0;
      cs_n  <= 1'b1;
      div   <= '0;
      edges <= '0;
      shreg <= '0;
      sample_data <= '0;
    end else begin
      case (state)
        S_IDLE: begin
          sclk <= 1'b0;
          cs_n <= 1'b1;
          if (start) begin
            cs_n  <= 1'b0;
            div   <= '0;
            edges <= '0;
            state <= S_RUN;
          end
        end

        S_RUN: begin
          if (div == DW'(HALF - 1)) begin
            div  <= '0;
            sclk <= ~sclk;
            if (!sclk) begin                       // rising edge: sample MISO
              if (edges >= EW'(LEAD_CLKS))
                shreg <= {shreg[BITS-2:0], miso};
              edges <= edges + 1'b1;
            end else if (edges == EW'(TOTAL)) begin // falling edge after last bit
              state <= S_END;
            end
          end else begin
            div <= div + 1'b1;
          end
        end

        S_END: begin
          cs_n         <= 1'b1;
          sclk         <= 1'b0;
          sample_data  <= shreg;
          sample_valid <= 1'b1;
          state        <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
