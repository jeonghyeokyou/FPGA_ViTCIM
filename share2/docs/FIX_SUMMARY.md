# FIX_SUMMARY — Blackbox 환경에서 찾은 문제와 해결 (2026-10-06, weight / 출력 경로 추가 2026-10-13)

원본(`rtl/`, `LHJ/`)은 한 줄도 바꾸지 않았다. 수정은 전부 `verif/blackbox/` 안의 **별도 파일**이고,
기본 파일 목록(`scripts/files_bb_sim.f`, `files_bb_synth.f`)이 이 수정본을 쓴다.
수정 전 동작은 `scripts/09_run_bb_integ_orig.bat` (`files_bb_sim_orig.f` + `-d BB_ORIG_MUX`) 로 언제든 재현된다.

## 한눈에

| # | 문제 | 어디 문제인가 | 해결 파일 | 결과 |
|---|---|---|---|---|
| 1 | ch0(64b) 와 ch1_in(512b) 의 L2 배치가 다름 | 사양 가정 (RTL 정상) | `tb/bb_pkg.sv`, `scripts/gen_vectors.py` (lane 별 주소) | S1~S5 통과로 공식 검증 |
| 2 | 원본 `L1_FIFO_intf.v` elaborate 실패 | NOC 원본 | `rtl/noc_L1_FIFO_intf.v` (없는 파라미터 제거) | 컴파일 OK |
| 3 | LOAD busy↓ 직후 START 하면 마지막 입력 beat 유실 | NOC 파이프라인 + mux | `rtl/l1_port_mux.sv` | S4 gap0 FAIL → PASS |
| 4 | handshake LOAD hang | NOC `FIFO_interface` ↔ L2 불일치 | `rtl/fix/noc_FIFO_interface_hsfix.v` | S6a FAIL → PASS |
| 5 | handshake LOAD→STORE 연속 시 hang | L2 `cmd_decoder_channel_1_in` | `rtl/fix/cmd_decoder_channel_1_in.sv` | S6c/S6d/S7 FAIL → PASS |
| 6 | **weight** handshake LOAD 가 첫 줄만 반복 (C) | L2 `cmd_decoder_channel_1_wgt` | `rtl/fix/cmd_decoder_channel_1_wgt.sv` (1줄) | W1h/W2h/W4h FAIL → PASS |
| 7 | **출력** ch2_in handshake STORE 불능 (E1~E3) | L2 `cmd_decoder_channel_2_in` | `rtl/fix/cmd_decoder_channel_2_in.sv` (3곳) | O5/O6 FAIL → PASS |

burst 모드의 weight / 출력 경로 (W1~W4, O1~O4, O7, O8) 는 **원본 RTL 그대로 처음부터 PASS** — 문제는 handshake 에만 있었다.
weight START 간격 0 (W3) 은 문제 3 의 mux 수정으로 통과한다 (원래 mux 로는 weight 경로에서도 마지막 줄 유실).

### 테스트벤치에서 찾은 문제 (RTL 아님, 결과 판정에 영향)

| 문제 | 영향 | 처리 |
|---|---|---|
| `psum ? "psum16.hex" : "out8.hex"` — 길이가 다른 문자열 리터럴의 `?:` 는 짧은 쪽 앞에 공백을 채운다 → `"  out8.hex"` 파일 열기 실패 | Golden 이 전부 X. L2 에도 X 가 써져서 **X === X 로 비교가 "같음"** → O2/O7 이 아무것도 검증하지 않고 PASS 로 찍힘 (거짓 PASS) | if/else 로 바꿈 + **모든 테스트가 읽은 벡터에 X 가 하나라도 있으면 FAIL** 하도록 검사 추가 |
| `cond ? $sformatf(...) : "문자열"` | XSim 2024.2 커널이 FATAL_ERROR 로 종료 | if/else 로 바꿈 |
## 수정 전 / 후 (Phase 2, 같은 TB, 같은 hex)

| 테스트 | 수정 전 (`09_run_bb_integ_orig.bat`) | 수정 후 (`01_run_bb_integ.bat`) |
|---|---|---|
| R0, S1, S2×3, S3, S5×2, S6b | PASS | PASS |
| S4 burst, START 간격 0 | **FAIL** (CP-A 1, beat 191 유실) | PASS |
| S6a handshake LOAD | **FAIL** (LOAD hang) | PASS (LOAD 1742 clk) |
| S6c handshake LOAD+STORE | **FAIL** | PASS |
| S6d handshake 2회 연속 (리셋 없이) | **FAIL** | PASS |
| S7 handshake + 간격 0 | **FAIL** | PASS |
| W1, W2×4 (burst / custom), W4 (store) | PASS | PASS |
| W3 weight, START 간격 0 | **FAIL** (원래 mux) | PASS |
| W1h, W2h, W4h×4 (weight handshake) | **FAIL** (원본은 NoC (A) 때문에 LOAD hang, (A) 만 고치면 (C) 의 "첫 줄 반복") | PASS |
| O1~O4, O7, O8 (ch2 burst store) | PASS | PASS |
| O5, O6 (ch2 handshake store) | **FAIL** | PASS |
| 합계 (MAP 포함 36개) | 22 / 36 (실측, `09_run_bb_integ_orig.bat`) | **36 / 36** |

Phase 3 (PS 인터페이스, AXI4 + AXI-Lite): 수정 후 **21/21 PASS** (REG, MAP, PW1~3, PO1~3, S1~S7).
Phase 1: 10/10 PASS (ch2 출력 U8~U10 추가). 전체 실행 동안 PE/NoC L1 포트 충돌 0 회 (TB 감시, 입력·weight 둘 다).

### 어떤 수정이 어떤 실패를 고쳤나 (하나씩 빼 본 실험)

| 조합 | S4 | S6a | S6c / S6d |
|---|---|---|---|
| 수정 없음 | FAIL | FAIL | FAIL |
| 3 만 빼기 (mux 원래대로, 나머지 수정) | **FAIL** | PASS | PASS |
| 4 만 적용 (NoC 수정만) | — | PASS | **FAIL** (S6c STORE hang, S6d 는 이 조합에서 미실행) |
| 5 만 적용 (L2 수정만) | — | **FAIL** | **FAIL** (LOAD hang) |
| 3+4+5 | PASS | PASS | PASS |

→ 각 수정은 자기 문제만 고치고, 셋 다 있어야 전부 통과한다.

weight / 출력 수정도 같은 방식으로 하나씩 되돌려 봤다 (`scripts/10_run_ablate.ps1`):

| 되돌린 것 | 실패하는 테스트 |
|---|---|
| 원본 전부 | W1h, W2h, W3, W4h×4 / O5, O6 |
| (C) ch1_wgt SRAM 모드 | W1h, W2h, W4h×4 |
| (E1) ch2 SRAM 모드 | O5, O6 |
| (E2) HANDSHAKE_STORE 종료 조건 | O5, O6 |
| (E3) handshake 저장 주소 | O5, O6 |

처음엔 ch1_in (B) 와 같은 IDLE_HS 수정도 ch1_wgt / ch2_in 에 넣었지만, 되돌려도 아무 테스트도 실패하지 않아
(ch1_wgt 는 handshake LOAD→STORE 간격 10~13 클럭 전부 PASS) **증거가 없는 수정이라 뺐다.**

---

## 문제 3 — busy↓ 직후 START 시 입력 마지막 beat 유실

**디버깅 과정**
1. S4 에서 CP-A 가 beat 191 하나만 불일치, 값은 TB 가 미리 심어둔 poison → "LOAD 가 그 beat 를 안 썼다".
2. LOAD busy↓ 순간 L1 을 보니 190/192 beat 만 들어와 있음 → NoC 는 posted write, 2 beat 가 아직 이동 중.
3. START 간격을 0~6 으로 바꿔 보니 0 만 실패 → 남은 쓰기는 busy↓ 후 2 클럭 안에 끝남.
4. "게이트에서 버려진 쓰기" 카운터(`L1_FIFO_interface` 출력 valid && pe_busy)는 0 → 게이트는 통과했다.
   SRAM 에 실제로 쓰인 시점을 찍어 보니 마지막 쓰기는 busy↓+2 엣지 = pe_busy 가 이미 1 인 클럭.
5. 결론: `L1_FIFO_interface` 는 pe_busy 로 **새 요청**을 막지만, 그 뒤 `noc_sram_controller` 가
   ceb/web/addr/din 을 **레지스터로 한 번 더** 잡는다. pe_busy 가 올라간 클럭에 이 레지스터에 남아 있던
   접근 1개를 `l1_port_mux` 가 PE 쪽으로 바꿔버려 사라졌다.

**수정** (`rtl/l1_port_mux.sv`, 우리 파일)
```verilog
wire sel_pe = i_pe_busy && i_noc_ceb;   // 원래: i_pe_busy
```
pe_busy 가 1 이어도 NoC 쪽에 이미 출발한 접근(ceb=0)이 있으면 그 클럭만 NoC 가 쓴다.
- 안전한 이유: pe_busy=1 이후 NoC 가 새 요청을 내지 못하므로 남는 것은 최대 1클럭. PE 는 pe_busy 를 올린 뒤
  GUARD(2) 클럭 동안 SRAM 에 접근하지 않으므로 둘이 겹칠 수 없다. 겹치면 `o_pe_conflict` 가 1 이 되는데
  모든 테스트에서 0 회.
- 실제 MAC IP 를 붙일 때의 규칙: **pe_busy 를 올린 뒤 최소 1 클럭은 L1 에 접근하지 말 것** (blackbox 는 GUARD=2).
- 수정 후 sweep: 간격 0~6 모두 PASS, 마지막 NoC 쓰기는 여전히 busy↓+2 에 정상 기록됨.

## 문제 4 — handshake LOAD hang (NoC 쪽)

**디버깅 과정**: `+TRACE` 로 명령 직후 40 클럭을 찍으니 L2 가 `HANDSHAKE_LOAD / DATA_FETCH_LOAD` 에서
`sram_read_response=1` 인데 `o_sram_read_data_ready=0` 으로 멈춤. 이 ready 는
`r_sram_read_data_ready && i_noc_write_ready` 이고, `i_noc_write_ready` (= NoC `o_FIFO_write_ready`) 가
명령 시작과 동시에 0 으로 떨어짐. NoC `FIFO_interface.v` 가 handshake 모드에서 이 신호를 `1'b0` 으로 고정.
같은 NOC 설계의 `L1_FIFO_interface.v` 는 같은 자리에 `1'b1` 을 낸다.

**수정** (`rtl/fix/noc_FIFO_interface_hsfix.v`, `noc_FIFO_interface` 사본, 2줄)
```verilog
assign o_FIFO_read_ready_M  = i_control_mode ? 1'b1 : w_FIFO_read_ready_on_fire;   // 1'b0 -> 1'b1
assign o_FIFO_write_ready_M = i_control_mode ? 1'b1 : w_FIFO_write_ready_on_fire;  // 1'b0 -> 1'b1
```
burst 모드(control_mode=0) 경로는 그대로라 R0~S5 결과 동일.

## 문제 5 — handshake LOAD 뒤 handshake STORE hang (L2 쪽)

**디버깅 과정**: 문제 4 를 고치자 LOAD 는 통과, 이번엔 STORE 에서 멈춤. trace:
```
c=4175 hs=CMD_DONE_HS -> c=4176 hs=IDLE_HS -> c=4177 hs=DATA_FETCH_LOAD (명령은 STORE 인데!)
c=4178 메인 FSM = HANDSHAKE_STORE, 보조 FSM = DATA_FETCH_LOAD ... 영원히
```
보조 FSM 의 `IDLE_HS` 는 `r_control_mode` 만 보고 출발하는데, 이 레지스터는 지난 명령(LOAD=01) 값이 남아
있다. 그래서 LOAD 가 끝나자마자 명령 없이 재출발했고, 그 사이 STORE 가 오자 서로 기다렸다.
(burst LOAD 뒤 handshake STORE(S6b) 는 남은 값이 00 이라 통과했던 것.)

**수정** (`rtl/fix/cmd_decoder_channel_1_in.sv`, L2 사본, 조건 2곳)
```verilog
if(current_state==CMD_DECODE && r_control_mode==2'b01) next_state_handshake = DATA_FETCH_LOAD;
if(current_state==CMD_DECODE && r_control_mode==2'b11) next_state_handshake = ADDR_GEN_STORE;
```
새 명령을 decode 하는 클럭에만 출발. r_control_mode 는 그 직전 엣지에 latch 되므로 값은 새 명령 것이고,
출발 클럭도 원본의 첫 명령과 같다 (타이밍 변화 없음). 리셋 없이 handshake 를 연속으로 돌린 S6d 로 확인.

**같은 패턴이 남아 있는 곳 (이번 범위 밖, 미수정)**: `cmd_decoder_channel_1_wgt.sv` 653행,
`cmd_decoder_channel_2_in.sv` 178행. ch1_wgt / ch2 를 handshake 로 쓸 때 같은 수정이 필요할 것.

## 문제 6 — weight handshake LOAD 가 첫 줄만 반복 (C)

**디버깅**: W1h 에서 1024줄 중 1줄만 맞음 → 실패 시 L1 각 줄에 "실제로 몇 번 weight 줄이 들어 있는지" 찾는 진단을 추가 →
**전부 weight 0번 줄**. 주소는 맞게 증가하므로 L2 가 같은 데이터를 계속 보냄. ch1_in 과 ch1_wgt 의 handshake FSM 코드는
똑같았고, 차이는 `o_sram_control_mode` 한 줄: ch1_in 은 `1'b0` (L2 내부 SRAM 쪽은 항상 on-fire), ch1_wgt 는
`r_control_mode[0]` (handshake 명령이면 SRAM 쪽 FIFO 인터페이스도 handshake 모드 → 읽기 데이터가 넘어가지 않음).

**수정**: ch1_in 과 같게 `1'b0`. NoC 쪽 모드는 그대로 handshake.

## 문제 7 — 출력 ch2_in handshake STORE (E1~E3)

**디버깅** (`+TRACE2` 로 ch2 FSM 추적):
1. Blackbox 가 첫 beat 를 보내고 L2 가 응답 펄스까지 냈는데 `DATA_SEND_STORE` 에서 영원히 정지. 내부 FIFO 의 SRAM 쓰기 valid 는 1 인데
   빠지지 않음 → 문제 6 과 같은 `o_sram_control_mode` (E1).
2. 메인 FSM `HANDSHAKE_STORE` 블록이 비어 있어 빠져나갈 수 없음 (E2, RTL 리뷰로 발견 → BURST_STORE 와 같은 종료 조건).
3. E1·E2 를 고치니 명령은 끝났지만 CP-B 가 "word 0 만 바뀌고 나머지 15워드는 poison 그대로" → 모든 beat 가 같은 주소에 써짐 →
   저장 주소 오프셋 `w + h·W + ch·H·W` 가 `current_state==BURST_STORE` 일 때만 계산되고 아니면 0 (E3).

**수정**: 세 곳 모두 `rtl/fix/cmd_decoder_channel_2_in.sv`. burst STORE / LOAD 경로는 변화 없음.

## 합성 영향
입력 · weight · 출력 경로를 모두 넣고 수정본으로 합성 (OOC, ZCU102, 100 MHz, 2026-10-13):
LUT 28.4% / FF 10.5% / BRAM 316.5 (34.7%) / DSP 4, **WNS +1.569 ns, WHS +0.021 ns — 타이밍 만족.**
SRAM 쪽 모드를 상수로 고정한 수정 (C, E1) 덕분에 L2 LUT 는 오히려 줄었다 (68.2k, 입력만 있던 이전 합성은 81.7k).
최악 경로는 `l1_port_mux` 수정이 만든 NoC `r_ceb` → L1 BRAM 주소 경로 (+1.569 ns, 로직 1단). README 7절.

## 200 MHz 타이밍 수정 (2026-10-20) — 기능 변화 없음

200 MHz (5 ns) 로 구현하면 실패 경로는 없었지만 **WNS +0.002 ns** 로 여유가 없었다. 막는 경로는 L2 ch2_in 의
store 주소 계산 (`r_fifo_noc_read_addr`, 4.98 ns, 로직 20단):

| 구간 | 지연 | 내용 |
|---|---|---|
| ① | ≈1.2 ns | 입력 FIFO `wr_ptr` 비교 (empty) → `i_noc_read_valid` → h / w / ch 필드를 0 으로 막는 mux |
| ② | ≈1.5 ns | DSP `h × W` |
| ③ | ≈1.0 ns | DSP `+ ch × (H·W) + w` |
| ④ | ≈1.2 ns | `addr > offset ? addr − offset + first − 1 : addr + start` |

**수정 (지연 / 인터페이스 변화 없음)**

| ID | 파일 | 내용 |
|---|---|---|
| E4 | `rtl/fix/cmd_decoder_channel_2_in.sv` | ① 필드의 valid · store 상태 게이팅 제거 (값은 어차피 valid 이고 store 상태일 때만 레지스터에 들어감 → 기능 동일, E3 도 이 안에 포함). ④ 의 `first − 1 − offset` 을 명령 받을 때 `r_wrap_k` 로 미리 계산 → 덧셈 1단 감소 |
| P3 | `rtl/blackbox_pe.sv` | 512b 비교 결과를 1클럭 레지스터 (p3) 에 담은 뒤 mismatch 카운터 / first_* 갱신. 파이프라인 drain 조건에 p3 포함 |
| — | `scripts/build_synth_bb.tcl` | place / route 뒤 `phys_opt_design` 추가. `-tclargs <period> [<uncertainty>]` |

**확인**
- Phase 1 / 2 / 3 : 10/10, 36/36, 21/21 PASS. 하나씩 빼 본 실험 결과도 전과 같음 (E1 / E2 / E3 각각 O5, O6 실패).
  `10_run_ablate.ps1` 의 E3 되돌리기 패턴은 E4 에 맞게 바꿨다 (주소식 앞에 `BURST_STORE` 게이트를 다시 넣음).
- E4 의 주소식은 이전 식과 무작위 200만 건 비교 → **불일치 0** (wrap 쪽 분기 150만 건 포함). wrap 분기는 기존 TB 에서
  쓰이지 않아 (ch2 목적지가 14b 라 17b 끝을 넘지 않음) 이 비교로 따로 확인했다.

| 200 MHz, post-route | WNS | WHS | 가장 느린 경로 |
|---|---|---|---|
| 수정 전 | +0.002 ns | +0.019 ns | ch2_in 주소 계산, 4.98 ns, 20단 |
| 수정 후 | **+0.357 ns** | +0.021 ns | ch2_in 주소 계산, 4.63 ns, 16단 (출발점이 FIFO 비교 → FIFO 레지스터) |
| 수정 후 + uncertainty 0.15 ns | **+0.284 ns** | +0.011 ns | L2 ch2_in `sram_controller` `del2_i_read_valid` → 로직 1단, 배선 4.37 ns (fanout) |

uncertainty 0.15 ns 는 보드에서 PS 클럭 jitter 등을 미리 반영해 본 것. 이것까지 만족하므로 실보드 200 MHz 를 기대할 수 있다
(그래도 BD 전체 구현 결과로 최종 확인 필요). 남는 경로는 모두 L2 원본 쪽이고 우리 모듈은 +0.4 ns 안쪽 목록에 없다.
L2 설계자에게 넘길 변경은 E4 한 곳 (위 표) — 기능 동일 · 지연 동일이라 원본에 그대로 반영 가능.
