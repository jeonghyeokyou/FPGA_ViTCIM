# Blackbox system-level 검증 환경 (입력 · weight · 출력 경로, L2 1 MiB)

PS → L2 → NoC → L1 / cluster array → **Blackbox (MAC IP 자리)** → L2 → PS 경로를 bit-exact 로 검증한다.
실제 MAC IP 가 오면 Blackbox 만 바꾸고 나머지는 그대로 쓴다. 작업 지시: [BLACKBOX_TASK.md](BLACKBOX_TASK.md)

마지막 갱신: 2026-10-13 (weight 경로 ch1_wgt, 출력 경로 ch2_in store 추가)

| 경로 | L2 명령 | 상대 | 판정 |
|---|---|---|---|
| **입력** L2 → L1 | ch1_in LOAD (cmd 1) | L1 512b × 2048 (`FIFO_intf_bb`) ← Blackbox 가 읽어 비교 | CP-A |
| **weight** L2 → cluster array | ch1_wgt LOAD burst / custom (cmd 5), STORE (cmd 6) | cluster array 흉내 256b × 1024 ← weight Blackbox 가 읽어 비교 | CP-W |
| **출력** 엔진 → L2 | ch2_in STORE (cmd 4) | Blackbox 가 Accumulator / VE 출력단 역할로 L2 에 직접 씀 | CP-B (PS 가 읽어 비교) |
| (보조) L1 → L2 | ch1_in STORE (cmd 2) | Blackbox 가 L1 OUT 영역에 쓰고 STORE 로 회수 | CP-B |

---

## 1. 실행법

| Phase | 실행 | 판정 (log 마지막 줄) | 시간 |
|---|---|---|---|
| 1 Blackbox 단독 | `scripts\00_run_bb_unit.bat` | `PASS (errors=0)` 10/10 | 수 초 |
| 2 L2 + NoC + Blackbox (TB 가 L2 포트 직접) | `scripts\01_run_bb_integ.bat` | `PASS (errors=0)` 36/36 | ~3 분 |
| 3 PS 인터페이스 top (AXI4 + AXI-Lite) | `scripts\02_run_bb_top.bat` | `PASS (errors=0)` 21/21 | ~4 분 |
| (참고) 수정 전 RTL 로 Phase 2 | `scripts\09_run_bb_integ_orig.bat` | `FAIL` 22/36 — 일부러 문제 재현 | ~3 분 |
| 4 합성 (OOC, ZCU102) | `vivado -mode batch -source scripts\build_synth_bb.tcl` | `scripts\build_bb\*.rpt` | ~20 분 |

- 모든 `.bat` 은 먼저 `gen_vectors.py` 로 `vectors/seed1..4` 를 만든다.
  **이 PC 에는 시스템 Python 이 없어서** Vivado 번들 Python (`C:\Xilinx\Vivado\2024.2\tps\win64\python-3.8.3\python.exe`, numpy 1.18.4) 을 쓴다.
- 테스트 묶음 하나만: `cd scripts\work_integ` 후 `xsim bb_integ_snap --testplusarg "ONLY=W" --tclbatch ../run_nowave.tcl`
  - Phase 2 `ONLY` = R0 / MAP / S1~S7 / **W** (weight) / **O** (출력) / SWEEP / O5, Phase 3 = REG / MAP / W / O / S1~S7
  - `--testplusarg "TRACE=40"` ch1_in 핸드셰이크, `"TRACE2=300"` ch2_in store FSM 을 명령마다 n 클럭 출력
  - ※ cmd 에서는 `=` 가 인자 구분자라서 **따옴표 필수**.
- 수정 하나씩 되돌려 보기: `powershell -ExecutionPolicy Bypass -File scripts\10_run_ablate.ps1`

## 2. 파일

| 경로 | 설명 |
|---|---|
| `rtl/blackbox_pe.sv` | PE 흉내. Expected/Golden BRAM, CP-A 비교, latency, inject, pe_busy. **출력 2종**: L1 OUT 영역 / L2 ch2_in store 포트 (burst · handshake). 파라미터로 weight 검사기(256b × 1024)로도 재사용 |
| `rtl/l1_sram.sv` | L1 SRAM = `sram_mimic` × 4 (512b×2048 = 128b×4, weight 는 256b×1024 = 64b×4) |
| `rtl/l1_port_mux.sv` | `pe_busy ? PE : NoC`. NoC 의 진행 중 접근 1클럭 우선 (문제 3 수정, `-d BB_ORIG_MUX` 로 원래 동작) |
| `rtl/noc_L1_FIFO_intf.v` | `rtl/NOC_260902/L1_FIFO_intf.v` 사본 (원본과 diff 3줄) |
| `rtl/FIFO_intf_bb.sv` | `noc_FIFO_interface` + `noc_L1_FIFO_intf` + mux + `l1_sram`. 입력 (512b) / weight (256b) 두 곳에 사용 |
| `rtl/fix/noc_FIFO_interface_hsfix.v` | NoC `FIFO_interface` 수정 사본 — handshake ready (문제 4) |
| `rtl/fix/cmd_decoder_channel_1_in.sv` | L2 수정 사본 — handshake FSM 재출발 (문제 5) |
| `rtl/fix/cmd_decoder_channel_1_wgt.sv` | L2 수정 사본 — weight handshake SRAM 모드 (문제 6) |
| `rtl/fix/cmd_decoder_channel_2_in.sv` | L2 수정 사본 — ch2_in handshake STORE 3곳 (문제 7) |
| `rtl/axi_lite_ctrl.sv` | AXI4-Lite 레지스터 (3절) |
| `rtl/l2_noc_bb_top.sv` | bridge(LHJ) + ctrl + L2(1 MiB) + ch1_in 경로 + ch1_wgt 경로 + ch2_in store + Blackbox 2개 |
| `rtl/l2_noc_bb_bd_wrapper.v` | Block Design 용 Verilog-2001 껍데기, `S_AXI` + `S_AXI_LITE` (포트 변화 없음) |
| `tb/bb_pkg.sv` | 상수, 명령어 생성 (`mk_load/store`, `mk_wload_burst/custom`, `mk_wstore`, `mk_c2_store`), L2 배치 공식, custom load 행 공식 |
| `tb/tb_blackbox_pe.sv`, `tb/tb_l2_noc_bb.sv`, `tb/tb_l2_noc_bb_top.sv` | Phase 1 / 2 / 3 TB |
| `scripts/gen_vectors.py` | x / expected / golden, **wgt / wgt_custom_*, psum16 / out8** hex + meta.json |
| `scripts/files_bb_unit.f`, `files_bb_sim.f`, `files_bb_synth.f` | 파일 목록 — sim·synth 는 수정본 사용 (`verif/integ/noc_ch1_wgt_adapter.sv` 포함) |
| `scripts/files_bb_sim_orig.f`, `09_run_bb_integ_orig.bat` | 수정 전 조합 (문제 재현용) |
| `scripts/10_run_ablate.ps1` | 수정 하나씩 되돌려 보는 실험 (변형 파일도 스스로 만듦) |
| `scripts/build_synth_bb.tcl`, `constraints_bb.xdc` | Phase 4 합성 |
| `FIX_SUMMARY.md` | **문제별 디버깅 과정과 해결, 수정 전/후, 하나씩 빼 본 실험** |
| `FINDING_*.md` | 발견한 문제 (RTL 4건 묶음 + 사양 1건 + TB 문제는 FIX_SUMMARY) |

## 3. 메모리 맵 / 명령어 (1 MiB)

| 영역 | PS 바이트 주소 | 채널 워드 주소 | 내용 |
|---|---|---|---|
| X (입력) | `0x0_0000` | ch1_in `0x0000` (512b) | 192 beat |
| weight 이미지 | `0x1_0000` | ch1_wgt `0x0800` (256b) | 1024 줄 |
| 0 영역 | `0x1_8000` | ch1_wgt `0x0C00` | 1024 줄 0 (custom load 전에 cluster array 지우기) |
| weight STORE 목적지 | `0x2_0000` | ch1_wgt `0x1000` | W4 |
| 출력 (ch1_in STORE) | `0xA_0000` | ch1_in `0x2800` | 16 beat |
| 출력 (ch2 store, psum16) | `0xA_1000` | ch2 `0x2840` (14b = ch1_in 워드 주소) | 32 워드 |
| 출력 (ch2 store, out8) | `0xA_2000` | ch2 `0x2880` | 16 워드 |

| 명령 | 필드 (1 MiB) |
|---|---|
| ch1_in LOAD (001) / STORE (010) | L2 `[53:40]` / `[54:41]` (14b), 길이 `[39:29]` / `[40:27]`, L1 `[28:18]` / `[23:13]` |
| ch1_wgt LOAD (101) burst | L2 `[53:39]` (15b), 길이-1 `[38:29]`, cluster array `[28:19]`, multicast `[14:7]` |
| ch1_wgt LOAD (101) custom (`[57]=1`) | L2 `[53:39]`, `[38:36]` wgt_grp_sel, `[35:34]` LCU_sel, `[33:32]` LCC_sel → beat 수 = (grp+1)(LCU+1)(LCC+1)·8, 행 = grp·96 + LCU·32 + LCC·8 + r |
| ch1_wgt STORE (110) | L2 `[54:40]`, 길이-1 `[39:27]`, cluster array `[23:14]` |
| ch2_in STORE (100) | `[57]` 채널필드 형식, L2 `[53:40]` (14b), H `[39:30]`, W `[29:20]`. beat 주소 = {last, j>>1, j&1, h, w} → L2 = 시작 + (j>>1)·H·W + h·W + w |

256b 워드(ch1_wgt / ch2) 의 lane b 는 PS 바이트 주소 `8 × ((c>>12)<<14 | (((c>>10)&3)*4 + b)<<10 | (c & 1023))`.
ch2 store 의 512b 워드 하나 = beat 2개 (아래 / 위 256b) = **ch1_in 이 다시 읽는 512b 워드와 같은 배치** (O2/O7/O8 의 chain 으로 확인).

## 4. AXI-Lite 레지스터 맵

| 오프셋 | 이름 | R/W | 내용 |
|---|---|---|---|
| `0x00` / `0x04` | CMD_LO / CMD_HI | RW | 명령어 [31:0] / [63:32] |
| `0x08` | CMD_PUSH | W | bit0=1 → 명령 1클럭 push (그 클럭에 큐가 차 있으면 overflow) |
| `0x0C` | STATUS | R | bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow (sticky), **bit3 busy_ch2_in, bit4 busy_ch1_wgt** |
| `0x20` | BB_CTRL | RW | bit0 START (쓰기 펄스), bit1 Golden beat0 bit0 반전, bit2 Expected beat0 bit0 반전, **bit3 OUT_SEL (0 L1 OUT, 1 ch2 store), bit4 C2_HS** |
| `0x24` / `0x28` | BB_IN / BB_OUT | RW | [10:0] L1 시작 워드, [24:16] beat 수 (1~256) |
| `0x2C` | BB_LATENCY | RW | 비교 후 출력 전 대기 클럭 |
| `0x30` | BB_STATUS | R | bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy (sticky) |
| `0x34` | BB_MISMATCH | R | [15:0] 불일치 beat 수, [31:16] 첫 불일치 beat |
| `0x38` / `0x3C` | BB_MM_GOT / EXP | R | 첫 불일치 beat 하위 32b |
| `0x40` | BB_CYCLES | R | START~DONE 클럭 수 |
| `0x44` | BRAM_ADDR | RW | [7:0] addr, bit8 sel (0 Expected / 1 Golden) |
| `0x48` | BRAM_COMMIT | W | bit0=1 → 쓰기 창 512b 를 BRAM 에 기록, addr 자동 +1 |
| `0x4C` | **BB_C2_CFG** | RW | [9:0] W, [19:10] H, [26:20] NB (위치당 256b beat 수), bit31 PREC (0 8b 필드, 1 32b 필드 — 16b 부분합도 1) |
| `0x80`~`0xBC` | BRAM_WDATA[0..15] | RW | 512b 쓰기 창 (`0x80` = bit[31:0]) |
| `0x120` | **WBB_CTRL** | RW | bit0 START, bit2:1 inject (weight Blackbox) |
| `0x124` | **WBB_IN** | RW | [9:0] cluster array 시작 행, [26:16] 행 수 (1~1024) |
| `0x130`~`0x140` | **WBB_STATUS / MISMATCH / MM_GOT / MM_EXP / CYCLES** | R | BB_* 와 같은 형식 |
| `0x144` | **WBRAM_ADDR** | RW | [9:0] weight Expected 주소 |
| `0x148` | **WBRAM_COMMIT** | W | bit0=1 → 쓰기 창 아래 256b (`0x80`~`0x9C`) 를 weight Expected 에 기록, addr +1 |

정의 안 된 주소는 읽으면 0, 쓰기 무시. 응답은 항상 OKAY. WSTRB 는 일반 레지스터에 바이트 단위 적용.

## 5. 결과

### Phase 1 — Blackbox 단독: **10/10 PASS**
U1~U7 (입력 비교, inject, latency 0/1/1000 → +L 클럭 정확, beat 37 변조 검출, noc_busy 중 START 무시, 길이 1·256) +
**U8** ch2 출력 burst (ready 무작위 끊김, 32b 필드, H=2 W=8 NB=4, 64 beat) / **U9** ch2 handshake (8b 필드, NB=3 홀수) /
**U10** ch2 inject → 64·15·32 beat 의 주소 필드·데이터·last 전부 일치.

### Phase 2 — L2 + NoC + Blackbox: **36/36 PASS** (수정 전 22/36, [FIX_SUMMARY.md](FIX_SUMMARY.md))

| 묶음 | 테스트 | 결과 / 소요 클럭 |
|---|---|---|
| 입력 | R0, S1~S7 (seed 1~4, inject, 간격 0, latency 0·10000, handshake 5종) | 전부 PASS (LOAD 192 beat 207 clk) |
| 1 MiB | MAP: M1 ch0 전체 1 MiB / M2 ch1_in 8 group·경계 / M3 STORE top·경계 / **M4 ch1_wgt quad·group 경계, top 0x7FFF** | PASS |
| weight | W1 burst 1024 줄 / W1h handshake | CP-W 1024/1024, LOAD 1039 / 9230 clk |
| | W2 custom (7,1,1) PDF p27 / (3,2,2) PDF p28 / (7,2,3) 최대 768 줄 / (0,0,0) 최소 8 줄 — **0 으로 지운 뒤 1024 줄 전부 비교 (안 쓰는 줄 = 0 확인)** | 각 256 / 288 / 768 / 8 beat, LOAD 271 / 303 / 783 / 23 clk |
| | W2h custom handshake (리셋 없이 W1h 다음) / W3 START 간격 0 | PASS |
| | W4 STORE (cluster array → L2) 256 줄 / W4h handshake LOAD→STORE, 간격 10~13 | PASS |
| 출력 | O1 psum16 (32b 필드, NB=4, 32 워드) / O3 H=2 W=8 NB=3 (홀수, 위 256b 안 씀 확인) / O4 inject 검출 | CP-B 32/32, 343 clk |
| | **O2 out8 → ch1_in LOAD 로 다시 읽어 L1 비교 (layer 연결)** / O7 1 MiB 맨 위 / O8 group 경계 | CP-B + chain 일치 |
| | O5 handshake out8 + chain / O6 handshake 연속 (리셋 없이) | 372 / 532 clk |
| 전체 | PE/NoC L1 포트 충돌 (입력·weight) | 0 회 |

### Phase 3 — PS 인터페이스 top: **21/21 PASS**
REG (새 레지스터 포함), MAP (AXI 창 1 MiB), **PW1** weight burst / **PW2** custom (7,1,1) / **PW3** custom (3,2,2) handshake —
WBB_MISMATCH 0, **PO1** psum16 / **PO2** out8 + chain / **PO3** handshake out8 + chain — CP-B AXI 읽기 일치, chain 은 다시 LOAD 한
워드를 Blackbox 가 비교 (BB_MISMATCH 0), S1~S7.

### Phase 4 — 합성
6절.

### 1 MiB 구조 확인
L2 = `1024x64` RAM 128개 (각 8 KiB), ch0 17b · ch1_in 14b · ch1_wgt/ch2 15b(14b) 주소 전 범위 시뮬레이션 확인 (MAP, O7, O8).
Address Editor 에서 `S_AXI` range 는 **1M** (bridge 는 하위 20비트만 본다).

## 6. PS C 코드 순서 (의사코드)

```c
// L2 = S_AXI 창 base (range 1M),  REG = S_AXI_LITE 창 base
// !! S_AXI 는 64b 정렬 + WSTRB 전부 1 만 허용 (LHJ bridge) -> 64b 단위로 쓰고, 캐시는 끄거나 flush/invalidate.
// 명령: W32(REG+0, lo); W32(REG+4, hi); W32(REG+8, 1);  완료 = STATUS 의 해당 busy 비트 1 -> 0

// ---- 입력 (ch1_in) ----
for (b = 0; b < 8; b++) for (k = 0; k < 192; k++) W64(L2 + x_lane_byte_addr[b] + 8*k, x[k].u64[b]);
W32(REG+0x44, 0<<8);  for (k...) { 16 x W32(REG+0x80+4w, x[k].u32[w]); W32(REG+0x48, 1); }     // Expected
CMD(load_burst); wait(STATUS bit1);
W32(REG+0x24, (192<<16)|0); W32(REG+0x2C, latency);

// ---- 출력 A : ch2 store (실제 경로) ----
W32(REG+0x44, 1<<8);  for (k < 32) { 16 x W32(REG+0x80+4w, psum[k].u32[w]); W32(REG+0x48, 1); }  // Golden = L2 512b 워드 순서
W32(REG+0x4C, (1u<<31) | (4<<20) | (1<<10) | 16);   // PREC 32b 필드, NB=4, H=1, W=16
CMD(out_ch2.psum16.cmd);                              // ch2_in STORE 를 먼저 걸어 둔다
W32(REG+0x20, (1<<3) | 1);                            // OUT_SEL=1, START
while (!(R32(REG+0x30) & 2)); wait(STATUS bit3);      // Blackbox done, ch2 busy 0
cpa_ok = (R32(REG+0x34) & 0xFFFF) == 0;
// CP-B : 512b 워드 k (L2 0x2840+k) 의 lane b 를 읽어 비교 (ch1_in 과 같은 lane 공식)

// ---- 출력 B : L1 OUT -> ch1_in STORE (보조) ----
W32(REG+0x28, (16<<16)|1024); W32(REG+0x20, 1); ... CMD(store_burst); wait(STATUS bit1);

// ---- weight (ch1_wgt) ----
for (b = 0; b < 4; b++) for (r = 0; r < 1024; r++) W64(L2 + wgt.lane_byte_addr[b] + 8*r, w[r].u64[b]);
W32(REG+0x144, 0); for (r < 1024) { 8 x W32(REG+0x80+4w, exp[r].u32[w]); W32(REG+0x148, 1); }  // weight Expected
CMD(wgt.cmd_clear); wait(STATUS bit4);                 // custom 이면 먼저 0 으로 지움
CMD(wgt.custom["711"].cmd); wait(STATUS bit4);          // 또는 wgt.cmd_burst_all
W32(REG+0x124, (1024<<16)|0); W32(REG+0x120, 1);
while (!(R32(REG+0x130) & 2));
cpw_ok = (R32(REG+0x134) & 0xFFFF) == 0;               // exp = wgt_custom_711.hex
```

## 7. Phase 4 합성 결과

2026-10-13, 입력 · weight · 출력 경로를 모두 넣은 top, OOC, xczu9eg-ffvb1156-2-e, aclk 100 MHz, 약 20분.

| 자원 | 사용 | % | 비고 (post-route 계층별) |
|---|---|---|---|
| CLB LUT | 77,974 | 28.5 | L2 68.2k / NoC 입력 4.8k / NoC weight 2.6k / Blackbox 1.2k / weight Blackbox 254 / ctrl 581 / bridge 184 |
| CLB FF | 57,861 | 10.6 | |
| BRAM tile | 316.5 | 34.7 | L2 256 / L1 입력 28+2 / cluster array 8 / Blackbox 14+1 / weight Expected 7+0.5 |
| DSP | 3 | 0.1 | L2 ch2 store 주소 계산 (h·W, ch·H·W) |

- **BRAM**: 처음 예상 약 312 tile (L2 256 + L1 32 + weight mem 8 + Blackbox 16) + 이번에 추가한 weight Expected 7.5 → 실측 316.5. 예상과 일치.
- **LUT 가 오히려 줄었다** (입력만 있던 이전 합성 88.0k → 77.7k): ch1_wgt / ch2_in decoder 수정본이 L2 내부 SRAM 쪽 모드를
  상수(on-fire)로 고정해서, 그 채널들의 SRAM 쪽 handshake 인터페이스 로직이 합성에서 지워졌다.
- **DSP 3개** (E4 전 4개): 이전에는 ch2_in 입력이 0 으로 묶여 있어 store 주소 곱셈이 지워졌는데, 이제 실제로 연결되어 남는다.
- **타이밍 (post-route, 2026-10-20 재구현: E4 / P3 / phys_opt 반영)**: **WNS +2.126 ns**, TNS 0 / **WHS +0.019 ns**, THS 0 → 100 MHz 만족.
  (E4 이전 2026-10-13 구현은 WNS +1.569 ns, 최악 경로 `l1_port_mux` 경유 r_ceb → L1 BRAM 주소)
- **critical path 상위 3개** — 모두 로직 1~2단, 배선 위주:
  1. +2.126 ns : L2 ch1_wgt `r_control_mode` → weight NoC L1_FIFO 데이터 (LUTRAM)
  2. +2.174 ns : 같은 출발점 → 다른 비트
  3. +2.213 ns : L2 ch2_in `r_fifo_noc_read_valid` → 내부 데이터 FIFO CE (fanout 256)
- DRC: Warning 만 (DSP 파이프라인 권고 DPIP/DPOP, RTSTAT-10). OOC 라 I/O 관련 DRC 없음.
- 리포트: `scripts/build_bb/util_route*.rpt`, `timing_route.rpt`, `top3_paths.rpt`, `ram_route.rpt`, `drc.rpt`

### 7.1 200 MHz (2026-10-14 확인 → 2026-10-20 수정)

클럭만 바꿔 구현: `vivado.bat -mode batch -log <dir>/vivado.log -source build_synth_bb.tcl -tclargs 5.0 [0.15]`
(`-log` 는 `-tclargs` 앞에. 결과 `scripts/build_bb_200MHz/`, 두 번째 인자 = 추가 clock uncertainty → `build_bb_200MHz_u150/`.
인자 없으면 100 MHz → `build_bb/`.)

| 구현 | WNS | WHS | 실패 | 가장 느린 경로 |
|---|---|---|---|---|
| 100 MHz | +2.126 ns | +0.019 ns | 0 | 위 7절 |
| 200 MHz, 수정 전 | +0.002 ns | +0.019 ns | 0 | L2 ch2_in store 주소 계산, 4.98 ns, 로직 20단 |
| **200 MHz, 수정 후** | **+0.357 ns** | +0.021 ns | 0 | 같은 경로, 4.63 ns, 16단 |
| **200 MHz, 수정 후 + uncertainty 0.15 ns** | **+0.284 ns** | +0.011 ns | 0 | L2 ch2_in `sram_controller` 1단, 배선 4.37 ns |

- 수정 내용 (모두 기능 · 지연 변화 없음, 자세한 것은 [FIX_SUMMARY.md](FIX_SUMMARY.md) "200 MHz 타이밍 수정"):
  - **E4** `rtl/fix/cmd_decoder_channel_2_in.sv` : 주소 필드의 valid · store 상태 게이팅 mux 제거, wrap 상수 `r_wrap_k` 미리 계산.
    이전 식과 무작위 200만 건 비교 불일치 0.
  - **P3** `rtl/blackbox_pe.sv` : 512b 비교 결과를 1클럭 레지스터에 담은 뒤 카운터 갱신.
  - 구현 흐름 : place / route 뒤 `phys_opt_design`.
- uncertainty 0.15 ns 는 보드 PS 클럭 jitter 등을 미리 반영한 것. 이것도 만족하므로 실보드 200 MHz 를 기대할 수 있다
  (최종 확인은 BD 전체 구현으로). 이때 실보드 클럭은 PS `pl_clk` 대신 Clocking Wizard (MMCM) 200 MHz 를 권장.
- 남은 최악 경로는 모두 L2 원본 쪽. 새로 만든 모듈은 slack 0.4 ns 이내 목록에 없다.
- 자원: LUT 78,042 / FF 57,875 / BRAM 316.5 / DSP 3 (100 MHz 와 거의 같음).
- 경로별 slack 목록: `build_bb_200MHz*/path_hier.rpt` (setup 최악 2000개, 시작점 → 끝점).

## 8. 남은 확인 사항 (TODO(JH))
1. **부분합 int16 넘침 규칙** (saturation / wrap) 과 int8 requant 는 MAC / VE 결정 사항. 지금 Golden 은 넘치지 않는 범위 (Wp ∈ [-3,3]) 로 만들었다.
2. **Accumulator 쪽 ch2 load (L2 → Accum)** 는 받는 쪽 모델이 없어 미검증. 16b 부분합이면 32b 모드의 offset 0~3 (256b × 4칸) 대신 0~1 을 쓰는지 Accumulator 설계 확인 필요.
3. ch2_wgt (VE 파라미터 load) 미검증.
4. STATUS 의 busy 폴링만으로는 아주 짧은 명령의 완료를 놓칠 수 있음 → 완료 카운터 레지스터 추가 여부.
5. `cmd_overflow` / `err_start_busy` 를 리셋으로만 해제 vs W1C.
6. 실제 MAC IP 규칙: pe_busy 를 올린 뒤 최소 1 클럭은 L1 / cluster array 접근 금지 (Blackbox 는 GUARD=2).
7. 출력 Blackbox 는 ch2 로 보내는 동안에도 pe_busy 를 유지한다 (단순화). 실제 IP 가 L1 을 놓는 시점에 맞춰 바꿀 수 있음.
