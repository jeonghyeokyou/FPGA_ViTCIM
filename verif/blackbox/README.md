# Blackbox system-level 검증 환경 (ch1_in)

PS → L2 → adapter → NoC → L1 → **blackbox_pe (MAC IP 자리)** → L1 → NoC → L2 → PS 경로를 bit-exact 로 검증한다.
실제 MAC IP 가 오면 `blackbox_pe` 만 바꾸고 나머지는 그대로 쓴다. 작업 지시: [BLACKBOX_TASK.md](BLACKBOX_TASK.md)

마지막 갱신: 2026-10-06 (Phase 1~4 1차 완료)

---

## 1. 실행법

| Phase | 실행 | 판정 (log 마지막 줄) | 시간 |
|---|---|---|---|
| 1 `blackbox_pe` 단독 | `scripts\00_run_bb_unit.bat` | `PASS (errors=0)` | 수 초 |
| 2 L2+NoC+BB (TB 가 ch0/명령 직접) | `scripts\01_run_bb_integ.bat` | `PASS (errors=0)` (15/15) | ~45 초 |
| 3 PS 인터페이스 top (AXI4 + AXI-Lite) | `scripts\02_run_bb_top.bat` | `PASS (errors=0)` (15/15) | ~2 분 |
| (참고) 수정 전 RTL 로 Phase 2 | `scripts\09_run_bb_integ_orig.bat` | `FAIL (errors=17)` — 일부러 문제 재현 | ~30 초 |
| 4 합성 (OOC, ZCU102) | `vivado -mode batch -source scripts\build_synth_bb.tcl` | `scripts\build_bb\*.rpt` | 수십 분 |

- 모든 `.bat` 은 먼저 `gen_vectors.py` 로 `vectors/seed1..4` 를 만든다.
  **이 PC 에는 시스템 Python 이 없어서** Vivado 번들 Python (`C:\Xilinx\Vivado\2024.2\tps\win64\python-3.8.3\python.exe`, numpy 1.18.4) 을 쓴다.
- 테스트 하나만: `cd scripts\work_integ` 후 `xsim bb_integ_snap --testplusarg "ONLY=S4" --tclbatch ../run_nowave.tcl`
  (`ONLY` = R0/S1/S2/S3/S4/S5/S6/SWEEP, Phase 3 은 REG/S1~S6. `--testplusarg "TRACE=40"` 은 명령마다 ch1_in 핸드셰이크 40 클럭 출력)
  ※ cmd 에서는 `=` 가 인자 구분자라서 **따옴표 필수**.

## 2. 파일

| 경로 | 설명 |
|---|---|
| `rtl/blackbox_pe.sv` | PE 흉내. Expected/Golden BRAM 512b×256, CP-A 비교, latency, inject, pe_busy |
| `rtl/l1_sram.sv` | L1 SRAM 512b×2048 = `sram_mimic` 128b×4 (sim/synth 모델은 파일 목록에서 선택) |
| `rtl/l1_port_mux.sv` | `pe_busy ? PE : NoC` SRAM 입력 선택 (조합). NoC 의 진행 중 접근 1클럭 우선 (문제 3 수정, `-d BB_ORIG_MUX` 로 원래 동작) |
| `rtl/fix/noc_FIFO_interface_hsfix.v` | NoC `FIFO_interface` 수정 사본 — handshake ready (문제 4) |
| `rtl/fix/cmd_decoder_channel_1_in.sv` | L2 `cmd_decoder_channel_1_in` 수정 사본 — handshake FSM 재출발 (문제 5) |
| `rtl/noc_L1_FIFO_intf.v` | `rtl/NOC_260902/L1_FIFO_intf.v` 사본. 원본과 diff 3줄 (이름 2 + 없는 파라미터 제거 1) |
| `rtl/FIFO_intf_bb.sv` | `noc_FIFO_interface` + `noc_L1_FIFO_intf` + mux + `l1_sram`. NoC 쪽 포트 = `FIFO_intf` |
| `rtl/axi_lite_ctrl.sv` | AXI4-Lite 레지스터 (3절) |
| `rtl/l2_noc_bb_top.sv` | bridge(LHJ) + ctrl + L2(1 MiB) + adapter + `FIFO_intf_bb` + `blackbox_pe` |
| `rtl/l2_noc_bb_bd_wrapper.v` | Block Design 용 Verilog-2001 껍데기, `S_AXI` + `S_AXI_LITE` |
| `tb/bb_pkg.sv` | 상수, `mk_load` / `mk_store` / `ch1_to_ch0` (SRC_W 는 L2 크기에서 계산) |
| `tb/tb_blackbox_pe.sv`, `tb/tb_l2_noc_bb.sv`, `tb/tb_l2_noc_bb_top.sv` | Phase 1 / 2 / 3 TB |
| `scripts/gen_vectors.py` | x / expected / golden hex + meta.json (명령어 값, ch0 lane 주소) |
| `scripts/files_bb_unit.f`, `files_bb_sim.f`, `files_bb_synth.f` | 파일 목록 (unit / sim / synth) — sim·synth 는 수정본 사용 |
| `scripts/files_bb_sim_orig.f`, `09_run_bb_integ_orig.bat` | 수정 전 조합 (문제 재현용) |
| `FIX_SUMMARY.md` | **문제별 디버깅 과정과 해결 방법, 수정 전/후 비교** |
| `scripts/build_synth_bb.tcl`, `constraints_bb.xdc` | Phase 4 합성 |
| `FINDING_*.md` | 발견한 문제 4건 (4절) |

## 3. AXI-Lite 레지스터 맵 (최종)

| 오프셋 | 이름 | R/W | 내용 |
|---|---|---|---|
| `0x00` / `0x04` | CMD_LO / CMD_HI | RW | 명령어 [31:0] / [63:32] |
| `0x08` | CMD_PUSH | W | bit0=1 → `i_command_valid` 1클럭 펄스 (그 클럭에 `o_command_ready=0` 이면 overflow) |
| `0x0C` | STATUS | R | bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow (sticky, 리셋으로만 해제) |
| `0x20` | BB_CTRL | RW | bit0 START (쓰기 펄스, 읽으면 0), bit2:1 inject (bit1: Golden beat0 bit0 반전, bit2: Expected beat0 bit0 반전) |
| `0x24` | BB_IN | RW | [10:0] L1 base, [24:16] beat 수 (1~256) |
| `0x28` | BB_OUT | RW | [10:0] L1 base, [24:16] beat 수 (1~256) |
| `0x2C` | BB_LATENCY | RW | 비교 후 Golden 쓰기 전 대기 클럭 |
| `0x30` | BB_STATUS | R | bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy (sticky) |
| `0x34` | BB_MISMATCH | R | [15:0] 불일치 beat 수, [31:16] 첫 불일치 beat 번호 |
| `0x38` / `0x3C` | BB_MM_GOT / BB_MM_EXP | R | 첫 불일치 beat 하위 32b (L1 값 / Expected) |
| `0x40` | BB_CYCLES | R | START~DONE 클럭 수 |
| `0x44` | BRAM_ADDR | RW | [7:0] addr, bit8 sel (0 Expected / 1 Golden) |
| `0x48` | BRAM_COMMIT | W | bit0=1 → 쓰기 창 512b 를 BRAM[sel][addr] 에 기록, addr 자동 +1 |
| `0x80`~`0xBC` | BRAM_WDATA[0..15] | RW | 512b 쓰기 창, `0x80` = bit[31:0] |

정의 안 된 주소는 읽으면 0, 쓰기 무시. 응답은 항상 OKAY. WSTRB 는 일반 레지스터에 바이트 단위 적용.

## 4. 결과 요약

### Phase 1 — `blackbox_pe` 단독: **7/7 PASS**
| # | 결과 | 비고 |
|---|---|---|
| U1 | PASS | mismatch 0, OUT 16/16, 228 clk |
| U2 | PASS | mismatch 1, first_idx 0, got=X[0], exp=X[0]^1 |
| U3 | PASS | OUT beat0 = Golden^1 (bit 0 만), 나머지 15 beat 일치 |
| U4 | PASS | latency 0/1/1000 → 218/219/1218 clk (정확히 +L) |
| U5 | PASS | mismatch 1, first_idx 37, got/exp 하위 32b 일치 |
| U6 | PASS | noc_busy 중 START 무시, err_start_busy sticky |
| U7 | PASS | 1/1, 256/256 (OUT+256 / IN+256 침범 없음) |

### Phase 2 — L2 + NoC + BB: **15/15 PASS** (수정 적용 후. 수정 전 9/14 → [FIX_SUMMARY.md](FIX_SUMMARY.md))
| # | 결과 | CP-A / CP-B | 소요 클럭 (ch0 쓰기 / LOAD / BB / STORE / ch0 읽기) |
|---|---|---|---|
| R0 | PASS | 5/5 (512b 전체 비교) | — |
| MAP 1MiB | PASS | ch0 1 MiB 전체 쓰기/읽기, LOAD 8 group·경계, STORE top·경계 | M1 271,360 clk |
| S1 seed1 | PASS | 0 / 16/16 | 1576 / 207 / 228 / 29 / 232 |
| S2 seed2,3,4 | PASS ×3 | 0 / 16/16 | 같음 |
| S3 inject[0] | PASS | CP-B badmap=0001 (beat0 만 검출, 차이 = bit 0) | |
| S4 burst 간격 0 | PASS | 0 / 16/16 | (수정 전 FAIL: beat 191 유실) |
| S5 lat 0 / 10000 | PASS ×2 | 0 / 16/16 | BB 218 / 10218 |
| S6a hs LOAD | PASS | 0 / 16/16 | LOAD 1742 (수정 전 hang) |
| S6b hs STORE | PASS | 0 / 16/16 | STORE 181 |
| S6c hs LOAD+STORE | PASS | 0 / 16/16 | (수정 전 hang) |
| S6d hs 2회 연속 (리셋 없이) | PASS | 0 / 16/16 | 추가 테스트 |
| S7 hs + 간격 0 | PASS | 0 / 16/16 | 추가 테스트 |
| 전체 | PE/NoC L1 포트 충돌 0 회 | | |

SWEEP (`ONLY=SWEEP`, START 간격 0~6): 수정 후 전부 PASS. 마지막 NoC→L1 쓰기는 busy↓ + 2 클럭에 정상 기록.

### Phase 3 — PS 인터페이스 top: **15/15 PASS** (수정 적용 후)
| # | 결과 | 비고 (AXI4 쓰기 / BRAM 적재 / LOAD / BB / STORE / AXI4 읽기, clk) |
|---|---|---|
| REG | PASS | 레지스터 R/W, WSTRB 바이트 병합, BRAM_ADDR 자동 증가, 창 → Golden BRAM |
| MAP 1MiB | PASS | AXI4 창 맨 아래/맨 위, top 워드 LOAD, bridge 20-bit decode, 1 MiB 넘는 burst → SLVERR |
| S1, S2×3, S3, S5×2 | PASS | 1592 / 10614 / 210 / 228(10218) / 32 / 240 |
| S4 fastest | PASS | PS 가 낼 수 있는 가장 빠른 순서 (START 간격 = busy↓ + 14 clk) |
| S6a~S6d, S7 | PASS | handshake: LOAD 1744 / STORE 184 |

### Phase 4 — 합성
`scripts/build_bb/` 리포트 참고 (아래 6절에 요약).

### 1 MiB 구조 확인 (2026-10-13)

| 항목 | 기대 (8 × 16 × 1024 × 64b) | 확인 |
|---|---|---|
| L2 SRAM | 128 개 × 64b × 1024 row = 1 MiB | 합성 넷리스트: `1024x64` RAM 128개 (각 8 KiB), RAMB36 256개 |
| ch0 주소 | 17b 워드 (= PS byte addr[19:3]) | `CH0_AW=17`, M1 에서 131,072 워드 전부 서로 다른 값으로 쓰고 읽음 (겹침 없음) |
| ch1_in 명령 L2 주소 | 14b (`SRC_W`) = {group 3b, pair 1b, row 10b} | M2: 8 group 모두, pair·group 경계를 넘는 burst, top 0x3FFF LOAD 정상 |
| ch1_in → ch0 배치 | lane b = ch0 `(grp<<14)\|((pair*8+b)<<10)\|row` | M2/M3 에서 1 MiB 전 범위 일치 |
| PS(AXI4) 창 | 1 MiB (bridge 는 addr[19:0], 상위는 SmartConnect) | 0xFF800~0xFFFFF OK, 0x100000 = 0x0 (20b decode), 끝을 넘는 burst SLVERR |
| L1 / BB | 512b × 2048 / 512b × 256 × 2 (L2 크기와 무관) | BRAM 28+2 / 14+1 |

Vivado Address Editor 에서 `S_AXI` range 는 **1M** 로 잡아야 한다 (bridge 가 하위 20비트만 본다).
명령어의 L2 주소 필드는 14비트이므로 LOAD 는 `[53:40]`, STORE 는 `[54:41]` 을 쓰고 그 위 비트는 0.

## 5. PS C 코드 순서 (의사코드)

```c
// 준비: Host 에서 gen_vectors.py -> x.hex, expected.hex, golden.hex, meta.json
// L2  = S_AXI  창 base (Address Editor, range 1 MiB),  REG = S_AXI_LITE 창 base
// !! S_AXI 는 64b 정렬 + WSTRB 전부 1 만 허용 (LHJ bridge). 32b 쓰기(Xil_Out32)는 SLVERR + fault 래치.
//    -> 64b 단위로 쓰고, 캐시는 끄거나 flush/invalidate.

// ① X -> L2 : 512b beat 하나가 L2 안에서 8 lane 으로 흩어져 있음 (FINDING_l2_ch0_ch1_layout.md)
for (b = 0; b < 8; b++)                         // lane b = beat 의 바이트 [8b .. 8b+7]
    for (k = 0; k < 192; k++)
        W64(L2 + meta.x_lane_byte_addr[b] + 8*k, beat_x[k].u64[b]);
//    Expected / Golden -> Blackbox BRAM
W32(REG+0x44, (0<<8) | 0);                      // sel=Expected, addr=0
for (k = 0; k < 192; k++) { for (w = 0; w < 16; w++) W32(REG+0x80+4*w, exp[k].u32[w]); W32(REG+0x48, 1); }
W32(REG+0x44, (1<<8) | 0);                      // sel=Golden
for (k = 0; k < 16;  k++) { for (w = 0; w < 16; w++) W32(REG+0x80+4*w, gold[k].u32[w]); W32(REG+0x48, 1); }

// ② LOAD (meta.cmd.load_burst, 또는 load_handshake - 수정본에서 둘 다 동작)
W32(REG+0x00, (u32)cmd); W32(REG+0x04, cmd >> 32); W32(REG+0x08, 1);
while (!(R32(REG+0x0C) & 2)) ;                  // busy 1 대기   (TODO(JH): 짧은 명령은 놓칠 수 있음, 6절)
while (  R32(REG+0x0C) & 2 ) ;                  // busy 0 대기
assert(!(R32(REG+0x0C) & 4));                   // overflow 없음

// ③ START (busy↓ 직후 바로 시작해도 됨 - l1_port_mux 수정, FIX_SUMMARY 문제 3)
W32(REG+0x24, (192<<16) | 0);   W32(REG+0x28, (16<<16) | 1024);   W32(REG+0x2C, latency);
W32(REG+0x20, (inject<<1) | 1);
while (!(R32(REG+0x30) & 2)) ;                  // done
cpa_ok = ((R32(REG+0x34) & 0xFFFF) == 0) && !(R32(REG+0x30) & 8);

// ⑤ STORE (meta.cmd.store_burst) : ② 와 같은 방식

// ⑥ CP-B : OUT 을 lane 별로 읽어 512b beat 로 다시 조립 후 golden 과 비교
for (b = 0; b < 8; b++) for (k = 0; k < 16; k++) out[k].u64[b] = R64(L2 + meta.out_lane_byte_addr[b] + 8*k);
cpb_ok = memcmp(out, gold, 16*64) == 0;
PASS = done && cpa_ok && cpb_ok;   // seed 를 바꿔 반복 (판정 ③)
```

## 6. Phase 4 합성 결과 (2026-10-06, 수정본 기준 재합성, OOC, xczu9eg-ffvb1156-2-e, aclk 100 MHz, 약 18분)

| 자원 | 사용 | % | 비고 (post-route 계층별) |
|---|---|---|---|
| CLB LUT | 88,006 | 32.1 | L2 81.7k / NoC 4.8k / BB 889 / ctrl 468 / bridge 184 |
| CLB FF | 63,415 | 11.6 | |
| BRAM tile | 301 (RAMB36 298 + RAMB18 6) | 33.0 | L2 256 / L1 28+2 / BB 14+1 |
| DSP | 0 | 0 | |

- BRAM 예상 (memory 정의 SVG): 약 312 tile (34%) 에는 Weight mem 8 tile 이 들어 있다. 이 top 에는 Weight mem 이 없으므로
  비교 대상은 **304** → 실측 **301** (L1·BB 의 512b 폭 일부가 RAMB18 로 매핑돼 0.5 tile 씩). **예상과 일치.**
- 타이밍 (post-route): **WNS +1.280 ns**, TNS 0 / **WHS +0.019 ns**, THS 0 → 100 MHz 만족.
  (수정 전 합성은 WNS +1.910 / WHS +0.012. 최악 경로가 수정과 무관한 같은 L2 ch2_in 경로라 배치 차이로 봄)
- critical path 상위 3개 (수정 전 합성에서 서로 다른 출발점 기준으로 뽑은 것, 수정 후에도 1번이 최악 경로):
  1. L2 `cmd_decoder_channel_2_in/r_control_mode_reg` → ch2_in stage_2 `UFIFO_DATA/mem_reg/CE` (LUT 3단, 배선 95%)
  2. L2 `SRAM_GRP[3]/u_L2_FIFO_interface_channel_1_wgt/.../wr_ptr_reg` → ch1_wgt stage_2 handshake `r_read_data_M_reg/CE`
  3. L2 ch2_in stage_2 `UFIFO_DATA/rd_ptr_reg` → ch2_in stage_1 `UFIFO_DATA/mem_reg/CE`
  → 전부 **L2 원본 내부**, 이 top 에서 안 쓰는 ch2_in / ch1_wgt 경로. 명령(`i_command`)이 공유라 로직이 지워지지 않는다.
  Blackbox / ctrl / bridge / 이번 수정 로직은 상위 경로에 없음.
- DRC: RTSTAT-10 (No routable loads) Warning 1건만. OOC 라 I/O 관련 DRC 없음.
- 리포트: `scripts/build_bb/util_route*.rpt`, `timing_route.rpt`, `top3_paths.rpt`, `top3_hold.rpt`, `ram_route.rpt`, `drc.rpt`

## 7. 남은 확인 사항 (TODO(JH))
1. STATUS 의 busy 폴링만으로는 아주 짧은 명령의 완료를 놓칠 수 있음 (busy=1 을 못 보고 끝남). "완료 카운터"나 "busy↓ sticky" 비트를 레지스터 맵에 추가할지.
2. `cmd_overflow` / `err_start_busy` 를 리셋으로만 해제 vs W1C.
3. ch1_wgt / ch2_in 의 handshake 보조 FSM 에도 문제 5 와 같은 패턴이 있음 (그 채널을 쓸 때 같은 방식으로 사본 수정).
4. 실제 MAC IP 규칙: pe_busy 를 올린 뒤 최소 1 클럭은 L1 접근 금지 (blackbox 는 GUARD=2).
5. 12절 ①(MAC IP 의 L1 접근 방식), ③ ch1_wgt, ④ ch2 는 그대로 미결.
