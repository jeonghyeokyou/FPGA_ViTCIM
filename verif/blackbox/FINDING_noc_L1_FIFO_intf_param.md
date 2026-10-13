# FINDING — `L1_FIFO_intf.v` 가 없는 파라미터 `MEMORY_BITWIDTH` 를 넘겨 elaborate 실패

| 항목 | 내용 |
|---|---|
| 종류 | NOC 원본 RTL 버그 (버그 #2 와 같은 종류, 다른 파일) |
| 발견 | 2026-10-06, Blackbox 환경용 `noc_L1_FIFO_intf.v` 사본 작성 중 |
| 상태 | **✅ 해결** — 사본 `verif/blackbox/rtl/noc_L1_FIFO_intf.v` 에서 수정. 원본 그대로 |
| 심각도 | Low (컴파일 단계에서 바로 드러남, 동작 영향 없음) |

## 1. 위치
`rtl/NOC_260902/L1_FIFO_intf.v` 84행 — `L1_FIFO_interface` 인스턴스의 `.MEMORY_BITWIDTH (MEMORY_BITWIDTH)`.
`L1_FIFO_interface.v` 의 파라미터는 `ADDR_DEPTH, DATA_WIDTH, FIFO_DEPTH, INPUT_DELAY` 뿐이다.

## 2. 증상 / 재현
원본 파일만으로 elaborate (2026-10-06 실행):
```
xvlog  noc_FIFO.v noc_FIFO_modified.v L1_FIFO_interface_on_fire.v L1_FIFO_interface_handshake.v
       L1_FIFO_interface.v sram_controller.v L1_FIFO_intf.v
xelab  work.L1_FIFO_intf
ERROR: [VRFC 10-2861] module 'L1_FIFO_interface' does not have a parameter named MEMORY_BITWIDTH
       [rtl/NOC_260902/L1_FIFO_intf.v:84]
```

## 3. 수정 (사본)
그 한 줄만 삭제. 동시에 이름 충돌 회피용 변경 2개 (`module L1_FIFO_intf → noc_L1_FIFO_intf`,
`sram_controller → noc_sram_controller`). 원본과의 diff 는 정확히 3줄 — 사본 머리 주석 참고.

## 4. 영향
`L1_FIFO_intf` 는 `i_pe_busy` 와 외부 SRAM 포트를 가진 "설계자 의도 구조"인데, 이 버그 때문에 원본 그대로는
한 번도 elaborate 될 수 없었다 → 이 top 은 설계자 쪽에서도 시뮬레이션되지 않았을 가능성이 높다.
(설계자에게 따로 보내지 않고 사본으로 처리하기로 함 — 2026-10-06 JH)
