# L2 / NOC 검증 작업 폴더

```
verif/
  l2/
    l2_files.f            # L2_260901 RTL 파일 목록 (top = TOP_L2_cache)
    00_compile_l2.bat     # Phase 0: 컴파일 + elaborate 확인
    10_run_l2_ch1_in.bat  # Phase 1: ch1_in 기능 시뮬 실행 -> work/l2_ch1.wdb
    20_open_wave.bat      # 저장된 파형(l2_ch1.wdb)을 XSim 파형뷰어로 열기
    sim_l2_ch1_in.tcl     # xsim batch tcl (log_wave -> run all)
    tb/
      tb_l2_ch1_in.sv     # Phase 1 테스트벤치 (NOC 자리는 간단 모델)
    work/                 # 빌드/시뮬 산출물 (지워도 됨)
    phase0_run.log / phase1_run.log
```

## 검증 로드맵

| 단계 | 내용 | 상태 |
|------|------|------|
| Phase 0 | RTL이 문법 오류 없이 컴파일/elaborate 되는지 확인 (TB 없음) | **L2 통과 (2026-09-02)** / NOC 미착수 |
| Phase 1 | L2 단독 테스트벤치 — NOC 자리는 간단한 모델, 커맨드 넣고 파형 확인 | **ch1_in burst load 동작 (2026-09-02)** / ch1_in store, ch2_in 미착수 |
| Phase 2 STEP 0 | NOC 단독 테스트벤치 — FIFO_intf 마스터 포트 직접 구동 | **PASS 5/5 (2026-09-03)**, 버그 3개 fix |
| Phase 2 STEP 1 | NOC 쪽 이름 충돌 모듈 6개 rename | **완료 (2026-09-15)** |
| Phase 2 STEP 2 | 어댑터 (`noc_ch1_in_adapter.sv`) | **완료 (2026-09-15)** |
| Phase 2 STEP 3 | L2+NOC 통합 TB (ch1_in) | **4/5 beat 일치, 1건 finding (2026-09-15)** |
| Phase 2 STEP 3-b | L2+NOC 통합 TB (ch1_wgt, ch1_in과 동일 패턴 재사용) | **4/5 beat 일치, 동일 finding 재현 (2026-09-15)** |
| ch2_in / ch2_wgt | 상대가 Vector Engine/Accumulator/Pooling Engine — `NOC_260902`(L1 캐시 모델)로 대응 불가 | **범위 밖으로 확정** |

## Phase 2 (L2 + NOC 통합, ch1_in + ch1_wgt)

**상세 문서 → [integ/CONNECTION_GUIDE.md](integ/CONNECTION_GUIDE.md)** — 채널별 역할 정리, 이름 충돌을
어떻게 풀었는지, 어댑터 신호 매핑표, 통합 TB 구조, Vivado 실행법 전부 정리.
**요약 슬라이드 덱**: https://claude.ai/artifact/9wynmxHt37sEPNWa1YVA1V (ch1_in 기준, ch1_wgt 결과는 미반영)

- `verif\noc\00_compile_noc.bat` / `10_run_noc_tb.bat` / `20_wave_gui_noc.bat` — NOC 단독 (STEP 0)
- `verif\noc\rename\` — STEP 1 rename 사본들, 필드리스트 `verif\noc\noc_files_integ.f`
- `verif\integ\noc_ch1_in_adapter.sv` / `noc_ch1_wgt_adapter.sv` — STEP 2 어댑터
- ch1_in: `verif\integ\00_run_integ.bat` (headless) / `10_wave_gui_integ.bat` (GUI)
- ch1_wgt: `verif\integ\01_run_integ_ch1_wgt.bat` (headless) / `11_wave_gui_integ_wgt.bat` (GUI)
- 찾은 이슈: [noc/FINDING_noc_sim_bugs.md](noc/FINDING_noc_sim_bugs.md), [integ/FINDING_first_write_beat_timing.md](integ/FINDING_first_write_beat_timing.md) (ch1_in+ch1_wgt 둘 다 재현)

## Phase 1 (L2 ch1_in)

**공부하며 직접 하려면 → [l2/GUIDE_phase1_ch1_in.md](l2/GUIDE_phase1_ch1_in.md) 을 볼 것.**
테스트벤치가 무엇을/어떻게/왜, Vivado GUI 단계별, 어떤 파형을 어떻게 읽는지 전부 설명돼 있음.

배치 파일 (`verif\l2\`):
| 파일 | 내용 |
|---|---|
| `00_compile_l2.bat` | Phase 0 — RTL만 compile/elaborate 확인 |
| `10_run_l2_ch1_in.bat` | v1 : ch1_in load only (headless). load data = X (GUIDE 5) |
| `11_run_l2_ch1_in_storeload.bat` | v2 : store→load, **원본 RTL** → load = X (버그 재현) |
| `12_run_l2_ch1_in_storeload_ramfix.bat` | v2 + `fix\ram_mimic.sv` → **RESULT: PASS 5/5** (headless) |
| **`30_wave_gui_storeload.bat`** | **v2 + fix → Vivado XSim 파형 GUI 자동 오픈** (신호 미리 배치) |

**파형 보려면 → `30_wave_gui_storeload.bat`.** GUI 프로젝트 흐름을 익히려면
`vivado -mode gui -source l2\make_vivado_project.tcl`.

### store→load 확장 & 발견한 버그 (GUIDE 5절)
- `l2\11_run_l2_ch1_in_storeload.bat` : 원본 RTL → load 값 X (**버그**)
- `l2\12_run_l2_ch1_in_storeload_ramfix.bat` : `verif\l2\fix\ram_mimic.sv` 적용 → **RESULT: PASS 5/5**

**버그:** `rtl/L2_260901/ram_mimic.sv` 가 `if(ena)/if(wea)` (active-high) 인데
L2 설계는 SRAM 인터페이스를 active-low 로 몲 → 시뮬에서 L2 내부 SRAM이 read/write를 아예 안 함.
원본 미수정, `verif\l2\fix\ram_mimic.sv` 에 사본만. 설계자 보고 or 원본 수정은 사용자 판단.

## Phase 0 실행 방법 (L2)

1. 시작 메뉴에서 **"Vivado 2024.2 Tcl Shell"** 실행 (또는 그냥 `cmd` 창)
2. 아래 실행:
   ```
   C:\RTL_YJH\L2_verification\verif\l2\00_compile_l2.bat
   ```
3. 마지막에 `PHASE 0 PASSED` 가 뜨면 성공.
   실패하면 `VRFC ... ERROR` 줄을 읽고 해당 파일/라인을 고친다.

### 스크립트가 하는 일
- `xvlog` : SystemVerilog 파일들을 분석(=컴파일). 문법 오류를 여기서 잡는다.
- `xelab` : 최상위 모듈 `TOP_L2_cache` 부터 계층 전체를 연결(=elaborate).
  포트 폭 불일치, 없는 모듈, 파라미터 오류를 여기서 잡는다.
- 결과물: `work/xsim.dir/l2_top_snap` 이라는 시뮬레이션 스냅샷.
  Phase 1에서 테스트벤치와 함께 다시 만들어 `xsim` 으로 실행하게 된다.
