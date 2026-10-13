# share2 — L2 Cache (1 MiB) + NoC + Blackbox PE 시스템 (ch1_in 입력 경로)

PS → L2 → NoC → L1 → **Blackbox PE (MAC IP 자리)** → L1 → NoC → L2 → PS 경로 전체를 bit-exact 로 검증한 RTL 묶음.
이 폴더만 있으면 다른 PC 에서도 그대로 시뮬레이션 / 합성할 수 있다 (모든 경로가 상대경로).

- 작성: 2026-10-13, 유정혁 (원본 작업 폴더: 저장소의 `verif/blackbox/`)
- 상태: 시뮬레이션 Phase 1~3 전부 PASS, 합성·배치·배선 100 MHz 타이밍 만족. **실보드 미검증.**
- 범위: **ch1_in (입력) 경로만.** weight(ch1_wgt) / 출력(ch2_in store) 경로는 다음 작업 (8절)

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
| Phase 1 — Blackbox 단독 | `00_run_bb_unit.bat` | `PASS (errors=0)` 7/7 | 수 초 |
| Phase 2 — L2 + NoC + Blackbox (TB 가 L2 포트를 직접 구동) | `01_run_bb_integ.bat` | `PASS (errors=0)` 15/15 | ~45 초 |
| Phase 3 — PS 인터페이스 top (AXI4 + AXI-Lite master TB) | `02_run_bb_top.bat` | `PASS (errors=0)` 15/15 | ~2 분 |
| Phase 4 — 합성 (OOC) | `vivado -mode batch -source build_synth_bb.tcl` | `scripts\build_bb\*.rpt` | ~18 분 |

- 각 `.bat` 은 먼저 `gen_vectors.py` 로 `vectors/seed1..4` 를 다시 만든다 (이미 들어 있는 것과 같은 값).
- 테스트 하나만: `cd scripts\work_integ` 후
  `xsim bb_integ_snap --testplusarg "ONLY=S4" --tclbatch ../run_nowave.tcl` (cmd 에서는 따옴표 필수)

## 3. 구조

```
 S_AXI (AXI4 64b) ─► axi4_l2_ch0_bridge ─► TOP_L2_cache ch0           (PS 가 L2 에 데이터 적재 / 읽기)
 S_AXI_LITE       ─► axi_lite_ctrl ──────► i_command / Blackbox 레지스터 / BRAM 쓰기 창
 TOP_L2_cache ch1_in ─► noc_ch1_in_adapter ─► FIFO_intf_bb ─► l1_sram (512b × 2048)
                                                   ▲ l1_port_mux (pe_busy 로 선택)
                                             blackbox_pe ── Expected / Golden BRAM
```

| 블록 | 크기 / 설정 |
|---|---|
| L2 | GROUPS 8 × BLOCKS 16 × ROW 1024 × 64b = **1 MiB** (BRAM 256 tile) |
| L1 (ch1_in, cluster 1개) | 512b × 2048 = 128 KiB |
| Blackbox | Expected / Golden 각 512b × 256 |
| 클럭 / 리셋 | `aclk` 100 MHz 하나, `aresetn` active-low 하나 |
| Block Design top | `rtl/bb/l2_noc_bb_bd_wrapper.v` (Verilog-2001, `S_AXI` + `S_AXI_LITE` 에 X_INTERFACE_INFO) |

### 폴더

| 경로 | 내용 |
|---|---|
| `rtl/l2/` | L2 원본 RTL (`rtl/L2_260901`) — 아래 2개 파일 제외하고 그대로 |
| `rtl/noc/` | NoC RTL. 이름 충돌 회피용 `noc_` 사본 + 버그 #6 수정본 + 원본 `L1_FIFO_interface*.v` |
| `rtl/fix/` | **이번에 고친 사본 2개** (원본 대신 사용, 4절) |
| `rtl/bb/` | Blackbox 환경 RTL (blackbox_pe, FIFO_intf_bb, l1_sram, l1_port_mux, axi_lite_ctrl, top, BD wrapper, adapter, LHJ bridge) |
| `rtl/model_sim/` | 시뮬레이션용 메모리 모델 (`ram_mimic.sv` 극성 수정본, `sram_mimic.v`) |
| `rtl/model_fpga/` | 합성용 메모리 모델 (`ram_mimic_fpga_bram.sv`, `sram_mimic_fpga.v`) — 같은 모듈 이름, 파일 목록에서 선택 |
| `tb/` | `bb_pkg.sv` (명령어 생성 / 주소 공식) + Phase 1~3 TB |
| `scripts/` | 실행 스크립트, 파일 목록 (`files_unit.f`, `files_sim.f`, `files_synth.f`), `gen_vectors.py`, 합성 tcl / xdc |
| `vectors/seedN/` | x.hex / expected.hex / golden.hex / meta.json (명령어 64b 값, PS 용 주소) |
| `docs/` | 작업 지시서, FINDING 4건, FIX_SUMMARY, 구조도 SVG |

## 4. 원본 RTL 대비 바꾼 것 (자세한 디버깅 과정은 `docs/FIX_SUMMARY.md`)

| 파일 | 원본 | 바꾼 이유 |
|---|---|---|
| `rtl/fix/cmd_decoder_channel_1_in.sv` | L2 `cmd_decoder_channel_1_in.sv` | handshake 보조 FSM 이 지난 명령의 모드로 재출발 → handshake LOAD 뒤 STORE 에서 hang. 조건 2곳 |
| `rtl/fix/noc_FIFO_interface_hsfix.v` | NoC `FIFO_interface.v` | handshake 모드에서 FIFO ready 를 0 고정 → L2 handshake LOAD hang. 2줄 (0 → 1) |
| `rtl/bb/l1_port_mux.sv` (신규) | — | pe_busy 가 올라간 클럭에 NoC 쪽에 이미 출발한 L1 쓰기 1개를 끝까지 보냄 → LOAD 직후 START 해도 마지막 beat 유실 없음 |
| `rtl/bb/noc_L1_FIFO_intf.v` | NoC `L1_FIFO_intf.v` | 없는 파라미터(`MEMORY_BITWIDTH`) 전달로 elaborate 불가 → 그 줄 삭제 + 이름 변경 |
| `rtl/model_sim/ram_mimic.sv` | L2 `ram_mimic.sv` | ceb/web 극성 (버그 #1) |
| `rtl/noc/*` | NoC 원본 | 이름 충돌 회피(`noc_`), 버그 #6 (STORE 직후 LOAD 첫 beat 오염) |

## 5. 결과

| Phase | 테스트 | 결과 |
|---|---|---|
| 1 | 기본 / CP-A 자가검사 / Golden 자가검사 / latency 0·1·1000 / beat 37 변조 / NoC busy 중 START / 길이 경계 | 7/7 |
| 2 | 회귀, **1 MiB 전 범위 (MAP)**, seed 1~4, inject 검출, LOAD→START 간격 0, latency 0·10000, handshake 5종 | 15/15 |
| 3 | 레지스터 맵, **AXI4 창 1 MiB (MAP)**, 위 시나리오 전부를 PS 인터페이스로 | 15/15 |
| 4 | LUT 32.1% / FF 11.6% / BRAM 301 (33%) / DSP 0, **WNS +1.280 ns, WHS +0.019 ns** @ 100 MHz | 만족 |

소요 클럭 (seed 1, 192 beat 입력 / 16 beat 출력): ch0 쓰기 1576 / LOAD 207 / Blackbox 228 / STORE 29 / ch0 읽기 232.

## 6. PS 에서 쓸 때 꼭 알아야 할 것

1. **Address Editor: `S_AXI` range = 1M.** bridge 는 주소 하위 20비트만 본다 (상위는 SmartConnect 몫).
2. **`S_AXI` 는 64b 단위로만 쓴다** (WSTRB 전부 1). 32b 쓰기는 SLVERR 이 나고 bridge 가 리셋까지 fault 상태가 된다.
3. **512b beat 는 L2 안에서 64b 8개로 흩어져 있다** (`docs/FINDING_l2_ch0_ch1_layout.md`).
   ch1 워드 c 의 lane b (beat 의 바이트 `[8b..8b+7]`) 는 PS 바이트 주소
   `8 × ((c>>11)<<14 | (((c>>10)&1)*8 + b)<<10 | (c & 1023))` 에 있다. `meta.json` 의 `x_lane_byte_addr` / `out_lane_byte_addr` 를 그대로 쓰면 된다.
4. 명령어의 L2 주소는 14비트 (1 MiB): LOAD `[53:40]`, STORE `[54:41]`. `meta.json` 의 `cmd` 값 사용.
5. 명령 완료 = `STATUS.busy` 가 1 이 됐다가 0. `o_command_ready` 는 "큐에 자리 있음" 일 뿐이다.

### 레지스터 맵 (`S_AXI_LITE`)

| 오프셋 | 이름 | R/W | 내용 |
|---|---|---|---|
| `0x00` / `0x04` | CMD_LO / CMD_HI | RW | 명령어 [31:0] / [63:32] |
| `0x08` | CMD_PUSH | W | bit0=1 → 명령 1클럭 push (그 클럭에 큐가 차 있으면 overflow) |
| `0x0C` | STATUS | R | bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow (sticky) |
| `0x20` | BB_CTRL | RW | bit0 START (쓰기 펄스), bit1 Golden beat0 bit0 반전, bit2 Expected beat0 bit0 반전 |
| `0x24` / `0x28` | BB_IN / BB_OUT | RW | [10:0] L1 시작 워드, [24:16] beat 수 (1~256) |
| `0x2C` | BB_LATENCY | RW | 비교 후 Golden 쓰기 전 대기 클럭 |
| `0x30` | BB_STATUS | R | bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy (sticky) |
| `0x34` | BB_MISMATCH | R | [15:0] 불일치 beat 수, [31:16] 첫 불일치 beat |
| `0x38` / `0x3C` | BB_MM_GOT / EXP | R | 첫 불일치 beat 하위 32b |
| `0x40` | BB_CYCLES | R | START~DONE 클럭 수 |
| `0x44` | BRAM_ADDR | RW | [7:0] addr, bit8 sel (0 Expected / 1 Golden) |
| `0x48` | BRAM_COMMIT | W | bit0=1 → 쓰기 창 512b 를 BRAM 에 기록, addr 자동 +1 |
| `0x80`~`0xBC` | BRAM_WDATA[0..15] | RW | 512b 쓰기 창 (`0x80` = bit[31:0]) |

### PS 순서 (의사코드)

```c
// ① X -> L2 (lane 별)
for (b = 0; b < 8; b++) for (k = 0; k < 192; k++) W64(L2 + x_lane_byte_addr[b] + 8*k, x[k].u64[b]);
//    Expected / Golden -> Blackbox BRAM
W32(REG+0x44, 0<<8);  for (k=0;k<192;k++){ for(w=0;w<16;w++) W32(REG+0x80+4*w, x[k].u32[w]);    W32(REG+0x48,1); }
W32(REG+0x44, 1<<8);  for (k=0;k<16; k++){ for(w=0;w<16;w++) W32(REG+0x80+4*w, gold[k].u32[w]); W32(REG+0x48,1); }
// ② LOAD
W32(REG+0x00, (u32)cmd_load); W32(REG+0x04, cmd_load>>32); W32(REG+0x08, 1);
while (!(R32(REG+0x0C) & 2)); while (R32(REG+0x0C) & 2);
// ③ Blackbox
W32(REG+0x24, (192<<16)|0); W32(REG+0x28, (16<<16)|1024); W32(REG+0x2C, latency); W32(REG+0x20, 1);
while (!(R32(REG+0x30) & 2));
cpa_ok = ((R32(REG+0x34) & 0xFFFF) == 0) && !(R32(REG+0x30) & 8);
// ④ STORE (cmd_store) : ② 와 같은 방식
// ⑤ 결과 읽기 (lane 별) -> golden 과 비교
for (b = 0; b < 8; b++) for (k = 0; k < 16; k++) out[k].u64[b] = R64(L2 + out_lane_byte_addr[b] + 8*k);
cpb_ok = (memcmp(out, gold, 16*64) == 0);
```

## 7. 미결 / 주의

- 실제 MAC IP 를 붙일 때 규칙: **pe_busy 를 올린 뒤 최소 1 클럭은 L1 에 접근하지 말 것** (Blackbox 는 2클럭 대기).
- PS 가 STATUS.busy 폴링만 하면 아주 짧은 명령은 busy=1 을 못 보고 끝날 수 있다 (완료 카운터 레지스터 추가 검토 중).
- `cmd_overflow`, `err_start_busy` 는 리셋으로만 해제된다.
- ch1_wgt, ch2_in 의 handshake FSM 에도 `rtl/fix/cmd_decoder_channel_1_in.sv` 와 같은 패턴이 있다 (아직 미수정).
- `docs/` 의 FINDING / FIX_SUMMARY 에 나오는 경로(`verif/blackbox/...`, `09_run_bb_integ_orig.bat`)는 원본 저장소 기준이다.
  수정 전 동작 재현은 원본 저장소에서만 가능.

## 8. 다음 작업

1. **출력 경로 = ch2_in store** (Pooling / Vector Engine → L2). 지금의 ch1_in STORE 는 보조 경로로 유지.
   부분합은 16b 기준 (256b beat = 16채널), 최종 출력은 int8.
2. **weight 경로 = ch1_wgt** (burst load + custom load: wgt_grp / LCU / LCC).
