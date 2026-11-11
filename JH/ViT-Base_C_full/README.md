# ViT-Base 전체 (patch embedding → 12 layer → 분류) — 진행본

작업: JH, 2026-11-11 · 지시서: [VIT_FULL_TASK.md](VIT_FULL_TASK.md) · 출발점: [`../ViT-Base_C_mlp/`](../ViT-Base_C_mlp/) (layer 0 attention + MLP 완료본, 커밋 c3db75b)
변경 목록: [CHANGES.md](CHANGES.md) · 빌드 · 데이터 · 보드 명령은 지금은 [`../ViT-Base_C_mlp/README.md`](../ViT-Base_C_mlp/README.md) 와 같다.

## 상태

| Phase | 내용 | 결과 |
|---|---|---|
| **0 준비** | 폴더 복사, 회귀, HF 구조 확인, 함수 분리 계획 | **완료** (2026-11-11) |
| **1 생성기 `--full`** | 12 layer golden, layer별 cosine · top-1 | **완료** (2026-11-11) — 회귀 byte 동일, mock / HF PASS, top-1 285 = HF |
| **2 PS 함수** | `ps_embed`, `ps_ln_bf16`, `ps_head` (x86 + aarch64) | **완료** (2026-11-11) — `test_full_ps` x86 / aarch64 (qemu) PASS, mock · data_full |
| 3 전체 흐름 | `layer_run` 분리, `vit_full_sim --layers 12` | 미착수 |
| 4 보드 준비 | 데이터 zip, 보드 명령 | 미착수 |

## Phase 1 결과 (생성기 `golden/vit_golden_gen.py --full`)

실행 (Windows venv, 절차는 `../ViT-Base_C_mlp/README.md` "데이터" 절 — torchvision · `PYTHONUTF8=1` 필수):
```
%VPY% golden\run_gen_win.py golden\vit_golden_gen.py --full --out C:\RTL_YJH\data_full          (HF, 약 55 s)
%VPY% golden\run_gen_win.py golden\vit_golden_gen.py --full --mock --out <dir>                    (형식 시험, 약 50 s)
```
출력 (`C:\RTL_YJH\data_full`, 166 MB, git 에 없음): `meta.json` (전체 정보 · layer 별 cosine 표 · id2label),
`embed/` 6개 + meta.json, `l00/` … `l11/` 각 42개 (지금의 40개 + `ln1_w.bin`, `ln1_b.bin`) + meta.json, `head/` 6개 + meta.json.
각 `lXX/` 는 기존 C 코드에 그대로 쓸 수 있다: `vit_main_sim --mlp --data …\l00 / l05 / l11` = 23 PASS, 1308 / 1080 / 511.

| 확인 | 결과 |
|---|---|
| `--full` 없이 (mock) | 40개 + meta.json, 로그까지 `ViT-Base_C_mlp` 생성기와 byte 동일 (이전 numpy 1.24 mock 과도 동일) |
| `--full` 없이 (HF) | 40개 + meta.json = `C:\RTL_YJH\data_l0_mx` 와 byte 동일 |
| `--full --mock` | layer 12개 각각 기존 verify / verify_mlp 전부 ok, 앞뒤 단계 · 연결 검사 전부 ok, 발산 없음 (max\|R2\| 4.7 → 10.6) |
| `--full` (HF) | 같은 검사 전부 ok (`[ok]` 838줄, `[FAIL]` 0) + FP64 embed == HF embedding (6.9e-07), FP64 12 layer + LN + head == HF logits (2.6e-06) → `PASS` |

앞뒤 단계 검사 (파일만 읽어서 다른 경로로): h0 패치 (index 계산으로 모은 패치 + `np.cumsum` 순차 합), CLS (python float),
`l00/h_in == h0`, `l(l+1)/h_in == l(l)/r2` (11개), 12 layer `x.bin` / `x_scale.bin` == MXFP4(LN1(h_in)) (python float),
lnc (python float), logits (python float 순서대로 합, bit-exact), top-1 = argmax.

**HF 비교 (보고용, 판정 아님)** — 기본 COCO 이미지, R2_l (BF16 golden) vs HF `vit.layers.l` 출력:

| layer | cosine vs HF | 상대오차 vs HF | max\|R2\| |
|---|---|---|---|
| 0 | 0.975577 | 22.15 % | 20.1 |
| 1 | 0.955166 | 29.62 % | 21 |
| 2 | 0.941581 | 33.69 % | 21 |
| 3 | 0.927451 | 37.45 % | 29.3 |
| 4 | 0.911784 | 42.05 % | 243 |
| 5 | **0.876050** | 48.99 % | 732 |
| 6 | 0.926353 | 39.18 % | 1232 |
| 7 | 0.927602 | 38.87 % | 1280 |
| 8 | 0.927698 | 38.75 % | 1304 |
| 9 | 0.927184 | 38.83 % | 1360 |
| 10 | 0.921390 | 39.95 % | 1344 |
| 11 | 0.911995 | 41.82 % | 1376 |

| 최종 | 결과 |
|---|---|
| logits cosine vs HF | 0.917219 |
| top-1 | 우리 **285 Egyptian cat** = HF 285 Egyptian cat (같음) |
| HF top-5 | 285 Egyptian cat, 281 tabby, 282 tiger cat, 287 lynx, 284 Siamese cat → 우리 top-1 포함 |
| top-1 − top-2 logit 차이 (우리) | 11.0883 − 9.7691 (281 tabby) = **1.3191** |
| top-1 − top-2 logit 차이 (HF) | 12.4216 − 9.2270 (281 tabby) = **3.1946** |

`meta.json` 의 `summary` 에 `top2`, `top1_top2_gap`, `hf_top2`, `hf_top1_top2_gap` 로도 기록. 같은 결론이지만 여유가 HF 의 약 41 % 로 줄었다
(양자화 오차가 쌓인 결과 — 다른 이미지에서는 top-1 이 바뀔 수 있음, 지시서 10절 ③ 여러 장 검증 때 확인).
meta.json 에는 지시서 5.3절대로 `torchvision` 버전 (0.29.2+cpu) 과 `image_processor`
(`transformers.models.vit.image_processing_vit.ViTImageProcessor`) 도 기록한다.

## Phase 2 결과 (`full_ps.c`, `test_full_ps.c`)

| 함수 | 파일 | 내용 |
|---|---|---|
| `ps_embed` | `full_ps.c` | pixels → 패치 (t/14, t%14), 원소 (ch, kh, kw) 를 직접 index → 순서대로 double 합 + b + pos → BF16. CLS = cls + pos[0] |
| `ps_ln_bf16` | `full_ps.c` | 토큰 1개 LN → BF16 (마지막 LN, CLS). 식은 `ps_ln_row` 공유 |
| `ps_ln_row` | `mlp_ps.c` | `ps_ln2_mx` 안의 토큰 1개 LN 을 함수로 뺀 것 (`ps_ln2_mx` 결과 불변) |
| LN1 | `ps_ln2_mx` 그대로 | 파라미터만 `ln1_w` / `ln1_b` |
| `ps_head`, `ps_top1` | `full_ps.c` | 768 BF16 → logits float32 (순서대로 double 합 + b), 첫 번째 최댓값 index |

빌드: `make test_full_ps` (x86: `mingw32-make test_full_ps CC=gcc EXE=.exe`, aarch64: `CC=aarch64-linux-gnu-gcc CFLAGS="... -static"`),
`full_ps.c` / `mlp_ps.c` 는 `-ffp-contract=off`. 실행: `test_full_ps --data C:\RTL_YJH\data_full`.

| 테스트 | x86 mock | x86 data_full | aarch64 (qemu) mock | aarch64 (qemu) data_full |
|---|---|---|---|---|
| T1 embed == h0_golden (151,296 BF16) | PASS | PASS (51 ms) | PASS | PASS (806 ms) |
| T2 LN1 × 12 layer == x.bin + x_scale.bin | 12 PASS | 12 PASS (3–4 ms / layer) | 12 PASS | 12 PASS (25 ms / layer) |
| T3 마지막 LN (l11 R2 CLS) == lnc_golden | PASS | PASS | PASS | PASS |
| T4 head == logits_golden (bit-exact), top-1 | PASS, 492 | PASS, **285** | PASS, 492 | PASS, **285** |
| T5 1 bit 고장 4가지 (pixel / l05 h_in / LN_f γ / head W) | 4 검출 | 4 검출 | 4 검출 | 4 검출 |
| 마지막 줄 | `PASS (errors=0)` | `PASS (errors=0)` | `PASS (errors=0)` | `PASS (errors=0)` |

- 회귀: `ps_ln_row` 분리 후 `test_mlp_ps` PASS — `data_l0_mx`, `data_full/l00`…`l11` (x86), `l05` (aarch64).
- 경고: x86 / aarch64 경고 0, 새 파일 `-Wconversion -Werror` 통과. aarch64 `full_ps.o` / `mlp_ps.o` fmadd 0개.
- (참고, 판정 아님) `-ffp-contract=off` 없이 빌드하면 `ps_embed` / `ps_head` / `ps_ln_row` 에 fmadd 가 생기지만 data_full 결과는 같았다.
  embed / head 는 float × float 곱이 double 에서 정확해서 FMA 를 써도 값이 같고, LN 은 BF16 반올림이 차이를 흡수한 것. 규칙대로 플래그는 유지.
- 시간은 참고값 (x86 clock, qemu 는 에뮬레이션이라 보드 A53 시간과 다름). 보드 예상은 Phase 4.

- cosine 은 layer 5 에서 가장 낮고 (0.876) 6 부터 0.92 대로 회복. layer 4–6 에서 max\|R2\| 가 커지는 (243 → 1232) 것은 ViT 의 큰 activation 채널로 보이며 [추론], MXFP4 블록 scale 이 그 값에 맞춰지면서 같은 블록의 작은 값이 0 으로 깎이는 영향일 수 있다 [추론] — Phase 3 이후 필요하면 분석.
- layer 0 cosine (0.975577) 이 `data_l0_mx` (0.975498) 와 조금 다른 것은 x.bin 이 HF float LN1 대신 PS LN1 (BF16 입력) 결과이기 때문 (지시서 3.1절, 정상).
- HF hook 은 transformers 5.x 구조 (`vit.layers.l`, `vit.embeddings`, `vit.layernorm`, `classifier`) 를 이름이 아니라 크기 · 구조로 찾는다 (`get_tensors_hf_full`).

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
