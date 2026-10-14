# NEO Doppler FPGA — Space-Segment Payload (SystemVerilog)

Microwave-Doppler IF → ADC → DSP (FFT) → AES-128-CTR + CRC → UART/RF downlink.

```
 Doppler IF ──► adc_spi_master ──► doppler_dsp_chain ──► secure_tlm_tx ──► uart_tx ──► RF TX
                                   │ dc_blocker                │ aes128_core (CTR)
                                   │ window_mult (Hann)        │ CRC-16
                                   │ fft_radix2 (256-pt)       │ framer (28 B)
                                   │ peak_detect
                                   └ doppler_calc (bin → mm/s)
```

## Layout
| Folder | Content |
|---|---|
| `rtl/pkg` | `neo_pkg` (parameters/frame format), `crc_pkg`, `aes_pkg` (generated) |
| `rtl/common` | `reset_sync`, `sync_2ff`, `tick_gen`, `sdp_ram` |
| `rtl/dsp` | ADC SPI master, DC blocker, window, radix-2 FFT, peak detect, Doppler→velocity |
| `rtl/crypto` | `aes128_core` (iterative, on-the-fly key schedule) |
| `rtl/comm` | `uart_tx`, `uart_rx`, `secure_tlm_tx` |
| `rtl/top` | `neo_doppler_top` |
| `tb` | self-checking testbenches + golden vectors |
| `scripts` | table generator, bit-accurate Python model, ground-station decoder |
| `constraints` | SDC |

## Quick start
```
python3 scripts/gen_tables.py     # (re)generate S-box / twiddle / window ROMs
make model                         # Python golden model + golden_frame.svh
make regress                       # iverilog (SIM=questa also supported)
make test_system                   # end-to-end, slow
python3 scripts/ground_station.py --port COM5 --baud 115200
```

## Wire frame (28 bytes)
`A5 5A | boot_id[4] | frame_ctr[4] | AES-CTR ciphertext[16] | CRC16[2]`
Plaintext: `bin[2] velocity_mm/s[4] magnitude[4] timestamp_ms[3] flags[1] frame_id[2]`.

## Security notes
* The key in `neo_doppler_top` is a **test key** — load the real one from protected storage.
* CTR requires a unique `(boot_id, frame_ctr)` per key: increment `boot_id` in non-volatile memory at every power-up.
* CRC detects corruption only; for authenticity add AES-GCM / CMAC.

## Physics note
v = f_d·c / (2·f0). With fs = 2 kHz, N = 256, f0 = 10.525 GHz the resolution is 7.8125 Hz/bin ≈ 0.111 m/s, a
laboratory/HB100-class range. Real meteoroid speeds (km/s) need a different RF band, much higher IF sampling
and an I/Q front-end (also required to resolve approach vs. recede). All of these are parameters in `neo_pkg`.
