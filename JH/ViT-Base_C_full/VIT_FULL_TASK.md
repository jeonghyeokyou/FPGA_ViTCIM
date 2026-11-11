# VIT_FULL_TASK.md — ViT-Base 전체 (이미지 → 12 layer → 분류) 작업 지시서 (Claude Code용)

> 작성: 2026-11-11 · 작업자: JH (유정혁) · 저장소: `C:\RTL_YJH\L2_verification` (GitHub `jeonghyeokyou/FPGA_ViTCIM`)
> 기준 코드: `JH/ViT-Base_C_mlp/` (layer 0 attention + MLP, PC 모델 · 보드 PASS 이후)
>
> **Claude Code에게**: 이 문서는 작업 지시서다. 처음부터 끝까지 읽은 뒤 **JH가 지정한 Phase만** 진행한다.
> 각 Phase가 끝나면 "Gate"에 적힌 보고를 하고 **멈춰서 JH의 확인을 기다린다.**
> 결과만 주지 말고 **왜 그렇게 했는지를 한국어로 짧게 설명**한다.

---

## 0. 먼저 읽을 것

| 파일 | 왜 읽나 |
|---|---|
| `JH/ViT-Base_C_mlp/MLP_TASK.md` | 지난 지시서. 규칙 (1절), 연산 규칙 (5절), 데이터 파일 (6절) — **이번에도 그대로 적용** |
| `JH/ViT-Base_C_mlp/README.md`, `CHANGES.md` | 현재 상태, 빌드 · 실행법, 검사 개수 |
| `vit_main.c` | 지금의 layer 0 실행 흐름 (attention → `mlp_block`) — 이번에 layer 함수로 정리할 대상 |
| `mlp_ps.c` (`ps_ln2_mx`) | LN1 · 마지막 LN에 그대로 재사용할 LN 규칙 |
| `golden/vit_golden_gen.py` | `get_tensors_hf`, `build`, `build_mlp`, `verify*` — 12 layer로 확장할 대상 |

---

## 1. 절대 규칙 (MLP_TASK.md 1절 + 아래)

1. `LHJ/`는 수정하지 않는다. 작업 폴더는 **`JH/ViT-Base_C_full/`** (Phase 0에서 `JH/ViT-Base_C_mlp/`를 복사해서 만든다). `JH/ViT-Base_C_mlp/`도 그대로 둔다 (보드에서 PASS한 기준 버전).
2. **기존 동작 유지 (회귀)**: 새 폴더에서도 `vit_main --mlp`, `vit_dbg` 4가지가 지금과 같은 검사 개수 · 명령 수로 PASS해야 한다. 생성기도 `--full` 없이 실행하면 **지금의 40개 파일과 byte 단위로 같아야 한다.**
3. PS 계산은 Python golden과 **bit-exact**. 새 PS 함수도 `-ffp-contract=off`로 컴파일한다.
4. 추측으로 사양을 정하지 않는다. 10절 미결 항목은 `TODO(JH)`.
5. commit / push는 JH가 요청할 때만. `.bin`, 데이터 zip, venv는 커밋하지 않는다.
6. 테스트 마지막 줄은 `PASS (errors=0)` / `FAIL (errors=N)`.

---

## 2. 목표

이미지 1장 (기본: 생성기의 COCO 예시 이미지)을 넣어 **patch embedding → layer 0~11 → 마지막 LN → 분류 head → top-1**까지 BB 기반으로 돌린다.
- layer마다 attention + MLP는 **지금 코드 그대로** (명령 · L2 배치 · BB 동일), layer별로 weight와 golden만 바뀐다.
- **앞뒤 단계와 LN1은 PS (C)에서 계산한다** (JH 결정: 현 단계는 최대한 PS).
- 판정: (a) 모든 검사 bit-exact PASS, (b) 최종 logits == golden (bit-exact), (c) top-1을 HF 결과와 비교해 **보고** (같아야 한다는 판정은 아님 — 양자화 오차 측정이 목적).

---

## 3. 전체 흐름

```
이미지 (HF ViTImageProcessor 전처리, float32 [3,224,224])          ← 생성기가 pixels.bin으로 저장
 PS  : patch embedding (196 패치 × 768 × W 768×768 + b) , CLS 토큰 결합, + position embedding → h0 (BF16 [197,768])
 for l = 0..11 :
   PS  : LN1_l (h_l) → BF16 → MXFP4 = x_l                           ← 지금은 HF float에서 가져옴 → 이번에 PS로
   BB  : attention (현준 흐름 그대로) → PS Residual 1 : R_l = h_l + Y_l
   PS/BB : MLP (JH 흐름 그대로) → R2_l = R_l + Y2_l
   h_{l+1} = R2_l
 PS  : 마지막 LN (CLS 토큰 1개만) → BF16 → 분류 head (768 → 1000) → logits (float32) → top-1
```

### 3.1 왜 LN1을 PS로 옮기나
지금 layer 0의 `x.bin`은 HF가 float로 계산한 LN1 출력을 그대로 양자화한 것이다. layer를 이어 붙이면 layer l의 입력은 **앞 layer의 BF16 결과 (R2)** 이므로 LN1도 그 값에서 PS가 직접 계산해야 한다. 그래서 `--full` 모드의 layer 0 `x.bin`은 현준 데이터와 조금 달라진다 (정상).

---

## 4. PS 연산 규칙 (Python = C, bit-exact)

공통: BF16 ↔ float, MXFP4, LN 규칙은 MLP_TASK.md 5절과 같다. **곱셈 두 개의 float32 값을 double로 곱하면 정확**하므로 순서만 맞추면 bit-exact가 된다. 합은 모두 **인덱스 오름차순으로 한 번에 하나씩** (numpy `sum` / `@` 금지 — pairwise · BLAS 순서가 다름).

| 연산 | 규칙 |
|---|---|
| 전처리 | 생성기에서만 (HF `ViTImageProcessor`), 결과 `pixels.bin` = float32 [3][224][224] |
| patch 벡터 | 패치 t (0..195) = 행 r = t / 14, 열 c = t % 14. 원소 순서 i = (ch, kh, kw) = HF conv weight [768, 3, 16, 16]을 [768, 768]로 펼친 순서와 같게 |
| patch embedding | 출력 o마다: acc = 0.0 (double); i = 0..767 : acc += double(p[i]) · double(W[o][i]); v = acc + double(b[o]) + double(pos[1+t][o]) → float32 → BF16 RNE = h0[1+t][o] |
| CLS 토큰 | h0[0][o] = BF16(float32(double(cls[o]) + double(pos[0][o]))) |
| LN1 | `ps_ln2_mx`와 같은 식, 파라미터만 `layernorm_before` (ln1_w, ln1_b) |
| 마지막 LN | 같은 LN 식을 **CLS 토큰 1개**에만 → BF16 (양자화 없음) |
| 분류 head | logits[o] = float32( (Σ_i 순서대로 double(lnc[i]) · double(Wh[o][i])) + double(bh[o]) ), o = 0..999. top-1 = 가장 큰 값의 첫 index |
| layer 연결 | h_{l+1} = R2_l (BF16 그대로) |

- patch embedding은 약 1.15억 번 곱셈 → A53에서 수백 ms 예상 (참고값, Phase 4에서 측정). 나중에 MAC BB로 옮길 수 있다 (out proj와 같은 모양) — 이번 범위 아님.
- head의 W는 float32 그대로 쓴다 (양자화 없음).

---

## 5. 생성기 확장 (`golden/vit_golden_gen.py`)

- 새 옵션 `--full`. **없으면 지금과 byte 단위로 같은 40개 파일** (규칙 2).
- `get_tensors_hf`: 12 layer 전부의 QKV / out proj / LN1 / LN2 / FC1 / FC2, patch embedding (conv W, b), CLS, position embedding, 마지막 LN, classifier (W, b)를 꺼낸다. 찾는 방식은 지금처럼 **크기와 구조**로 (이름 하드코딩 최소화). 각 layer 출력 (`layer.l` hook)과 마지막 logits, HF top-1도 저장한다 (비교용).
- `get_tensors_mock`: 같은 크기의 무작위 텐서 (12 layer). 값이 layer를 거치며 발산하지 않는지 확인 (non-finite면 scale 조정).
- 기존 `build()`, `build_mlp()`를 layer마다 재사용한다:
  - `build(x, h_in, W_l, b_l)`에 x = LN1 PS 규칙 결과 (BF16 → float64), h_in = h_l (BF16 → float32)을 넘기면 내부 동작은 그대로다.
  - `build_mlp(r_bytes, W_l, b_l, eps)` 그대로.
- `verify()` / `verify_mlp()`를 layer마다 실행하고, 앞뒤 단계용 검사를 추가한다 (다른 경로로 재계산해서 비교).

### 5.1 출력 폴더

```
<out>/
├─ meta.json                 ← 전체 정보 (이미지, 버전, eps, HF top-1, 우리 top-1, layer별 cosine 표)
├─ embed/   pixels.bin, patch_w.bin (f32 [768][768]), patch_b.bin, cls.bin, pos.bin (f32 [197][768]), h0_golden.bin (BF16 [197][768])
├─ l00/ … l11/               ← 각각 지금과 같은 40개 파일 + ln1_w.bin, ln1_b.bin (f32) + meta.json (layer별 md5)
│                               h_in.bin = h_l , r2_golden.bin = h_{l+1}
└─ head/    lnf_w.bin, lnf_b.bin, head_w.bin (f32 [1000][768]), head_b.bin, lnc_golden.bin (BF16 [768]), logits_golden.bin (f32 [1000])
```
- `l00/x.bin`은 3.1절대로 PS LN1 결과다. `l00/h_in.bin` = `embed/h0_golden.bin`과 같아야 한다 (검사).
- `l{l+1}/h_in.bin` == `l{l}/r2_golden.bin` (검사).
- 용량 예상: layer당 약 13 MB → 전체 약 160 MB.

### 5.2 HF 비교 (보고용, 판정 아님)
- layer별: 우리 R2_l (BF16) vs HF layer l 출력 — cosine, 상대오차.
- 마지막: logits cosine, **우리 top-1 vs HF top-1 (클래스 이름)**, HF top-5 안에 우리 top-1이 있는지.

### 5.3 실행 환경 (2026-11-11 layer 0 실제 데이터 생성 때 확인된 것)
- Python: `C:\RTL_YJH\venv_golden` (Python 3.11.9, torch 2.15.0+cpu, transformers 5.22.2)을 그대로 쓴다. Windows는 `golden/run_gen_win.py`로 실행.
- **torchvision 필수**: transformers 5.x는 torchvision이 없으면 이미지 전처리를 PIL 방식으로 바꿔 `pixels` / `x.bin`이 달라진다 (현준 데이터와 md5 불일치). 생성 전에 `import torchvision` 확인, meta.json에 torchvision 버전과 사용된 image processor 클래스 이름을 기록.
- `PYTHONUTF8=1` (생성기가 meta.json을 encoding 지정 없이 연다 — Windows cp949 문제).
- 출력은 저장소 밖 (`C:\RTL_YJH\data_full\`).
- 보드 빌드는 `make OUT=.` (기본 `make`는 `../vit_main`을 덮어써 현준 실행 파일을 지운다).

---

## 6. C 코드

### 6.1 구조
- `vit_main.c`의 attention 흐름과 `mlp_block()`을 **`layer_run.c` / `layer_run.h`로 옮겨 함수화**한다: `int layer_run(hw_ctx*, const char *layer_dir, const uint8_t *h_in, uint8_t *r2_out, ...)`. `vit_main`은 이 함수를 한 번 부르는 얇은 main이 된다 (회귀: 검사 개수 · 명령 수 그대로).
- 새 PS 함수 (`full_ps.c`, `-ffp-contract=off`): `ps_embed`, `ps_ln_bf16` (LN만, 양자화 없음 — `ps_ln2_mx`와 같은 식을 공유하도록 내부 함수로 분리해도 됨. 단 `ps_ln2_mx`의 결과는 바뀌면 안 됨), `ps_head`.
- 새 실행 파일 `vit_full`: `vit_full --data <out> [--layers N]`
  - embed (PS) → h0 == `h0_golden` 검사
  - layer l = 0..N−1: 그 layer 파일만 읽고 (끝나면 해제 — 메모리 ~15 MB 유지), LN1 PS → x == `x.bin` 검사, `layer_run`, R2 == `r2_golden` 검사, 다음 layer로 R2 전달
  - N = 12면 head (PS) → logits == `logits_golden` (bit-exact), top-1 출력 (index, 클래스 이름은 meta.json에서)
  - 시간 표: layer별 합계 + embed / head / LN1 행. 마지막 줄 `BOARD_RESULT=PASS op=full layers=N top1=<idx>`
- `vit_dbg`: `--data <out>/lXX`로 그 layer의 기존 검사를 그대로 쓸 수 있으면 충분 (새 옵션 불필요하면 만들지 않는다).
- enum 추가: `OP_EMBED, OP_LN1, OP_HEAD` (`OP_N` 21 ≤ `PROF_OPS` 24).
- Makefile: `vit_full`, `vit_full_sim`, `test_full_ps` 추가.

### 6.2 L2
- 새로 쓰는 L2 영역 없음 (앞뒤 단계와 LN1은 PS). layer 사이에 L2 내용을 이어 쓸 필요도 없다 (각 layer는 DDR의 h_l에서 시작).

---

## 7. Phase별 작업과 Gate

### Phase 0 — 준비
- `JH/ViT-Base_C_full/` 생성 (복사), 이 문서 복사. 복사본 그대로 빌드 + PC 모델 회귀 (검사 23개, 명령 1308 / BB 1080 / CDMA 511, dbg 4가지).
- HF 모델 구조 확인: 12 layer, patch embedding conv, CLS, position embedding, 마지막 LN, classifier의 모듈 경로와 크기 (python으로 출력).

**Gate 0 보고**: 회귀 결과, 모듈 경로 · 크기 표, 6.1절 함수 분리 계획 (어느 static 함수를 어디로 옮기는지).

### Phase 1 — 생성기 `--full` (Python만)
- `--full` 없이: 지금 40개와 byte 동일 확인 (mock).
- `--full --mock`: 형식 · 연결 검사 (5.1절) 전부 ok.
- `--full` (HF, 실제 모델 · 이미지 1장): 5.2절 비교표.

**Gate 1 보고**: 파일 구조 · 용량, 회귀 결과, mock 결과, **layer별 cosine 표와 top-1 비교 (HF 클래스 이름)**, 실행 시간.

### Phase 2 — PS 함수 (x86 + aarch64)
- `full_ps.c` + `test_full_ps.c`: embed == `h0_golden`, LN1 (12 layer) == `x.bin` / `x_scale.bin`, 마지막 LN == `lnc_golden`, head == `logits_golden`, 실패 검출 (1 bit 바꾸기).
- mock → 실제 데이터 순서. aarch64 크로스 컴파일 + qemu로도 같은 결과.

**Gate 2 보고**: 테스트 표 (x86 / aarch64), 시간 (x86 참고).

### Phase 3 — 전체 흐름 (PC 모델)
- `layer_run` 분리 → `vit_main` 회귀 PASS (검사 · 명령 수 동일).
- `vit_full_sim --layers 1` → `--layers 12` (mock, 실제 데이터). top-1 == golden.
- 고장 주입 몇 개 (예: layer 5 R2 1 bit, head W 1 bit)가 검출되는지.

**Gate 3 보고**: 결과 표, layer별 시간 (PC 모델), 명령 / BB / CDMA 수 (layer 0과 ×12 비교), 변경 파일 표.

### Phase 4 — 보드 준비 (실행은 JH / 현준)
- 데이터 zip (embed / l00~l11 / head), 보드 명령 정리: 새 폴더 `~/vit_base/data_full`, `make OUT=.`, `vit_full --layers 1` → `--layers 12`, 회귀용 `vit_main --mlp --data ~/vit_base/data_l0`.
- 예상 검사 개수와 예상 시간 [추론]을 README에 표로.

**Gate 4 보고**: 보드 명령, 예상 출력, 빌드 확인.

---

## 8. 보고 형식

MLP_TASK.md 9절과 같다.

---

## 9. 참고 숫자

| 항목 | 값 |
|---|---|
| 토큰 / d_model / head / layer | 197 (CLS + 196) / 768 / 12 / 12 |
| patch | 16 × 16 × 3 = 768, 14 × 14 = 196개 |
| 분류 | 1000 class (ImageNet), classifier 768 → 1000 |
| layer 0 PC 모델 | 검사 23개 (attention 15 + MLP 8), 명령 1308, BB 1080, CDMA 511 |
| 보드 예상 [추론] | layer당 약 0.8 s (Golden 주입이 대부분) → 12 layer 약 10 s. 실제 IP 성능과 무관 |

---

## 10. 미결 항목 — `TODO(JH)`

1. **patch embedding과 head의 위치**: 지금은 PS (JH 결정). 칩 데모에서 MAC으로 옮길지는 IP 사양을 보고 결정.
2. **FC2 partial 누산, GELU 식, g6 사용**: MLP_TASK.md 11절 그대로 (미결 유지).
3. **입력 이미지**: 지금은 1장 (기본 COCO 이미지). 여러 장 검증은 다음 단계.
4. **top-1이 HF와 다르면**: 판정 실패가 아니라 결과로 보고한다 (MXFP4/BF16 누적 오차). 어느 layer부터 cosine이 떨어지는지 표로.

---

## 11. JH가 Claude Code에 처음 줄 프롬프트 (예시)

```
C:\RTL_YJH\VIT_FULL_TASK.md 를 처음부터 끝까지 읽고, 0절의 파일들을 읽은 다음
Phase 0만 진행해줘. 끝나면 8절 형식으로 Gate 0 보고하고 멈춰.
```
