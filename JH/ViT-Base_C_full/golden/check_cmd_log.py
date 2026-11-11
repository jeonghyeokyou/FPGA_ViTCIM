# check_cmd_log.py - hw_sim 명령 로그 (HWSIM_LOG) 의 MLP 부분을 MLP_TASK.md 4.3 / 4.4 절과 대조 (JH, 2026-11-10)
#
#   python check_cmd_log.py cmd.log [--start N] [--table]
#     --start : MLP 첫 명령 번호 (기본 588 = 현준 attention 블록 명령 수)
#     --table : 연산 종류별 첫 명령의 필드 해석표 출력
#
# 64-bit 원본 값을 vit_hw.h 의 bit 표로 다시 해석하고 (hw_sim 해석과 독립),
# 4.3 / 4.4 절에서 만든 기대 순서와 한 줄씩 비교한다. 마지막 줄 : PASS (errors=0) / FAIL (errors=N)
import re
import sys

N_TOK = 197


def fld(v, hi, lo):
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)


def decode(v):
    op, mode = fld(v, 62, 60), fld(v, 59, 58)
    if op == 1:
        return ("ch1_in LOAD", fld(v, 54, 40), fld(v, 39, 29) + 1, "L1", fld(v, 28, 18), mode, fld(v, 14, 7))
    if op == 2:
        return ("ch1_in STORE", fld(v, 55, 41), fld(v, 40, 27) + 1, "L1", fld(v, 23, 13), mode, None)
    if op == 5:
        return ("ch1_wgt LOAD", fld(v, 53, 39), fld(v, 38, 29) + 1, "WMEM", fld(v, 28, 19), mode, fld(v, 14, 7))
    if op == 3:
        return ("ch2_in LOAD", fld(v, 53, 39), fld(v, 38, 25) + 1, "v_row", fld(v, 23, 10), mode, None)
    if op == 4:
        return ("ch2_in STORE", fld(v, 54, 40), (fld(v, 39, 30), fld(v, 29, 20)), "HxW", None, mode, None)
    return ("?", None, None, None, None, mode, None)


def L2_W1(b): return 0x1800 if b else 0x1000
def L2_H(b): return 0x2800 if b else 0x2000
def L2_H4(k): return 0x7000 if k == 3 else 0x3000 + 0x1000 * k
def L2_W2(b): return 0x0800 if b else 0x0000
def L2_P(b): return 0x1800 if b else 0x1000


def mac_tile(in_c, out_c):
    e = []
    for g in range(2):
        g0, nt = 128 * g, (N_TOK - 128 if g else 128)
        e.append(("ch1_in LOAD", in_c + 12 * g0, 12 * nt, "L1", 0))
        e.append(("ch1_in STORE", out_c + 4 * g0, 4 * nt, "L1", 1536))
    return e


def expected():
    e = []
    for j in range(48):                                     # FC1 tile j, GELU tile j
        b = j & 1
        e.append(("ch1_wgt LOAD", L2_W1(b), 768, "WMEM", 0, f"FC1 {j}"))
        e += [x + (f"FC1 {j}",) for x in mac_tile(0x0000, L2_H(b))]
        e.append(("ch2_in LOAD", L2_H(b), 788, "v_row", 0, f"GELU {j}"))
        for i in range(4):
            t0, nt = 64 * i, min(64, N_TOK - 64 * i)
            e.append(("ch2_in STORE", L2_H(b) + 4 * t0, (1, 4 * nt), "HxW", None, f"GELU {j}"))
    for n in range(12):                                     # FC2 (n, k)
        for k in range(4):
            b = (4 * n + k) & 1
            e.append(("ch1_wgt LOAD", L2_W2(b), 768, "WMEM", 0, f"FC2 ({n},{k})"))
            e += [x + (f"FC2 ({n},{k})",) for x in mac_tile(L2_H4(k), L2_P(b))]
    return e


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    path, start, table = args[0], 588, "--table" in args
    if "--start" in args:
        start = int(args[args.index("--start") + 1])
    rows = []
    for line in open(path):
        m = re.match(r"\s*(\d+)\s+0x([0-9a-fA-F]{16})\s+(.*)", line)
        if m and int(m.group(1)) >= start:
            rows.append((int(m.group(1)), int(m.group(2), 16), m.group(3).strip()))
    exp = expected()
    errors = 0
    if len(rows) != len(exp):
        print(f"  command count {len(rows)} != expected {len(exp)}")
        errors += 1
    kinds, seen = {}, set()
    for (idx, raw, sim), e in zip(rows, exp):
        d = decode(raw)
        kinds[e[5].split()[0] + " " + d[0]] = kinds.get(e[5].split()[0] + " " + d[0], 0) + 1
        got = d[:5]
        bad = got != e[:5]
        bad |= d[5] != (2 if "STORE" in d[0] else 0)          # [59:58] burst LOAD 00 / STORE 10
        bad |= d[6] not in (None, 1)                           # multicast [14:7] = 1
        sim_l2 = re.search(r"L2 0x([0-9A-F]{4})", sim)
        bad |= not sim_l2 or int(sim_l2.group(1), 16) != d[1]  # hw_sim decoder agrees
        if bad:
            errors += 1
            if errors <= 10:
                print(f"  MISMATCH #{idx} 0x{raw:016X} {e[5]}: got {got} exp {e[:5]} | hw_sim: {sim}")
        key = (e[5].split()[0], d[0])
        if table and key not in seen:
            seen.add(key)
            f = f"{d[3]} {d[4]}" if d[4] is not None else f"H {d[2][0]} W {d[2][1]}"
            n = d[2] if d[3] != "HxW" else d[2][0] * d[2][1]
            print(f"  | {e[5]:<10} | #{idx:<5} | 0x{raw:016X} | {d[0]:<12} | op {fld(raw, 62, 60):03b} mode {d[5]:02b}"
                  f" | L2 0x{d[1]:04X} (grp {d[1] >> 12} quad {(d[1] >> 10) & 3} row {d[1] & 0x3FF}) | n {n} | {f} |")
    print("  counts : " + ", ".join(f"{k} {v}" for k, v in kinds.items()))
    print(f"{'PASS' if errors == 0 else 'FAIL'} (errors={errors})")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
