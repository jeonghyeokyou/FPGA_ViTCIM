# PROJECT_SUMMARY — L2 캐시 + NOC 통합 검증 및 FPGA 구현

> 이 문서는 이 프로젝트를 처음 접하는 사람이나 AI 어시스턴트가 이전 대화 없이 전체
> 맥락을 파악하도록 쓴 것입니다. 마지막 갱신: 2026-10-05.

---

## 0. 한눈에 보기

- **무엇을**: 다른 사람이 설계한 RTL 블록 2개를 검증하고, 하나로 합쳐서 FPGA에 올림
  - `L2_260901`: L2 캐시. SystemVerilog, 최상위 모듈 `TOP_L2_cache`
  - `NOC_260902`: NOC 브리지와 L1 캐시 모델. Verilog, 최상위 모듈 `FIFO_intf`
- **도구**: Vivado 2024.2 XSim (`C:\Xilinx\Vivado\2024.2`), Windows 11
- **타겟 보드**: Xilinx ZCU102 (`xczu9eg-ffvb1156-2-e`)
- **저장소**: `C:\RTL_YJH\L2_verification` → GitHub private 저장소 `jeonghyeokyou/FPGA_ViTCIM`
- **현재 상태**: 단독 검증과 통합 검증(2개 채널) 모두 통과, FPGA 합성·배치·배선·타이밍 통과.
  **실제 보드에서는 아직 돌려보지 않음.**

---

## 1. 작업 원칙 (반드시 지킬 것)

1. **`rtl/` 아래 원본 RTL은 절대 수정하지 않는다.** 원본은 설계자에게 버그를 보고할 때 기준이 되는
   사본이기 때문이다. 수정은 `verif/` 아래 사본에서만 한다.
   - `verif/l2/fix/`, `verif/noc/fix/`: 버그 수정본
   - `verif/noc/rename/`: 모듈 이름 충돌을 피하려고 이름을 바꾼 사본 (버그 #6 수정도 여기 반영됨)
   - `verif/fpga/fpga_fix/`: FPGA 합성용으로 고친 사본
2. 버그를 찾으면 `FINDING_*.md`로 문서화한다. 위치, 증상, 원인, 재현 방법, 수정 내용, 영향을 적는다.
3. 사용자는 RTL 검증과 Vivado를 처음 배우는 중이다. 결과만 주지 말고 **왜 그렇게 되는지 단계별로
   설명**하는 것을 원한다. 대화는 한국어로 한다.
4. git 커밋은 작업 단위로 하고 GitHub에 push한다.
5. 이 저장소는 공동작업자(GitHub 아이디 `JUN4216`)와 함께 쓴다. `LHJ/` 폴더는 공동작업자의 작업 공간이다.
   push하기 전에 항상 `git pull --rebase`로 상대 작업을 먼저 받는다. 강제 push는 하지 않는다.

---

## 2. 디렉터리 구조

```
L2_verification/
├─ rtl/
│   ├─ L2_260901/          원본 L2 RTL (34개 파일)      ← 수정 금지
│   └─ NOC_260902/         원본 NOC RTL                 ← 수정 금지
├─ verif/
│   ├─ README.md, GUIDE_phase2_integration.md
│   ├─ l2/                 L2 단독 검증
│   │   ├─ fix/ram_mimic.sv            버그 #1 수정본
│   │   ├─ l2_files.f, l2_files_ramfix.f
│   │   ├─ tb/                         테스트벤치
│   │   ├─ FINDING_ram_mimic_polarity.md
│   │   └─ GUIDE_phase1_ch1_in.md      초보자용 해설
│   ├─ noc/                NOC 단독 검증
│   │   ├─ fix/                        버그 #2~#4 수정본
│   │   ├─ rename/                     noc_ 접두어 사본 + 버그 #6 수정본
│   │   ├─ noc_files_fix.f (단독 테스트용), noc_files_integ.f (통합용)
│   │   └─ FINDING_noc_sim_bugs.md
│   ├─ integ/              L2+NOC 통합 검증
│   │   ├─ noc_ch1_in_adapter.sv, noc_ch1_wgt_adapter.sv
│   │   ├─ tb/tb_l2_noc_ch1_in.sv, tb/tb_l2_noc_ch1_wgt.sv
│   │   ├─ 00_run_integ.bat (ch1_in), 01_run_integ_ch1_wgt.bat (ch1_wgt)
│   │   ├─ 10_wave_gui_integ.bat, 11_wave_gui_integ_wgt.bat (파형 보기)
│   │   ├─ CONNECTION_GUIDE.md         L2와 NOC를 어떻게 연결했는지 설명
│   │   └─ FINDING_first_write_beat_timing.md   버그 #6 (해결됨)
│   └─ fpga/               FPGA 합성
│       ├─ l2_noc_fpga_top.sv          합성 대상 최상위
│       ├─ fpga_fix/sram_mimic_fpga.v
│       ├─ fpga_files.f                합성에 쓰는 파일 48개 목록
│       ├─ build_synth.tcl             합성부터 배선까지 자동 실행
│       ├─ constraints.xdc             임시 제약 (클럭만 지정)
│       ├─ zcu102_wrapper.sv, constraints_zcu102.xdc   실보드용 (아직 안 씀)
│       ├─ build/*.rpt                 합성 리포트
│       ├─ SYNTH_RESULTS.md, HW_SPEC.md
│       └─ GUIDE_synthesis_gui.md      Vivado GUI로 직접 합성하는 실습 가이드
├─ share/
│   ├─ l2_noc_fpga_rtl/    공동작업자 공유용: RTL 48개 + files.f + README (단독으로 컴파일 확인됨)
│   └─ l2_noc_fpga_rtl.zip
├─ LHJ/                    공동작업자(JUN4216)가 9/29에 올린 PS↔L2 연결 작업 (6.5절)
├─ RTL_FIFO_첫_데이터_오류_설명과_수정.md   버그 #6 원인 분석 (공동작업자가 작성)
└─ PROJECT_SUMMARY.md      (이 문서)
```

`.gitignore`로 빌드 산출물을 제외했습니다 (`work/`, `xsim.dir/`, `*.dcp`, `*.wdb`, `vivado_proj/` 등).
제외하지 않으면 약 500 MB, 제외하면 약 2 MB입니다.

---

## 3. 설계 구조

### 3.1 L2 캐시 (`TOP_L2_cache`)

- 내부 SRAM은 `ram_mimic` 인스턴스를 GROUPS × BLOCKS 개 배열한 구조다. 인스턴스 하나는 64비트 폭에 ADDRESS_ROW 행.
- 이 SRAM에 접근하는 채널이 5개 있다. **5개 채널은 같은 물리 메모리를 공유**하고, 워드 폭만 다르게 본다.

| 채널 | 데이터 폭 | 상대 블록 | 이 NOC 모델로 검증 가능? |
|---|---|---|---|
| ch0 | 64b | AXI 형태의 호스트 접근 | 해당 없음 (현재 연결 안 함) |
| ch1_in | 512b | CIM 클러스터의 L1 캐시 | ✅ 검증 완료 |
| ch1_wgt | 256b | CIM 가중치 | ✅ 검증 완료 |
| ch2_in | 256b | Vector Engine 등 | ❌ 상대 RTL이 없음 |
| ch2_wgt | 256b | Vector Engine | ❌ 상대 RTL이 없음 |

- ch0은 AXI와 비슷하지만 완전한 AXI4는 아니다. ID, SIZE, BURST, WSTRB, RESP 신호가 없다.

### 3.2 명령 인터페이스

- 신호: `i_command[63:0]`, `i_command_valid`, `o_command_ready`, 그리고 완료 확인용 `o_busy_channel_1_in`
- **명령에는 데이터가 들어있지 않다.** 주소, 길이, 모드만 담는다. 실제 데이터는 두 메모리 사이를 자동으로 오간다.
- `o_command_ready`는 "명령 큐(64개 깊이)에 넣을 자리가 있다"는 뜻이다. 명령이 끝났다는 뜻이 아니다.
  완료 여부는 `busy`가 1이 됐다가 다시 0이 되는 것으로 확인한다.
- 방향은 L2 기준이다.
  - STORE: NOC → L2
  - LOAD: L2 → NOC

64비트 명령어 필드 (`cmd_decoder_channel_1_in.sv` 기준):

| | STORE | LOAD |
|---|---|---|
| [62:60] cmd_idx | `010` | `001` |
| [59:58] 모드 | `10` = burst | `00` = burst |
| L2쪽 주소 | [57:41] 도착 주소 | [56:40] 출발 주소 |
| 길이 (beat 수 − 1) | [40:27] | [39:29] |
| NOC쪽 주소 | [26:13] 출발 주소 | [28:18] 도착 주소 |
| multicast | — | [14:7] |

### 3.3 L2와 NOC 연결

`TOP_L2_cache`의 ch1_in 포트 → `noc_ch1_in_adapter` → `FIFO_intf`

- 어댑터는 순수 조합논리다 (클럭과 리셋 없음).
- 주소는 19비트 중 하위 11비트만 넘긴다. 상위 8비트(multicast)는 버린다.
- 신호 이름의 write/read는 L2 입장이다. 그래서 LOAD 때 `*_write_*` 신호를, STORE 때 `*_read_*` 신호를 쓴다.
- ready와 response는 이름이 엇갈려서 연결된다.
  - `l2_noc_write_ready` ← `o_FIFO_write_ready`
  - `l2_noc_write_response` ← `o_write_ready`
- 신호 단위 전체 대응표는 `verif/integ/CONNECTION_GUIDE.md`에 있다.

### 3.4 NOC 쪽 (`FIFO_intf`)

`FIFO_intf` 안에는 `noc_FIFO_interface_on_fire`(NOC 브리지)와 `L1_Cache_Mimic`(L1 캐시 모델)이 있다.
`L1_Cache_Mimic` 안에는 `sram_mimic`이 4개 있다.

- 이것은 실제 L1 캐시가 아니라 **흉내낸 대역 모델(mimic)**이다.
- L2와 달리 채널마다 `FIFO_intf` 인스턴스를 따로 만든다.

---

## 4. 찾은 버그 (6건, 전부 수정본에서 처리)

| # | 파일 | 내용 | 문서 |
|---|---|---|---|
| 1 | `ram_mimic.sv` (L2) | 원본은 `if(ena)`(active-HIGH)인데 설계는 active-LOW로 구동함. SRAM이 아예 동작하지 않았음 | `verif/l2/FINDING_ram_mimic_polarity.md` |
| 2 | `FIFO_intf.v` (NOC) | 하위 모듈에 없는 `.MEMORY_BITWIDTH` 파라미터를 넘겨서 elaborate 실패 | `verif/noc/FINDING_noc_sim_bugs.md` |
| 3 | `sram_mimic.v` (NOC) | `o_dout`이 `input`으로 선언됨 | 위와 같음 |
| 4 | `L1_Cache_Mimic.v` (NOC) | `o_read_data`가 `input`으로 선언됨 | 위와 같음 |
| 5 | `FIFO_intf` (NOC) | `i_pe_busy`가 연결되지 않음 → 0으로 고정 | 위와 같음 |
| **6** | `noc_FIFO_interface_on_fire.v`, `L1_FIFO_interface_on_fire.v` | **STORE 직후 LOAD를 하면 첫 beat 데이터가 오염됨** | `verif/integ/FINDING_first_write_beat_timing.md` 8절 |

### 버그 #6 상세 (가장 중요)

**원인**: 데이터 FIFO에 넣을 값을 고르는 mux가 "이전 읽기 상태(`r_read_signal`)"를 "지금 들어온 쓰기
요청(`i_write_valid_M`)"보다 먼저 확인했다. STORE(읽기)가 끝난 뒤에도 `r_read_signal`이 1로 남아 있어서,
LOAD(쓰기)의 첫 클럭에 읽기 쪽 값이 잘못 선택됐다. 둘째 beat부터는 정상이다.

**수정**: 두 파일에서 각 한 줄씩 우선순위를 뒤집었다.

```verilog
// 원본 (버그)
assign w_input_data_data = (r_read_signal) ? i_read_data_S
                         : ((i_write_valid_M) ? i_write_data_M : 0);
// 수정
assign w_input_data_data = (i_write_valid_M) ? i_write_data_M
                         : ((r_read_signal) ? i_read_data_S : 0);
```

**찾은 경위**: 공유본을 받은 공동작업자가 Verilator와 Icarus로 따로 분석해서 원인을 찾았다
(`RTL_FIFO_첫_데이터_오류_설명과_수정.md`). 처음에 이 프로젝트에서 세운 가설(`r_write_signal`의
pop 타이밍 문제)은 틀렸다.

**FPGA BIST가 이 버그를 못 잡은 이유**: BIST는 L2 출력을 비교했는데, 버그는 그보다 뒤쪽(NOC FIFO)에서
생긴다. 즉 비교 지점이 잘못돼 있었다.

**설계자 미전달**: `rtl/NOC_260902/`의 원본에는 아직 이 버그가 그대로 있다.

---

## 5. 검증 결과

| 테스트 | 실행 방법 | 결과 |
|---|---|---|
| L2 단독 STORE→LOAD | `verif/l2/12_run_l2_ch1_in_storeload_ramfix.bat` | 5/5 PASS |
| NOC 단독 쓰기 5개 → 읽기 5개 | `verif/noc/10_run_noc_tb.bat` | PASS |
| 통합 ch1_in (512b) | `verif/integ/00_run_integ.bat` | **5/5 PASS** (버그 #6 수정 후) |
| 통합 ch1_wgt (256b) | `verif/integ/01_run_integ_ch1_wgt.bat` | **5/5 PASS** (버그 #6 수정 후) |
| 공유 폴더 단독 빌드 | `xvlog -sv -f files.f` 후 `xelab l2_noc_fpga_top` | 에러 0 |

통합 테스트 시나리오:
1. L1 메모리에 테스트 패턴을 직접 써 넣는다 (backdoor preload)
2. STORE로 L1 → L2
3. LOAD로 L2 → L1의 다른 주소
4. L1 메모리를 직접 읽어 5개 beat를 512비트 전체로 비교한다

---

## 6. FPGA 구현 (`verif/fpga/`)

### 6.1 최상위 `l2_noc_fpga_top`

- 구성: `TOP_L2_cache` + `noc_ch1_in_adapter` + `FIFO_intf` + BIST FSM
- BIST FSM은 테스트벤치가 아니라 **합성되는 회로**다. 리셋이 풀리면 혼자 STORE와 LOAD를 실행하고 결과를 LED로 표시한다.
- 외부 포트는 5개: `i_clk`, `i_rst_n`, `o_led_done`, `o_led_pass`, `o_mismatch_count[2:0]`
- 사용하지 않는 채널(ch0, ch2_in, ch1_wgt, ch2_wgt)은 고정값으로 묶어 둠 (tie-off)
- 클럭 도메인은 하나뿐이다. 리셋은 플립플롭 3만여 개에 연결돼서 Vivado가 글로벌 버퍼(BUFG)에 올렸다.

### 6.2 파라미터와 스펙 (자세한 내용은 `HW_SPEC.md`)

| 항목 | 값 |
|---|---|
| L2 파라미터 | GROUPS=8, BLOCKS=16, ADDRESS_ROW=256 → **256 KB** (원본은 BLOCKS=32, ADDRESS_ROW=2048 → 4 MB) |
| NOC 메모리 | 2048 워드 × 512b = 128 KB |
| 동작 주파수 | 100 MHz 제약에서 WNS +3.117 ns → 최대 약 145 MHz 추정 (재합성으로 확인 필요) |
| hold 여유 (WHS) | +0.014 ns (통과했지만 여유가 매우 적음) |
| 자원 사용률 | LUT 17.0%, FF 5.8%, BRAM 17.3% (158/912 타일), DSP 0%, URAM 0 (이 칩엔 없음) |
| 대역폭 (이론값) | ch1_in 512b × 100 MHz = 6.4 GB/s |

### 6.3 제약과 알아둘 점

- `GROUPS`는 8로 고정해야 한다. wrapper 안에 8을 전제로 한 코드가 하드코딩돼 있다.
- `BLOCKS`는 16이 최솟값이다. 8 이하로 하면 `$clog2` 결과가 0이 돼서 에러가 난다.
- 용량을 줄인 이유는 합성 시간 단축이었다. 결과적으로 BRAM 한계도 맞았다:
  4 MB는 BRAM 약 1056타일이 필요해서 들어가지 않고(912 초과), 2 MB는 약 544타일로 들어간다.
- RTL의 `ram_style="ultra"`는 이 칩(ZU9EG)에 UltraRAM이 없어서 무시되고 BRAM으로 대체된다. 에러는 아니다.
- DRC 경고 2건(NSTD-1, UCIO-1)은 핀을 아직 지정하지 않아서 생긴다. bitstream을 만들 때만 문제가 된다.

### 6.4 실보드 준비물 (아직 사용 안 함)

- `zcu102_wrapper.sv`
  - 보드 클럭은 300 MHz 차동(`USER_SI570_P/N`)이라서 Clocking Wizard IP(`clk_wiz_0`)로 100 MHz로 바꿔야 한다.
  - 보드 리셋 버튼 `CPU_RESET`은 active-HIGH라서 반전해야 한다.
- `constraints_zcu102.xdc`: 핀 정보는 Vivado에 설치된 board file과 사용자가 받은 마스터 XDC에서 가져와 서로 대조했다.
  - LED: AG14 / AF13 / AE13 / AJ14 / AJ15
  - 리셋: AM13
  - 클럭: AL8 / AL7

### 6.5 공동작업자 작업: PS ↔ L2 ch0 (`LHJ/`, 2026-09-29)

공동작업자가 PS(ARM)에서 AXI4로 L2 내부 SRAM을 직접 읽고 쓰는 경로를 구현했다. 7절에서 말하는 "방법 B"를
**NOC 없이 L2만 대상으로** 구현한 것이다. 이 경로는 NOC FIFO를 지나지 않으므로 버그 #6과는 관계없다.

```
PS (HPM0) 또는 AXI CDMA ──AXI4──▶ axi4_l2_ch0_bridge ──▶ TOP_L2_cache의 ch0
```

| 파일 | 역할 |
|---|---|
| `l2_ps_pl_top.sv` | 최상위. 브리지와 `TOP_L2_cache`를 묶는다. 기본값 8/16/256으로 256 KiB, ch0 주소 폭 15비트 |
| `axi4_l2_ch0_bridge.sv` | 완전한 AXI4 슬레이브 신호를 L2 ch0의 간소화된 신호로 바꾼다. 3.1절에서 말한 "ch0은 완전한 AXI4가 아니다" 문제를 해결하는 변환 회로(shim)다 |
| `l2_ps_pl_bd_wrapper.v` | Vivado Block Design에 모듈로 넣기 위한 Verilog-2001 래퍼. 배선만 하고 AXI 인터페이스 정보를 붙인다 |
| `ram_mimic_fpga_bram.sv` | 극성 수정본(버그 #1)과 같고, `ram_style`만 `"block"`으로 바꿨다. UltraRAM이 없는 ZU9EG에 맞춘 것 |
| `l2_fpga_test` | 내용이 "ABC"뿐인 테스트용 파일. 의미 없음 |

`axi4_l2_ch0_bridge.sv`가 지원하는 범위 (파일 헤더 주석 기준):
- 데이터 폭 64비트 또는 128비트
- 워드 단위로 정렬된 INCR 버스트(1~256 beat), FIXED는 1 beat만
- 쓰기 시 `WSTRB`가 모두 1이어야 한다. 바이트 단위 부분 쓰기(read-modify-write)는 지원하지 않는다
- 잘못된 요청에는 `SLVERR`로 응답하고, 리셋할 때까지 오류 상태를 유지한다
- 대기열은 2칸, 동시에 처리 중인 요청은 1개
- 상위 주소 해석은 SmartConnect가 맡는다. Vivado Address Editor의 range를 L2 메모리 크기(256 KiB)와 같게 잡아야 한다

`LHJ/`의 L2 RTL 33개는 `rtl/L2_260901/`과 **완전히 같다** (2026-10-05에 diff로 확인).

**이 프로젝트 쪽에서는 아직 이 코드를 시뮬레이션하거나 합성하지 않았다.**

---

## 7. 앞으로 할 일

1. **FPGA 재합성**: 마지막 합성(`build/`)은 버그 #6 수정 전 RTL로 했다. `build_synth.tcl`이
   `verif/noc/rename/`을 읽으므로 다시 실행하면 수정본이 반영된다.
2. **BIST 비교 지점 이동**: L2 출력이 아니라 L1에 최종 저장된 데이터를 비교하도록 바꾼다.
   그래야 버그 #6 같은 문제를 다시 잡을 수 있다.
3. **NOC 설계자(윤현준)에게 버그 #6 전달**
4. **공동작업자에게 공유본 다시 전달**: 9/18에 보낸 zip에는 버그 #6이 남아 있다. 현재 `share/`는 최신 상태다.
5. **실보드 올리기**: Clocking Wizard IP 생성 → top을 `zcu102_wrapper`로 변경 → bitstream 생성 → JTAG로 프로그래밍
6. **PS(ARM) 연결**
   - 방법 B의 L2 부분(PS가 ch0으로 L2 SRAM에 데이터를 직접 읽고 쓰기)은 **공동작업자가 구현했다** (6.5절).
     남은 일은 이 코드를 시뮬레이션하고 실보드에서 확인하는 것이다.
   - 방법 A는 아직 안 했다. BIST 자리에 AXI4-Lite 레지스터 모듈(`axi_lite_l2_ctrl`)을 넣어 PS가 명령을
     보내게 하는 것이다. 레지스터 예: CMD_LO/CMD_HI, CTRL(valid 펄스), STATUS(ready, busy), MISMATCH.
     A를 하면 PS가 STORE와 LOAD 사이 간격을 조절할 수 있어서 타이밍 실험도 할 수 있다.
   - 최종적으로는 공동작업자의 ch0 경로(데이터 입력)와 방법 A(명령 입력), 그리고 NOC를 하나의 top으로 합쳐야
     "PS가 데이터를 넣고 → 명령으로 NOC와 주고받고 → 다시 읽어 확인"하는 전체 시험이 가능하다.
7. **아직 검증 안 한 범위**
   - handshake 모드 (`control_mode` = 01, 11)
   - resize 명령
   - 큐에 쌓인 명령이 연속 실행되는 경우
   - 읽기와 쓰기 요청이 같은 클럭에 겹치는 경우

---

## 8. 실행할 때 알아둘 점

- `.bat` 파일 안에서 `xvlog`, `xelab`을 부를 때는 앞에 `call`을 붙여야 한다. 둘 다 그 자체가 `.bat` 파일이라 `call` 없이 부르면 스크립트가 중간에 끝난다.
- `xsim --tclbatch`에 경로를 넘길 때는 슬래시(`/`)를 쓴다. 역슬래시는 Tcl이 이스케이프 문자로 해석해서 경로가 깨진다.
- `xelab -generic_top`으로는 하위 인스턴스의 파라미터를 바꿀 수 없다. `.sv` 파일의 기본값을 직접 고쳐야 한다.
- `.sv` 파일은 `-sv` 옵션으로 읽어야 한다. 공유 폴더는 `xvlog -sv -f files.f` 한 줄로 `.v` 파일까지 전부 통과한다.
