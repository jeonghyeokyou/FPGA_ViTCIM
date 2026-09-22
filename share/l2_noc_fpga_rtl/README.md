# L2 + NOC 통합 RTL (FPGA 합성용)

`L2_260901`(L2 캐시)과 `NOC_260902`(NOC/L1 캐시 모델)를 하나로 합쳐서
FPGA에 합성 가능하게 만든 RTL 묶음입니다. 파일 48개, 전부 이 폴더에 평평하게 들어있습니다.

- **최상위 모듈**: `l2_noc_fpga_top`
- **검증 환경**: Vivado 2024.2 / ZCU102 (`xczu9eg-ffvb1156-2-e`)
- **상태**: 합성·배치·배선·타이밍 전부 통과 (100MHz, WNS +3.117ns), 통합 시뮬레이션 5/5 완전 PASS

---

## 1. 빌드 방법

파일 목록은 `files.f`에 있습니다 (이 폴더 기준 상대경로).

### 시뮬레이션 (XSim)
```
xvlog -sv -f files.f
xelab -debug typical l2_noc_fpga_top -s top_sim
xsim top_sim
```

### 합성 (Vivado)
```tcl
create_project -in_memory -part xczu9eg-ffvb1156-2-e
foreach f [split [string trim [read [open files.f r]]] "\n"] {
    if {[string match "#*" $f] || $f eq ""} { continue }
    if {[string match "*.sv" $f]} { read_verilog -sv $f } else { read_verilog $f }
}
synth_design -top l2_noc_fpga_top -part xczu9eg-ffvb1156-2-e
```

---

## 2. ⚠️ 원본과 다른 파일이 있습니다

**이 폴더의 파일 중 일부는 원본 RTL이 아니라 수정된 사본입니다.** 원본 저장소와
비교하기 전에 아래를 먼저 읽어주세요. 원본 `L2_260901` / `NOC_260902` 폴더는
**전혀 건드리지 않았고**, 수정은 전부 사본에만 했습니다.

### 2-1. 기능 버그 수정

| 파일 | 무엇을 고쳤나 |
|---|---|
| `ram_mimic.sv` | **극성 버그.** 원본은 `if(ena)`/`if(wea)` (active-HIGH)인데, L2의 나머지 설계는 SRAM 인터페이스를 **active-LOW**로 구동합니다. 이 사본은 `if(!ena)`/`if(!wea)`로 뒤집었습니다. |
| `sram_mimic_fpga.v` | ① `o_dout`이 원본에서 `input`으로 선언돼 있어 읽기 경로가 끊겨 있던 것을 `output`으로 수정 ② BRAM 추론을 막는 전체 배열 리셋 루프 제거 ③ BIST용 초기 패턴 preload 추가 |
| `L1_Cache_Mimic.v` | `o_read_data`가 `input`으로 선언돼 있던 것을 `output`으로 수정 |
| `FIFO_intf.v` | 하위 모듈이 선언하지도 않은 `.MEMORY_BITWIDTH` 파라미터를 넘겨서 elaboration이 실패하던 것 제거 |
| **`noc_FIFO_interface_on_fire.v`** | **(2026-09-22 추가)** 버스트 STORE→LOAD 전환 시 **첫 write beat 데이터가 유실되던 버그** 수정. 데이터 FIFO 입력 mux가 "이전 읽기 상태(`r_read_signal`)"를 "지금 온 쓰기 요청(`i_write_valid_M`)"보다 먼저 확인해서, 읽기 직후 첫 쓰기 beat의 데이터가 잘못 선택됐음. 우선순위를 뒤집어 수정 (아래 2-3절) |
| **`L1_FIFO_interface_on_fire.v`** | **(2026-09-22 추가)** 위와 동일한 종류의 버그, 동일한 방식으로 수정 |

### 2-2. 이름 충돌 회피용 rename

두 저장소에 **같은 이름·다른 구현**의 모듈이 6개 있어서, 합쳐서 합성하면 잘못
바인딩됩니다. NOC 쪽 모듈에 `noc_` 접두어를 붙여 해결했습니다.

| 원본 이름 (NOC_260902) | 이 폴더에서 |
|---|---|
| `FIFO` | `noc_FIFO` |
| `FIFO_modified` | `noc_FIFO_modified` |
| `FIFO_interface` | `noc_FIFO_interface` |
| `FIFO_interface_handshake` | `noc_FIFO_interface_handshake` |
| `FIFO_interface_on_fire` | `noc_FIFO_interface_on_fire` |
| `sram_controller` | `noc_sram_controller` |

`L1_FIFO_interface_on_fire.v`, `L1_Cache_Mimic.v`, `FIFO_intf.v`는 **모듈 이름은
그대로**이고, 내부에서 위 모듈들을 부르는 인스턴스 참조만 바뀌었습니다.

### 2-3. 버스트 첫 beat 데이터 유실 버그 — 상세 (2026-09-22 해결)

**증상**: STORE(읽기) 직후 같은 세션에서 리셋 없이 LOAD(쓰기)로 넘어가면, 버스트의
**첫 beat 데이터만** 잘못된 값으로 저장됨 (주소는 정확). 두 번째 beat부터는 정상.

**원인**: `noc_FIFO_interface_on_fire.v` / `L1_FIFO_interface_on_fire.v` 둘 다
데이터 FIFO에 넣을 값을 고르는 조합논리 mux가 이렇게 되어 있었습니다:

```systemverilog
// 원본 (버그) — 이전 읽기 상태가 1이면 지금 쓰기 요청이 와도 무시
assign w_input_data_data = (r_read_signal) ? i_read_data_S
                         : ((i_write_valid_M) ? i_write_data_M : {(DATA_WIDTH){1'b0}});
```

`r_read_signal`(이전 읽기 상태를 기억하는 레지스터)이 새 쓰기 요청의 **첫 클럭에는
아직 0으로 안 내려가 있어서**, 그 클럭에 읽기 쪽 값(이 시점엔 무의미한 값)이 잘못
선택되어 FIFO에 들어갑니다. 두 번째 beat부터는 같은 클럭에 `r_read_signal`이 이미
0으로 갱신되어 있어 정상 동작합니다.

**수정**: 우선순위를 뒤집어 "지금 온 쓰기 요청"이 항상 이기게 함 (1줄):

```systemverilog
// 수정
assign w_input_data_data = (i_write_valid_M) ? i_write_data_M
                         : ((r_read_signal) ? i_read_data_S : {(DATA_WIDTH){1'b0}});
```

`L1_FIFO_interface_on_fire.v`도 신호 이름만 다르고(`i_write_valid`/`i_write_data`/
`i_read_data_L1`) 동일하게 수정했습니다.

**검증**: STORE→LOAD 왕복 통합 테스트를 두 채널(ch1_in 512b, ch1_wgt 256b)에서
재실행 — 수정 전엔 5 beat 중 beat 0만 항상 실패했는데, 수정 후 **5/5 전부 정확히
일치**로 확인됨.

### 2-4. 새로 작성한 파일

| 파일 | 역할 |
|---|---|
| `noc_ch1_in_adapter.sv` | L2의 channel 1_in NOC 포트 ↔ `FIFO_intf` 포트 연결. 순수 조합논리 |
| `l2_noc_fpga_top.sv` | 최상위. `TOP_L2_cache` + 어댑터 + `FIFO_intf` + 자체 테스트(BIST) 시퀀서 |

### 2-5. 손대지 않은 원본

나머지 파일(L2 33개 + NOC 2개)은 원본 그대로입니다.

---

## 3. 최상위 모듈이 하는 일

`l2_noc_fpga_top`은 호스트 인터페이스 없이 **혼자 자가 테스트**를 돌립니다.

1. 합성 시점에 NOC측 메모리 주소 0~4에 `0xDEAD_BEE0`~`0xDEAD_BEE4`가 BRAM 초기값으로 구워짐
2. 리셋 해제 후 BIST FSM이 자동으로 **STORE** 실행 — NOC[0..4] → L2 내부 SRAM[0..4]
3. 10클럭 후 **LOAD** 실행 — L2 SRAM[0..4] → NOC[20..24]
4. LOAD 중 나가는 5 beat를 기대값과 비교, 결과를 LED로 출력

포트는 5개뿐입니다:

| 포트 | 폭 | 의미 |
|---|---|---|
| `i_clk` | 1 | 클럭 (100MHz 가정) |
| `i_rst_n` | 1 | 비동기 리셋, active-low |
| `o_led_done` | 1 | BIST 종료 |
| `o_led_pass` | 1 | done && mismatch==0 |
| `o_mismatch_count` | 3 | 틀린 beat 개수 |

**주의**: 이 BIST의 비교 지점(`o_noc_write_data_channel_1_in`)은 L2가 데이터를
내보내는 시점 — 즉 위 2-3절 버그가 발생하는 지점보다 **앞쪽**입니다. 그래서 원래
버그가 있던 상태에서도 이 BIST 자체는 항상 PASS를 보고했습니다 (버그를 못 잡는
구조였던 것). 지금은 버그 자체가 고쳐졌으니 문제 없지만, 앞으로 비슷한 종류의
버그를 다시 잡으려면 최종 L1측 데이터를 비교하도록 바꾸는 게 더 안전합니다.

### 파라미터 (축소판)

```
GROUPS = 8, BLOCKS = 16, ADDRESS_ROW = 256   →  L2 내부 SRAM 256 KB
```

원본 기본값은 `GROUPS=8, BLOCKS=32, ADDRESS_ROW=2048` (4MB)이지만, 합성 시간을
줄이려고 축소했습니다. 키울 때 주의:

- **`GROUPS`는 8에서 바꿀 수 없습니다.** `cmd_decoder_channel_*_wrapper.sv` 안에
  GROUPS=8을 전제한 2단 그룹 분할이 하드코딩돼 있어, 다른 값이면 elaboration 에러가 납니다.
- **`BLOCKS`는 8의 배수이면서 몫이 2 이상**이어야 합니다. 최솟값 16.
- `ADDRESS_ROW`는 자유롭게 조정 가능합니다.
- 참고: 원본 4MB 구성은 BRAM 약 1056타일이 필요한데 ZU9EG는 912타일뿐이라
  **ZCU102에 들어가지 않습니다.** 2MB(`BLOCKS=16, ADDRESS_ROW=2048`)까지는 여유 있게 들어갑니다.

---

## 4. 문의

이 묶음은 검증 작업 중 만들어진 것입니다. 원본 RTL, 테스트벤치, 합성 스크립트,
상세 분석 문서는 원 저장소의 `verif/` 폴더에 있습니다.
