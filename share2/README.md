# share2 — L2 Cache (1 MiB) + NoC + Blackbox PE 시스템 (입력 · weight · 출력 경로)

PS → L2 → NoC → L1 / cluster array → **Blackbox (MAC IP 자리)** → L2 → PS 경로를 bit-exact 로 검증한 RTL 묶음.
이 폴더만 있으면 다른 PC 에서도 그대로 시뮬레이션 / 합성할 수 있다 (모든 경로가 상대경로).

- 작성: 2026-10-13, 유정혁 (원본 작업 폴더: 저장소의 `verif/blackbox/`)
- 상태: 시뮬레이션 Phase 1~3 전부 PASS (10 / 36 / 21), 합성·배치·배선 100 MHz 타이밍 만족 (WNS +2.126 ns, BRAM 34.7%), 200 MHz 도 만족 (WNS +0.357 ns, 보드 여유 0.15 ns 더해도 +0.284 ns, 7.1절). **실보드 미검증.**

| 경로 | L2 명령 | 상대 (이 패키지 안의 흉내) | 판정 |
|---|---|---|---|
| **입력** L2 → L1 | ch1_in LOAD | L1 512b × 2048, Blackbox 가 읽어 Expected 와 비교 | CP-A |
| **weight** L2 → cluster array | ch1_wgt LOAD burst / custom (wgt_grp · LCU · LCC), STORE | cluster array 흉내 256b × 1024, weight Blackbox 가 비교 | CP-W |
| **출력** 엔진 → L2 | ch2_in STORE | Blackbox 가 Accumulator / Vector Engine 출력단 역할로 L2 에 직접 씀 | CP-B (PS 가 읽어 비교) |
| (보조) L1 → L2 | ch1_in STORE | Blackbox 가 L1 OUT 영역에 쓰고 회수 | CP-B |

---

## 1. 필요한 것

| 항목 | 내용 |
|---|---|
| Vivado | 2024.2 (XSim + 합성). `C:\Xilinx\Vivado\2024.2` 가 아니면 각 `.bat` 첫 줄의 `XILINX_VIVADO` 수정 |
| Python | 3 + numpy. Vivado 번들 Python 을 먼저 찾고, 없으면 PATH 의 `python` 사용 |
| 보드 | ZCU102 (`xczu9eg-ffvb1156-2-e`) — 합성 기준 |

## 2. 실행

`scripts\` 폴더에서 (또는 탐색기에서 더블클릭):

| 무엇 | 실행 | 결과 (log 마지막 줄) | 시간 |
|---|---|---|---|
| Phase 1 — Blackbox 단독 | `00_run_bb_unit.bat` | `PASS (errors=0)` 10/10 | 수 초 |
| Phase 2 — L2 + NoC + Blackbox (TB 가 L2 포트 직접) | `01_run_bb_integ.bat` | `PASS (errors=0)` 36/36 | ~3 분 |
| Phase 3 — PS 인터페이스 top (AXI4 + AXI-Lite master TB) | `02_run_bb_top.bat` | `PASS (errors=0)` 21/21 | ~4 분 |
| Phase 4 — 합성 (OOC) | `vivado -mode batch -source build_synth_bb.tcl` | `scripts\build_bb\*.rpt` | ~20 분 |

- 각 `.bat` 은 먼저 `gen_vectors.py` 로 `vectors/seed1..4` 를 다시 만든다 (이미 들어 있는 것과 같은 값).
- 묶음 하나만: `cd scripts\work_integ` 후 `xsim bb_integ_snap --testplusarg "ONLY=W" --tclbatch ../run_nowave.tcl`
  (`ONLY` = R0 / MAP / S1~S7 / W / O, cmd 에서는 따옴표 필수)

## 3. 구조

```
 S_AXI (AXI4 64b) ─► axi4_l2_ch0_bridge ─► TOP_L2_cache ch0                  (PS 가 L2 에 적재 / 읽기)
 S_AXI_LITE       ─► axi_lite_ctrl ──────► i_command / Blackbox 레지스터 / BRAM 쓰기 창
 TOP_L2_cache ch1_in  ─► noc_ch1_in_adapter  ─► FIFO_intf_bb (512b × 2048) ◄─ blackbox_pe     입력
 TOP_L2_cache ch2_in  ◄──────────────────────────────────────────────────── blackbox_pe     출력 (ch2 store)
 TOP_L2_cache ch1_wgt ─► noc_ch1_wgt_adapter ─► FIFO_intf_bb (256b × 1024) ◄─ blackbox_pe(W)  weight
```

| 블록 | 크기 / 설정 |
|---|---|
| L2 | GROUPS 8 × BLOCKS 16 × ROW 1024 × 64b = **1 MiB** |
| L1 (ch1_in) / cluster array (ch1_wgt) | 512b × 2048 = 128 KiB / 256b × 1024 = 32 KiB |
| Blackbox | Expected / Golden 512b × 256, weight Expected 256b × 1024 |
| 클럭 / 리셋 | `aclk` 100 MHz 하나, `aresetn` active-low 하나 |
| Block Design top | `rtl/bb/l2_noc_bb_bd_wrapper.v` (Verilog-2001, `S_AXI` + `S_AXI_LITE`) |

### 폴더

| 경로 | 내용 |
|---|---|
| `rtl/l2/` | L2 원본 RTL (`rtl/L2_260901`) — `rtl/fix/` 로 대체된 3개와 `ram_mimic.sv` 제외 |
| `rtl/noc/` | NoC RTL. 이름 충돌 회피용 `noc_` 사본 + 버그 #6 수정본 + 원본 `L1_FIFO_interface*.v` |
| `rtl/fix/` | **원본 대신 쓰는 수정 사본 4개** (4절) |
| `rtl/bb/` | Blackbox 환경 RTL (blackbox_pe, FIFO_intf_bb, l1_sram, l1_port_mux, axi_lite_ctrl, top, BD wrapper, 어댑터 2개, LHJ bridge) |
| `rtl/model_sim/`, `rtl/model_fpga/` | 시뮬레이션용 / 합성용 메모리 모델 (같은 모듈 이름, 파일 목록에서 선택) |
| `tb/` | `bb_pkg.sv` (명령어 생성, 주소 공식) + Phase 1~3 TB |
| `scripts/` | 실행 스크립트, 파일 목록 (`files_unit.f`, `files_sim.f`, `files_synth.f`), `gen_vectors.py`, 합성 tcl / xdc |
| `vectors/seedN/` | x / expected / golden, **wgt / wgt_custom_*, psum16 / out8** hex, meta.json (명령어 64b 값, PS 용 주소) |
| `docs/` | 작업 지시서, FINDING, **FIX_SUMMARY (디버깅 과정과 해결)**, 구조도 SVG |

## 4. 원본 RTL 대비 바꾼 것 (자세한 디버깅 과정은 `docs/FIX_SUMMARY.md`)

| 파일 | 원본 | 바꾼 이유 |
|---|---|---|
| `rtl/fix/cmd_decoder_channel_1_in.sv` | L2 | handshake 보조 FSM 이 지난 명령의 모드로 재출발 → handshake LOAD 뒤 STORE 에서 hang |
| `rtl/fix/cmd_decoder_channel_1_wgt.sv` | L2 | handshake 명령이면 L2 내부 SRAM 쪽도 handshake 가 되어 weight 첫 줄만 반복 전송 → SRAM 쪽은 on-fire 고정 (ch1_in 과 같게), 1줄 |
| `rtl/fix/cmd_decoder_channel_2_in.sv` | L2 | handshake STORE 불능: SRAM 쪽 모드 (위와 같음), FSM 종료 조건 없음, 저장 주소 오프셋을 burst 에서만 계산 — 3곳 |
| `rtl/fix/noc_FIFO_interface_hsfix.v` | NoC `FIFO_interface.v` | handshake 모드에서 FIFO ready 를 0 고정 → L2 handshake LOAD hang. 2줄 (0 → 1) |
| `rtl/bb/l1_port_mux.sv` (신규) | — | pe_busy 가 올라간 클럭에 NoC 쪽에 이미 출발한 쓰기 1개를 끝까지 보냄 → LOAD 직후 START 해도 마지막 줄 유실 없음 |
| `rtl/bb/noc_L1_FIFO_intf.v` | NoC `L1_FIFO_intf.v` | 없는 파라미터 전달로 elaborate 불가 → 그 줄 삭제 + 이름 변경 |
| `rtl/model_sim/ram_mimic.sv` | L2 | ceb/web 극성 (버그 #1) |
| `rtl/noc/*` | NoC | 이름 충돌 회피(`noc_`), 버그 #6 |

burst 모드는 입력 · weight · 출력 모두 **원본 L2 그대로** 동작한다. 위 L2 수정은 전부 handshake 모드용이다.

## 5. 결과

| Phase | 내용 | 결과 |
|---|---|---|
| 1 | 입력 비교 / inject / latency / 경계 + **ch2 출력** burst (ready 무작위) · handshake · inject | 10/10 |
| 2 | 입력 (seed 1~4, 간격 0, handshake 5종), **1 MiB 전 범위 (MAP, weight 경계 포함)**, **weight** burst 1024 줄 · custom 4종 (PDF 예시 2개, 최대 768 줄, 최소 8 줄) · handshake · 간격 0 · STORE, **출력** psum16 · 홀수 NB · H>1 · inject 검출 · int8 결과를 다시 LOAD 해 비교 (layer 연결) · 1 MiB 맨 위 · group 경계 · handshake | 36/36 |
| 3 | 레지스터 맵, AXI4 창 1 MiB, weight burst / custom / custom handshake, 출력 psum16 / out8 + chain / handshake + chain, 입력 S1~S7 — 전부 PS 가 레지스터·AXI 로 판정 | 21/21 |
| 4 | 7절 | |

## 6. PS 에서 쓸 때 꼭 알아야 할 것

1. **Address Editor: `S_AXI` range = 1M.** bridge 는 주소 하위 20비트만 본다.
2. **`S_AXI` 는 64b 단위로만 쓴다** (WSTRB 전부 1). 32b 쓰기는 SLVERR + bridge fault 래치.
3. **L2 안에서 512b / 256b 워드는 64b lane 으로 흩어져 있다.** `vectors/seedN/meta.json` 의 `*_lane_byte_addr` 를 쓰면 된다.
   - 512b (ch1_in) 워드 c, lane b(0~7): `8 × ((c>>11)<<14 | (((c>>10)&1)*8 + b)<<10 | (c & 1023))`
   - 256b (ch1_wgt) 워드 c, lane b(0~3): `8 × ((c>>12)<<14 | (((c>>10)&3)*4 + b)<<10 | (c & 1023))`
4. 명령 64b 값은 `meta.json` 의 `cmd`, `wgt`, `out_ch2` 에 있다. 완료 = STATUS 의 해당 busy 비트 (bit1 ch1_in, bit3 ch2_in, bit4 ch1_wgt) 가 1 → 0.
5. **custom weight load 는 목적지 주소가 항상 0 부터**이고 안 쓰는 줄은 건드리지 않는다. 비교하려면 먼저 0 영역을 burst LOAD 해서 지운다 (`wgt.cmd_clear`).
6. **ch2 store 는 명령을 먼저 걸어 두고** Blackbox 를 START 해도, 반대 순서여도 된다 (Blackbox 는 L2 ready 를 기다림).

### 레지스터 맵 (`S_AXI_LITE`)

| 오프셋 | 이름 | R/W | 내용 |
|---|---|---|---|
| `0x00` / `0x04` / `0x08` | CMD_LO / CMD_HI / CMD_PUSH | RW / RW / W | 명령어, bit0=1 → 1클럭 push |
| `0x0C` | STATUS | R | bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow (sticky), bit3 busy_ch2_in, bit4 busy_ch1_wgt |
| `0x20` | BB_CTRL | RW | bit0 START, bit1 Golden beat0 bit0 반전, bit2 Expected beat0 bit0 반전, bit3 OUT_SEL (0 L1 OUT, 1 ch2 store), bit4 C2_HS |
| `0x24` / `0x28` | BB_IN / BB_OUT | RW | [10:0] L1 시작 워드, [24:16] beat 수 (1~256) |
| `0x2C` | BB_LATENCY | RW | 비교 후 출력 전 대기 클럭 |
| `0x30`~`0x40` | BB_STATUS / MISMATCH / MM_GOT / MM_EXP / CYCLES | R | bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy / [15:0] cnt, [31:16] first_idx / ... |
| `0x44` / `0x48` | BRAM_ADDR / BRAM_COMMIT | RW / W | [7:0] addr, bit8 sel (0 Expected, 1 Golden) / 쓰기 창 512b 기록, addr +1 |
| `0x4C` | BB_C2_CFG | RW | [9:0] W, [19:10] H, [26:20] NB (위치당 256b beat 수), bit31 PREC (0 8b 필드, 1 32b 필드 — 16b 부분합도 1) |
| `0x80`~`0xBC` | BRAM_WDATA[0..15] | RW | 512b 쓰기 창 (`0x80` = bit[31:0]) |
| `0x120` / `0x124` | WBB_CTRL / WBB_IN | RW | weight Blackbox: bit0 START, bit2:1 inject / [9:0] 시작 행, [26:16] 행 수 (1~1024) |
| `0x130`~`0x140` | WBB_STATUS / MISMATCH / MM_GOT / MM_EXP / CYCLES | R | BB_* 와 같은 형식 |
| `0x144` / `0x148` | WBRAM_ADDR / WBRAM_COMMIT | RW / W | [9:0] / 쓰기 창 아래 256b (`0x80`~`0x9C`) 를 weight Expected 에 기록, addr +1 |

### PS 순서 (의사코드)

```c
// 명령: W32(REG+0, lo); W32(REG+4, hi); W32(REG+8, 1);  완료 = STATUS busy 비트 1 -> 0
// ① 입력 : X -> L2 (lane 별), Expected -> BRAM, LOAD, BB_IN / BB_LATENCY 설정
// ② 출력 (ch2 store) : Golden(L2 512b 워드 순서) -> BRAM sel=1,
W32(REG+0x4C, (prec<<31) | (NB<<20) | (H<<10) | W);
CMD(out_ch2.*.cmd);  W32(REG+0x20, (1<<3) | 1);          // OUT_SEL=1, START
while (!(R32(REG+0x30) & 2)); wait(STATUS bit3);
cpa_ok = (R32(REG+0x34) & 0xFFFF) == 0;  // CP-B : L2 출력 워드를 lane 별로 읽어 Golden 과 비교
// ③ weight : 이미지 -> L2 (lane 별), Expected -> W32(REG+0x144,0); for(r){ 8 x W32(REG+0x80+4w,..); W32(REG+0x148,1); }
CMD(wgt.cmd_clear); wait(bit4);  CMD(wgt.custom[..].cmd); wait(bit4);
W32(REG+0x124, (1024<<16)|0); W32(REG+0x120, 1); while (!(R32(REG+0x130) & 2));
cpw_ok = (R32(REG+0x134) & 0xFFFF) == 0;
```

## 7. 합성 (OOC, xczu9eg, aclk 100 MHz / 200 MHz)

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

## 8. 미결 / 주의

- **부분합 int16 넘침 규칙** (saturation / wrap) 과 int8 requant 는 MAC / VE 결정 사항. Golden 은 넘치지 않는 범위로 만들었다.
- Accumulator 쪽 ch2 load (L2 → Accum), ch2_wgt (VE 파라미터) 는 받는 쪽 모델이 없어 미검증.
- 실제 MAC IP 규칙: **pe_busy 를 올린 뒤 최소 1 클럭은 L1 / cluster array 에 접근하지 말 것** (Blackbox 는 2클럭 대기).
- PS 가 STATUS busy 폴링만 하면 아주 짧은 명령은 busy=1 을 못 보고 끝날 수 있다 (완료 카운터 추가 검토 중).
- `cmd_overflow`, `err_start_busy` 는 리셋으로만 해제된다.
- `docs/` 의 FINDING / FIX_SUMMARY 에 나오는 경로(`verif/blackbox/...`, `09_run_bb_integ_orig.bat`, `10_run_ablate.ps1`)는 원본 저장소 기준이다.
