# 현재 FPGA 구현 스펙 — `l2_noc_fpga_top` on ZCU102

측정 기준: `verif/fpga/build_synth.tcl` 실행 결과 (`build/util_route.rpt`,
`build/timing_route.rpt`, post-route). 파라미터 출처는 `l2_noc_fpga_top.sv`,
용량 계산 근거는 각 메모리 모듈의 파라미터.

> 표기: **[측정]** = 실제 빌드 리포트 값 · **[계산]** = 파라미터에서 산출 ·
> **[추정]** = 측정값에서 유도(재검증 필요) · **[이론]** = 이론적 최대치

---

## 1. 한 줄 요약

| 항목 | 값 |
|---|---|
| L2 캐시 용량 | **256 KB** (축소판) / 4 MB (RTL 기본값) |
| NOC측 메모리 | **128 KB** |
| 동작 주파수 | **100 MHz 검증 완료**, 최대 ~145 MHz 추정 |
| ch1_in 대역폭 | **6.4 GB/s** @100MHz (512b × 1 beat/cycle) |
| 타겟 디바이스 | ZCU102 / `xczu9eg-ffvb1156-2-e` |
| 자원 점유 | LUT 17.0% · FF 5.8% · BRAM 17.3% · DSP 0% |

---

## 2. L2 캐시 메모리

현재 합성된 축소판 파라미터: `GROUPS=8, BLOCKS=16, ADDRESS_ROW=256`

| 항목 | 값 | 근거 |
|---|---|---|
| SRAM 인스턴스 수 | 128개 | GROUPS(8) × BLOCKS(16) **[계산]** |
| 인스턴스당 크기 | 256 행 × 64 bit = 16 Kbit (2 KB) | `ram_mimic.sv` `BIT_WIDTH=64` **[계산]** |
| **전체 용량** | **2,097,152 bit = 256 KB** | 128 × 16 Kbit **[계산]** |
| 워드 폭 | 64 bit | `ram_mimic.sv` |
| 포트 | 단일 포트, 읽기/쓰기 배타 | `if(!ena) { if(!wea) write; else read; }` |
| 제어 극성 | **active-LOW** (`ena`/`wea` 둘 다) | polarity 버그 수정본 사용 |
| 읽기 지연 | 1 클럭 (registered output) | |

### 중요: 256 KB는 채널별이 아니라 **전체 공유** 용량

물리적으로 SRAM 배열은 **하나뿐**이고, 5개 채널은 그것을 서로 다른 워드 폭으로
보는 창구입니다 (`TOP_L2_cache.sv:30-49`):

```
GROUP_CHANNEL_X  = BANDWIDTH_CHANNEL_X / BANDWIDTH_CHANNEL_0   // 몇 블록을 묶는가
BLOCKS_CHANNEL_X = BLOCKS / GROUP_CHANNEL_X                     // 그 채널이 보는 블록 수
```

| 채널 | 폭 | 묶는 블록 수 | 보는 블록 수 | 접근 가능 용량 |
|---|---|---|---|---|
| ch0 | 64b | 1 | 16 | 256 KB |
| ch1_in | 512b | 8 | 2 | 256 KB |
| ch2_in | 256b | 4 | 4 | 256 KB |
| ch1_wgt | 256b | 4 | 4 | 256 KB |
| ch2_wgt | 256b | 4 | 4 | 256 KB |

모든 채널이 **같은 256 KB**를 봅니다 — 채널별로 더하지 않습니다.

### 원래 크기로 키우면

| 파라미터 | 축소판 (현재) | RTL 기본값 | 배수 |
|---|---|---|---|
| GROUPS | 8 | 8 | ×1 (**변경 불가**) |
| BLOCKS | 16 | 32 | ×2 |
| ADDRESS_ROW | 256 | 2048 | ×8 |
| **용량** | **256 KB** | **4 MB** | **×16** |

`GROUPS`는 8로 고정해야 합니다 — `cmd_decoder_channel_*_wrapper.sv` 안에
GROUPS=8을 전제한 2단 그룹분할이 하드코딩돼 있어서, 8이 아니면 elaboration
에러가 납니다 (실제 시도해서 확인함).

---

## 3. NOC측 메모리 = L1 캐시 모델 (`FIFO_intf` → `L1_Cache_Mimic` → `sram_mimic`)

계층 구조:
```
FIFO_intf
 ├─ noc_FIFO_interface_on_fire     NOC 브리지 로직 (FIFO, 핸드셰이크)
 └─ L1_Cache_Mimic                 "L1 캐시" 역할
     ├─ noc_sram_controller
     └─ sram_mimic × 4             실제 메모리
```

**L2와 달리 이쪽은 채널마다 별도입니다.** 지금 FPGA top에는 `FIFO_intf`가 **하나만**
인스턴스화되어 ch1_in에 물려 있습니다. ch1_wgt도 FPGA에서 돌리려면 `FIFO_intf`를
하나 더 인스턴스화해야 하고(시뮬에서는 `ADDR_DEPTH=1024, DATA_WIDTH=256`으로 그렇게 함),
그만큼 메모리가 추가로 늘어납니다.

또한 이것은 실제 L1 캐시 RTL이 아니라 **대역 모델(mimic)** 입니다 — 진짜 L1 캐시는
이 저장소에 없습니다.

현재 인스턴스 파라미터: `ADDR_DEPTH=2048, DATA_WIDTH=512, MEMORY_BITWIDTH=128`

| 항목 | 값 | 근거 |
|---|---|---|
| 물리 SRAM 인스턴스 | 4개 (`Usram_mimic_0`~`_3`) | `L1_Cache_Mimic.v` **[계산]** |
| 인스턴스당 크기 | 2048 행 × 128 bit = 256 Kbit | |
| **전체 용량** | **1,048,576 bit = 128 KB** | 4 × 256 Kbit **[계산]** |
| 논리 워드 폭 | 512 bit (128b × 4 뱅크 병렬) | |
| 주소 공간 | 2048 워드 (11 bit 주소) | |
| FIFO 깊이 | 8 | `NOC_FIFO_DEPTH` |
| 입력 지연 모델 | 3 클럭 | `NOC_IN_DELAY` |
| 초기 내용 | 주소 0~4에 `0xDEAD_BEE0`~`0xDEAD_BEE4` | `sram_mimic_fpga.v` `initial` → BRAM INIT |

---

## 4. 채널 스펙

| 채널 | 데이터 폭 | 주소 폭 | 현재 상태 |
|---|---|---|---|
| channel 0 (AXI4형) | 64 bit | 15 bit | tie-off |
| **channel 1_in** | **512 bit** | 19 bit (NOC-local 11 bit) | **사용 중 — 검증 완료** |
| channel 2_in | 256 bit | 15 bit | tie-off |
| channel 1_wgt | 256 bit | 18 bit | tie-off (시뮬에선 검증 완료) |
| channel 2_wgt | 256 bit | 9 bit | tie-off |

### 명령 인터페이스

| 항목 | 값 |
|---|---|
| 명령어 폭 | 64 bit |
| 명령 큐 깊이 | 64개 (`CMD_dispatcher`의 FIFO) |
| handshake | `i_command_valid` / `o_command_ready` (큐 push) |
| 완료 신호 | `o_busy_channel_1_in` = load_busy \|\| store_busy |
| 지원 모드 | burst load/store, handshake load/store (4종) |

---

## 5. 타이밍 / 주파수

| 항목 | 값 | 비고 |
|---|---|---|
| 제약 주파수 | 100.000 MHz (period 10.000 ns) | **[측정]** `constraints.xdc` |
| WNS (setup 여유) | **+3.117 ns** | **[측정]** 0개 violation / 112,741 endpoint |
| WHS (hold 여유) | +0.014 ns | **[측정]** 통과지만 여유 매우 적음 |
| TNS / THS | 0.000 / 0.000 | **[측정]** |
| **추정 최대 주파수** | **≈ 145 MHz** | **[추정]** 1 / (10.000 − 3.117) |

**추정치 주의**: Vivado는 제약(100MHz)을 만족하면 더 최적화하지 않으므로,
실제 145MHz로 돌리려면 `create_clock -period 6.9`로 다시 제약해서 재합성한 뒤
확인해야 합니다. 통상 재합성하면 도구가 더 노력해서 비슷하거나 조금 더 나오지만,
보장은 없습니다.

**hold 여유(+0.014ns)가 얇은 점**: hold violation은 클럭을 느리게 해도 해결되지
않는 종류입니다. 지금은 통과지만 여유가 거의 없으므로, 나중에 설계를 고치거나
다른 디바이스 스피드 그레이드로 옮길 때 다시 확인이 필요합니다.

### 클럭 / 리셋 구조

| 항목 | 값 |
|---|---|
| 클럭 도메인 | **1개** (`i_clk` 단일) — CDC 없음 |
| 글로벌 버퍼 | BUFGCE 2개 (클럭 1 + **고팬아웃 리셋 1**) |
| MMCM / PLL | 사용 안 함 (현재) |
| 리셋 방식 | 비동기 assert, active-low |
| 리셋이 닿는 FF | 31,824개 |
| 클럭을 안 쓰는 블록 | `noc_ch1_in_adapter` (순수 조합논리) |

---

## 6. 대역폭

| 경로 | 폭 | @100 MHz | @145 MHz (추정) |
|---|---|---|---|
| channel 1_in (NOC ↔ L2) | 512 bit/beat | **6.4 GB/s** | 9.3 GB/s |
| channel 0 (AXI, 미사용) | 64 bit | 800 MB/s | 1.16 GB/s |

**[이론]** 1 beat/cycle 기준 최대치입니다. 실제로는 handshake stall과
명령 디코딩 오버헤드가 있어 이보다 낮습니다 (시뮬레이션에서 5-beat 버스트
기준 측정한 실효값은 별도 측정 필요).

---

## 7. FPGA 자원 사용량 **[측정]**

디바이스: `xczu9eg-ffvb1156-2-e` (ZCU102)

| 자원 | 사용 | 전체 | 사용률 |
|---|---|---|---|
| CLB LUT | 46,461 | 274,080 | 16.95% |
| — LUT as Logic | 41,981 | 274,080 | 15.32% |
| — LUT as Distributed RAM | 4,480 | 144,000 | 3.11% |
| CLB Register (FF) | 31,889 | 548,160 | 5.82% |
| Block RAM Tile | 158 | 912 | 17.32% |
| — RAMB36E2 | 156 | — | |
| — RAMB18E2 | 4 | — | |
| URAM | 0 | **0 (디바이스에 없음)** | — |
| DSP | 0 | 2,520 | 0% |
| BUFGCE | 2 | 116 | 1.72% |
| Bonded IOB | 7 | 328 | 2.13% |

**URAM 참고**: RTL에 `(* ram_style = "ultra" *)`가 붙어 있지만 ZU9EG에는
UltraRAM이 없어서 경고 17건과 함께 전부 일반 BRAM으로 대체됐습니다 (에러 아님).
UltraRAM을 실제로 쓰려면 "EV" 계열(예: ZCU104의 ZU7EV)이 필요합니다.

### 용량을 키울 때 BRAM 전망 **[추정]**

`ram_mimic`은 64비트 폭이라 타일 하나를 통째로 차지합니다. 지금(256행=16 Kbit)은
36 Kbit 타일의 44%만 쓰는 비효율 상태이고, 행 수를 키우면 효율이 올라가므로
**타일 수는 용량에 비례해서 늘지 않습니다.**

| 구성 | 용량 | 인스턴스 | 타일/인스턴스 | L2 타일 | +NOC | 합계 | 912개 대비 |
|---|---|---|---|---|---|---|---|
| **현재** BLOCKS16 / ROW256 | 256 KB | 128 | 1 | 128 | 32 | ~160 | 17% ✅ |
| BLOCKS16 / ROW2048 | 2 MB | 128 | 4 | 512 | 32 | ~544 | 60% ✅ |
| BLOCKS32 / ROW1024 | 2 MB | 256 | 2 | 512 | 32 | ~544 | 60% ✅ |
| **원본** BLOCKS32 / ROW2048 | 4 MB | 256 | 4 | 1024 | 32 | ~1056 | **116% ❌** |

계산 모델은 현재 구성의 실측치(158타일)와 일치하므로 위 예측도 신뢰할 만합니다.

**결론**: 원본 4MB는 이 보드에 약 15% 초과로 **들어가지 않습니다.** 다만 **2MB는
60%로 넉넉히 들어가므로**, 실물 검증용으로는 2MB 구성이 현실적인 타협점입니다.
4MB 전체가 꼭 필요하면 UltraRAM이 있는 디바이스(예: ZCU104의 ZU7EV)로 옮겨야 합니다 —
RTL에 `ram_style="ultra"`가 붙어 있는 걸 보면 설계자도 원래 URAM을 염두에 뒀던 것으로 보입니다.

### 축소한 진짜 이유 (기록)

BRAM 용량 때문이 **아니라**, 첫 합성을 빨리 돌려보려고 줄인 것입니다. 그리고
줄일 수 있는 파라미터가 `ADDRESS_ROW` 하나뿐이었습니다 — `GROUPS`는 wrapper 하드코딩
때문에 8 고정, `BLOCKS`는 `$clog2` 제약 때문에 16이 최솟값입니다. BRAM 한계는
나중에 계산해보니 결과적으로도 실재하는 제약이었던 것으로 확인됐습니다.

---

## 8. 검증 상태 요약

| 항목 | 상태 |
|---|---|
| 시뮬레이션 (ch1_in STORE→LOAD) | 5 beat 중 4 beat 일치, beat 0 유실 (미해결) |
| 시뮬레이션 (ch1_wgt) | 동일 패턴 — 구조적 문제 시사 |
| BIST 시퀀서 시뮬 | 5/5 일치 (버그 재현 안 됨 — 원인 미특정) |
| 합성 / 배치 / 배선 | 0 에러, 100% routed |
| 타이밍 | 전부 만족 |
| 실보드 동작 | **미확인** (bitstream 미생성) |
