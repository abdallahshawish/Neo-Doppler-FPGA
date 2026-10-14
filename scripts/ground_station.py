#!/usr/bin/env python3
"""
ground_station.py - Earth-segment receiver for the NEO Doppler payload.

Reads the UART/RF byte stream, hunts for the A5 5A sync, validates the
CRC-16, decrypts the AES-128-CTR payload and prints / logs the telemetry.

Wire frame (28 bytes):  A5 5A | boot_id(4) | frame_ctr(4) | cipher(16) | crc16(2)

Usage
  python3 scripts/ground_station.py --port COM5 --baud 115200 --key 000102...0f
  python3 scripts/ground_station.py --hexfile frame.hex          (offline test)
  python3 scripts/ground_station.py --selftest

Requires: pip install cryptography pyserial
"""
import argparse
import csv
import struct
import sys
import time

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

SYNC = b"\xA5\x5A"
FRAME_LEN = 28
DEFAULT_KEY = "000102030405060708090a0b0c0d0e0f"   # TEST KEY - replace!
DEFAULT_DEVICE_ID = 0x4E454F0000000001


def crc16_ccitt_false(data: bytes, crc: int = 0xFFFF) -> int:
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def keystream(key: bytes, device_id: int, boot_id: int, ctr: int) -> bytes:
    block = struct.pack(">QII", device_id, boot_id, ctr)
    enc = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return enc.update(block) + enc.finalize()


def parse_frame(frame: bytes, key: bytes, device_id: int):
    """Return dict of telemetry or raise ValueError."""
    if len(frame) != FRAME_LEN or frame[:2] != SYNC:
        raise ValueError("bad length / sync")
    rx_crc = struct.unpack(">H", frame[26:28])[0]
    if crc16_ccitt_false(frame[2:26]) != rx_crc:
        raise ValueError("CRC mismatch")
    boot_id, ctr = struct.unpack(">II", frame[2:10])
    ks = keystream(key, device_id, boot_id, ctr)
    pt = bytes(a ^ b for a, b in zip(frame[10:26], ks))
    bin_, vel, mag = struct.unpack(">HII", pt[0:10])
    ts = int.from_bytes(pt[10:13], "big")
    flags = pt[13]
    frame_id = struct.unpack(">H", pt[14:16])[0]
    return {
        "boot_id": boot_id, "frame_ctr": ctr, "bin": bin_,
        "velocity_mps": vel / 1000.0, "magnitude": mag, "timestamp_ms": ts,
        "detect": bool(flags & 1), "frame_id": frame_id,
    }


class FrameSync:
    """Byte-stream -> frames, resynchronising on A5 5A after any error."""

    def __init__(self):
        self.buf = bytearray()

    def push(self, data: bytes):
        self.buf += data
        while True:
            i = self.buf.find(SYNC)
            if i < 0:
                self.buf = self.buf[-1:]          # keep a possible half-sync
                return
            if i > 0:
                del self.buf[:i]
            if len(self.buf) < FRAME_LEN:
                return
            frame = bytes(self.buf[:FRAME_LEN])
            del self.buf[:FRAME_LEN]
            yield frame


def selftest():
    # golden vector produced by scripts/ref_model.py
    frame = bytes.fromhex("a55a00000007000000009a384738661eb398ce34dd23eab875378bae")
    t = parse_frame(frame, bytes.fromhex(DEFAULT_KEY), DEFAULT_DEVICE_ID)
    assert t["bin"] == 40 and t["detect"] and abs(t["velocity_mps"] - 4.44) < 1e-9, t
    fs = FrameSync()
    noisy = b"\x00\xFF\xA5" + frame + b"\x13" + frame
    got = [parse_frame(f, bytes.fromhex(DEFAULT_KEY), DEFAULT_DEVICE_ID) for f in fs.push(noisy)]
    assert len(got) == 2
    bad = bytearray(frame)
    bad[12] ^= 0x01
    try:
        parse_frame(bytes(bad), bytes.fromhex(DEFAULT_KEY), DEFAULT_DEVICE_ID)
        raise SystemExit("CRC failure not detected")
    except ValueError:
        pass
    print("selftest OK:", t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--key", default=DEFAULT_KEY)
    ap.add_argument("--device-id", type=lambda x: int(x, 0), default=DEFAULT_DEVICE_ID)
    ap.add_argument("--hexfile")
    ap.add_argument("--csv", default="neo_telemetry.csv")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        return selftest()

    key = bytes.fromhex(a.key)
    fs = FrameSync()
    out = open(a.csv, "a", newline="")
    wr = csv.writer(out)
    if out.tell() == 0:
        wr.writerow(["utc", "boot_id", "frame_ctr", "frame_id", "bin", "velocity_mps",
                     "magnitude", "timestamp_ms", "detect"])

    def handle(chunk: bytes):
        for frame in fs.push(chunk):
            try:
                t = parse_frame(frame, key, a.device_id)
            except ValueError as e:
                print(f"[drop] {e}")
                continue
            print(f"frame {t['frame_ctr']:6d} | bin {t['bin']:3d} | v = {t['velocity_mps']:8.3f} m/s | "
                  f"mag {t['magnitude']:6d} | t = {t['timestamp_ms']:8d} ms | "
                  f"{'** DETECT **' if t['detect'] else 'quiet'}")
            wr.writerow([time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()), t["boot_id"],
                         t["frame_ctr"], t["frame_id"], t["bin"], t["velocity_mps"],
                         t["magnitude"], t["timestamp_ms"], int(t["detect"])])
            out.flush()

    if a.hexfile:
        handle(bytes.fromhex(open(a.hexfile).read().strip()))
        return
    if not a.port:
        ap.error("--port or --hexfile required")
    import serial  # pyserial
    with serial.Serial(a.port, a.baud, timeout=0.5) as ser:
        print(f"listening on {a.port} @ {a.baud} baud ...")
        while True:
            chunk = ser.read(64)
            if chunk:
                handle(chunk)


if __name__ == "__main__":
    sys.exit(main())
