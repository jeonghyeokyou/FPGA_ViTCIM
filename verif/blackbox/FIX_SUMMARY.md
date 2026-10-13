# FIX_SUMMARY — Blackbox 환경에서 찾은 문제와 해결 (2026-10-06)

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

## 수정 전 / 후 (Phase 2, 같은 TB, 같은 hex)

| 테스트 | 수정 전 (`09_run_bb_integ_orig.bat`) | 수정 후 (`01_run_bb_integ.bat`) |
|---|---|---|
| R0, S1, S2×3, S3, S5×2, S6b | PASS | PASS |
| S4 burst, START 간격 0 | **FAIL** (CP-A 1, beat 191 유실) | PASS |
| S6a handshake LOAD | **FAIL** (LOAD hang) | PASS (LOAD 1742 clk) |
| S6c handshake LOAD+STORE | **FAIL** | PASS |
| S6d handshake 2회 연속 (리셋 없이) | **FAIL** | PASS |
| S7 handshake + 간격 0 | **FAIL** | PASS |
| 합계 | 9 / 14 | **14 / 14** |

Phase 3 (PS 인터페이스, AXI4 + AXI-Lite): 수정 후 **REG + S1~S7 14/14 PASS**.
Phase 1: 7/7 PASS (변화 없음). 전체 실행 동안 PE/NoC L1 포트 충돌 0 회 (TB 감시).

### 어떤 수정이 어떤 실패를 고쳤나 (하나씩 빼 본 실험)

| 조합 | S4 | S6a | S6c / S6d |
|---|---|---|---|
| 수정 없음 | FAIL | FAIL | FAIL |
| 3 만 빼기 (mux 원래대로, 나머지 수정) | **FAIL** | PASS | PASS |
| 4 만 적용 (NoC 수정만) | — | PASS | **FAIL** (S6c STORE hang, S6d 는 이 조합에서 미실행) |
| 5 만 적용 (L2 수정만) | — | **FAIL** | **FAIL** (LOAD hang) |
| 3+4+5 | PASS | PASS | PASS |

→ 각 수정은 자기 문제만 고치고, 셋 다 있어야 전부 통과한다.

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

## 합성 영향
수정본으로 다시 합성 (OOC, ZCU102, 100 MHz): LUT 32.1% / FF 11.6% / BRAM 301 (33.0%, 변화 없음) / DSP 0,
**WNS +1.280 ns, WHS +0.019 ns — 타이밍 만족.** 최악 경로는 수정 전과 같은 L2 ch2_in 경로 (수정과 무관). README 6절.
