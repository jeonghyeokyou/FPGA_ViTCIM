#!/usr/bin/env python3
# =============================================================================
#  gen_vectors.py  -  Blackbox 검증용 테스트 벡터 생성 (BLACKBOX_TASK.md 9절)
#
#  사용법:
#    python gen_vectors.py --seed 1 --out ../vectors/seed1
#  (이 PC에는 시스템 Python이 없어서 .bat 은 Vivado 번들 Python
#   C:\Xilinx\Vivado\2024.2\tps\win64\python-3.8.3\python.exe 를 쓴다.
#   Python 3.8 / numpy 1.18 에서 동작하도록 작성.)
#
#  출력 (모두 같은 패킹 규칙):
#    x.hex         L2 에 적재할 입력 X        (192 beat)
#    expected.hex  Blackbox Expected BRAM     (= X)
#    golden.hex    Blackbox Golden BRAM       (Y = X.W, int32, 16 beat)
#    meta.json     seed, beat 수, 주소, 명령어 64b 값, ch0 배치 공식
#
#  패킹 규칙: beat k = 바이트 [64k, 64k+63], 바이트 0 이 bit[7:0] (little-endian).
#            hex 한 줄 = 한 beat = 128 hex 문자, MSB 가 왼쪽.
#
#  !! 중요 (FINDING_l2_ch0_ch1_layout.md) !!
#  L2 안에서 ch1_in 512b beat 하나는 64b ch0 워드 8개로 "흩어져" 저장된다.
#  ch1 워드 c 의 lane b (bit [64b+63:64b]) 의 ch0 워드 주소:
#      ch0 = (grp << IN_GRP_CH0) | ((pair*8 + b) << ROW_BITS) | row
#      grp  = c >> IN_GRP_CH1,  pair = (c >> ROW_BITS) & (BLOCKS/8 - 1),
#      row  = c & (ADDRESS_ROW-1)
#  즉 "바이트 주소 / 64 = ch1 워드" 는 64 KiB 정렬된 영역의 시작 주소에서만 맞고,
#  beat 내용은 선형으로 이어지지 않는다. PS/TB 는 lane 별로 나눠 써야 한다.
# =============================================================================
import argparse
import json
import math
import os

import numpy as np

# ---- L2 / 명령어 파라미터 (bb_pkg.sv 와 같은 식으로 계산) --------------------
GROUPS = 8
BLOCKS = 16
ADDRESS_ROW = 1024
BW_CH0 = 64
BW_CH1 = 512
RATIO = BW_CH1 // BW_CH0                                   # 8 lane
clog2 = lambda v: int(math.ceil(math.log2(v)))
SRC_W = clog2(GROUPS) + clog2(ADDRESS_ROW * BLOCKS // RATIO)  # 14 (1 MiB)
CH0_AW = clog2(GROUPS) + clog2(ADDRESS_ROW * BLOCKS)          # 17
ROW_BITS = clog2(ADDRESS_ROW)
IN_GRP_CH1 = clog2(ADDRESS_ROW * BLOCKS // RATIO)
IN_GRP_CH0 = clog2(ADDRESS_ROW * BLOCKS)

# ---- 메모리 맵 (4.1 / 4.2절) ------------------------------------------------
X_BYTE_ADDR = 0x0_0000
OUT_BYTE_ADDR = 0xA_0000
L1_IN_BASE = 0
L1_OUT_BASE = 1024

# ---- 데이터 크기 (ViT-B N=16 tile) ------------------------------------------
N_TOK, D_MODEL, D_OUT = 16, 768, 16


def ch1_to_ch0(c, lane):
    """ch1_in 512b 워드 c 의 lane(0..7) 이 저장되는 ch0 64b 워드 주소."""
    grp = c >> IN_GRP_CH1
    pair = (c >> ROW_BITS) & ((BLOCKS // RATIO) - 1)
    row = c & (ADDRESS_ROW - 1)
    return (grp << IN_GRP_CH0) | ((pair * RATIO + lane) << ROW_BITS) | row


def byte_to_ch1_word(byte_addr):
    assert byte_addr % (64 * 1024) == 0, "영역 시작은 64 KiB 정렬이어야 byte/64 공식이 맞음"
    c = byte_addr // 64
    assert ch1_to_ch0(c, 0) * 8 == byte_addr
    return c


def mk_load(l2_word, nbeats, l1_word, handshake=False):
    c = 0
    c |= 0b001 << 60
    c |= (0b01 if handshake else 0b00) << 58
    c |= (l2_word & ((1 << SRC_W) - 1)) << 40
    c |= ((nbeats - 1) & 0x7FF) << 29
    c |= (l1_word & 0x7FF) << 18
    c |= 0x01 << 7                       # multicast
    return c


def mk_store(l1_word, nbeats, l2_word, handshake=False):
    c = 0
    c |= 0b010 << 60
    c |= (0b11 if handshake else 0b10) << 58
    c |= (l2_word & ((1 << SRC_W) - 1)) << 41
    c |= ((nbeats - 1) & 0x3FFF) << 27
    c |= (l1_word & 0x7FF) << 13         # [23:13] local, [26:24] cluster = 0
    return c


def to_beats(buf):
    assert len(buf) % 64 == 0
    return [buf[i:i + 64] for i in range(0, len(buf), 64)]


def beat_hex(b):
    return "".join("%02x" % v for v in reversed(bytearray(b)))


def write_hex(path, beats):
    with open(path, "w", newline="\n") as f:
        for b in beats:
            f.write(beat_hex(b) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    rng = np.random.RandomState(a.seed)
    X = rng.randint(-128, 128, size=(N_TOK, D_MODEL)).astype(np.int8)
    W = rng.randint(-128, 128, size=(D_MODEL, D_OUT)).astype(np.int8)
    Y = X.astype(np.int32).dot(W.astype(np.int32)).astype("<i4")

    x_beats = to_beats(X.tobytes(order="C"))
    y_beats = to_beats(Y.tobytes(order="C"))

    os.makedirs(a.out, exist_ok=True)
    write_hex(os.path.join(a.out, "x.hex"), x_beats)
    write_hex(os.path.join(a.out, "expected.hex"), x_beats)
    write_hex(os.path.join(a.out, "golden.hex"), y_beats)

    x_l2 = byte_to_ch1_word(X_BYTE_ADDR)
    out_l2 = byte_to_ch1_word(OUT_BYTE_ADDR)
    nx, ny = len(x_beats), len(y_beats)
    meta = {
        "seed": a.seed,
        "x_shape": [N_TOK, D_MODEL], "w_shape": [D_MODEL, D_OUT], "y_shape": [N_TOK, D_OUT],
        "x_beats": nx, "golden_beats": ny,
        "l2": {"groups": GROUPS, "blocks": BLOCKS, "address_row": ADDRESS_ROW,
               "src_w": SRC_W, "ch0_addr_w": CH0_AW,
               "x_byte_addr": hex(X_BYTE_ADDR), "x_ch1_word": hex(x_l2),
               "out_byte_addr": hex(OUT_BYTE_ADDR), "out_ch1_word": hex(out_l2)},
        "l1": {"in_base": L1_IN_BASE, "out_base": L1_OUT_BASE},
        "cmd": {
            "load_burst": "0x%016x" % mk_load(x_l2, nx, L1_IN_BASE),
            "load_handshake": "0x%016x" % mk_load(x_l2, nx, L1_IN_BASE, True),
            "store_burst": "0x%016x" % mk_store(L1_OUT_BASE, ny, out_l2),
            "store_handshake": "0x%016x" % mk_store(L1_OUT_BASE, ny, out_l2, True),
        },
        "ch0_layout": {
            "note": "ch1 512b word c, lane b (bits[64b+63:64b]) lives at ch0 64b word "
                    "(grp<<%d)|((pair*8+b)<<%d)|row ; grp=c>>%d, pair=(c>>%d)&%d, row=c&%d ; "
                    "PS byte addr = ch0_word*8" % (IN_GRP_CH0, ROW_BITS, IN_GRP_CH1, ROW_BITS,
                                                    BLOCKS // RATIO - 1, ADDRESS_ROW - 1),
            "x_lane_byte_addr": [hex(ch1_to_ch0(x_l2, b) * 8) for b in range(RATIO)],
            "out_lane_byte_addr": [hex(ch1_to_ch0(out_l2, b) * 8) for b in range(RATIO)],
        },
    }
    with open(os.path.join(a.out, "meta.json"), "w", newline="\n") as f:
        json.dump(meta, f, indent=2)
    print("seed %d -> %s : x %d beats, golden %d beats, LOAD %s STORE %s"
          % (a.seed, a.out, nx, ny, meta["cmd"]["load_burst"], meta["cmd"]["store_burst"]))


if __name__ == "__main__":
    main()
