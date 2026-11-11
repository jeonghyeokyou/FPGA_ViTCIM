# CHANGES — `LHJ/ViT-Base_C_261110/` (55d6f24) 복사본에서 바꾼 것

## ViT-Base_C_full (12 layer 진행본)

| 날짜 | Phase | 변경 |
|---|---|---|
| 2026-11-11 | 0 | `JH/ViT-Base_C_mlp/` (c3db75b) 를 그대로 복사, `VIT_FULL_TASK.md` 추가, `README.md` 를 이 폴더용으로 새로 씀. **코드 변경 없음** |

아래는 `ViT-Base_C_mlp` 에서 이어받은 내용 (MLP 단계).

작업: JH (2026-11-10), 지시서: `MLP_TASK.md`. 현준 파일은 **꼭 필요한 곳만** 고쳤고, 고친 파일의 머리 주석에 원본과 이유를 적었다.

## 현준 파일 (복사본) 변경

| 파일 | 변경 | 이유 |
|---|---|---|
| `vit_hw.h` | `PROF_OPS` 16 → 24 | MLP 연산 7개를 더하면 `OP_N` = 18 → `_Static_assert(OP_N <= PROF_OPS)` 실패 |
| `attn_ops.h` | enum 에 `OP_LN2, OP_FC1, OP_GELU, OP_H_MX, OP_FC2, OP_FC2_ACC, OP_RESID2` (`OP_VERIFY` 앞) | 시간 표에 MLP 연산을 따로 표시 |
| `attn_ops.c` | `OP_NAME[]` 에 위 7개 이름 (같은 순서) | 위와 같음 |
| `vit_main.c` | `mlp_block()`, `final_checks_mlp()`, `--mlp` / `--tiles N`, 호스트 버퍼, 배너 / `BOARD_RESULT op=layer` | MLP 순차 실행 + 최종 검사 9개 |
| `vit_dbg.c` | `--op mlp --tile J`, `--op fc2 --n N`, `mlp_files` 로드, 배너 / `BOARD_RESULT` | 호출별 검사 진입점 |

`--mlp` 없이 실행하면 명령 순서·검사·출력은 현준 버전과 같다 (x86 모델: 명령 588 / BB 504 / CDMA 218, 검사 15개).
`run_mac` / `run_store` (attn_ops.c static) 와 dbg_attn.c 의 static hook 은 풀지 않고 `mlp_ops.c` / `dbg_mlp.c` 에 같은 내용으로 따로 두었다.

## 새 파일

| 파일 | 내용 |
|---|---|
| `mlp_ops.h` / `mlp_ops.c` | 상수, L2 배치 (4.3절), `mlp_files`, `mlp_fc1_tile`, `mlp_gelu_tile`, `mlp_fc2_call` |
| `mlp_ps.c` | `ps_ln2_mx`, `ps_mx_g` (= `ps_mx_o` 래퍼), `ps_fc2_acc` — **`-ffp-contract=off` 로 컴파일** |
| `dbg_mlp.h` / `dbg_mlp.c` | `--op mlp` / `--op fc2` 호출별 C1–C6 |
| `test_mlp_ps.c` | x86 PS 단독 테스트 T1–T5 |
| `hw_sim.c` | x86 소프트웨어 하드웨어 모델 (`vit_hw.c` 대신 링크, 보드 불필요). 명령 로그·고장 주입 |
| `Makefile` | 보드 (`make`), x86 모델 (`make sim`) |
| `golden/vit_golden_gen.py` | 생성기 MLP 확장 (원본 `vit_golden_gen.py_261110`, 기존 23개 파일 byte 동일) |
| `golden/run_gen_win.py` | Windows numpy 용 실행기 (`np.ldexp` int64 지수 문제만 우회) |
| `golden/check_cmd_log.py` | hw_sim 명령 로그의 MLP 720개 명령을 4.3 / 4.4절과 대조 |
