# FINDING — ch1_in handshake 모드 (LOAD 01 / STORE 11) 가 멈춘다: 독립된 원인 2개 (S6)

| 항목 | 내용 |
|---|---|
| 종류 | (A) NOC 원본 RTL 과 L2 의 인터페이스 불일치, (B) L2 원본 RTL 버그 |
| 발견 | 2026-10-06, Phase 2 S6 (handshake 모드는 이전까지 한 번도 검증 안 됨) |
| 상태 | **✅ 해결 (2026-10-06)** — (A) `rtl/fix/noc_FIFO_interface_hsfix.v`, (B) `rtl/fix/cmd_decoder_channel_1_in.sv` 를 기본 파일 목록에 적용. S6a~S6d, S7 PASS. [FIX_SUMMARY.md](FIX_SUMMARY.md) 문제 4·5 |
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
같은 패턴이 `cmd_decoder_channel_1_wgt.sv`, `cmd_decoder_channel_2_in.sv` 에도 있음 (범위 밖, 미수정).

## 재현
```
scripts\09_run_bb_integ_orig.bat   -> S6a/S6c/S6d/S7 FAIL (수정 전 재현)  /  01_run_bb_integ.bat -> 전부 PASS (수정 후)
cd scripts\work_integ & xsim bb_integ_snap --testplusarg "ONLY=S6" --testplusarg "TRACE=40" --tclbatch ../run_nowave.tcl
(수정 하나씩 빼 보기는 FIX_SUMMARY.md 표 참고)
```

## 영향
- 지금은 **burst 모드만 사용**해야 한다 (PS C 코드 / meta.json 의 `load_burst`, `store_burst`).
- handshake LOAD 는 beat 당 약 9 클럭 (1742 clk / 192 beat) 으로 burst(약 1 클럭/beat)보다 훨씬 느리지만,
  busy↓ 시점에 L1 쓰기가 이미 끝나 있어 FINDING_busy_fall_before_l1_write 문제는 없다.
