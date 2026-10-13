# BLACKBOX_TASK.md — Blackbox IP system-level 검증 작업 지시서 (Claude Code용)

> 작성: 2026-10-06 · 작업자: JH (유정혁) · 저장소: `C:\RTL_YJH\L2_verification` (GitHub `jeonghyeokyou/FPGA_ViTCIM`)
>
> **Claude Code에게**: 이 문서는 작업 지시서다. 위에서부터 끝까지 읽은 뒤 **JH가 지정한 Phase만** 진행한다.
> 각 Phase가 끝나면 "Gate"에 적힌 보고를 하고 **멈춰서 JH의 확인을 기다린다.** 다음 Phase로 마음대로 넘어가지 않는다.
> JH는 RTL 검증과 Vivado를 배우는 중이다. 결과만 주지 말고 **왜 그렇게 되는지를 한국어로 짧게 설명**한다.

---

## 0. 먼저 읽을 것 (순서대로)

| 파일 | 왜 읽나 |
|---|---|
| `PROJECT_SUMMARY.md` | 프로젝트 전체 맥락 (L2/NOC, 버그 6건, 공동작업자 작업) |
| `verif/integ/CONNECTION_GUIDE.md` | L2 ch1_in ↔ `FIFO_intf` 신호 대응. 이름이 엇갈리는 부분 주의 |
| `verif/integ/FINDING_first_write_beat_timing.md` | 버그 #6. **중간 지점을 비교하면 버그를 놓친다**는 교훈 |
| `verif/integ/tb/tb_l2_noc_ch1_in.sv` | 기존 통합 TB. 명령어 만드는 법, `send_cmd`, busy 대기 방식 참고 |
| `verif/integ/00_run_integ.bat` | 실행 스크립트 형식 참고 (이 형식을 따른다) |
| `rtl/NOC_260902/L1_FIFO_intf.v`, `L1_FIFO_interface.v` | `i_pe_busy`와 외부 SRAM 포트 — 이번 구조의 근거 |
| `verif/noc/rename/FIFO_intf.v`, `noc_sram_controller.v` | 지금 쓰는 NOC top과 SRAM 컨트롤러 |
| `verif/noc/fix/sram_mimic.v` | L1 SRAM 모델 (ceb/web active-low, 읽기 1클럭 지연) |
| `LHJ/axi4_l2_ch0_bridge.sv`, `LHJ/l2_ps_pl_top.sv` | Phase 3에서 쓰는 PS↔L2 ch0 경로 (공동작업자 작성) |
| `verif/blackbox/docs/*.svg` | 구조도·메모리 맵 (JH와 합의한 그림) |

---

## 1. 절대 규칙

1. **`rtl/` 아래 원본은 절대 수정하지 않는다.** `LHJ/`도 수정하지 않는다 (공동작업자 폴더). 필요하면 `verif/blackbox/`로 **복사**해서 고치고, 파일 머리 주석에 "원본 경로 / 무엇을 왜 바꿨는지"를 적는다.
2. 새 파일은 전부 `verif/blackbox/` 아래에 만든다 (구조는 5절).
3. 원본 RTL에서 버그나 이상한 동작을 찾으면 **고치기 전에** `verif/blackbox/FINDING_<짧은이름>.md`로 정리한다: 위치 / 증상 / 원인 / 재현 방법 / 수정 내용 / 영향.
4. **추측으로 사양을 정하지 않는다.** 12절의 미결 항목에 걸리면 `TODO(JH)` 주석을 남기고 보고한다.
5. git: **commit / push는 JH가 요청할 때만.** push 전에는 반드시 `git pull --rebase`, 강제 push 금지. 빌드 산출물(`work/`, `xsim.dir/`, `*.wdb`, `*.log`, `*.dcp`)은 커밋하지 않는다 (`.gitignore`에 이미 있음).
6. TB는 반드시 마지막 줄에 `PASS (errors=0)` 또는 `FAIL (errors=N)`을 출력한다. 스크립트 결과 판정은 이 문자열로 한다.

---

## 2. 실행 환경 (Windows 11, Vivado 2024.2 XSim)

- 시뮬레이터: `xvlog` / `xelab` / `xsim` (`C:\Xilinx\Vivado\2024.2\bin`)
- `.bat` 안에서 `xvlog`, `xelab`, `xsim` 앞에는 **반드시 `call`** 을 붙인다 (그 자체가 .bat이라 없으면 스크립트가 중간에 끝남).
- `xsim --tclbatch`에 넘기는 경로는 **`/`** 를 쓴다 (`\`는 Tcl 이스케이프).
- `.sv`가 섞인 목록은 `xvlog -sv -f <list>` 한 줄로 `.v`까지 컴파일된다.
- `xelab -generic_top`으로는 하위 인스턴스 파라미터를 못 바꾼다 → TB의 `localparam`으로 넘긴다.
- 모듈 이름 충돌 주의: L2와 NOC에 같은 이름 모듈이 6개 있어서 NOC 쪽은 `noc_` 접두어 사본을 쓴다 (`verif/noc/noc_files_integ.f` 참고). **`sram_controller`도 충돌 대상**이다.
- 클럭 100 MHz 단일 도메인, 리셋 active-low. CDC 없음.
- Python 3 + numpy 사용 가능하다고 가정. 없으면 JH에게 알린다.

---

## 3. 목표 (한 문장)

실제 MAC IP가 오기 전에, **MAC 자리에 "PE 흉내 Blackbox"를 넣어** PS → L2 → adapter → NoC → L1 → (Blackbox) → L1 → NoC → L2 → PS 데이터 경로 전체를 bit-exact로 검증하는 환경을 만든다. IP가 도착하면 `blackbox_pe`만 실제 IP로 바꾸고 나머지 환경은 그대로 재사용한다.

판정 (10/1 발표 기준): ① timeout 안에 done ② 각 Check Point에서 golden 대비 bit-exact ③ 서로 다른 입력에서도 bit-exact → 셋 다 만족하면 PASS.

---

## 4. 확정된 설계 값

| 항목 | 값 | 근거 |
|---|---|---|
| L2 | `GROUPS=8, BLOCKS=16, ADDRESS_ROW=1024` → **1 MiB** | 10/1 slide 7 tiling 추정 591 KiB. 16/1024가 32/512보다 mux가 작음 |
| L1 (ch1_in, cluster 1개) | **512b × 2048 = 128 KiB**, `sram_mimic` 128b × 4 | 명령어 필드(도착 주소 11b, 길이 11b)가 고정 |
| Blackbox Expected BRAM | 512b × 256 (16 KiB) | 가장 큰 입력 tile X = 12 KiB = 192 beat |
| Blackbox Golden BRAM | 512b × 256 (16 KiB) | 출력 tile 1~3 KiB, 여유 |
| 범위 | **ch1_in만** (Phase 1~4). ch1_wgt / ch2는 12절 미결 해소 후 | weight 메모리 구조 미확정 |
| 데이터 | int8, N=16 tile (ViT-B, D=768, Dh=64) | slide 7 |

### 4.1 L2 메모리 맵 (바이트 주소, PS ch0 기준)

| 영역 | 주소 | 슬롯 | 실제 사용 |
|---|---|---|---|
| X (입력 tile) | `0x0_0000` | 16 KiB | 12 KiB (192 × 64B) |
| WQ/WK/WV (4 head) | `0x1_0000` | 576 KiB | (이번 범위 밖) |
| Projection 출력 | `0xA_0000` | 64 KiB | Golden 출력이 STORE로 돌아오는 곳 |
| Attention Q/K/S | `0xB_0000` | 64 KiB | (이번 범위 밖) |
| 여유 | `0xC_0000` | 256 KiB | |

ch1_in 명령의 L2 주소는 **512b(64B) 워드 단위**다: `L2 워드 주소 = 바이트 주소 / 64`. 예) `0xA_0000` → `0x2800`.

### 4.2 L1 메모리 맵 (512b 워드 주소)

| 영역 | 워드 | 용도 |
|---|---|---|
| IN | 0 ~ 255 | LOAD로 들어온 입력. Blackbox가 읽어서 Expected와 비교 (CP-A) |
| OUT | 1024 ~ 1279 | Blackbox가 Golden을 씀. STORE가 여기서 L2로 가져감 |

---

## 5. 만들 파일 구조

```
verif/blackbox/
├─ BLACKBOX_TASK.md            ← 이 문서
├─ README.md                   ← Phase마다 결과·실행법 갱신
├─ docs/                       ← 구조도 SVG (JH 제공)
├─ rtl/
│   ├─ noc_L1_FIFO_intf.v      ← rtl/NOC_260902/L1_FIFO_intf.v 사본, sram_controller → noc_sram_controller 만 변경
│   ├─ l1_sram.sv              ← sram_mimic 128b × 4 = 512b × 2048 (sim/fpga 모델은 파일 목록에서 선택)
│   ├─ l1_port_mux.sv          ← i_pe_busy ? PE 포트 : NoC 포트  (조합논리)
│   ├─ FIFO_intf_bb.sv         ← noc_FIFO_interface + noc_L1_FIFO_intf + l1_port_mux + l1_sram. NoC쪽 포트는 FIFO_intf와 동일
│   ├─ blackbox_pe.sv          ← PE 흉내 (7절)
│   ├─ axi_lite_ctrl.sv        ← (Phase 3) 명령 + Blackbox 레지스터 + BRAM 쓰기 창
│   └─ l2_noc_bb_top.sv        ← (Phase 3) bridge + axi_lite_ctrl + L2 + adapter + FIFO_intf_bb + blackbox
├─ tb/
│   ├─ tb_blackbox_pe.sv       ← Phase 1
│   ├─ tb_l2_noc_bb.sv         ← Phase 2
│   ├─ tb_l2_noc_bb_top.sv     ← Phase 3 (AXI4 / AXI-Lite BFM task)
│   └─ bb_pkg.sv               ← 명령어 생성 함수, 공통 상수
├─ scripts/
│   ├─ gen_vectors.py          ← input / expected / golden hex 생성 (9절)
│   ├─ files_bb_sim.f, files_bb_synth.f
│   ├─ 00_run_bb_unit.bat      ← Phase 1
│   ├─ 01_run_bb_integ.bat     ← Phase 2
│   ├─ 02_run_bb_top.bat       ← Phase 3
│   └─ build_synth_bb.tcl      ← Phase 4
└─ vectors/                    ← 생성된 hex (seed별 하위 폴더)
```

---

## 6. 연결 구조

```
                ch1_in 512b                     NoC 쪽 (기존, 수정 없음)
TOP_L2_cache ─────────────── noc_ch1_in_adapter ── noc_FIFO_interface ── noc_L1_FIFO_intf ──┐
  (1 MiB)                    (기존 그대로)          (버그#6 수정본)        (i_pe_busy 사용)    │ SRAM port (NoC)
                                                                                 ▲           ▼
                                                                    i_pe_busy    │     ┌───────────┐
                                                                    ─────────────┴────►│l1_port_mux│◄── SRAM port (PE)
                                                                                       └─────┬─────┘        ▲
                                                                                             ▼              │
                                                                                     l1_sram 512b×2048   blackbox_pe
```

- `FIFO_intf_bb`의 NoC쪽 포트 = 기존 `FIFO_intf`와 **이름·폭·동작이 같아야 한다** → `noc_ch1_in_adapter`를 그대로 붙일 수 있게.
- 추가 포트: `i_pe_busy`, PE쪽 SRAM 포트 (`i_pe_ceb, i_pe_web` active-low, `i_pe_addr[10:0]`, `i_pe_din[511:0]`, `o_pe_dout[511:0]`).
- `l1_port_mux`: `i_pe_busy=1`이면 SRAM 입력(ceb/web/addr/din)을 PE 쪽으로, 아니면 NoC 쪽으로. `dout`은 양쪽에 그대로 보낸다.
- `sram_mimic`: `ceb=0 & web=0` → 쓰기, `ceb=0 & web=1` → 읽기. **읽은 값은 다음 클럭에 `o_dout`에 나온다 (1클럭 지연).**

---

## 7. `blackbox_pe` 사양

### 7.1 파라미터

| 이름 | 기본값 | 의미 |
|---|---|---|
| `DW` | 512 | 데이터 폭 (CH2용 재사용 대비 파라미터화) |
| `L1_AW` | 11 | L1 워드 주소 폭 |
| `BRAM_DEPTH` | 256 | Expected / Golden 깊이 |
| `GUARD` | 2 | pe_busy를 올린 뒤 / 내리기 전 대기 클럭 |

### 7.2 포트

| 그룹 | 포트 | 방향 | 설명 |
|---|---|---|---|
| 공통 | `clk`, `rstn` | in | |
| 제어 | `i_start` | in | 1클럭 펄스. IDLE/DONE에서만 받음 |
| | `i_noc_busy` | in | L2 `o_busy_channel_1_in`. 1일 때 START가 오면 **무시하고 `err_start_busy` 세움** |
| | `i_in_base[10:0]`, `i_in_len[8:0]` | in | L1 IN 영역 시작 워드, beat 수 (1~256) |
| | `i_out_base[10:0]`, `i_out_len[8:0]` | in | L1 OUT 영역 시작 워드, beat 수 (1~256) |
| | `i_latency[31:0]` | in | 비교 끝난 뒤 Golden 쓰기 전 대기 클럭 |
| | `i_inject[1:0]` | in | bit0: Golden beat 0의 bit 0을 뒤집어 씀 (CP-B 자가검사) · bit1: Expected beat 0의 bit 0을 뒤집어 비교 (CP-A 자가검사) |
| BRAM 적재 | `i_bram_we`, `i_bram_sel` (0=Expected, 1=Golden), `i_bram_addr[7:0]`, `i_bram_wdata[511:0]` | in | Phase 1·2는 TB가, Phase 3는 `axi_lite_ctrl`이 구동 |
| L1 | `o_pe_busy` | out | `l1_port_mux` sel + `noc_L1_FIFO_intf.i_pe_busy` |
| | `o_ceb`, `o_web`, `o_addr[10:0]`, `o_din[511:0]`, `i_dout[511:0]` | | L1 SRAM 포트 (active-low) |
| 상태 | `o_busy`, `o_done` | out | `o_done`은 다음 START까지 유지 |
| | `o_mismatch_cnt[15:0]` | out | CP-A 불일치 beat 수 |
| | `o_first_mm_idx[15:0]`, `o_first_mm_valid` | out | 첫 불일치 beat 번호 |
| | `o_first_mm_got[31:0]`, `o_first_mm_exp[31:0]` | out | 첫 불일치 beat의 하위 32b (디버그용) |
| | `o_err_start_busy` | out | NoC busy 중 START 시도됨 (sticky, 리셋으로만 해제) |
| | `o_cycle_cnt[31:0]` | out | START~DONE 클럭 수 |

### 7.3 동작 (FSM)

```
IDLE ─START & !noc_busy─► GUARD_IN ─(GUARD클럭)─► RD_IN ─(in_len beat)─► WAIT ─(latency)─► WR_OUT ─(out_len beat)─► GUARD_OUT ─► DONE
  pe_busy:   0               1                       1                     1                   1                          1          0
```

- **RD_IN**: L1[in_base+k]를 읽고, 1클럭 뒤 나온 `i_dout`을 Expected[k]와 비교한다. Expected BRAM 읽기도 1클럭 지연이므로 **둘의 타이밍을 맞춰서** 비교한다 (k와 데이터가 한 칸 어긋나지 않게 — 이게 가장 흔한 실수다).
- **WAIT**: `i_latency` 클럭 대기. 0이면 바로 넘어간다.
- **WR_OUT**: Golden[k]를 L1[out_base+k]에 쓴다. Golden BRAM도 1클럭 지연을 고려한다.
- **pe_busy 규칙**: START에서 올리고 DONE 직전에 내린다. NoC 전송 도중에는 절대 올리지 않는다 (12절 ②). 그래서 `i_noc_busy` 검사를 한다.
- 리셋 시 모든 상태와 카운터를 0으로 만든다. Expected/Golden BRAM 내용은 리셋하지 않는다 (BRAM 추론을 위해 — `verif/fpga/fpga_fix/sram_mimic_fpga.v` 머리 주석 참고).
- 합성 가능한 RTL로 작성한다 (`initial`, `#delay`, `$display`는 RTL 안에 넣지 않는다).

---

## 8. 명령어 (ch1_in, L2 1 MiB 기준)

L2 주소 필드 폭은 L2 크기에서 자동으로 정해진다:
`SRC_W = clog2(GROUPS) + clog2(ADDRESS_ROW × BLOCKS / 8)` = 3 + clog2(1024×16/8) = **14** (1 MiB).
필드는 LSB 기준으로 고정이고 위쪽 비트는 0이다. **`bb_pkg.sv`와 `gen_vectors.py`에서 SRC_W를 파라미터로 계산**해서 쓴다 (하드코딩 금지).

| | LOAD (L2 → L1) | STORE (L1 → L2) |
|---|---|---|
| `[62:60]` cmd_idx | `001` | `010` |
| `[59:58]` 모드 | `00` burst / `01` handshake | `10` burst / `11` handshake |
| L2 워드 주소 | `[SRC_W+39 : 40]` (출발) | `[SRC_W+40 : 41]` (도착) |
| 길이 (beat−1) | `[39:29]` (11b) | `[40:27]` (14b) |
| L1 워드 주소 | `[28:18]` (도착, 11b) | `[26:13]` 중 `[23:13]` 로컬 11b, `[26:24]` cluster 선택 = 0 |
| 기타 | `[57]` prec_mode=0, `[17:15]` resize=0, `[14:7]` multicast=`8'h01` | |

근거 파일: `rtl/L2_260901/cmd_decoder_channel_1_in.sv` (LOAD 323~330행, STORE 620~625행), `cmd_decoder_channel_1_in_wrapper.sv` 143행.
**Phase 2 시작 전에 이 표를 RTL과 다시 대조**하고, 다르면 RTL을 따르고 JH에게 알린다.

완료 판정: 명령 전송 후 `o_busy_channel_1_in`이 1이 됐다가 0이 되면 완료 (`o_command_ready`는 "큐에 자리 있음"일 뿐 완료가 아니다).

---

## 9. 테스트 벡터 (`scripts/gen_vectors.py`)

```
python gen_vectors.py --seed 1 --out ../vectors/seed1
```
- **X**: int8 16×768 → 12,288 B → 192 beat. (Expected = X 그대로)
- **W**: int8 768×16 (테스트용 조각, L2로는 안 보냄)
- **Golden**: `Y = X·W` (int32, 16×16) → 1,024 B → 16 beat
- 패킹 규칙 (모든 hex 공통): beat k = 바이트 `[64k, 64k+63]`, **바이트 0이 bit [7:0]** (little-endian). hex 파일 한 줄 = 한 beat = 128 hex 문자, MSB가 왼쪽. int32는 little-endian 4바이트.
- 출력: `x.hex`(L2 적재용), `expected.hex`, `golden.hex`, `meta.json` (seed, beat 수, L2/L1 주소, 미리 계산한 명령어 64b 값)
- TB는 `$readmemh`로 읽는다. Phase 3 이후 PS C 코드도 **같은 hex와 meta.json**을 쓴다.

---

## 10. Phase별 작업과 Gate

### Phase 1 — `blackbox_pe` 단독 검증
범위: `blackbox_pe` + `l1_port_mux` + `l1_sram`. NoC 쪽 포트는 idle로 고정.
- TB가 L1 IN 영역을 backdoor로 채우고 (`l1_sram` 내부 `mem`에 직접 대입), Expected/Golden은 BRAM 적재 포트로 넣는다.

| # | 테스트 | 통과 조건 |
|---|---|---|
| U1 | 기본: in 192, out 16, latency 10 | mismatch 0, L1 OUT = Golden 16 beat, done |
| U2 | `inject[1]=1` (CP-A 자가검사) | mismatch **정확히 1**, first_idx = 0 |
| U3 | `inject[0]=1` | L1 OUT beat 0만 Golden과 bit 0이 다름 |
| U4 | latency 0 / 1 / 1000 | cycle_cnt가 latency에 맞게 증가, 결과 동일 |
| U5 | IN 영역 beat 37을 일부러 바꿈 | mismatch 1, first_idx = 37, got/exp 하위 32b 맞음 |
| U6 | `i_noc_busy=1`에서 START | 무시됨, `err_start_busy=1`, pe_busy 안 올라감 |
| U7 | in_len=1, out_len=1 / 256, 256 (경계) | 정상 |

**Gate 1 보고**: 테스트별 PASS/FAIL 표, pe_busy·ceb·addr 파형에서 확인한 것 (특히 1클럭 지연을 어떻게 맞췄는지), 만든 파일 목록, 실행법 (`00_run_bb_unit.bat`).

### Phase 2 — L2 + NoC + Blackbox 통합 (명령은 TB가 직접)
범위: `TOP_L2_cache`(1 MiB) + `noc_ch1_in_adapter` + `FIFO_intf_bb` + `blackbox_pe`. L2 적재와 회수는 **TOP_L2_cache ch0 포트를 TB task로 직접 구동** (AXI 비슷한 간소화 신호 — `LHJ/l2_ps_pl_top.sv`의 연결 참고).
- **먼저 회귀 테스트**: Blackbox를 idle로 두고 기존 `tb_l2_noc_ch1_in.sv`와 같은 STORE→LOAD 왕복을 돌려, `FIFO_intf_bb`가 기존 `FIFO_intf`와 똑같이 동작하는지 확인 (R0).
- 그다음 전체 흐름 ①~⑥:
  ① ch0로 X를 L2 `0x0_0000`에 씀 + Expected/Golden 적재 → ② LOAD (L2 X → L1 IN), busy↑↓ 대기 → ③ START, done 대기 (CP-A) → ④ (Blackbox가 latency 후 Golden → L1 OUT) → ⑤ STORE (L1 OUT → L2 `0xA_0000`), busy↑↓ 대기 → ⑥ ch0로 L2 `0xA_0000`을 읽어 Golden과 비교 (CP-B)

| # | 테스트 | 통과 조건 |
|---|---|---|
| R0 | 회귀 (BB idle) | 기존 TB와 같은 결과 5/5 |
| S1 | seed 1, ①~⑥ | CP-A mismatch 0, CP-B 16/16 |
| S2 | seed 2, 3, 4 | 모두 PASS (판정 ③) |
| S3 | `inject[0]` | CP-B에서 정확히 beat 0만 FAIL로 **검출됨** |
| S4 | LOAD→START→STORE 간격 0 (busy↓ 바로 다음 클럭) | PASS (버그 #6 유형 확인) |
| S5 | latency 0 / 10000 | PASS |
| S6 | handshake 모드 (LOAD `01`, STORE `11`) | PASS, 또는 실패 시 FINDING 작성 |

**Gate 2 보고**: 표, CP-A/CP-B 결과, 각 단계 소요 클럭 (LOAD / BB / STORE), 발견한 문제와 FINDING 문서.

### Phase 3 — PS 인터페이스 포함 시스템 top
- `axi_lite_ctrl.sv` (AXI4-Lite slave, 32b): 아래 레지스터.
- `l2_noc_bb_top.sv`: `LHJ/axi4_l2_ch0_bridge.sv`(**참조만, 수정 금지**) + `axi_lite_ctrl` + L2 + adapter + `FIFO_intf_bb` + `blackbox_pe`.
- Block Design용 Verilog-2001 wrapper `l2_noc_bb_bd_wrapper.v`: `S_AXI`(AXI4, ch0)과 `S_AXI_LITE` 두 인터페이스에 `X_INTERFACE_INFO`를 붙인다 (`LHJ/l2_ps_pl_bd_wrapper.v` 방식 그대로).
- TB는 AXI4 / AXI-Lite master task로 PS 역할을 한다. Phase 2의 S1~S6을 **같은 hex로** 다시 통과해야 한다.

| 오프셋 | 이름 | 내용 |
|---|---|---|
| `0x00` / `0x04` | CMD_LO / CMD_HI | 명령어 [31:0] / [63:32] |
| `0x08` | CMD_PUSH | bit0에 1 쓰면 `i_command_valid` 1클럭 펄스 (`o_command_ready=0`이면 STATUS에 overflow 표시) |
| `0x0C` | STATUS | bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow(sticky) |
| `0x20` | BB_CTRL | bit0 START(펄스), bit2:1 inject |
| `0x24` | BB_IN | [10:0] base, [24:16] len |
| `0x28` | BB_OUT | [10:0] base, [24:16] len |
| `0x2C` | BB_LATENCY | 32b |
| `0x30` | BB_STATUS | bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy |
| `0x34` | BB_MISMATCH | [15:0] cnt, [31:16] first_idx |
| `0x38` / `0x3C` | BB_MM_GOT / BB_MM_EXP | 첫 불일치 하위 32b |
| `0x40` | BB_CYCLES | START~DONE 클럭 수 |
| `0x44` | BRAM_ADDR | [7:0] addr, bit8 sel (0=Expected, 1=Golden) |
| `0x48` | BRAM_COMMIT | 1 쓰면 아래 창(512b)을 BRAM[addr]에 기록 후 addr 자동 +1 |
| `0x80 ~ 0xBC` | BRAM_WDATA[0..15] | 512b 쓰기 창, `0x80`이 bit [31:0] |

**Gate 3 보고**: 표, 레지스터 맵 최종본 (README에 반영), PS C 코드가 따라야 할 순서 (의사코드).

### Phase 4 — 합성
- `build_synth_bb.tcl`: `verif/fpga/build_synth_size.tcl` 방식 (non-project, `xczu9eg-ffvb1156-2-e`, 100 MHz XDC). top = `l2_noc_bb_bd_wrapper` (OOC 모드로 합성해 I/O 핀 문제 회피).
- 합성용 파일 목록은 `sram_mimic_fpga.v`(BRAM 추론용), L2는 `LHJ/ram_mimic_fpga_bram.sv`(`ram_style="block"`)를 쓴다.
- **Gate 4 보고**: LUT/FF/BRAM/DSP %, WNS/WHS, BRAM 실측이 예상(약 312 tile, 34%)과 맞는지, critical path 상위 3개.
- Block Design / bitstream / 보드는 이 문서 범위 밖이다 (현준과 함께 진행).

---

## 11. 보고 형식 (각 Gate 공통)

```
## Gate N 보고
- 결과: PASS a / FAIL b
- 표: (테스트 | 결과 | 비고)
- 만든/바꾼 파일: (경로 | 한 줄 설명)
- 실행법: (bat 이름)
- 왜 이렇게 했나: (설계 판단 2~3개, 쉬운 말로)
- 발견한 문제: (FINDING 문서 링크 또는 "없음")
- JH 확인 필요: (TODO(JH) 목록)
```

---

## 12. 미결 항목 — 추측하지 말고 `TODO(JH)`로 남길 것

1. **실제 MAC IP가 L1에 접근하는 방식**: SRAM 포트에 직접 붙는지, 폭 512b인지, IN/OUT 영역 배치. (지금 구조는 `L1_FIFO_intf`가 SRAM 포트를 밖으로 뺀 것을 근거로 한 추정)
2. **`pe_busy`를 NoC 전송 도중에 올리면?** `L1_FIFO_interface.v`는 `pe_busy`로 출력을 조합논리로 즉시 0으로 만든다 → 전송 중이면 데이터가 깨질 수 있다. 지금은 "NoC idle일 때만" 규칙으로 피한다. 의도된 사용법인지 NOC 설계자 확인 필요.
3. **ch1_wgt weight 메모리**: target 1개 = 256b × 1024 = 32 KiB인데 head 1개·행렬 1개 = 48 KiB. 명령어 `[38:32]`의 `wgt_grp/LCU/LCC sel`이 길이 필드와 겹침. MAC 설계자 확인 전에는 ch1_wgt를 다루지 않는다.
4. **ch2**: L2 쪽 ch2_in 반환 경로는 상대가 L2에 직접 쓰는 구조, ch2_wgt는 L2→NoC 단방향. adapter를 새로 설계해야 한다.

---

## 13. JH가 Claude Code에 처음 줄 프롬프트 (예시)

```
verif/blackbox/BLACKBOX_TASK.md 를 처음부터 끝까지 읽고, 0절의 파일들을 읽은 다음
Phase 1만 진행해줘. 끝나면 11절 형식으로 Gate 1 보고하고 멈춰.
```
