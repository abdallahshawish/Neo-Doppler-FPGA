// Compilation order: packages first, then leaf modules, then hierarchy.
// Paths are relative to the project root.

// ---- packages -------------------------------------------------------------
rtl/pkg/neo_pkg.sv
rtl/pkg/crc_pkg.sv
rtl/pkg/aes_pkg.sv

// ---- common ---------------------------------------------------------------
rtl/common/reset_sync.sv
rtl/common/sync_2ff.sv
rtl/common/tick_gen.sv
rtl/common/sdp_ram.sv

// ---- dsp ------------------------------------------------------------------
rtl/dsp/twiddle_rom.sv
rtl/dsp/window_rom.sv
rtl/dsp/adc_spi_master.sv
rtl/dsp/dc_blocker.sv
rtl/dsp/window_mult.sv
rtl/dsp/fft_radix2.sv
rtl/dsp/peak_detect.sv
rtl/dsp/doppler_calc.sv
rtl/dsp/doppler_dsp_chain.sv

// ---- crypto ---------------------------------------------------------------
rtl/crypto/aes128_core.sv

// ---- comm -----------------------------------------------------------------
rtl/comm/uart_tx.sv
rtl/comm/uart_rx.sv
rtl/comm/secure_tlm_tx.sv

// ---- top ------------------------------------------------------------------
rtl/top/neo_doppler_top.sv
