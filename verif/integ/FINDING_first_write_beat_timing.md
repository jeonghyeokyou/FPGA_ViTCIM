# 검증 이슈 보고 : NOC on-fire 브리지 — burst write 시작 첫 beat 데이터 유실

| 항목 | 내용 |
|---|---|
| 발견 경위 | Phase 2 STEP 3, L2+NOC 통합 시뮬레이션 (`tb_l2_noc_ch1_in.sv`, ch1_in STORE→LOAD) |
| 발견일 | 2026-09-15 |
| 심각도 | Medium — 데이터가 틀린 값이 아니라 "이전 상태(0)로 유실"되며, **버스트의 첫 beat에서만, write 방향에서만** 재현됨 |
| **상태** | **✅ 해결됨 (2026-09-22)** — 근본 원인 특정 + 수정 적용 + 재검증 완료. 8절 참고 |
| **재현성** | `tb_l2_noc_ch1_wgt.sv` (ch1_wgt, 256b/10b 주소, 완전히 다른 어댑터·FIFO_intf 인스턴스)에서도 동일 증상 재현 — L2 쪽 코드나 채널별 파라미터 문제가 아니라 `FIFO_interface_on_fire`/`L1_FIFO_interface_on_fire` 자체의 버스트 타이밍 이슈였음이 최종 확인됨 |

## 1. 증상

`tb_l2_noc_ch1_in.sv` 시나리오:
1. `L1_Cache_Mimic` addr 0~4 에 backdoor로 `0xC0DE_0000+k` (k=0..4) 를 미리 채움
2. L2 `ch1_in STORE` (cmd_idx=2) : NOC read path 로 L1 addr 0~4 → L2 내부 SRAM addr 0~4
3. L2 `ch1_in LOAD` (cmd_idx=1) : L2 내부 SRAM addr 0~4 → NOC write path 로 L1 addr 50~54
4. L1 addr 50~54 backdoor 검증

결과:
```
L1[50] = 0x00000000   MISMATCH (expected 0xc0de0000)   <- beat 0
L1[51] = 0xc0de0001   OK                                 <- beat 1
L1[52] = 0xc0de0002   OK
L1[53] = 0xc0de0003   OK
L1[54] = 0xc0de0004   OK
```
5 beat 중 **첫 beat(k=0)만 0으로 유실**, 나머지 4개는 주소·데이터 전부 정확.

STORE(읽기 방향)는 문제 없었음 — LOAD에서 읽어낸 `o_noc_write_data` 가 k=0 부터 이미
`0xC0DE0000` 으로 정확했으므로(아래 파형 근거), L2 내부 SRAM 에는 STORE 가 5개 전부
정확히 써 놓았다는 뜻. **유실은 오직 write(NOC_260902 쪽) 방향, 그것도 버스트 시작
첫 beat 에서만** 일어남.

## 2. 파형 근거 (VCD, `tb_l2_noc_ch1_in.vcd`)

| 시각 | 신호 | 값 |
|---|---|---|
| 585 ns | `o_noc_write_valid_channel_1_in` / `addr` / `data` | 1 / 50 / **0xC0DE0000** (k=0, 정확) |
| 585 ns | `dut_noc.i_write_valid` / `i_write_addr` | 1 / 50 — FIFO_intf 입력까지도 정확히 도달 |
| 605 ns | `L1_Cache_Mimic.w_sram_addr` | 50 (k=0 주소 그대로) |
| 605~655ns | `L1_Cache_Mimic.w_sram_din` | k=0 구간엔 값 변화 없음(이전 값 0 유지), 625ns 에서야 `0xC0DE0001`(k=1) 로 갱신 |
| 전 구간 | `dut_noc.w_write_data` | 0xC0DE0000 (k=0) 값은 **한 번도 나타나지 않음** |

즉 **주소(addr) FIFO 는 k=0 시점에 맞게 50 을 정확히 내놓는데, 데이터(data) FIFO 출력이
그 타이밍에 아직 예전 값(0)이고, k=0 데이터 자체가 파이프라인 전체에서 사라짐.**
addr 와 data 가 정확히 한 슬롯씩 밀려서 나온 게 아니라 k=0 데이터가 통째로 없어짐.

## 3. 원인 후보

`rtl/NOC_260902/FIFO_interface_on_fire.v` 와 `L1_FIFO_interface_on_fire.v` 모두 동일한
구조: `i_write_valid_M` 하나로 **주소 FIFO 와 데이터 FIFO 를 같은 사이클에 동시에 push**
하지만, 그 둘을 실제로 L1 쪽으로 내보내는(pop) 조건은
```verilog
reg r_write_signal;
always @(posedge clk...) if(i_control_mode==0) begin
    if (i_write_valid_M) r_write_signal <= 1'b1;   // ← 다음 사이클에야 1이 됨
    ...
end
assign w_output_ready_addr = ... (r_write_signal) ? (...) : 1'b0;
assign w_output_ready_data = ... (r_write_signal) ? (...) : 1'b0;
assign o_write_valid_L1    = (r_write_signal) ? (w_output_valid_addr && w_output_valid_data) : 1'b0;
```
`r_write_signal` 이 **`i_write_valid_M` 이 처음 1 이 되는 바로 그 사이클엔 아직 0** 이라서,
그 사이클의 pop 인에이블이 전부 꺼져 있음. L2 는 버스트 모드라 `i_write_valid_M` 을
사이클마다 연속으로 세우기 때문에, 이 "첫 사이클만 pop 불가" 구간에서 addr FIFO 와
data FIFO 가 서로 다르게 반응(둘 다 같은 조건이라 이론상 안 밀려야 하지만, 실제로는
data 경로에 `FIFO_modified`(INPUT_DELAY=3, `o_input_almost_ready`) 가 하나 더 얹혀 있어
addr 경로의 평범한 `FIFO` 와 구조가 다름) 하면서 k=0 데이터가 이 경계에서 빠진 것으로
보임. **정확한 단일 원인 라인은 특정하지 못했고, 이 부분(우선 `L1_FIFO_interface_on_fire.v`
의 addr-FIFO/`FIFO_modified` 데이터-FIFO 간 push/pop 정합)부터 보는 것을 제안.**

## 4. 재현

```
verif/integ/00_run_integ.bat            -> ch1_in  : RESULT CHECK (errors=1, beat0만 실패)
verif/integ/10_wave_gui_integ.bat       -> ch1_in  파형 GUI

verif/integ/01_run_integ_ch1_wgt.bat    -> ch1_wgt : RESULT CHECK (errors=1, beat0만 실패)
verif/integ/11_wave_gui_integ_wgt.bat   -> ch1_wgt 파형 GUI
```

### ch1_wgt 재현 로그 (2026-09-15) — ch1_in과 완전히 동일한 패턴
```
NOC[60] = 0x00000000   MISMATCH (expected 0xa11a0000)   <- 버스트 첫 beat
NOC[61] = 0xa11a0001   OK
NOC[62] = 0xa11a0002   OK
NOC[63] = 0xa11a0003   OK
NOC[64] = 0xa11a0004   OK
```
데이터 폭(512b→256b), 주소 폭(11b→10b), 어댑터/FIFO_intf 인스턴스가 전부 다른데도
**증상이 정확히 같음** — 채널별 우연이 아니라 `FIFO_interface_on_fire`/
`L1_FIFO_interface_on_fire` 공통 로직의 구조적 문제라는 뜻.

## 4-b. 그런데 BIST 시퀀서(`l2_noc_fpga_top.sv`)에서는 재현이 안 됨 (2026-09-15)

FPGA 합성용으로 만든 `verif/fpga/l2_noc_fpga_top.sv` — **완전히 같은 브리지 RTL**
(`noc_FIFO_interface_on_fire.v`/`L1_FIFO_interface_on_fire.v`, rename만 됐을 뿐 내용
동일)로 **같은 STORE→LOAD 시퀀스**를 always-block BIST 시퀀서로 돌렸더니
**5/5 beat 전부 정확히 일치** (`mismatch_count=0`). 이걸 재현시키려고 아래를 전부
`tb_l2_noc_ch1_in.sv` 와 맞춰봤지만 **전부 여전히 통과**:

| 바꿔본 것 | tb_l2_noc_ch1_in.sv 값 | 결과 |
|---|---|---|
| STORE 완료 → LOAD 발행 사이 gap | 10 클럭 | gap 없이(0클럭)도 PASS, 10클럭 맞춰도 PASS |
| GROUPS/BLOCKS/ADDRESS_ROW | 8/32/2048 (default) | 8/16/256(축소)도 PASS, 8/32/2048(동일)도 PASS |
| LOAD 목적지 주소 | 50 | 20도 PASS, 50로 맞춰도 PASS |

**같은 상태로 재확인**: 이 실험들 하는 동안 `verif/integ/00_run_integ.bat`(원본
`tb_l2_noc_ch1_in.sv`)를 다시 돌려서 **여전히 beat0 MISMATCH 재현되는 것 확인함**
(리그레션 아님, 환경 변화 아님). 즉 버그는 실재하지만, 정확히 어떤 조건에서
발현되는지는 아직 못 좁혔다. 안 맞춰본 후보:
- `L1_Cache_Mimic` preload 방식/타이밍 — `tb_l2_noc_ch1_in.sv`는 리셋 해제
  **5클럭 뒤** 절차적 blocking assign(`initial` 블록 안, 시뮬레이션 중간 시점)으로
  덮어쓰는데, `sram_mimic_fpga.v`는 **t=0 시점 `initial` 블록**으로 미리 채워둠.
  둘 다 STORE가 읽을 때쯤엔 내용이 같아서 영향 없을 것 같았지만 완전히 배제 못 함.
- BIST 시퀀서가 리셋 해제 즉시(0클럭 뒤) STORE를 내보내는 반면, TB는 리셋 해제
  5클럭 뒤에야 preload, 그 이후 `send_cmd` 로 STORE 발행 — 커맨드 발행 자체의
  절대 타이밍(사이클 오프셋)까지는 맞춰보지 않음.
- 이 정도로 안 잡히는 걸 보면 시뮬레이터의 이벤트 순서(delta-cycle) 관련 아티팩트일
  가능성도 배제 못 함 — 그렇다면 FPGA 실물에서는 애초에 안 나타날 수도 있음.

**실무적 의미**: 이 결과가 "버그 없음"을 증명하진 않지만(트리거 조건 특정 못했으니),
**always-block 기반 시퀀서로 도는 실사용 패턴(=FPGA에서 실제로 도는 방식)에서는
안 나타났다는 것 자체가 유의미한 데이터**. FPGA 브링업을 이 이유로 미룰 필요는
없어 보이고, 대신 `o_mismatch_count` 를 ILA/LED로 계속 관찰해서 실제 하드웨어에서도
0으로 나오는지 보는 게 다음 확인 스텝.

## 8. 해결 (2026-09-22)

**근본 원인 특정 및 수정 완료.** 3절의 원인 후보(`r_write_signal`/pop 타이밍)는 방향이
틀렸었고, 실제 원인은 **데이터 FIFO 입력단의 mux 우선순위**였습니다. 외부 분석
문서([`RTL_FIFO_첫_데이터_오류_설명과_수정.md`](../../RTL_FIFO_첫_데이터_오류_설명과_수정.md),
같은 RTL을 공유받은 다른 학생이 Verilator/Icarus로 독립 분석)가 정확히 짚어냈습니다.

### 진짜 원인

`noc_FIFO_interface_on_fire.v`/`L1_FIFO_interface_on_fire.v` 둘 다 데이터 FIFO에
넣을 값을 고르는 mux가 **"이전 읽기 상태(`r_read_signal`)"를 "지금 들어온 쓰기
요청(`i_write_valid_M`)"보다 먼저** 확인했습니다:

```verilog
// 원본 (틀림) — r_read_signal이 1이면 쓰기 요청이 와도 무시하고 읽기값을 고름
assign w_input_data_data = (r_read_signal) ? i_read_data_S
                         : ((i_write_valid_M) ? i_write_data_M : {(DATA_WIDTH){1'b0}});
```

STORE(읽기) 직후 `r_read_signal`이 1로 남아있는 상태에서 LOAD(쓰기)의 첫 beat가
들어오면, `r_read_signal`은 그 클럭에서 아직 0으로 안 내려간 상태라 **읽기값
(이 시점엔 0)이 잘못 선택되어 데이터 FIFO에 들어갑니다.** 주소 FIFO는 이 mux를
안 거치므로 영향이 없어서, "주소는 맞는데 데이터만 첫 beat 유실"로 보였던 것입니다.
(4절 파형 근거의 `w_sram_addr=50`은 맞고 `w_sram_din`만 갱신 안 됐던 것과 정확히 일치)

2번째 beat부터는 같은 클럭에 `r_read_signal`이 0으로 갱신되어 있어 정상 동작 —
그래서 딱 beat 0만 항상 틀렸습니다.

### 수정

두 파일 모두 mux 우선순위만 뒤집었습니다 (각 1줄):

```verilog
// 수정 — 지금 들어온 쓰기 요청을 최우선으로
assign w_input_data_data = (i_write_valid_M) ? i_write_data_M
                         : ((r_read_signal) ? i_read_data_S : {(DATA_WIDTH){1'b0}});
```

적용 위치: `verif/noc/rename/noc_FIFO_interface_on_fire.v`,
`verif/noc/rename/L1_FIFO_interface_on_fire.v` (이 통합 검증 흐름과 FPGA 합성
흐름 둘 다 이 rename 사본을 참조하므로 여기 적용. **`rtl/NOC_260902/`의 원본은
이번에도 수정하지 않았습니다** — 프로젝트 정책대로 설계자 확인용 원본 보존).

### 재검증 결과 (2026-09-22)

수정 적용 후 기존 테스트를 그대로 재실행:

```
verif/integ/00_run_integ.bat          ch1_in  : L1[50..54] 5/5 전부 OK (기존 beat0만 실패 → 해결)
verif/integ/01_run_integ_ch1_wgt.bat  ch1_wgt : NOC[60..64] 5/5 전부 OK (기존 beat0만 실패 → 해결)
```

두 채널 모두 이제 **진짜 5/5 완전 통과**입니다.

### 4-b절(BIST 미재현)에 대한 설명도 이걸로 풀림

BIST가 재현 안 됐던 건 "환경이 달라서"가 아니라 **BIST의 비교 지점이 틀린 곳이었기
때문**입니다. `l2_noc_fpga_top.sv`의 BIST는 `o_noc_write_data_channel_1_in`(L2가
내보내는 시점의 값, 버그가 발생하기 **이전** 지점)을 비교했습니다 — 그 값은 원본
버그 상태에서도 항상 정확했으므로 BIST는 무조건 PASS를 보고했던 것입니다. 즉
BIST는 버그를 "재현 안 한 것"이 아니라 애초에 **버그가 있는 지점을 보고 있지
않았습니다.** (외부 분석 문서 9절이 이 부분도 정확히 지적함)

**TODO**: `l2_noc_fpga_top.sv`의 BIST 비교 지점을 L1측 최종 쓰기 데이터로 옮기는
게 이 문제를 재발 방지하는 데 더 안전하지만, 이번 수정 범위에서는 하지 않았습니다
(내부 계층 참조가 필요해 별도 작업).

### 남은 것

- `rtl/NOC_260902/FIFO_interface_on_fire.v` / `L1_FIFO_interface_on_fire.v` 원본은
  같은 버그를 그대로 가지고 있습니다 — NOC 설계자(윤현준)에게 이 발견을 전달 필요.
- FPGA 합성(`verif/fpga/`)은 `verif/noc/rename/`을 참조하므로 이 수정이 이미 반영된
  상태입니다. 다음 재합성부터 적용됨 — 아직 재합성은 안 함.

## 5. 참고 — 이번 건은 이전 2개 발견과 성격이 다름

- `FINDING_ram_mimic_polarity.md` / `FINDING_noc_sim_bugs.md` 는 **시뮬레이션 전용 모델**
  (mimic 모듈)의 포트 방향/극성 버그로, 한 줄 수정으로 명확히 고쳐지고 실제 하드웨어
  동작과 무관.
- 이번 건은 **`FIFO_interface_on_fire` / `L1_FIFO_interface_on_fire` 자체의 버스트
  타이밍 동작**이라 실제 합성 대상 RTL 에 영향. NOC 설계자(윤현준) 확인이 필요합니다.
  임시 우회(예: burst 시작 전 dummy 1 cycle 삽입)는 가능하지만 근본 수정이 아니므로
  이 보고서에서는 적용하지 않았습니다.
