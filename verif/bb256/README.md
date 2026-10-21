# bb256 : 256b blackbox 시스템 (CH1 + CH2, LHJ/261020 구조 기반)

모든 채널(ch1_in, ch1_wgt, ch2_in, ch2_wgt)을 256b로 통일했다. blackbox는 연산을 하지 않고 동작만 모사한다. 하는 일은 weight 저장, input 읽기, PS가 넣어둔 Golden 출력뿐이다.

```
PS ─S_AXI_DATA─> L2 1 MiB (ch0)
PS ─S_AXI_CMD──> L2 명령 (opcode 1~7)
PS ─S_AXI_BB───> blackbox 제어, Golden 적재, CH2 디버그 읽기

CH1 (linear / MAC 자리) : blackbox_ip
  L2 ch1_in  (256b) ─> L1 (256b x 2048) <──> blackbox_ip : input 읽기, Golden 을 L1 OUT 에 쓰기
  L2 ch1_wgt (256b) ─> blackbox_ip 내부 weight 메모리 (256b x 1024)   (ch1_wgt STORE 로 다시 읽기 가능)
  출력 : L1 OUT ─ ch1_in STORE ─> L2

CH2 (nonlinear 자리) : blackbox_nl
  L2 ch2_in  LOAD (256b) ─> blackbox_nl 내부 input 메모리  (256b x 2048, NoC 주소 하위 11b)
  L2 ch2_wgt LOAD (256b) ─> blackbox_nl 내부 weight 메모리 (256b x 512)
  출력 : blackbox_nl ─ Golden ─> L2 ch2_in STORE 포트 (BB 가 master, 주소 {last, ch, h, w})
  확인 : ch2 에는 weight / input 을 되돌리는 STORE 가 없으므로 BB 레지스터의 DBG2 창으로 한 줄씩 읽는다
```

- 명령은 한 번에 하나만 L2에 들어간다.
- blackbox와 명령은 채널 묶음별로 서로 막는다.
  - CH1 명령(1, 2, 5, 6)은 blackbox_ip와 동시에 실행되지 않는다.
  - CH2 LOAD(3, 7)는 blackbox_nl과 동시에 실행되지 않는다.
  - ch2_in STORE(4)는 blackbox_nl의 출력 경로이므로 blackbox_nl이 실행 중이어도 받는다. STORE 명령이 blackbox_nl을 기다리는 동안 CH1 blackbox는 따로 실행할 수 있다.

## 폴더

| 경로 | 내용 |
|---|---|
| `rtl/base/` | LHJ/261020 사본 (수정 안 함) |
| `rtl/fix/FIFO_intf_bb.sv` | assign 위치만 옮김. LHJ 사본은 선언 전에 신호를 사용해 XSim 컴파일 에러가 남 |
| `rtl/fix/cmd_decoder_channel_1_wgt.sv` | share2 수정본 (C) |
| `rtl/fix/cmd_decoder_channel_2_in.sv` | share2 수정본 (E1~E4) |
| `rtl/fix/cmd_decoder_channel_2_wgt.sv` | **새 수정본 (C2, C3)**, 아래 "찾은 문제" 참고 |
| `rtl/bb256/blackbox_ip.sv` | CH1 blackbox |
| `rtl/bb256/blackbox_nl.sv` | CH2 blackbox (input/weight 메모리, ch2 store master, 디버그 읽기) |
| `rtl/bb256/noc_wr_adapter.sv` | ch2_in / ch2_wgt LOAD용 쓰기 전용 adapter |
| `rtl/bb256/axi_lite_bb_ctrl.sv` | BB 레지스터 (CH1 뱅크 + CH2 뱅크) |
| `rtl/bb256/l2_noc_bb_core.sv` | 전체 연결, 채널별 fence |
| `rtl/bb256/l2_system_top.sv` | `ALLOWED_OPCODES = 8'hFE`. 포트는 LHJ와 같음 |
| `rtl/bb256/noc_ch1_wgt_adapter.sv` | share2 사본 |
| `rtl/model_sim/` | 시뮬레이션용 메모리 모델 |
| `tb/` | `bb256_pkg.sv` (주소 공식, 명령어), `tb_bb256_system.sv` (T0~T17) |
| `scripts/00_run_sim.bat` | 실행 스크립트. `wave` 인자를 주면 파형도 저장 |

## BB 레지스터 (S_AXI_BB, 32b)

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
| 0x124 | IN2 | `{in_len[27:16], in_base[10:0]}`, input 메모리 len 0~2048 |
| 0x128 | SHAPE2 | `{nb[30:24], h[19:10], w[9:0]}`, 출력 beat 수 = nb·h·w ≤ 256 |
| 0x12C | LATENCY2 | |
| 0x130 | STATUS2 | `{err_start_busy[3], dbg_valid[2], done[1], busy[0]}` |
| 0x140 | CYCLES2 | |
| 0x144 | GOLD_ADDR2 | |
| 0x148 | GOLD_COMMIT2 | bit0: Golden2[GOLD_ADDR2] ← WIN |
| 0x14C | WGT2 | `{w_len[25:16], w_base[8:0]}`, weight 메모리 len 0~512 |
| 0x150 | DBG2 | W: `{sel[16], row[10:0]}`로 한 줄 읽기 (sel 0 = input, 1 = weight). STATUS2.dbg_valid가 1이 되면 읽기 완료 |
| 0x160~0x17C | DBG2_DATA | 읽은 256b (32b × 8) |

- 범위를 벗어난 START나 DBG2는 SLVERR로 거절한다.
- 그 채널 묶음의 명령이 진행 중일 때 들어온 START나 DBG2도 SLVERR로 거절한다.

## L2 배치와 명령어 (256b 워드 c, 15b)

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
- 공식은 `tb/bb256_pkg.sv`에 있다.

## 찾은 문제 (이번 작업)

| # | 위치 | 문제 | 해결 | 확인 |
|---|---|---|---|---|
| C3 | `cmd_decoder_channel_2_wgt.sv` (원본, LHJ 동일) | CMD_DECODE에서 handshake LOAD의 다음 상태가 `ADDR_GEN_LOAD`다. 이것은 보조 FSM의 상태 이름이고 값이 3'd3 = 메인 FSM의 `BURST_LOAD`라서, handshake 명령이 burst 상태로 실행된다 | `HANDSHAKE_LOAD` | T11 |
| C2 | 같은 파일 | `o_sram_control_mode = r_control_mode[0]`. ch1_wgt의 (C)와 같은 패턴이다 | `1'b0` | T11 |
| - | LHJ `FIFO_intf_bb.sv` 외 3개 | 선언 전에 신호를 사용해 XSim 컴파일 에러가 난다 | 선언 순서 정리 | 컴파일 |

수정이 각각 필요한지는 하나씩 되돌려서 확인했다.

- C2만 되돌리거나 C3만 되돌려도 T11이 실패한다.
- ch1_wgt (C)를 되돌리면 T2부터 실패한다.
- ch2_in (E)를 되돌리면 T13부터 실패한다.

## 결과 (2026-10-21, XSim 2024.2) : 18 / 18 PASS

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
| T12 / T13 | CH2 input 192 beat LOAD → DBG2 일치 (burst / handshake, 목적지 1024~) |
| T14 | CH2 실행. STORE 명령 먼저, NB 3 · H 2 · W 8 = 48 beat가 (ch,h,w) 위치마다 일치, 주변 poison 유지 |
| T15 | CH2 실행. START 먼저, handshake, prec 1, NB 4 · H 8 · W 8 = 256 beat (전체 깊이) |
| T16 | CH2 inject 1비트 검출 |
| T17 | CH2 LOAD 중 START2 / DBG2 거절. ch2 STORE 대기 중 CH1 blackbox 실행 |

PE와 NoC의 동시 접근은 0회였다.

## 합성 (OOC, xczu9eg-ffvb1156-2-e, 배치 · 배선 후, 2026-10-21)

실행 방법:

```
cd scripts
"C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_synth.tcl -log build/vivado.log -journal build/vivado.jou
"C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_synth.tcl -log build_200MHz/vivado.log -journal build_200MHz/vivado.jou -tclargs 5.0
```

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

- BRAM 배분: L2 256, L1 16, CH1 blackbox 12 (weight 1024줄 + Golden), CH2 blackbox 24 (input 2048줄 + weight 512줄 + Golden).
- 200 MHz의 가장 느린 경로는 L2 원본 ch2_in의 store 주소 계산이다. share2에서 (E4)로 줄였던 경로다. 새로 만든 모듈은 0.4 ns 이내 목록에 없다.
- 처음 구현에서는 새 모듈 두 곳이 200 MHz를 막았다 (WNS −0.27 ns). 둘 다 레지스터를 넣어 고쳤다. 기능과 인터페이스 타이밍은 같고 T0~T17도 다시 통과했다.
  - `blackbox_nl`: `o_c2_valid = (st == S_C2_SEND)` 비교가 L2 ch2_in 입력 FIFO 전체의 write enable로 퍼졌다. valid와 addr를 레지스터로 바꿨다.
  - `axi_lite_bb_ctrl`: 범위 검사의 `nb*h*w` 곱셈이 조합논리로 바로 판정에 들어갔다. 2단 레지스터로 바꿨다.
- 보드 클럭 흔들림을 가정한 추가 여유 (`-tclargs 5.0 0.15`)는 이번에는 돌리지 않았다.
