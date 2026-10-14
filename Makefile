# =============================================================================
# NEO Doppler FPGA - build / verification flow
#   make model        Python golden model (AES, CRC, FFT, tones) + golden vectors
#   make tables       regenerate S-box / twiddle / window ROMs
#   make test_aes     FIPS-197 known-answer test
#   make test_uart    UART loopback
#   make test_tlm     encrypted frame vs golden vector
#   make test_dsp     DSP chain with synthetic tones
#   make test_system  end-to-end (slow: ~2 M clocks)
#   make regress      model + all fast tests
#   make lint         Verilator lint (if installed)
# Simulator: SIM=iverilog (default) | SIM=questa
# =============================================================================
SIM    ?= iverilog
PY     ?= python3
FILES  := filelist.f
BUILD  := sim

ifeq ($(SIM),iverilog)
  define RUN
	iverilog -g2012 -Wall -I tb -o $(BUILD)/$(1).vvp -f $(FILES) tb/$(2).sv && vvp -n $(BUILD)/$(1).vvp
  endef
else
  define RUN
	vlib $(BUILD)/work_$(1) && vlog -sv -work $(BUILD)/work_$(1) +incdir+tb -f $(FILES) tb/$(2).sv \
	  && vsim -c -work $(BUILD)/work_$(1) $(2) -do "run -all; quit"
  endef
endif

.PHONY: all model tables test_aes test_uart test_tlm test_dsp test_system regress lint clean

all: regress

$(BUILD):
	mkdir -p $(BUILD)

tables:
	$(PY) scripts/gen_tables.py

model:
	$(PY) scripts/ref_model.py
	$(PY) scripts/ground_station.py --selftest

test_aes: $(BUILD)
	$(call RUN,aes,tb_aes128_core)

test_uart: $(BUILD)
	$(call RUN,uart,tb_uart_loopback)

test_tlm: $(BUILD) model
	$(call RUN,tlm,tb_secure_tlm_tx)

test_dsp: $(BUILD)
	$(call RUN,dsp,tb_dsp_chain)

test_system: $(BUILD) model
	$(call RUN,sys,tb_system)

regress: model test_aes test_uart test_tlm test_dsp
	@echo "=== regression finished: grep the logs for FAIL ==="

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module neo_doppler_top -f $(FILES)

clean:
	rm -rf $(BUILD)
