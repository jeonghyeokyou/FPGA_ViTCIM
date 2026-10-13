# FINDING — L2 안에서 ch1_in 512b beat 는 ch0 주소로 "연속"이 아니다 (메모리 맵 해석 문제)

| 항목 | 내용 |
|---|---|
| 종류 | **사양/문서 문제** (RTL 버그 아님). BLACKBOX_TASK.md 4.1절, 9절의 가정이 RTL 과 다름 |
| 발견 | 2026-10-06, Phase 2 준비 중 `SRAM_group_decoder.sv` 대조 |
| 상태 | 검증 환경에서 처리함 (`bb_pkg::ch1_to_ch0`, `gen_vectors.py`). PS C 코드에도 같은 처리가 필요 |
| 심각도 | High (모르고 PS 가 X 를 선형으로 쓰면 LOAD 결과가 전부 틀림) |

## 1. 위치
`rtl/L2_260901/SRAM_group_decoder.sv` — `GRP_CH_0`, `GRP_CH_1_IN` generate 블록.
`cmd_decoder_SRAM_group_interface.sv` — group 번호 = 주소 MSB.

## 2. 증상 (예상되는 오동작)
BLACKBOX_TASK.md 9절 / 4.1절은 "beat k = 바이트 [64k, 64k+63]" 이고 "L2 워드 주소 = 바이트 주소 / 64" 라고
가정한다. PS 가 X(12 KiB)를 ch0 로 `0x0_0000` 부터 **선형으로** 쓰고 LOAD(ch1_in word 0..191) 하면,
L1 에 들어가는 데이터는 X 와 전혀 다르다.

## 3. 원인
L2 는 64b `ram_mimic` 을 그룹당 BLOCKS(16)개 가진다. 두 채널이 같은 SRAM 을 다르게 자른다.

| | 그룹 내 주소 | 비트 분해 (8/16/1024) |
|---|---|---|
| ch0 (64b) | 14b | `[13:10]` block (0..15), `[9:0]` row |
| ch1_in (512b) | 11b | `[10]` block-pair g (0..1), `[9:0]` row. 512b = block `g*8+0 .. g*8+7` 의 **같은 row** |

즉 ch1_in 워드 c 의 lane b (bit `[64b+63:64b]`) 는 ch0 64b 워드
```
ch0 = (grp << 14) | ((g*8 + b) << 10) | row        grp = c >> 11, g = (c >> 10) & 1, row = c & 1023
PS 바이트 주소 = ch0 * 8
```
에 있다. 한 beat 의 8개 lane 은 **8 KiB 간격**으로 흩어져 있고, ch0 로 연속된 주소는 "같은 lane 의 다음 beat" 다.

## 4. 그래도 맞는 것
64 KiB 정렬된 영역 **시작 주소**에서는 `바이트/64 = ch1 워드`가 성립한다 (`0x0_0000 → 0x0000`, `0xA_0000 → 0x2800`).
그리고 각 영역의 데이터는 그 64 KiB 슬롯 안에 머문다 (X: block 0..7 row 0..191 ⊂ 0x0_0000~0x0_FFFF,
OUT: group 5 block 0..7 row 0..15 ⊂ 0xA_0000~0xA_FFFF). **메모리 맵의 영역 구분은 유효, 영역 안의 배치만 다르다.**

## 5. 재현 / 확인
`scripts/01_run_bb_integ.bat` — S1~S5 가 lane 별 burst 로 쓰고 읽어서 CP-A 0, CP-B 16/16 → 위 공식이 맞음을 시뮬레이션으로 확인.
(공식이 틀렸다면 CP-A 에서 192 beat 거의 전부 불일치가 났을 것.)

## 6. 처리 내용
- `tb/bb_pkg.sv::ch1_to_ch0()`, `scripts/gen_vectors.py::ch1_to_ch0()` (같은 식)
- TB 의 `l2_write_beats` / `l2_read_beats` 는 lane 마다 burst (X: 8 × 192 beat, OUT: 8 × 16 beat)
- `meta.json` 의 `ch0_layout` 에 공식과 lane 별 시작 주소를 넣음 → PS C 코드가 그대로 사용

## 7. 영향
- **PS C 코드**: X 적재 = lane b 마다 `x_lane_byte_addr[b]` 부터 192 × 8 B burst. readback 도 lane 별 16 × 8 B.
  (AXI 4 KB 경계: 192 × 8 = 1536 B 라 문제 없음)
- BLACKBOX_TASK.md 4.1 / 9 절의 "바이트/64" 설명은 영역 시작 주소에만 해당 (이 문서가 정정본)
- ch1_wgt(256b, 4 lane) 도 같은 구조일 것 (이번 범위 밖)
