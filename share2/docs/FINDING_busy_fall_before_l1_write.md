# FINDING — LOAD 의 `o_busy_channel_1_in` 이 내려간 뒤에도 L1 SRAM 쓰기가 2클럭 더 남아 있다 (S4)

| 항목 | 내용 |
|---|---|
| 종류 | 시스템 통합 문제 (L2 완료 신호 의미 + NOC 파이프라인 + pe_busy 게이팅). 12절-② 미결 항목의 실제 증거 |
| 발견 | 2026-10-06, Phase 2 S4 (LOAD→START 간격 0) |
| 상태 | **✅ 해결 (2026-10-06)** — `rtl/l1_port_mux.sv` 에서 NoC 의 진행 중 접근을 우선. S4 / SWEEP 간격 0~6 전부 PASS. [FIX_SUMMARY.md](FIX_SUMMARY.md) 문제 3 |
| 심각도 | High (실제 MAC IP 가 busy↓ 직후 시작하면 입력 마지막 beat 가 조용히 사라짐) |

## 1. 증상
`tb_l2_noc_bb.sv` S4: LOAD 의 busy↓ 바로 다음 클럭에 START.
```
[2] LOAD cmd->busy fall : 207 clk ; L1 IN at busy fall : 190/192 beats == X
[3] BB   CP-A mismatch=1 first_idx=191  got=dead00bf (TB가 심어둔 poison)  exp=802826c8
```
**마지막 beat(191) 가 L1 에 끝내 쓰이지 않는다.** CP-B 는 통과(16/16) — 중간 지점(CP-A)을 안 봤으면 놓쳤을 버그.
(버그 #6 의 교훈 "중간 지점만 비교하면 놓친다"의 반대 경우: 최종 지점만 봐도 놓친다)

START 간격 sweep (`xsim ... --testplusarg "ONLY=SWEEP"`):

| START 간격 (busy↓ 후) | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| CP-A | **FAIL (beat 191)** | PASS | PASS | PASS | PASS | PASS | PASS |

모든 burst 실행에서 "마지막 NoC→L1 SRAM 쓰기 = busy↓ + 2 클럭" 으로 측정됨.

## 2. 원인 (파이프라인 순서)
1. L2 의 burst LOAD 는 NoC 가 마지막 beat 를 **받으면**(`o_FIFO_write_ready` 핸드셰이크) 완료 → busy↓.
   NoC 는 posted write 라서 이 시점에 데이터가 아직 NoC FIFO 안에 있다 (busy↓ 순간 L1 IN 190/192).
2. `L1_FIFO_interface` 는 `i_pe_busy` 로 자기 **출력**을 조합논리로 끈다. 그런데 그 뒤의
   `noc_sram_controller` 는 ceb/web/addr/din 을 **레지스터로 한 번 더** 잡는다 (1클럭 파이프).
3. 간격 0: busy↓+1 엣지에서 START → pe_busy=1. 이 엣지에서 컨트롤러는 이미 beat 191 쓰기를 레지스터에 잡았고,
   busy↓+2 엣지에 SRAM 에 쓰려는 순간 `l1_port_mux` 가 PE 쪽을 선택 → **쓰기가 mux 에서 버려진다.**
   (그래서 TB 의 "게이트에서 버려진 쓰기" 카운터는 0 이다 — 게이트는 통과했고 mux 에서 사라짐)

handshake LOAD (실험 수정본으로 측정) 에서는 마지막 쓰기가 busy↓ **5클럭 전**에 끝난다 → 이 문제 없음.

## 3. 재현
```
scripts\09_run_bb_integ_orig.bat            -> S4 gap0 FAIL (수정 전 재현)   /  01_run_bb_integ.bat -> PASS (수정 후)
cd scripts\work_integ
xsim bb_integ_snap --testplusarg "ONLY=SWEEP" --tclbatch ../run_nowave.tcl
```

## 4. 수정 — 적용함: 선택지 (e) (2026-10-06)
`l1_port_mux` 를 `sel_pe = i_pe_busy && i_noc_ceb` 로 바꿈 → pe_busy 가 올라간 클럭에 컨트롤러 레지스터에 남은
NoC 접근 1개를 끝까지 보내 준다. 원본 RTL 무수정, PE 인터페이스 변화 없음. 자세한 근거는 FIX_SUMMARY.md 문제 3.
원래 검토했던 선택지 (참고):
- (a) **사용 규칙**: "START 는 busy↓ 후 N(≥1, 여유 두고 4) 클럭 뒤". PS(AXI-Lite) 경로는 레지스터 접근만으로
  수십 클럭이 걸려 실제로는 자동 만족 (Phase 3 에서 확인). 하드웨어 시퀀서가 생기면 깨짐.
- (b) `blackbox_pe` 가 START 를 받은 뒤 pe_busy 를 올리기 **전에** 몇 클럭 기다림 (지금 GUARD 는 pe_busy 를
  올린 **뒤** 기다리는 것이라 효과 없음). 사양 7.3 의 FSM 표와 달라지므로 JH 확인 필요.
- (c) NOC 쪽에 "L1 쓰기 완료/idle" 상태 출력을 추가하고 PE 가 그것을 보고 시작. NOC 설계자 확인 필요.
- (d) L2 가 NOC 의 write response 를 다 받은 뒤 busy↓ (burst 모드 의미 변경, L2 설계자 확인 필요).

## 5. 영향
- 실제 MAC IP 를 붙일 때 같은 규칙이 필요하다 (MAC 이 busy↓ 를 보고 바로 L1 을 잡으면 마지막 입력이 사라짐).
- STORE 방향 (BB done → STORE 간격 0) 은 문제 없음 (S4 의 CP-B 16/16).
