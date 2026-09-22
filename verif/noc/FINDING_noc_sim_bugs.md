# 검증 이슈 보고 : NOC_260902 — 시뮬레이션에서 `FIFO_intf` 가 elaborate/동작 불가

| 항목 | 내용 |
|---|---|
| 발견 경위 | NOC 단독 기능검증 STEP 0 (`FIFO_intf` compile → elaborate → write/read TB) |
| 발견일 | 2026-09-03 |
| 환경 | Vivado 2024.2 XSim, top = `FIFO_intf` (default params) |
| 결론 | 아래 3건 수정 시 write→read 왕복 **PASS** (5/5). 원본은 그대로, `verif/noc/fix/` 에 사본. |

---

## 이슈 1 — `FIFO_intf.v` : 존재하지 않는 파라미터 전달 (elaborate 실패)

```
ERROR: [VRFC 10-2861] module 'FIFO_interface' does not have a parameter named MEMORY_BITWIDTH   [FIFO_intf.v:68]
ERROR: [VRFC 10-2861] module 'L1_FIFO_interface' does not have a parameter named MEMORY_BITWIDTH [FIFO_intf.v:103]
```
`FIFO_intf.v` 가 `FIFO_interface` / `L1_FIFO_interface` 인스턴스에
`.MEMORY_BITWIDTH(MEMORY_BITWIDTH)` 를 넘기는데 두 모듈에 그 파라미터가 없음
(`L1_Cache_Mimic` 만 가짐).
→ **수정**: 두 인스턴스에서 `.MEMORY_BITWIDTH(...)` 줄 삭제.

## 이슈 2 — `sram_mimic.v` L29 : `o_dout` 이 `input` 으로 선언됨

```verilog
input wire   [BIT_WIDTH-1 : 0 ]  o_dout      // ← output 이어야 함
...
assign o_dout = r_dout;                       // input port 에 대입
```
→ L1 cache read data 가 모듈 밖으로 안 나감. **수정**: `output wire`.

## 이슈 3 — `L1_Cache_Mimic.v` L30 : `o_read_data` 가 `input` 으로 선언됨

```verilog
input  wire  [DATA_WIDTH -1 : 0]   o_read_data,   // ← output 이어야 함
...
.o_read_data (o_read_data)   // Usram_controller.o_read_data (output) 에 연결
```
→ `FIFO_intf` 의 read data 경로 단절. **수정**: `output wire`.

## 이슈 4 (경미) — `FIFO_intf.v` : `L1_FIFO_interface.i_pe_busy` 미연결

`i_pe_busy` 를 안 묶어서 게이팅 로직이 X 를 봄.
→ `verif/noc/fix/FIFO_intf.v` 에서 `.i_pe_busy(1'b0)` 로 연결.
(원 설계 의도상 PE busy 신호를 상위에서 받아야 하는데 top 에 포트가 없음 —
`L1_FIFO_intf.v` 에는 포트로 노출돼 있음.)

---

## 재현

```
verif/noc/00_compile_noc.bat     → NOC STEP 0 PASSED   (fix 3건 반영)
verif/noc/10_run_noc_tb.bat      → NOC standalone : PASS (errors = 0)
```
수정본: `verif/noc/fix/{FIFO_intf.v, sram_mimic.v, L1_Cache_Mimic.v}`,
filelist `verif/noc/noc_files_fix.f`.

## 참고 (polarity)

NOC `sram_mimic.v` 의 chip/write enable 는 **active-low** 로 올바르게 처리됨
(`i_ceb==0 && i_web==0` write / `==1` read). L2 `ram_mimic.sv` 의 polarity 버그와는 다른 이슈.
