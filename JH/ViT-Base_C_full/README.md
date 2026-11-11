# ViT-Base 전체 (patch embedding → 12 layer → 분류) — 진행본

작업: JH, 2026-11-11 · 지시서: [VIT_FULL_TASK.md](VIT_FULL_TASK.md) · 출발점: [`../ViT-Base_C_mlp/`](../ViT-Base_C_mlp/) (layer 0 attention + MLP 완료본, 커밋 c3db75b)
변경 목록: [CHANGES.md](CHANGES.md) · 빌드 · 데이터 · 보드 명령은 지금은 [`../ViT-Base_C_mlp/README.md`](../ViT-Base_C_mlp/README.md) 와 같다.

## 상태

| Phase | 내용 | 결과 |
|---|---|---|
| **0 준비** | 폴더 복사, 회귀, HF 구조 확인, 함수 분리 계획 | **완료** (2026-11-11) |
| 1 생성기 `--full` | 12 layer golden, layer별 cosine · top-1 | 미착수 |
| 2 PS 함수 | `ps_embed`, `ps_ln_bf16`, `ps_head` (x86 + aarch64) | 미착수 |
| 3 전체 흐름 | `layer_run` 분리, `vit_full_sim --layers 12` | 미착수 |
| 4 보드 준비 | 데이터 zip, 보드 명령 | 미착수 |

## Phase 0 결과

### 회귀 (복사본 그대로, PC x86 모델 `hw_sim.c`, 실제 HF 데이터 `C:\RTL_YJH\data_l0_mx`)

| 실행 | 결과 | 명령 / BB / CDMA |
|---|---|---|
| 빌드 x86 (MinGW gcc 9.5) / aarch64 (GCC 13.3, `make OUT=.`) | 경고 0 / 경고 0 | — |
| `test_mlp_ps` | T1–T5 `PASS (errors=0)` | — |
| `vit_main_sim --mlp` | 검사 **23** PASS (검사 줄이 ViT-Base_C_mlp 실행과 똑같음) | 1308 / 1080 / 511 |
| `vit_main_sim` (`--mlp` 없음) | 15 PASS | 588 / 504 / 218 |
| `check_cmd_log.py` (MLP 720 명령) | `PASS (errors=0)` | — |
| `vit_dbg_sim --op mlp --tile 0` / `47` | PASS, C1–C6 = 2 / 9 / 8 / 17 / 4 / 4 | 32 / 12 / 3 |
| `vit_dbg_sim --op fc2 --n 0` / `11` | PASS, C1–C6 = 8 / 32 / 16 / 32 / 2 / 2 | 88 / 18 / 12 |

> 지시서 1·7·9절의 "검사 24개" 는 이전 문서의 오기이고 실제는 **23개** (attention 15 + MLP 8). 회귀 기준은 23개로 한다.

### HF 모델 구조 (`google/vit-base-patch16-224`, transformers 5.22.2)

config: layer 12, hidden 768, head 12, intermediate 3072, patch 16, image 224, `layer_norm_eps` 1e-12, `hidden_act` gelu, label 1000, qkv bias 있음, pooler 없음.

| 부분 | 모듈 경로 | 크기 (float32) |
|---|---|---|
| patch embedding | `vit.embeddings.patch_embeddings.projection` (Conv2d 3→768, k 16, stride 16) | W 768×3×16×16, b 768 |
| CLS 토큰 | `vit.embeddings.cls_token` | 1×1×768 |
| position embedding | `vit.embeddings.position_embeddings` | 1×197×768 |
| layer l (0..11) | `vit.layers.l` | — |
| LN1 / LN2 | `vit.layers.l.layernorm_before` / `layernorm_after` | 768 / 768 (w, b) |
| Q / K / V / out proj | `vit.layers.l.attention.q_proj` / `k_proj` / `v_proj` / `o_proj` | 768×768 + 768 |
| FC1 / FC2 | `vit.layers.l.mlp.fc1` / `mlp.fc2` | 3072×768 + 3072 / 768×3072 + 768 |
| 마지막 LN | `vit.layernorm` | 768 (w, b) |
| 분류 head | `classifier` (Linear, CLS 토큰 입력) | 1000×768 + 1000 |

transformers 5.x 는 경로가 4.x (`vit.encoder.layer.l.attention.attention.query`, `intermediate.dense` …) 와 다르다.
생성기는 이름이 아니라 **크기와 구조**로 찾으므로 영향 없음 (지시서 5절 방침 그대로). 기본 이미지 HF top-1 = 285 "Egyptian cat".

### 함수 분리 계획 (지시서 6.1절, Phase 3 에서 실행)

| 지금 (`vit_main.c` static) | 옮길 곳 | 비고 |
|---|---|---|
| `run_ctx` | `layer_run.h` 의 `layer_ctx` | hw / DMA 버퍼 (wr, rb, pb) / 호스트 결과 버퍼 / FC2 누산 버퍼. layer 사이에 재사용 |
| main 안의 `host[]` malloc 표 | `layer_run.c` `layer_ctx_init()` / `layer_ctx_free()` | 한 번 할당 (약 6 MB) 후 12 layer 재사용 |
| `to_l2`, `from_l2`, `poison_l2`, `arm_rb`, `PS_STEP` | `layer_run.c` (static) | 그대로 |
| `qkv_head`, `attn_head`, `out_block`, `mlp_block` | `layer_run.c` (static) | 본문 그대로 |
| main 의 실행 순서 (X → L2, QKV 12 → attention 12 → out → MLP) | `layer_run()` | 입력 x (MXFP4, 지금 `qf->x`) 와 h_in (지금 `af->hin`) 을 인자로 받도록 |
| `cmp_bytes`, `check`, `g_bad_total`, `final_checks`, `final_checks_mlp` | `layer_run.c` `layer_check()` | 실패 수를 전역 대신 반환값으로 |
| `report()` (시간 표) | `vit_main.c` 에 남김 | `vit_full` 은 layer 합계 표를 따로 |

```
int  layer_ctx_init(layer_ctx *x, hw_ctx *h);
int  layer_run(layer_ctx *x, const qkv_files *qf, const attn_files *af, const mlp_files *mf,
               const uint8_t *x4, const uint8_t *h_in, int nh, int ntiles);   /* 결과: x->r, x->r2 ... */
size_t layer_check(const layer_ctx *x, const qkv_files *qf, const attn_files *af, const mlp_files *mf,
                   int nh, int ntiles);                                       /* 지금 23 / 15 / 18 개 */
void layer_ctx_free(layer_ctx *x);
```
- `vit_main` 은 파일을 읽고 `layer_run(…, qf.x, af.hin, …)` → `layer_check` → `report` 만 하는 얇은 main 이 된다. 회귀 = 검사 줄 · 명령 수가 지금과 같은지.
- `vit_full` 은 layer l 마다 `lXX/` 파일만 읽고, x4 = PS LN1 (`ps_ln2_mx` 를 ln1 파라미터로 그대로 호출 — 출력 형식이 X2 와 같은 MXFP4), h_in = 이전 R2 를 넘긴다. 파일은 layer 가 끝나면 해제.
- LN: `ps_ln2_mx` 의 토큰 1개 정규화 부분을 `mlp_ps.c` 내부 함수로 빼서 `ps_ln_bf16` (마지막 LN, CLS 1개, 양자화 없음) 과 공유. `ps_ln2_mx` 결과는 `test_mlp_ps` T1 로 바뀌지 않았는지 확인.
- `ps_embed`, `ps_head` 는 새 파일 `full_ps.c` (`-ffp-contract=off`). enum `OP_EMBED, OP_LN1, OP_HEAD` 추가 → `OP_N` 21 ≤ `PROF_OPS` 24 (vit_hw.h 변경 불필요).
- `vit_dbg` 는 `--data <out>/lXX` 로 그 layer 의 40개 파일을 그대로 쓰면 되므로 바꾸지 않는다.

## TODO(JH) (지시서 10절)
- patch embedding · head 의 위치 (지금 PS), FC2 누산 · GELU 식 · g6 (MLP_TASK.md 11절), 입력 이미지 여러 장 — 모두 미결 유지.
