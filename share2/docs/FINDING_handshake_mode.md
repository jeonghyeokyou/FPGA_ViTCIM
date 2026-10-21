# FINDING — handshake 모드 (ctrl_mode 01 / 11) 문제: ch1_in (A)(B), ch1_wgt (C), ch2_in store (E1~E3)

| 항목 | 내용 |
|---|---|
| 종류 | (A) NOC 원본 RTL 과 L2 의 인터페이스 불일치, (B)(C)(E1~E3) L2 원본 RTL 버그 |
| 발견 | (A)(B) 2026-10-06 Phase 2 S6, (C)(E) 2026-10-13 weight / 출력 경로 검증 (W1h, O5) |
| 상태 | **✅ 해결** — (A) `rtl/fix/noc_FIFO_interface_hsfix.v`, (B) `rtl/fix/cmd_decoder_channel_1_in.sv`, (C) `rtl/fix/cmd_decoder_channel_1_wgt.sv`, (E1~E3) `rtl/fix/cmd_decoder_channel_2_in.sv`. [FIX_SUMMARY.md](FIX_SUMMARY.md) 문제 4~7 |
| 심각도 | Medium (burst 모드는 정상. handshake 를 쓰면 시스템이 hang) |

## 결과 요약

| 테스트 | 원본 NOC | NOC 실험 수정 (A만) |
|---|---|---|
| S6a handshake LOAD + burst STORE | **FAIL (LOAD hang)** | PASS (LOAD 1742 clk) |
| S6b burst LOAD + handshake STORE | PASS (STORE 181 clk) | PASS |
| S6c handshake LOAD + handshake STORE | **FAIL (LOAD hang)** | **FAIL (STORE hang)** ← (B) |

## (A) NOC `FIFO_interface.v` 가 handshake 모드에서 `o_FIFO_write_ready_M = 0` 을 낸다

**위치**: `rtl/NOC_260902/FIFO_interface.v` 101~102행 (사본 `verif/noc/rename/noc_FIFO_interface.v` 98~99행)
```verilog
assign o_FIFO_read_ready_M  = i_control_mode ? 1'b0 : w_FIFO_read_ready_on_fire;
assign o_FIFO_write_ready_M = i_control_mode ? 1'b0 : w_FIFO_write_ready_on_fire;
```
**L2 쪽**: `cmd_decoder_channel_1_in.sv` 270행
```verilog
assign o_sram_read_data_ready = r_sram_read_data_ready && i_noc_write_ready;   // = NOC o_FIFO_write_ready
```
handshake LOAD 의 `DATA_FETCH_LOAD` 는 `i_sram_read_response && o_sram_read_data_ready` 를 기다리는데,
NOC 가 ready 를 0 으로 고정하므로 영원히 대기 (trace: `st=4 hs=2 sram_rv=1 sram_rresp=1 sram_rdr=0 noc_wr(fifo)=0`).

**같은 NOC 설계 안에서도 불일치**: `L1_FIFO_interface.v` 는 같은 신호를 handshake 모드에서 `1'b1` 로 낸다.
```verilog
assign o_FIFO_read_ready  = i_pe_busy ? 1'b0 : (w_control_mode_gated ? 1'b1 : w_FIFO_read_ready_on_fire);
assign o_FIFO_write_ready = i_pe_busy ? 1'b0 : (w_control_mode_gated ? 1'b1 : w_FIFO_write_ready_on_fire);
```
**수정**: `verif/blackbox/rtl/fix/noc_FIFO_interface_hsfix.v` (두 줄을 `1'b1` 로) → S6a PASS. 즉 handshake LOAD 의 유일한 막힘 지점이 이것.
어느 쪽(L2 가 이 ready 를 안 봐야 하나, NOC 가 1 을 내야 하나)이 맞는지는 설계자 판단 — **TODO(JH)**

## (B) L2 handshake 보조 FSM 이 "지난 명령의" control_mode 로 다시 출발한다

**위치**: `rtl/L2_260901/cmd_decoder_channel_1_in.sv` 164~171행
```verilog
IDLE_HS: begin
    if(r_control_mode==2'b01) next_state_handshake = DATA_FETCH_LOAD;
    if(r_control_mode==2'b11) next_state_handshake = ADDR_GEN_STORE;
end
```
`r_control_mode` 는 명령 decode 때만 갱신되고 그 뒤에도 값이 남는다. 그래서 handshake LOAD 가 끝나
`CMD_DONE_HS → IDLE_HS` 로 돌아오면, 다음 명령이 오기도 전에 남아 있는 `01` 때문에 곧바로
`DATA_FETCH_LOAD` 로 다시 들어간다. 이후 handshake STORE 가 오면 메인 FSM 은 `HANDSHAKE_STORE`,
보조 FSM 은 `DATA_FETCH_LOAD` 에 머물러 서로 기다림 → hang.
trace (실험 수정본, S6c STORE 직후):
```
c=4174 st=1(IDLE)       hs=2(DATA_FETCH_LOAD)
c=4175 st=1             hs=7(CMD_DONE_HS)
c=4176 st=1             hs=1(IDLE_HS)          <- r_control_mode 아직 01
c=4177 st=2(CMD_DECODE) hs=2(DATA_FETCH_LOAD)  <- STORE 인데 LOAD 쪽으로 출발
c=4178 st=6(HANDSHAKE_STORE) hs=2 ... 이후 변화 없음
```
S6b (burst LOAD 뒤 handshake STORE) 가 통과하는 이유: 남아 있던 값이 `00` 이라 보조 FSM 이 IDLE 에 머묾.
**수정 (적용)**: `verif/blackbox/rtl/fix/cmd_decoder_channel_1_in.sv` — IDLE_HS 전이 조건에 `current_state==CMD_DECODE` 추가.
같은 코드가 `cmd_decoder_channel_1_wgt.sv`, `cmd_decoder_channel_2_in.sv` 에도 있다 → 아래 (C), (E) 의 "고치지 않은 것" 참고.

## (C) ch1_wgt : handshake LOAD 가 첫 줄만 반복해서 보낸다

**증상**: handshake burst LOAD 1024줄 (W1h) 이 끝나기는 하는데 (9230 clk) cluster array 1024줄이 **전부 weight 0번 줄**.
주소는 정상 증가 → L2 가 같은 데이터를 계속 내보냄.

**원인**: `rtl/L2_260901/cmd_decoder_channel_1_wgt.sv` 102행
```verilog
assign o_sram_control_mode = r_control_mode[0];   // ch1_wgt, ch2_in, ch2_wgt 모두 이렇게
```
handshake 명령이면 **L2 내부 SRAM 쪽 FIFO 인터페이스까지 handshake 모드**가 되어 SRAM 읽기 데이터가 다음 것으로
넘어가지 않는다. 같은 handshake FSM 코드를 쓰는 ch1_in 은 이 줄이 `1'b0` (SRAM 쪽은 항상 on-fire) 라서 문제가 없었다
(`cmd_decoder_channel_1_in.sv` 278행). NoC 쪽 모드(`o_noc_control_mode`)는 그대로 handshake.

**수정**: `rtl/fix/cmd_decoder_channel_1_wgt.sv` — 그 한 줄을 `1'b0`. → W1h, W2h(handshake custom), W4h(handshake LOAD → STORE) PASS.

**고치지 않은 것**: ch1_wgt 에도 (B) 와 같은 IDLE_HS 코드가 있다. 하지만 handshake LOAD → handshake STORE 를
간격 10/11/12/13 클럭 (재출발 루프의 모든 위상) 으로 돌려도 hang 이 나지 않아 (W4h, (B) 수정 없이) 바꾸지 않았다.

## (E) ch2_in : handshake STORE (엔진 → L2) 가 동작하지 않는다 — 원인 3개

| | 위치 (`rtl/L2_260901/cmd_decoder_channel_2_in.sv`) | 증상 |
|---|---|---|
| E1 | 295행 `o_sram_control_mode = r_control_mode[0]` ((C) 와 같은 줄) | 내부 FIFO 가 SRAM 쪽으로 빠지지 않아 가득 참 → `DATA_SEND_STORE` 에서 정지 (첫 beat 후 hang) |
| E2 | 273행 메인 FSM `HANDSHAKE_STORE: begin end` — **빠져나가는 조건이 없음** | 마지막 beat 를 써도 busy 가 영원히 1 |
| E3 | 312~313행 저장 주소 오프셋을 `current_state==BURST_STORE` 일 때만 계산, 그 외 0 | E1·E2 를 고치면 끝나긴 하지만 **모든 beat 가 시작 주소 한 곳에 덮어써짐** (16워드 중 1워드만, 마지막 값) |

**디버깅**: `+TRACE2` 로 ch2 FSM 을 찍어 E1 을 찾았다 (L2 가 beat 를 받고 응답도 냈지만 hs=5 에서 정지, SRAM 쓰기 valid 는 1 인데
빠지지 않음). E1·E2 를 고치자 명령은 끝났지만 CP-B 가 "word 0 만 다른 값, 나머지는 poison" → 주소 계산을 의심 → E3.

**수정**: `rtl/fix/cmd_decoder_channel_2_in.sv` (E1 `1'b0`, E2 `if (r_sram_write_done) CMD_DONE`, E3 `BURST_STORE || HANDSHAKE_STORE`)
→ O5 (handshake out8 + 다시 LOAD 해서 비교), O6 (handshake 연속, 리셋 없이) PASS. 셋 중 하나만 빼도 O5/O6 FAIL (FIX_SUMMARY 표).

**고치지 않은 것**: ch2_in 에도 IDLE_HS 패턴이 있다. handshake STORE 연속(O6)은 문제없었고, handshake LOAD (L2 → Accumulator)
는 이 환경에 받는 쪽이 없어 확인할 수 없어서 바꾸지 않았다. ch2_wgt 도 `o_sram_control_mode = r_control_mode[0]` 이다 (범위 밖).

## 재현
```
scripts\09_run_bb_integ_orig.bat   -> S6a/S6c/S6d/S7, W1h/W2h/W4h, O5/O6 FAIL (수정 전 재현)  /  01_run_bb_integ.bat -> 전부 PASS
cd scripts\work_integ & xsim bb_integ_snap --testplusarg "ONLY=O5" --testplusarg "TRACE2=300" --tclbatch ../run_nowave.tcl
cd scripts\work_integ & xsim bb_integ_snap --testplusarg "ONLY=S6" --testplusarg "TRACE=40" --tclbatch ../run_nowave.tcl
(수정 하나씩 빼 보기는 FIX_SUMMARY.md 표 참고)
```

## 영향
- 원본 RTL 로는 **burst 모드만 사용**해야 한다. `rtl/fix/` 사본을 쓰면 ch1_in / ch1_wgt / ch2_in(store) 모두 handshake 동작.
- handshake LOAD 는 beat 당 약 9 클럭 (1742 clk / 192 beat) 으로 burst(약 1 클럭/beat)보다 훨씬 느리지만,
  busy↓ 시점에 L1 쓰기가 이미 끝나 있어 FINDING_busy_fall_before_l1_write 문제는 없다.
