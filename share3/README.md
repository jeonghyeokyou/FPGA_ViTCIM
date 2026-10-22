# share3 : L2 1 MiB + CH1 / CH2 256b blackbox 시스템

LHJ/261020 구조(PS 포트 3개, `l2_system_top`, 명령 adapter, fence)를 바탕으로 만들었다. 모든 L2 채널(ch1_in, ch1_wgt, ch2_in, ch2_wgt)을 256b로 통일하고, CH1과 CH2에 blackbox를 하나씩 붙인 RTL 묶음이다.

이 폴더만 있으면 다른 PC에서도 그대로 시뮬레이션과 합성을 할 수 있다. 모든 경로가 상대경로다.

- 작성: 2026-10-22, 유정혁. 원본 작업 폴더는 저장소의 `verif/bb256/`이고, 이 폴더는 그 내용을 정리한 사본이다.
- 상태:
  - 시뮬레이션 T0~T17, 18 / 18 PASS
  - 합성 · 배치 · 배선: 100 MHz WNS +2.559 ns, 200 MHz WNS +0.411 ns, BRAM 33.8%
  - **실보드는 아직 확인하지 않았다.**
- 블록도: `docs/PL_block_diagram.html` (브라우저로 열기)

blackbox는 연산을 하지 않고 동작만 모사한다. 하는 일은 weight 저장, input 읽기, PS가 넣어둔 Golden 출력뿐이다. 판정은 PS가 L2에서 결과를 읽어 Golden과 비교해서 한다.

## 1. 필요한 것

| 항목 | 내용 |
|---|---|
| Vivado | 2024.2 (XSim + 합성). 설치 경로가 `C:\Xilinx\Vivado\2024.2`가 아니면 각 `.bat` 파일 위쪽의 `XILINX_VIVADO`를 고친다 |
| 보드 | ZCU102 (`xczu9eg-ffvb1156-2-e`), 합성 기준 |

## 2. 실행

`scripts\` 폴더에서 실행하거나, 탐색기에서 더블클릭한다.

| 무엇 | 실행 | 결과 | 시간 |
|---|---|---|---|
| 시뮬레이션 (PS 인터페이스 TB) | `00_run_sim.bat` | `scripts\work_sim\bb256.log` 마지막 줄 `PASS (errors=0)` | ~1 분 |
| 시뮬레이션 + 파형 | `00_run_sim.bat wave` | `scripts\work_sim\bb256_snap.wdb` | ~2 분 |
| 합성 100 MHz | `01_build_synth.bat` | `scripts\build\timing_route.rpt` 등 | ~20 분 |
| 합성 200 MHz | `01_build_synth.bat 200` | `scripts\build_200MHz\` | ~25 분 |
| 합성 200 MHz + 클럭 여유 0.15 ns | `01_build_synth.bat 200u` | `scripts\build_200MHz_u150\` | ~25 분 |

이미 돌려둔 합성 리포트는 `reports\synth_100MHz\`와 `reports\synth_200MHz\`에 있다.

## 3. 구조

```
PS ─S_AXI_DATA (AXI4 64b)───► axi4_l2_ch0_bridge ──► L2 ch0 (64b, addr 17b)        PS 가 L2 에 쓰고 읽기
PS ─S_AXI_CMD  (Lite 64b)───► axi_lite_l2_cmd_adapter ─► L2 명령 (opcode 1~7)
PS ─S_AXI_BB   (Lite 32b)───► axi_lite_bb_ctrl ─► CH1 / CH2 blackbox 제어, Golden 적재, DBG2

CH1 (linear / MAC 자리) : blackbox_ip
  L2 ch1_in  256b ◄──► L1 (256b × 2048) ◄──► blackbox_ip : input 읽기, Golden 을 L1 OUT 에 쓰기
  L2 ch1_wgt 256b ◄──► blackbox_ip 내부 weight 메모리 (256b × 1024)   (ch1_wgt STORE 로 다시 읽기 가능)
  출력 : L1 OUT ─ ch1_in STORE ─► L2

CH2 (nonlinear 자리) : blackbox_nl
  L2 ch2_in  LOAD  256b ──► input 메모리  (256b × 2048, NoC 주소 하위 11b)
  L2 ch2_wgt LOAD  256b ──► weight 메모리 (256b × 512)
  L2 ch2_in  STORE 256b ◄── Golden (256b × 256), BB 가 master, 주소 {last, ch, h, w}
  확인 : ch2 의 weight / input 은 L2 로 되돌리는 STORE 가 없으므로 DBG2 창으로 한 줄씩 읽는다
```

- 명령은 한 번에 하나만 L2에 들어간다.
- blackbox와 명령은 채널 묶음별로 서로 막는다.
  - CH1 명령(1, 2, 5, 6)은 blackbox_ip와 동시에 실행되지 않는다.
  - CH2 LOAD(3, 7)는 blackbox_nl과 동시에 실행되지 않는다.
  - ch2_in STORE(4)는 blackbox_nl의 출력 경로이므로 blackbox_nl이 실행 중이어도 받는다.
- 최상위 포트(`l2_system_bd_wrapper`)는 LHJ/261020과 같다. Block Design을 그대로 쓸 수 있다.

## 4. 폴더

| 경로 | 내용 |
|---|---|
| `rtl/l2/` | L2 (TOP_L2_cache 이하). LHJ/261020 사본, 수정 안 함 |
| `rtl/noc/` | NoC 브리지, L1 FIFO interface. LHJ/261020 사본, 수정 안 함 |
| `rtl/bb/` | 이번에 새로 만들거나 바꾼 것: `blackbox_ip`, `blackbox_nl`, `axi_lite_bb_ctrl`, `l2_noc_bb_core`, `l2_system_top`, `noc_wr_adapter`, `noc_ch1_wgt_adapter` |
| | LHJ/261020 그대로인 것: `axi4_l2_ch0_bridge`, `axi_lite_l2_cmd_adapter`, `l2_system_bd_wrapper`, `l1_sram`, `l1_port_mux`, `noc_L1_FIFO_intf`, `noc_ch1_in_adapter` |
| `rtl/fix/` | 원본 버그를 고친 사본. 같은 모듈 이름이며, 파일 목록에서 원본 대신 들어간다 (6장) |
| `rtl/model_sim/` | 시뮬레이션용 메모리 모델 (리셋 시 0) |
| `rtl/model_fpga/` | 합성용 메모리 모델 (BRAM 추론) |
| `tb/` | `bb256_pkg.sv` (주소 공식, 명령어 생성), `tb_bb256_system.sv` (T0~T17) |
| `scripts/` | `00_run_sim.bat`, `01_build_synth.bat`, `build_synth.tcl`, `files_sim.f`, `files_synth.f`, `constraints.xdc` |
| `reports/` | 합성 리포트 (100 MHz, 200 MHz) |
| `docs/PL_block_diagram.html` | PL 블록도 (폭과 주소 비트) |

## 5. 레지스터 맵 (S_AXI_BB, 32b)

### CH1 (blackbox_ip)

| 주소 | 이름 | 내용 |
|---|---|---|
| 0x20 | CTRL | W: bit0 START, bit1 INJECT (Golden 0번 beat bit0 반전) |
| 0x24 | IN | `{in_len[27:16], in_base[10:0]}`, len 0~2048 |
| 0x28 | OUT | `{out_len[24:16], out_base[10:0]}`, len 0~256 |
| 0x2C | LATENCY | 클럭 수 |
| 0x30 | STATUS | `{err_start_busy[3], 0, done[1], busy[0]}` |
| 0x40 | CYCLES | 마지막 job의 클럭 수 |
| 0x44 | GOLD_ADDR | 다음 COMMIT이 쓸 Golden 줄 (자동 증가) |
| 0x48 | GOLD_COMMIT | bit0: Golden[GOLD_ADDR] ← WIN |
| 0x4C | WGT | `{w_len[26:16], w_base[9:0]}`, len 0~1024 |
| 0x80~0x9C | WIN | 256b 적재 창 (32b × 8). CH1과 CH2 Golden이 같이 쓴다 |

### CH2 (blackbox_nl)

| 주소 | 이름 | 내용 |
|---|---|---|
| 0x120 | CTRL2 | W: bit0 START, bit1 INJECT, bit2 HS (ch2 store handshake), bit3 PREC (주소 필드 배치) |
| 0x124 | IN2 | `{in_len[27:16], in_base[10:0]}`, len 0~2048 |
| 0x128 | SHAPE2 | `{nb[30:24], h[19:10], w[9:0]}`, 출력 beat 수 = nb·h·w ≤ 256 |
| 0x12C | LATENCY2 | |
| 0x130 | STATUS2 | `{err_start_busy[3], dbg_valid[2], done[1], busy[0]}` |
| 0x140 | CYCLES2 | |
| 0x144 | GOLD_ADDR2 | |
| 0x148 | GOLD_COMMIT2 | bit0: Golden2[GOLD_ADDR2] ← WIN |
| 0x14C | WGT2 | `{w_len[25:16], w_base[8:0]}`, len 0~512 |
| 0x150 | DBG2 | W: `{sel[16], row[10:0]}`로 한 줄 읽기 (sel 0 = input, 1 = weight). STATUS2.dbg_valid가 1이 되면 읽기 완료 |
| 0x160~0x17C | DBG2_DATA | 읽은 256b (32b × 8) |

- 범위를 벗어난 START나 DBG2는 SLVERR로 거절한다.
- 그 채널 묶음의 명령이 진행 중일 때 들어온 START나 DBG2도 SLVERR로 거절한다.

### CMD (S_AXI_CMD, 64b)

LHJ의 `axi_lite_l2_cmd_adapter` 그대로다. 0x000 PUSH (64b 명령, wstrb FF), 0x008 STATUS, 0x020 채널 busy, 0x038 완료 카운터, 0x040 `{fence_error, start_allowed, in_flight}`.

## 6. L2 배치와 명령어

256b 워드 c (15b):

```
c = {grp[2:0], quad[1:0], row[9:0]}
lane b (64b) 의 PS 바이트 주소 = 8 × ((grp<<14) | ((quad*4+b)<<10) | row)
```

| 명령 | opcode | 필드 |
|---|---|---|
| ch1_in LOAD | 1 | L2 `[54:40]`, len-1 `[39:29]`, L1 `[28:18]` |
| ch1_in STORE | 2 | L2 `[55:41]`, len-1 `[40:27]`, L1 `[23:13]` |
| ch2_in LOAD | 3 | L2 `[53:39]`, len-1 `[38:25]`, 목적지 `[23:10]`. L2가 `{c[14:11], c[9:0]}`만 +1 하고 c[10]은 고정 |
| ch2_in STORE | 4 | 시작 w14 `[53:40]`, prec `[57]`, H `[39:30]`, W `[29:20]` |
| ch1_wgt LOAD | 5 | L2 `[53:39]`, len-1 `[38:29]`, WMEM `[28:19]` |
| ch1_wgt STORE | 6 | L2 `[54:40]`, len-1 `[39:27]`, WMEM `[23:14]` |
| ch2_wgt LOAD | 7 | L2 `[54:40]` (+1), len-1 `[39:31]`, 목적지 `[30:22]` |

- `[59:58]`: LOAD는 00 burst, 01 handshake. STORE는 10 burst, 11 handshake.
- ch2 STORE에서 beat (jp, col, h, w)가 저장되는 위치:
  - a14 = w14 + w + h·W + jp·H·W
  - 256b 워드 = `{a14[13:10], col, a14[9:0]}`
  - beat 번호 j = 2·jp + col
  - blackbox_nl은 (jp, h, w)마다 col 0, col 1 순서로 보낸다.
- 공식과 명령어 생성 함수는 `tb/bb256_pkg.sv`에 있다.

## 7. 원본 대신 들어간 수정본 (`rtl/fix/`)

| 파일 | 수정 | 이유 | 확인 |
|---|---|---|---|
| `cmd_decoder_channel_2_wgt.sv` | **(C3)** handshake LOAD의 다음 상태 `ADDR_GEN_LOAD` → `HANDSHAKE_LOAD` | `ADDR_GEN_LOAD`는 보조 FSM의 상태 이름이고 값이 3'd3 = 메인 FSM의 `BURST_LOAD`라서, handshake 명령이 burst 상태로 실행됐다 | T11 |
| | **(C2)** `o_sram_control_mode` → `1'b0` | ch1_wgt의 (C)와 같은 패턴. SRAM 읽기가 다음 줄로 넘어가지 않았다 | T11 |
| `cmd_decoder_channel_1_wgt.sv` | (C) `o_sram_control_mode` → `1'b0` | handshake LOAD가 첫 줄만 반복했다 (share2와 같음) | T2 |
| `cmd_decoder_channel_2_in.sv` | (E1~E4) handshake STORE 동작, 200 MHz 주소 경로 | share2와 같음 | T13~T15 |
| `FIFO_intf_bb.sv` | assign 두 줄을 선언 뒤로 옮김 | LHJ 사본은 선언 전에 신호를 사용해 XSim 컴파일 에러가 났다. 동작은 같다 | 컴파일 |

각 수정이 필요한지는 하나씩 되돌려서 확인했다. 수정을 하나라도 빼면 오른쪽 열의 테스트가 실패한다.

## 8. 결과

### 시뮬레이션 (XSim 2024.2) : 18 / 18 PASS

| 테스트 | 내용 |
|---|---|
| T0 REG | 레지스터, SLVERR |
| T1 / T2 | CH1 weight 1024줄 LOAD → STORE 일치 (burst / handshake) |
| T3 | CH1 input 192 beat LOAD → STORE 일치 |
| T4 / T5 | CH1 실행 → Golden 64 / 256 beat가 L2에서 일치, weight 그대로 |
| T6 | CH1 inject 1비트 검출 |
| T7 | LOAD 중 START 거절, 직후 START, 유실 없음 |
| T8 | L2 맨 위 ↔ L1 끝 / WMEM 끝 |
| T9 | opcode 0 SLVERR |
| T10 / T11 | CH2 weight 512줄 LOAD → DBG2로 전부 일치 (burst / handshake) |
| T12 / T13 | CH2 input 192 beat LOAD → DBG2 일치 (burst / handshake) |
| T14 | CH2 실행. STORE 명령 먼저, NB 3 · H 2 · W 8 = 48 beat가 (ch,h,w) 위치마다 일치, 주변 poison 유지 |
| T15 | CH2 실행. START 먼저, handshake, prec 1, 256 beat (전체 깊이) |
| T16 | CH2 inject 1비트 검출 |
| T17 | CH2 LOAD 중 START2 / DBG2 거절. ch2 STORE 대기 중 CH1 blackbox 실행 |

판정은 TB가 PS처럼 AXI로 읽은 값만으로 한다. 내부 메모리를 직접 보는 것은 진단 출력에만 쓴다. PE와 NoC의 동시 접근은 0회였다.

### 합성 (OOC, xczu9eg-ffvb1156-2-e, 배치 · 배선 후)

| aclk | WNS (ns) | WHS (ns) | 실패 경로 |
|---|---|---|---|
| 100 MHz | +2.559 | +0.021 | 0 |
| 200 MHz | +0.411 | +0.021 | 0 |

| 자원 | 사용 | 비율 |
|---|---|---|
| LUT | 78,290 | 28.6% |
| FF | 56,509 | 10.3% |
| BRAM tile | 308 | 33.8% |
| DSP | 5 | 0.2% |

- BRAM 배분: L2 256, L1 16, CH1 blackbox 12, CH2 blackbox 24.
- 200 MHz의 가장 느린 경로는 L2 원본 ch2_in의 store 주소 계산이다. 새로 만든 모듈은 0.4 ns 이내 목록에 없다.
- 보드 클럭 흔들림 여유(`01_build_synth.bat 200u`)는 아직 돌리지 않았다.

## 9. 아직 안 한 것

- 실보드 (Block Design, bitstream, PS C 코드)
- MAC IP와 nonlinear 엔진 교체. blackbox 자리에 넣으면 되고, pe_busy를 올린 뒤 GUARD 클럭 동안은 메모리에 접근하지 않아야 한다.
