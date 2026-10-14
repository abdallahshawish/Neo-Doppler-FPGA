#!/usr/bin/env python3
"""
ref_model.py - bit-accurate Python golden model of the RTL.

What it does
  1. AES-128 : mirrors aes_pkg/aes128_core, checks FIPS-197 vectors and the
               `cryptography` library.
  2. CRC-16  : mirrors crc_pkg, checks the standard "123456789" -> 0x29B1.
  3. DSP     : mirrors dc_blocker / window_mult / fft_radix2 / peak_detect /
               doppler_calc (same index math, same Q1.15 truncation) and runs
               tone tests.
  4. Frame   : mirrors secure_tlm_tx and writes tb/golden_frame.svh so the
               SystemVerilog testbench can compare RTL output byte-for-byte.

Run:  python3 scripts/ref_model.py
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_tables import build_sbox, q15  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent

# ----------------------------------------------------------- parameters ------
CLK_HZ, FS_HZ = 50_000_000, 2_000
ADC_BITS, DATA_W = 12, 16
FFT_LOG2 = 8
N = 1 << FFT_LOG2
DC_SHIFT = 6
PEAK_MIN_BIN, PEAK_THRESH = 2, 200
F0_HZ, C_MPS = 10_525_000_000, 299_792_458
VEL_K = (1000 * FS_HZ * C_MPS) // (2 * F0_HZ * N)

SBOX = build_sbox()


# ================================ AES (mirrors aes_pkg) =====================
def xtime(x):
    return ((x << 1) & 0xFF) ^ (0x1B if x & 0x80 else 0)


def sub_bytes(s):
    return [SBOX[b] for b in s]


def shift_rows(s):  # new(r,c) = old(r,(c+r)%4), byte index = r + 4c
    r = [0] * 16
    for c in range(4):
        for row in range(4):
            r[row + 4 * c] = s[row + 4 * ((c + row) % 4)]
    return r


def mix_columns(s):
    r = [0] * 16
    for c in range(4):
        a0, a1, a2, a3 = s[4 * c:4 * c + 4]
        r[4 * c + 0] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3
        r[4 * c + 1] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3
        r[4 * c + 2] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3)
        r[4 * c + 3] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3)
    return r


RCON = [0, 1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]


def next_round_key(k, rnd):
    w = [k[0:4], k[4:8], k[8:12], k[12:16]]
    t = w[3][1:] + w[3][:1]
    t = [SBOX[b] for b in t]
    t[0] ^= RCON[rnd]
    n0 = [a ^ b for a, b in zip(w[0], t)]
    n1 = [a ^ b for a, b in zip(w[1], n0)]
    n2 = [a ^ b for a, b in zip(w[2], n1)]
    n3 = [a ^ b for a, b in zip(w[3], n2)]
    return n0 + n1 + n2 + n3


def aes128_encrypt(key, block):
    st = [a ^ b for a, b in zip(block, key)]
    rk = list(key)
    for rnd in range(1, 11):
        rk = next_round_key(rk, rnd)
        st = shift_rows(sub_bytes(st))
        if rnd != 10:
            st = mix_columns(st)
        st = [a ^ b for a, b in zip(st, rk)]
    return bytes(st)


def check_aes():
    vecs = [
        ("2b7e151628aed2a6abf7158809cf4f3c", "3243f6a8885a308d313198a2e0370734",
         "3925841d02dc09fbdc118597196a0b32"),
        ("000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff",
         "69c4e0d86a7b0430d8cdb78070b4c55a"),
    ]
    for k, p, c in vecs:
        got = aes128_encrypt(bytes.fromhex(k), bytes.fromhex(p)).hex()
        assert got == c, f"AES mismatch: {got} != {c}"
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        import os
        for _ in range(50):
            k, p = os.urandom(16), os.urandom(16)
            enc = Cipher(algorithms.AES(k), modes.ECB()).encryptor()
            assert enc.update(p) + enc.finalize() == aes128_encrypt(k, p)
        print("[ok] AES-128: FIPS-197 B & C.1 vectors + 50 random blocks vs cryptography lib")
    except ImportError:
        print("[ok] AES-128: FIPS-197 vectors (cryptography lib not installed, random check skipped)")


# ================================ CRC-16 (mirrors crc_pkg) ==================
def crc16_update(crc, byte):
    c = crc ^ (byte << 8)
    for _ in range(8):
        c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
    return c


def crc16(data, init=0xFFFF):
    for b in data:
        init = crc16_update(init, b)
    return init


def check_crc():
    assert crc16(b"123456789") == 0x29B1
    print("[ok] CRC-16/CCITT-FALSE check value 0x29B1")


# ================================ Frame (mirrors secure_tlm_tx) =============
def build_plaintext(bin_, vel, mag, ts, detect, frame_id):
    return (bin_ & 0xFFFF).to_bytes(2, "big") + (vel & 0xFFFFFFFF).to_bytes(4, "big") + \
        (mag & 0xFFFFFFFF).to_bytes(4, "big") + (ts & 0xFFFFFF).to_bytes(3, "big") + \
        bytes([detect & 1]) + (frame_id & 0xFFFF).to_bytes(2, "big")


def build_frame(key, device_id, boot_id, ctr, plaintext):
    nonce_block = device_id.to_bytes(8, "big") + boot_id.to_bytes(4, "big") + ctr.to_bytes(4, "big")
    ks = aes128_encrypt(key, nonce_block)
    cipher = bytes(a ^ b for a, b in zip(plaintext, ks))
    body = bytes([0xA5, 0x5A]) + boot_id.to_bytes(4, "big") + ctr.to_bytes(4, "big") + cipher
    crc = crc16(body[2:])
    return body + crc.to_bytes(2, "big")


# ================================ DSP (mirrors dsp/*.sv) ====================
def sat16(v):
    return max(-32768, min(32767, v))


def dc_blocker(samples):
    xs_out, avg_fx, primed = [], 0, False
    for code in samples:
        x = code - (1 << (ADC_BITS - 1))
        avg_int = avg_fx >> DC_SHIFT
        y = x - avg_int
        if not primed:
            avg_fx, primed = x << DC_SHIFT, True
        else:
            avg_fx = avg_fx + x - avg_int
        xs_out.append(y << (DATA_W - (ADC_BITS + 1)))
    return xs_out


def window_rom():
    return [max(0, min(32767, int(round(0.5 * (1 - math.cos(2 * math.pi * i / (N - 1))) * 32767.0))))
            for i in range(N)]


def twiddles():
    return [(q15(math.cos(2 * math.pi * i / N)), q15(math.sin(2 * math.pi * i / N)))
            for i in range(N // 2)]


def bitrev(x):
    return int(format(x, f"0{FFT_LOG2}b")[::-1], 2)


def fft_rtl(x_real):
    tw = twiddles()
    re = [0] * N
    im = [0] * N
    for n, v in enumerate(x_real):
        re[bitrev(n)] = v
    for stage in range(1, FFT_LOG2 + 1):
        sh = stage - 1
        for k in range(N // 2):
            j = k & ((1 << sh) - 1)
            i0 = ((k >> sh) << stage) | j
            i1 = i0 | (1 << sh)
            c, s = tw[(j << (FFT_LOG2 - stage)) & (N // 2 - 1)]
            tr = (c * re[i1] + s * im[i1]) >> 15
            ti = (c * im[i1] - s * re[i1]) >> 15
            ar, ai = re[i0], im[i0]
            re[i0], im[i0] = sat16((ar + tr) >> 1), sat16((ai + ti) >> 1)
            re[i1], im[i1] = sat16((ar - tr) >> 1), sat16((ai - ti) >> 1)
    return re[:N // 2], im[:N // 2]


def peak_and_velocity(re, im):
    best_mag, best_bin = 0, 0
    for i in range(N // 2):
        mag = abs(re[i]) + abs(im[i])
        if i >= PEAK_MIN_BIN and mag > best_mag:
            best_mag, best_bin = mag, i
    return best_bin, best_mag, best_mag >= PEAK_THRESH, best_bin * VEL_K


def dsp_frame(codes):
    dc = dc_blocker(codes)
    win = window_rom()
    xw = [(d * win[i]) >> 15 for i, d in enumerate(dc)]
    re, im = fft_rtl(xw)
    return peak_and_velocity(re, im)


def check_fft_scaling():
    """RTL FFT must equal DFT/N within fixed-point error."""
    import random
    random.seed(1)
    x = [int(8000 * math.sin(2 * math.pi * 40 * n / N)) + random.randint(-50, 50) for n in range(N)]
    re, im = fft_rtl(x)
    worst = 0.0
    for kbin in (0, 5, 17, 40, 63, 100, 127):
        ref_r = sum(x[n] * math.cos(2 * math.pi * kbin * n / N) for n in range(N)) / N
        ref_i = -sum(x[n] * math.sin(2 * math.pi * kbin * n / N) for n in range(N)) / N
        worst = max(worst, abs(re[kbin] - ref_r), abs(im[kbin] - ref_i))
    assert worst < 12, f"FFT error too large: {worst}"
    print(f"[ok] FFT model == DFT/N, worst abs error {worst:.2f} LSB (Q1.15)")


def check_tones():
    for tone in (40, 17, 100):
        codes = [int(round(2048 + 1000 * math.sin(2 * math.pi * tone * n / N))) for n in range(N)]
        b, m, det, v = dsp_frame(codes)
        assert b == tone and det, (tone, b, m, det)
        print(f"[ok] tone bin {tone:3d} -> peak bin {b}, mag {m}, detect {int(det)}, v = {v} mm/s")
    codes = [2048] * N
    b, m, det, v = dsp_frame(codes)
    assert not det and m == 0
    print("[ok] no-signal frame -> detect 0")


# ================================ golden vectors for the testbench ==========
def write_golden():
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    device_id, boot_id, ctr = 0x4E454F0000000001, 0x00000007, 0x00000000
    codes = [int(round(2048 + 1000 * math.sin(2 * math.pi * 40 * n / N))) for n in range(N)]
    b, m, det, v = dsp_frame(codes)
    pt = build_plaintext(b, v, m, 0x00ABCD, int(det), 1)
    frame = build_frame(key, device_id, boot_id, ctr, pt)
    lines = [
        "// AUTO-GENERATED by scripts/ref_model.py - golden vectors for tb_secure_tlm_tx / tb_system",
        f"localparam logic [127:0] G_KEY       = 128'h{key.hex()};",
        f"localparam logic [63:0]  G_DEVICE_ID = 64'h{device_id:016X};",
        f"localparam logic [31:0]  G_BOOT_ID   = 32'h{boot_id:08X};",
        f"localparam logic [15:0]  G_BIN       = 16'd{b};",
        f"localparam logic [31:0]  G_VEL_MMPS  = 32'd{v};",
        f"localparam logic [31:0]  G_MAG       = 32'd{m};",
        f"localparam logic [23:0]  G_TS_MS     = 24'h00ABCD;",
        f"localparam logic         G_DETECT    = 1'b{int(det)};",
        f"localparam logic [15:0]  G_FRAME_ID  = 16'd1;",
        f"localparam logic [223:0] G_FRAME     = 224'h{frame.hex()};",
    ]
    (ROOT / "tb/golden_frame.svh").write_text("\n".join(lines) + "\n")
    print(f"[ok] wrote tb/golden_frame.svh  (frame = {frame.hex()})")
    print(f"     plaintext telemetry: bin={b} v={v} mm/s mag={m} detect={int(det)}")


if __name__ == "__main__":
    print(f"VEL_MMPS_PER_BIN = {VEL_K}  (resolution {FS_HZ / N:.4f} Hz/bin)")
    check_aes()
    check_crc()
    check_fft_scaling()
    check_tones()
    write_golden()
    print("ALL MODEL CHECKS PASSED")
