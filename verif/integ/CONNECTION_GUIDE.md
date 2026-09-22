# L2 ↔ NOC 연결 상세 — Phase 2 (ch1_in / ch1_wgt) 통합 검증

이 문서는 `L2_260901`(`TOP_L2_cache`)과 `NOC_260902`(`FIFO_intf`)를 **어떻게 한 시뮬레이션
안에서 연결했는지**를 처음부터 끝까지 설명한다. 대상 채널: **ch1_in**, **ch1_wgt**.

> **채널 정리 (`SRAM_group_decoder.sv` 주석 근거)** — `NOC_260902`가 실제로 흉내내는 건
> "L1 캐시"(`L1_Cache_Mimic`) 하나뿐이다. L2의 5개 채널 중 **L2가 항상 마스터인
> ch1_in(→CIM Cluster L1) / ch1_wgt(→CIM Cluster Array)** 만 이 모델로 대응 가능하고,
> ch2_in/ch2_wgt(→Vector Engine/Accumulator/Pooling Engine, 방향도 반대)는 대응하는
> RTL이 이 저장소에 없어 범위 밖이다.

```
verif/
  l2/     ... Phase 0/1 (L2 단독)
  noc/    ... Phase 2 STEP 0 (NOC 단독) + STEP 1 (이름 충돌 해소)
  integ/  ... Phase 2 STEP 2 (어댑터) + STEP 3 (통합 TB)   ← 이 문서가 다루는 부분
```

---

## 1. 왜 그냥 합치면 안 되는가

`L2_260901`(.sv)과 `NOC_260902`(.v)는 서로 다른 설계자가 만든 별도 IP라서 두 가지 문제가
있다.

### 1-1. 모듈 이름 충돌
두 폴더에 **이름은 같은데 포트/내용이 다른 모듈**이 6개 있다.

| 모듈 이름 | L2_260901 | NOC_260902 |
|---|---|---|
| `FIFO` | FIFO.sv | FIFO.v |
| `FIFO_modified` | FIFO_modified.sv | FIFO_modified.v |
| `FIFO_interface` | FIFO_interface.sv (L2_FIFO_interface와 다른, SRAM용) | FIFO_interface.v (M↔S 브리지) |
| `FIFO_interface_handshake` | ✓ | ✓ |
| `FIFO_interface_on_fire` | ✓ | ✓ |
| `sram_controller` | sram_controller.sv | sram_controller.v (내용 거의 동일하지만 별도 파일) |

한 시뮬레이션에 두 폴더를 그냥 다 컴파일하면 "모듈 재정의" 에러가 나거나, 최악의 경우
에러 없이 **엉뚱한 쪽 모듈로 바인딩**될 수 있다 (Vivado 프로젝트 모드처럼 라이브러리
구분이 약한 흐름에서 특히 위험).

### 1-2. 포트 이름·의미가 안 맞음
L2가 밖으로 내는 "NOC 마스터 포트"(`o_noc_write_*`, `o_noc_read_*` …)와 NOC 쪽
`FIFO_intf`가 기대하는 "마스터 포트"(`i_write_*_M`, `i_read_*_M` …)는 신호 이름도
다르고, 주소 폭도 다르다 (L2: 19비트 = multicast 8b + 로컬주소 11b / NOC: 11비트).
즉 단순히 이름만 맞춰 잇는 게 아니라 **주소 비트를 잘라내는 어댑터**가 필요하다.

이 두 문제를 푸는 게 STEP 1(이름 rename)과 STEP 2(어댑터)다.

---

## 2. STEP 1 — NOC 쪽 이름 충돌 해소 (`verif/noc/rename/`)

**원본(`rtl/NOC_260902/*.v`)은 전혀 건드리지 않았다.** 대신 충돌하는 6개 모듈만
`noc_` 접두어를 붙인 사본을 새로 만들고, 그 사본을 참조하는 상위 모듈들도 같이
사본으로 만들었다.

| 파일 | 내용 |
|---|---|
| `rename/noc_FIFO.v` | `module FIFO` → `module noc_FIFO` (내용 그대로) |
| `rename/noc_FIFO_modified.v` | `module FIFO_modified` → `module noc_FIFO_modified` |
| `rename/noc_FIFO_interface_handshake.v` | `module FIFO_interface_handshake` → `noc_FIFO_interface_handshake` (내부에 다른 충돌 모듈 인스턴스 없음) |
| `rename/noc_FIFO_interface_on_fire.v` | `module FIFO_interface_on_fire` → `noc_FIFO_interface_on_fire`; 내부 `FIFO` 인스턴스 2개 → `noc_FIFO` |
| `rename/noc_FIFO_interface.v` | `module FIFO_interface` → `noc_FIFO_interface`; 내부 `FIFO_interface_on_fire`/`_handshake` 인스턴스 → renamed 버전 |
| `rename/noc_sram_controller.v` | `module sram_controller` → `noc_sram_controller` |
| `rename/L1_FIFO_interface_on_fire.v` | **모듈명은 그대로**(충돌 아님) — 내부 `FIFO`/`FIFO_modified` 인스턴스만 `noc_FIFO`/`noc_FIFO_modified` 로 교체 |
| `rename/FIFO_intf.v` | **모듈명 그대로** — STEP 0에서 찾은 sim 버그 수정 + 내부 `FIFO_interface` 인스턴스를 `noc_FIFO_interface` 로 교체 |
| `rename/L1_Cache_Mimic.v` | **모듈명 그대로** — STEP 0 sim 버그 수정 + 내부 `sram_controller` 인스턴스를 `noc_sram_controller` 로 교체 |

`L1_FIFO_interface.v`, `L1_FIFO_interface_handshake.v`는 충돌 모듈을 인스턴스하지
않으므로 `rtl/NOC_260902/`의 원본을 그대로 쓴다.

통합용 파일 목록: **`verif/noc/noc_files_integ.f`** (top: `FIFO_intf`, 모듈명은
`FIFO_intf` 그대로라 L2 쪽과 안 겹침).

**검증**: `verif/noc/noc_files_integ.f` 로 `FIFO_intf` 를 단독 elaborate 하고,
STEP 0 의 write5→read5 TB(`tb_noc_fifo_intf.sv`)를 이 파일 목록으로 다시 돌려서
여전히 `PASS (errors=0)` 인지 확인함 — rename이 동작에 영향 없음을 증명.

---

## 3. STEP 2 — 어댑터 (`verif/integ/noc_ch1_in_adapter.sv`)

L2의 `TOP_L2_cache` ch1_in NOC 포트와 NOC의 `FIFO_intf` 마스터 포트를 1:1로 잇는
순수 배선(assign) 모듈. 상태(레지스터)는 없다.

### 3-1. 방향 확인
`cmd_decoder_channel_1_in.sv` 기준으로 ch1_in 은 커맨드에 따라 **둘 중 하나만** 씀:

| L2 커맨드 | 방향 | 쓰는 포트 |
|---|---|---|
| `ch1_in LOAD` (cmd_idx=1) | L2 내부 SRAM → NOC/L1 | `o_noc_write_*` (write path) |
| `ch1_in STORE` (cmd_idx=2) | NOC/L1 → L2 내부 SRAM | `o_noc_read_*` (read path) |

동시에 두 방향이 겹치지 않으므로, `FIFO_intf` 의 마스터 포트 하나(내부적으로
read/write 를 알아서 mux 하는 `FIFO_interface_on_fire`)를 그대로 공유해도 된다.

### 3-2. 신호 매핑표

`cmd_decoder_SRAM_group_read_interface.sv` 포트 주석(`i_sram_read_addr //o_read_addr`
형태)에서 추론 + STEP 3 시뮬레이션으로 실제 확인한 매핑:

| L2 (`TOP_L2_cache` ch1_in) | 방향 | NOC (`FIFO_intf` 마스터 포트) |
|---|---|---|
| `o_noc_write_valid_channel_1_in` | → | `i_write_valid` |
| `o_noc_write_addr_channel_1_in[10:0]` | → | `i_write_addr` |
| `o_noc_write_data_channel_1_in` | → | `i_write_data` |
| `i_noc_write_ready_channel_1_in` | ← | `o_FIFO_write_ready` |
| `i_noc_write_response_channel_1_in` | ← | `o_write_ready` |
| `o_noc_read_valid_channel_1_in` | → | `i_read_valid` |
| `o_noc_read_addr_channel_1_in[10:0]` | → | `i_read_addr` |
| `o_noc_read_data_ready_channel_1_in` | → | `i_data_fifo_ready` |
| `i_noc_read_ready_channel_1_in` | ← | `o_FIFO_read_ready` |
| `i_noc_read_response_channel_1_in` | ← | `o_read_ready` |
| `i_noc_read_data_channel_1_in` | ← | `o_read_data` |
| `o_noc_control_mode_channel_1_in` | → | `i_control_mode` |

### 3-3. 주소 폭 — multicast 비트 버리기
L2 ch1_in 의 NOC 주소는 19비트 = `{multicast[7:0], local_addr[10:0]}`.
`FIFO_intf` 는 `ADDR_DEPTH=2048` → `$clog2(2048)=11`비트 주소 공간만 있다.
→ 어댑터에서 **하위 11비트만** 잘라서 넘긴다 (`l2_noc_write_addr[ADDR_BW-1:0]`).
상위 8비트(multicast, 어느 cluster로 보낼지)는 실제 NOC 라우팅 하드웨어가 처리할
몫이라 `FIFO_intf` 한 개짜리 모델에는 없음 — 이번 검증 범위 밖.

### 3-4. control_mode
L2 `o_noc_control_mode = r_control_mode[0]` (ctrl_mode[1:0] 의 최하위 비트).
burst 모드(00/10)에서는 0 → NOC 쪽 `i_control_mode==0`(fire-on-valid)과 의미가
일치한다. **이번 STEP 3 는 burst 모드만 검증했다** — handshake 모드(01/11)는
`i_control_mode==1` 경로라서 별도 확인이 필요 (미착수).

---

## 4. STEP 3 — 통합 테스트벤치 (`verif/integ/tb/tb_l2_noc_ch1_in.sv`)

```
                    ┌───────────────┐   ch1_in NOC 포트   ┌────────────────────┐   ┌──────────┐
 i_command  ───────▶│  TOP_L2_cache │◀───────────────────▶│ noc_ch1_in_adapter │◀─▶│ FIFO_intf│──▶ L1_Cache_Mimic
 (dut_l2)           │  (ram_mimic   │                      │    (STEP 2)        │   │ (dut_noc,│    (backdoor 로
                     │   fix 적용)   │                      └────────────────────┘   │  STEP1   │     preload/검증)
                     └───────────────┘                                              │  renamed)│
                                                                                      └──────────┘
```

- `dut_l2` = `TOP_L2_cache` (파일 목록 `verif/l2/l2_files_ramfix.f` — ram_mimic
  polarity 수정판 사용. 원본 미수정, [FINDING_ram_mimic_polarity.md](../l2/FINDING_ram_mimic_polarity.md))
- `dut_noc` = `FIFO_intf` (파일 목록 `verif/noc/noc_files_integ.f` — STEP 1 rename +
  STEP 0 sim 버그 수정판)
- `u_adapter` = STEP 2 어댑터
- ch2_in / ch1_wgt / ch2_wgt 는 이번엔 전부 tie-off (Phase 1 TB 와 동일 패턴)

### 4-1. 시나리오 — 왜 이렇게 짰는가
L2 내부 SRAM도, L1_Cache_Mimic도 리셋 후 알 수 없는/0 값이라 "그냥 LOAD 한 번"으로는
의미 있는 데이터 비교가 안 된다 (Phase 1 GUIDE 5절에서 겪은 것과 같은 문제). 그래서:

1. **backdoor preload** — TB 가 계층 참조로 `L1_Cache_Mimic` 의 SRAM 배열에 직접
   `0xC0DE_0000+k` (k=0..4) 를 addr 0~4 에 심는다. (`dut_noc.UL1_Cache_Mimic.
   Usram_mimic_0.mem[k] = ...`) — 실제로는 L1 캐시에 이미 데이터가 있던 상황을 흉내.
2. **STORE** (L1 addr 0~4 → L2 SRAM addr 0~4) — NOC read path 경유.
3. **LOAD** (L2 SRAM addr 0~4 → **L1 addr 50~54**, 일부러 다른 주소) — NOC write
   path 경유. 목적지를 다르게 해서 "진짜로 그 경로를 통과했는지" 증명.
4. **backdoor 검증** — L1 addr 50~54 를 다시 계층 참조로 읽어 1단계 패턴과 비교.

### 4-2. 결과 — 2026-09-15 (최초) → 2026-09-22 (수정 후 재검증)

최초 결과 (버스트 첫 beat 유실 버그 발견):
```
L1[50] = 0x00000000   MISMATCH (expected 0xc0de0000)
L1[51] = 0xc0de0001   OK
L1[52] = 0xc0de0002   OK
L1[53] = 0xc0de0003   OK
L1[54] = 0xc0de0004   OK
  L2 <-> NOC integration (ch1_in) : CHECK   (errors=1)
```
**✅ 2026-09-22 수정 후**: `noc_FIFO_interface_on_fire.v`/`L1_FIFO_interface_on_fire.v`의
데이터 FIFO 입력 mux 우선순위를 고친 뒤 재실행하면 5/5 전부 `OK`, `PASS (errors=0)`.
근본 원인과 수정 내역 → [FINDING_first_write_beat_timing.md](FINDING_first_write_beat_timing.md) 8절.

---

## 5. 두 번째 채널 — ch1_wgt (`noc_ch1_wgt_adapter.sv`, `tb_l2_noc_ch1_wgt.sv`)

`cmd_decoder_channel_1_wgt.sv` 를 보면 ch1_wgt 는 **포트 모양이 ch1_in 과 완전히
동일**하다 — load/store 둘 다 L2 가 항상 마스터. 그래서 STEP 2/3 를 그대로 반복하되
폭만 바꿨다:

| | ch1_in | ch1_wgt |
|---|---|---|
| NOC 주소 폭 | 19b = multicast(8b) + local(11b) | 18b = multicast(8b) + local(**10b**) |
| 데이터 폭 | 512b | **256b** |
| `FIFO_intf` 파라미터 | `ADDR_DEPTH=2048, DATA_WIDTH=512` | `ADDR_DEPTH=1024, DATA_WIDTH=256` (RTL은 재사용, 파라미터만 다름) |
| 주소 조립 (write) | `{r_multicast, r_destination_start_addr[10:0]}` | `{r_multicast, r_destination_start_addr[9:0]}` |
| 주소 조립 (read) | `{w_multicast_store, r_source_start_addr_store[10:0]}` | `{w_multicast_store, r_source_start_addr_store[9:0]}` |

어댑터(`noc_ch1_wgt_adapter.sv`)는 `noc_ch1_in_adapter.sv` 와 로직이 100% 동일 —
파라미터(`DA_L2=18, ADDR_BW=10, DW=256`)만 다르게 인스턴스한다. `FIFO_intf` 도 새
RTL이 아니라 **같은 `verif/noc/rename/FIFO_intf.v` 를 다른 파라미터로 다시 인스턴스**
한 것뿐이다 (STEP 1 rename의 재사용성 확인).

시나리오는 4절과 동일한 패턴(backdoor preload → STORE → LOAD → backdoor 검증),
패턴 값만 `0xA11A_0000+k` 로, 목적지 주소만 60~64 로 바꿨다.

### 결과 — 2026-09-15 (최초) → 2026-09-22 (수정 후 재검증)

최초 결과:
```
NOC[60] = 0x00000000   MISMATCH (expected 0xa11a0000)
NOC[61] = 0xa11a0001   OK
NOC[62] = 0xa11a0002   OK
NOC[63] = 0xa11a0003   OK
NOC[64] = 0xa11a0004   OK
  L2 <-> NOC integration (ch1_wgt) : CHECK   (errors=1)
```
**ch1_in 과 정확히 같은 패턴** (버스트 첫 beat만 유실, 나머지 4개 완전 일치) —
폭·주소·어댑터·FIFO_intf 인스턴스가 전부 다른데도 증상이 똑같다는 건 채널별 우연이
아니라 NOC on-fire 브리지 공통 로직의 구조적 문제라는 강한 증거였고, 실제로 그렇게
확인됨. **✅ 2026-09-22 수정 후**: 5/5 전부 `OK`, `PASS (errors=0)`.

---

## 6. Vivado 에서 직접 실행하기

### 6-1. 빠른 실행 (headless)
```
verif\integ\00_run_integ.bat           REM ch1_in
verif\integ\01_run_integ_ch1_wgt.bat   REM ch1_wgt
```
컴파일→elaborate→run, 콘솔에 STEP A/B 로그와 `RESULT` 줄 출력. 파형은
`work\integ.wdb` / `work\integ_wgt.wdb` 에 저장.

### 6-2. 파형 GUI (신호 미리 배치)
```
verif\integ\10_wave_gui_integ.bat       REM ch1_in
verif\integ\11_wave_gui_integ_wgt.bat   REM ch1_wgt
```
Vivado XSim GUI 가 열리고 `wave_setup_integ.tcl` 이 아래 그룹으로 신호를 미리 올려
900ns 까지 실행해 둔다:
- `clock / reset / command`
- `L2 ch1_in FSM` (`current_state`, `o_load_busy`, `o_store_busy`)
- `STEP A STORE : L2 NOC-read path`
- `STEP B LOAD : L2 NOC-write path`
- `noc_ch1_in_adapter` (STEP 2 신호)
- `FIFO_intf -> L1_Cache_Mimic` (NOC 내부)

`F` = Zoom Fit, 버스 신호 우클릭 → Radix → Hexadecimal 로 보는 것을 추천.
`o_noc_write_addr_channel_1_in` 값이 50(0x32) 부근(ch1_wgt는 60(0x3C))일 때가 STEP B(LOAD)다.

### 6-3. 파일 구성
```
verif/integ/
  noc_ch1_in_adapter.sv          ch1_in 어댑터
  noc_ch1_wgt_adapter.sv         ch1_wgt 어댑터 (동일 로직, 파라미터만 다름)
  tb/tb_l2_noc_ch1_in.sv         ch1_in 통합 TB
  tb/tb_l2_noc_ch1_wgt.sv        ch1_wgt 통합 TB
  00_run_integ.bat / 10_wave_gui_integ.bat / wave_setup_integ.tcl           ch1_in 실행/파형
  01_run_integ_ch1_wgt.bat / 11_wave_gui_integ_wgt.bat / wave_setup_integ_wgt.tcl   ch1_wgt 실행/파형
  CONNECTION_GUIDE.md             (이 문서)
  FINDING_first_write_beat_timing.md   두 채널 모두에서 재현된 이슈
  work/                          빌드 산출물
```

---

## 7. 아직 안 한 것 / 다음 단계

- ~~버스트 첫 beat 유실 원인 확정 + 수정~~ → **✅ 2026-09-22 완료** ([FINDING_first_write_beat_timing.md](FINDING_first_write_beat_timing.md) 8절)
- FPGA 합성(`verif/fpga/`)은 이 수정을 참조하는 상태지만 **아직 재합성은 안 함** — 다음
  `build_synth.tcl` 실행부터 반영됨
- `l2_noc_fpga_top.sv`의 BIST 비교 지점이 L2 출력(버그 발생 이전 지점)이라 애초에
  이 버그를 못 잡는 구조였음 — L1측 최종 데이터를 보게 고치는 게 안전하지만 미적용
- 이 발견을 NOC 설계자(윤현준)에게 전달 필요 — `rtl/NOC_260902/` 원본은 아직 버그 있음
- **ch1_in / ch1_wgt handshake 모드**(ctrl_mode 01/11) 는 미검증 — `i_control_mode==1` 경로
- **ch2_in / ch2_wgt** — 상대가 Vector Engine/Accumulator/Pooling Engine 이라 `NOC_260902`
  (L1 캐시 모델)로 대응 불가. 방향도 ch2_in STORE 는 NOC 가 master 라 이번 어댑터 패턴을
  그대로 못 씀. PE/VE 를 흉내내는 TB BFM 을 새로 짜야 함 (연결 검증이 아니라 L2 단독 검증 성격)
- resize 있는 load, first/last addr 순환, ch1_wgt custom load(LCU/LCC 매핑) 등 다른 커맨드 변형들
