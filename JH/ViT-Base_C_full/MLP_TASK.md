# MLP_TASK.md — ViT-Base Encoder MLP 단계 PS C 코드 작업 지시서 (Claude Code용)

> 작성: 2026-11-10 · 작업자: JH (유정혁) · 저장소: `C:\RTL_YJH\L2_verification` (GitHub `jeonghyeokyou/FPGA_ViTCIM`)
> 기준 코드: `LHJ/ViT-Base_C_261110/` (이현준, commit `55d6f24`, 2026-11-10, golden 생성기 `vit_golden_gen.py_261110` 포함)
>
> **Claude Code에게**: 이 문서는 작업 지시서다. 처음부터 끝까지 읽은 뒤 **JH가 지정한 Phase만** 진행한다.
> 각 Phase가 끝나면 "Gate"에 적힌 보고를 하고 **멈춰서 JH의 확인을 기다린다.** 다음 Phase로 마음대로 넘어가지 않는다.
> 결과만 주지 말고 **왜 그렇게 했는지를 한국어로 짧게 설명**한다.

---

## 0. 먼저 읽을 것 (순서대로)

| 파일 | 왜 읽나 |
|---|---|
| `LHJ/ViT-Base_C_261110/2026-11-10_ViT-Base_C프로그램_정리.md` | 현준 코드 전체 설명. L2 줄 주소, 명령, BB, 검증 체계(C1~C6), 보드 결과 |
| `vit_hw.h` | 주소 맵, 명령 생성 함수(`cmd_x_load` 등), BB 레지스터, `hw_*` API, `PROF_OPS` |
| `vit_ops.h` | ViT 크기 상수, QKV 호출 패턴 (FC1·FC2가 그대로 따라 할 패턴) |
| `attn_ops.h`, `attn_ops.c` | `at_oproj_tile` (FC1·FC2의 원형), `at_softmax_head` (GELU의 원형), `ps_mx_o` (H 양자화의 원형), `ps_residual`, hook 구조체 |
| `mxfp4.h`, `mxfp4.c` | MXFP4 규칙, BF16 변환 (`f32_to_bf16`은 RNE) |
| `vit_main.c` | 실행 순서, DMA 도우미(`to_l2`, `from_l2`, `poison_l2`), 최종 검사, 시간 표 |
| `vit_dbg.c`, `dbg_common.*`, `dbg_attn.*` | 호출별 검사(C1~C6) 붙이는 방식 |

---

## 1. 절대 규칙

1. **`LHJ/` 아래 파일은 절대 수정하지 않는다** (공동작업자 폴더). 작업은 전부 `JH/ViT-Base_C_mlp/`에서 한다.
2. `JH/ViT-Base_C_mlp/`는 Phase 0에서 `LHJ/ViT-Base_C_261110/`을 **복사**해서 만든다. 복사본을 고칠 때는 파일 머리 주석에 `원본: LHJ/ViT-Base_C_261110/<파일> (55d6f24) / 무엇을 왜 바꿨는지`를 적고, `JH/ViT-Base_C_mlp/CHANGES.md`에도 한 줄씩 남긴다. 현준 코드 수정은 **꼭 필요한 곳만** (2절 표).
3. **추측으로 사양을 정하지 않는다.** 11절 미결 항목에 걸리면 `TODO(JH)` 주석을 남기고 보고한다.
4. PS 계산 결과는 Python golden과 **bit 단위로 같아야 한다.** 다르면 C를 Python에 맞추는 게 아니라, 어느 규칙(5절)이 어긋났는지 먼저 보고한다.
5. git: **commit / push는 JH가 요청할 때만.** push 전 `git pull --rebase`, 강제 push 금지. 빌드 산출물(`vit_main`, `vit_dbg`, `*.o`, 테스트 실행 파일)과 데이터 `.bin`은 커밋하지 않는다.
6. 테스트 프로그램은 마지막 줄에 `PASS (errors=0)` 또는 `FAIL (errors=N)`을 출력한다.
7. 컴파일 경고 0: `-O2 -std=gnu11 -Wall -Wextra` (현준 기준). aarch64 cross 컴파일러가 있으면 `-Wconversion -Werror`까지.

---

## 2. 현준 코드에서 바꿔야 하는 곳 (복사본에서만)

| 파일 | 변경 | 이유 |
|---|---|---|
| `vit_hw.h` | `PROF_OPS` 16 → 24 | 현재 `OP_N` = 11. MLP 연산 7개를 추가하면 18이 되어 `attn_ops.h`의 `_Static_assert(OP_N <= PROF_OPS)`에서 컴파일 실패 |
| `attn_ops.h` | enum에 `OP_LN2, OP_FC1, OP_GELU, OP_H_MX, OP_FC2, OP_FC2_ACC, OP_RESID2`를 **`OP_VERIFY` 앞에** 추가 | 시간 표에 MLP 연산을 따로 보이기 위해 |
| `attn_ops.c` | `OP_NAME[]`에 위 7개 이름 추가 (enum 순서와 같게) | 위와 같음 |
| `vit_main.c` | `out_block()` 뒤에 `mlp_block()` 호출, 최종 검사 항목 추가, `--mlp` / `--tiles N` 옵션 | 7절 |
| `vit_dbg.c` | `--op mlp --tile J` / `--op fc2 --n N` 진입점 추가 | 8절 |

`run_mac` / `run_store`는 `attn_ops.c`의 `static` 함수다. **복사본에서 static을 풀지 말고** `mlp_ops.c`에 같은 내용의 static 함수를 따로 둔다 (현준 파일 변경 최소화).

---

## 3. 목표 (한 문장)

현준이 완성한 layer 0 attention 블록(QKV → … → out proj → Residual 1, 보드 PASS) 뒤에 **LN2 → FC1 → GELU → FC2 → Residual 2**를 붙여, BB(Golden 출력) 기반으로 **Encoder 1 layer 전체**를 ZCU102에서 bit-exact로 돌린다. 실제 IP가 오면 BB만 교체하고 명령 순서·L2 배치·PS 코드는 그대로 쓴다.

---

## 4. 확정된 설계 (2026-11-10, JH 결정)

### 4.1 연산 위치

| 연산 | 수행 | 입력 → 출력 |
|---|---|---|
| LN2 + MXFP4 | **PS (C)** | R (BF16, `r_golden.bin` = Residual 1 결과) → X2 MXFP4 (토큰당 12줄 = 2,364줄) |
| FC1 (tile j = 0..47) | MAC BB (ch1) | X2 × W1 tile j (64 출력 열 × 768 입력) → H tile j (BF16, 788줄) |
| GELU (tile j) | **Vector BB (ch2)** — Nonlinear IP 자리 | H tile j → G tile j (BF16, **같은 L2 주소에 덮어씀**) |
| G → MXFP4 | **PS (C)** | G tile j → H4 plane k = j / 12 의 줄 `12t + (j % 12)` |
| FC2 (n = 0..11, k = 0..3) | MAC BB (ch1) | H4 plane k × W2 (n, k) → partial (n, k) (BF16, 788줄) |
| partial 누산 | **PS (C)** | partial (n, 0..3) → Y2 tile n (f32 누산 → BF16) |
| Residual 2 | **PS (C)** | R2 = BF16(f32(R) + f32(Y2)) — `ps_residual` 그대로 |

### 4.2 왜 FC2를 입력 축 4조각으로 나누나

- `WMEM_LINES = 1024`. FC2 W tile 하나 (64 출력 열 × 입력 3072 × 4bit) = **3,072줄 → WMEM에 안 들어감.**
- 입력 축을 768씩 4조각으로 나누면 각 조각은 X / O concat과 **같은 모양 (토큰당 12줄, W 768줄)** → FC2 호출이 `at_oproj_tile`과 똑같아진다.
- H4 plane k = FC1 tile 12k ~ 12k+11의 출력 (입력 축 768k ~ 768k+767). 그래서 G tile j의 양자화 결과는 plane j/12의 "head 자리" j%12에 들어간다 → `ps_mx_o(o, head = j % 12, oc = plane, ocs = plane scale)`를 **그대로 재사용**할 수 있다.
- partial 누산은 IP 지원 여부 미정 → **우선 PS f32 누산** (11절 ③).

### 4.3 L2 배치 (줄 주소 c, 32 B/줄, c = {grp[2:0], quad[1:0], row[9:0]})

현준 규칙 유지: **연산기와 CDMA가 동시에 쓰는 영역은 서로 다른 half (64 KiB = 2048줄)**, A/B 버퍼는 index의 parity로 고른다.

| 매크로 (제안) | c 시작 | 줄 수 | PS/CDMA byte 주소 | 위치 |
|---|---|---|---|---|
| `L2_X2` | `0x0000` | 2,364 | `0xA0000000~0xA001277F` | g0 / b0~11 |
| `L2_W1(b)` | `0x1000` / `0x1800` | 768 | `0xA0020000~` / `0xA0030000~` | g1 / b0~3, b8~11 |
| `L2_H(b)` | `0x2000` / `0x2800` | 788 | `0xA0040000~` / `0xA0050000~` | g2 / b0~3, b8~11 |
| `L2_H4(k)` | `0x3000`, `0x4000`, `0x5000`, `0x7000` | 2,364 | `0xA0060000~`, `0xA0080000~`, `0xA00A0000~`, `0xA00E0000~` | g3, g4, g5, **g7** / b0~11 |
| `L2_W2(b)` | `0x0000` / `0x0800` | 768 | `0xA0000000~` / `0xA0010000~` | g0 / b0~3, b8~11 (X2 자리 재사용) |
| `L2_P(b)` | `0x1000` / `0x1800` | 788 | `0xA0020000~` / `0xA0030000~` | g1 / b0~3, b8~11 (W1 자리 재사용) |

- **g6 (`0x6000~0x6A01`)은 현준 dbg scratch** → MLP는 쓰지 않는다 (H4 k3를 g7에 둔 이유).
- FC1 단계: b = j & 1. FC2 단계: i = 4n + k, b = i & 1.
- H4 4개 plane은 FC2가 끝날 때까지 L2에 유지 (FC2가 plane마다 12번 다시 읽음).
- attention 단계 데이터(Q/K/Vᵀ, S, O, Y tile)는 Residual 1 이후 필요 없으므로 덮어써도 된다.

### 4.4 명령 순서 (첫 버전은 **순차 실행**, 현준 vit_main과 같은 이유: 연산별 시간 측정)

**LN2 (PS)**: `ps_ln2_mx(R, ln2_w, ln2_b, x2, x2s)` → `to_l2(x2, LB(2364), L2_X2)`

**FC1 tile j** (`mlp_fc1_tile`, `at_oproj_tile`과 같은 패턴):
```
WLOAD  L2_W1(j&1), 768 → WMEM 0                       (CDMA로 w1 tile j를 먼저 L2_W1(j&1)에 적재)
group g = 0, 1 :  g0 = 128g, nt = g ? 69 : 128, n2 = nt − 64
  LOAD   L2_X2 + 12·g0, 12·nt → L1 0
  BB #1  in 0, 768        w 0, 768   out 1536, 256      gold = h tile j, token g0
  BB #2  in 768, 12·n2    w 0, 768   out 1792, 4·n2     gold = h tile j, token g0+64
  STORE  L1 1536, 4·nt → L2_H(j&1) + 4·g0
```

**GELU tile j** (`mlp_gelu_tile`, `at_softmax_head`과 같은 방식):
```
ch2 LOAD  L2_H(j&1), 788 → vector 입력 메모리 0          (VIN_LINES 2048 안에 들어감)
call i = 0..3 : t0 = 64i, nt = min(64, 197 − t0)        (64, 64, 64, 5)
  Golden  g tile j, token t0, 4·nt 줄 → hw_bb2_gold_load  (≤ 256줄)
  hw_bb2_run_store(in_base 4·t0, in_len 4·nt, l2_c L2_H(j&1) + 4·t0, H = 1, W = 4·nt)
```
기대 CYCLES2 = in_len + 3·beats + 6 = 4nt + 12nt + 6.

**G 회수와 양자화 (PS)**: `from_l2(L2_H(j&1), LB(788), g)` → `ps_mx_o(g, j % 12, h4[k], h4s[k])` (k = j / 12) → `j % 12 == 11`이면 `to_l2(h4[k], LB(2364), L2_H4(k))`

**FC2 (n, k)** (`mlp_fc2_call`, 역시 `at_oproj_tile` 패턴):
```
i = 4n + k, b = i & 1
CDMA   w2 (n, k) → L2_W2(b);  WLOAD L2_W2(b), 768 → WMEM 0
group g = 0, 1 : LOAD L2_H4(k) + 12·g0, 12·nt → L1 0, BB #1, BB #2 (위와 같은 인자),
                 STORE L1 1536, 4·nt → L2_P(b) + 4·g0
CDMA   L2_P(b) → DDR, PS: ps_fc2_acc(acc_n, partial, k)  (k = 3이면 Y2 tile n 확정)
```

**Residual 2 (PS)**: `ps_residual(R, Y2, R2)` (Y2는 `yo_golden`과 같은 12 tile × 788줄 배치로 호스트에 모은다)

규모: FC1 48 tile × (WLOAD 1 + LOAD 2 + STORE 2) = 240 명령, MAC BB 96회 · GELU ch2 LOAD 48 + vector BB 192회 · FC2 48 × 5 = 240 명령, MAC BB 96회.

---

## 5. 연산 규칙 (Python golden과 같아야 함)

기준: `LHJ/ViT-Base_C_261110/vit_golden_gen.py_261110` (HF `google/vit-base-patch16-224`, Colab에서 실행). 이 생성기의 규칙을 **그대로 이어 쓴다.**

| 연산 | 규칙 | 상태 |
|---|---|---|
| BF16 ↔ float | `bf16_bits` / `bf16_to_f32` = C의 `f32_to_bf16` / `bf16_to_f` (RNE) | 확정 (현준) |
| MXFP4 (PS) | `mx_of_bf16`: BF16 → float64 → `mx_quant` (마지막 축 32개 블록) = C `mx_quant` | 확정 (현준) |
| MAC golden (FC1, FC2) | `mx_dot` (블록마다 정수 합 × 2^(Xa+Xb−2), **블록 순서대로 float64 누산**) **+ bias (float64)** → float32 → BF16 RNE. QKV · out proj와 같은 식 | 확정 (현준 규칙) |
| W packing | torch weight [out, in]를 `mx_quant` (입력 축 블록) → tile = 출력 열 64개 행을 `pack4` (= `wo.bin`과 같음). scale은 `wo_scale`처럼 col*24 + 블록 | 확정 (현준 규칙) |
| LN2 | 토큰마다: x = float64(BF16 R), mean = Σx / 768, var = Σ(x − mean)² / 768 (biased), y = ((x − mean) / sqrt(var + eps)) · γ + β, **모두 float64** → float32 → BF16 RNE → `mx_of_bf16` = X2. **합산은 i = 0..767 순서대로** (numpy `mean`/`sum`은 pairwise 합이라 C와 마지막 bit가 다를 수 있음 → Python도 순서대로 더하는 루프로 쓴다). eps = `model.config.layer_norm_eps` (HF ViT = **1e-12**), γ/β = `layernorm_after` (float32) | 규칙 확정, eps 값은 생성기에서 읽어 `meta.json`에 기록 |
| GELU (vector BB golden, Python만) | g = BF16(float32(0.5 · h · (1 + erf(h / √2)))) , h = float64(BF16 H), float64로 계산 (HF `gelu` = exact erf). `softmax_bf16`과 같은 방식 | 확정 (Nonlinear IP 사양 나오면 재검토) |
| G 양자화 | G 전체 [197, 3072]에 `mx_of_bf16` → plane k = 열 768k ~ 768k+767을 `pack4` (토큰당 12줄). C에서는 `ps_mx_o(g, j % 12, plane k, scale k)`와 같은 결과여야 함 | 확정 |
| FC2 partial | partial (n, k) = BF16(float32(`mx_dot`(H4 plane k, W2 (n, k)))) — **bias 없음** | 임시 (11절 ③) |
| partial 누산 + bias | acc = float32(b2[col]); k = 0..3 순서로 acc += f32(partial_k) (**float32**) → BF16 RNE = Y2 | 임시 (11절 ③) |
| Residual 2 | R2 = BF16(f32(R) + f32(Y2)) (= `ps_residual`, R 식과 같음) | 확정 (현준) |

- `ps_ln2_mx`, `ps_fc2_acc`는 **`mlp_ps.c`에 따로 둔다** (`/dev/mem`을 쓰는 `vit_hw.c` 없이 x86에서 빌드·테스트할 수 있게).
- **`mlp_ps.c`는 `-ffp-contract=off`로 컴파일한다.** gcc는 gnu 모드에서 `a*b + c`를 FMA 한 번으로 합칠 수 있고(aarch64에서 실제로 합침), 그러면 numpy와 반올림이 달라져 LN2 결과가 bit 단위로 어긋난다. 같은 이유로 `x87`이 아닌 SSE2 (x86-64 기본) 환경에서 테스트한다.
- FC2를 4조각으로 나눠 BF16 partial로 더하면, 한 번에 float64로 누산하는 "이상적인" FC2와 값이 조금 다르다. Phase 1에서 두 결과가 다른 원소 수와 최대 오차를 **보고만** 한다 (판정 아님).

---

## 6. 데이터 파일 (`vit_golden_gen.py` 확장, 출력 폴더 = 현준 `data/`와 같은 곳)

| 파일 | 크기 (B) | 내용 / 배치 |
|---|---|---|
| `ln2_w.bin`, `ln2_b.bin` | 768 × 4 each | LN2 γ, β (`layernorm_after`, float32 LE) |
| `x2_fp4.bin`, `x2_scale.bin` | 75,648 / 4,728 | LN2 출력 MXFP4 (`x.bin`과 같은 배치), 기대값 |
| `w1.bin`, `w1_scale.bin` | 48 × 24,576 = 1,179,648 / 3072 × 24 = 73,728 | FC1 (`intermediate.dense`, [3072, 768]). tile j = 출력 열 64j ~ 64j+63, `wo.bin`과 같은 packing. scale = j*1536 + col*24 + 블록 |
| `b1.bin` | 3072 × 4 | FC1 bias float32 (golden 계산에만 쓰임, 보드는 읽지 않아도 됨) |
| `h_golden.bin` | 48 × 25,216 = 1,210,368 | FC1 BF16 출력, tile j*25216 + token*128 (`yo_golden` 배치) |
| `g_golden.bin` | 1,210,368 | GELU 출력 BF16 (같은 배치) |
| `h4_fp4.bin`, `h4_scale.bin` | 4 × 75,648 / 4 × 4,728 | H4 plane k = 0..3, 기대값 (plane 안은 `x.bin` 배치) |
| `w2.bin`, `w2_scale.bin` | 48 × 24,576 / 768 × 96 = 73,728 | FC2 (`output.dense`, [768, 3072]). tile i = 4n + k: 출력 열 64n ~ 64n+63, 입력 768k ~ 768k+767을 `pack4`. scale = i*1536 + col*24 + 블록 (조각 k의 24블록) |
| `b2.bin` | 768 × 4 | FC2 bias float32 — **PS 누산에 필요하므로 보드도 읽는다** |
| `p_golden.bin` | 48 × 25,216 | FC2 partial (n, k) BF16, index 4n + k |
| `y2_golden.bin` | 12 × 25,216 | Y2 tile n (5절 누산 규칙 결과) |
| `r2_golden.bin` | 302,592 | R2 = layer 0 출력 [197][768] BF16, token*1536 |

- 기존 파일 `r_golden.bin` (Residual 1 결과)이 LN2 입력이다.
- `FILES` 목록에 위 항목을 추가하고, `meta.json`에 md5 · 크기 · `layer_norm_eps`를 기록한다.
- `get_tensors_hf`에서 block 0의 `intermediate.dense`, `output.dense`, `layernorm_after`를 찾아 W1 / b1 / W2 / b2 / γ / β를 꺼낸다 (현준 코드는 지금 QKV · out proj · LN1만 꺼냄). 이름으로 찾지 말고 **in/out 크기로 찾는 현준 방식**을 따른다 (D→3072 Linear 1개, 3072→D Linear 1개, LN 중 LN1이 아닌 것).
- `get_tensors_mock`에도 같은 크기의 무작위 텐서를 추가한다 (`--mock`으로 형식 시험).
- `verify()`에 참고 비교 추가: HF block 0 출력 (`layer.0` hook 출력) 대비 R2의 cosine · 최대 오차, 그리고 5절의 "이상적인 FC2"와 Y2의 차이.

---

## 7. 만들 파일 구조

```
JH/ViT-Base_C_mlp/
├─ MLP_TASK.md          ← 이 문서
├─ CHANGES.md           ← 현준 복사본에서 바꾼 것 목록
├─ README.md            ← Phase마다 결과 · 빌드 · 실행법 갱신
├─ (현준 파일 복사본 전체)
├─ mlp_ops.h            ← 상수, L2 매크로(4.3), 파일 구조체, 함수 선언
├─ mlp_ops.c            ← mlp_files_load, mlp_fc1_tile, mlp_gelu_tile, mlp_fc2_call (hook은 attn_hooks 재사용)
├─ mlp_ps.c             ← ps_ln2_mx, ps_fc2_acc (+ ps_mx_o / ps_residual 호출 래퍼)
├─ dbg_mlp.h / .c       ← 호출별 C1~C6 검사
├─ test_mlp_ps.c        ← x86 PS 단독 테스트 (보드 불필요)
└─ golden/              ← vit_golden_gen.py MLP 확장 (Phase 1, 생성기를 받은 뒤)
```

hook 구조체(`mac_call`, `mac_store`, `vec_load`, `vec_call`, `attn_hooks`)는 **새로 만들지 말고 재사용**한다 (`op` 필드로 MLP 연산 구분). 그래야 `dbg_common`의 C2~C5 도우미를 그대로 쓸 수 있다.

---

## 8. Phase별 작업과 Gate

### Phase 0 — 준비 (코드 작성 없음)
1. `git pull --rebase` 후 `LHJ/ViT-Base_C_261110/`가 있는지 확인. `JH/ViT-Base_C_mlp/` 생성, 현준 파일 복사, 이 문서를 그 폴더로 복사.
2. 빌드 환경 확인: Windows에서 쓸 수 있는 gcc (WSL / MinGW), aarch64 cross 컴파일러, Python + numpy. `vit_hw.c`는 `/dev/mem`·`mmap`을 써서 **Linux(WSL 또는 보드)에서만** 빌드된다.
3. 복사본 그대로 `vit_main`, `vit_dbg`를 빌드 (가능한 환경에서).
4. 현준 문서 6.3절의 **x86 "소프트웨어 하드웨어 모델"**이 저장소에 있는지 찾는다 (없으면 TODO(JH)). Python 환경에 numpy가 있는지, torch · transformers가 있는지 (없으면 Phase 1은 `--mock` + Colab).

**Gate 0 보고**: 환경 표 (gcc / WSL / cross / Python 버전), 복사본 빌드 결과, 없는 파일 목록, 2절 변경을 할 위치 (줄 번호).

### Phase 1 — golden 생성기 확장
- `LHJ/ViT-Base_C_261110/vit_golden_gen.py_261110`을 `JH/ViT-Base_C_mlp/golden/vit_golden_gen.py`로 복사해서 고친다 (원본 수정 금지).
- **기존 출력 파일 23개는 byte 단위로 그대로여야 한다.** 고친 뒤 `--mock`으로 원본 / 수정본을 둘 다 돌려 23개 파일 md5가 같은지 먼저 확인한다.
- 6절 파일 추가, 5절 규칙 그대로 구현 (LN2 합산은 순서대로 도는 루프).
- 실제 모델(HF) 실행은 torch · transformers가 필요하다. 로컬에 없으면 `--mock`까지만 하고, **Colab에서 돌릴 명령과 결과 폴더 확인 방법**을 JH에게 적어 준다.

**Gate 1 보고**: 생성 파일 표 (크기, md5), 기존 23개 md5 일치 여부, `--mock` / HF 결과, cosine · 이상적 FC2 대비 차이, 남은 TODO.

### Phase 2 — PS 함수 (x86 단독)
- `mlp_ps.c`: `ps_ln2_mx`, `ps_fc2_acc`, H 양자화 래퍼 (`ps_mx_o` 호출).
- `test_mlp_ps.c`: data 폴더의 파일로
  T1 LN2: `r_golden` → x2 FP4 / scale == `x2_fp4`, `x2_scale` ·
  T2 H 양자화: `g_golden` 48 tile → H4 plane 4개 == `h4_fp4`, `h4_scale` ·
  T3 누산: `p_golden` → Y2 == `y2_golden` ·
  T4 Residual 2: `r_golden` + `y2_golden` → == `r2_golden` ·
  T5 실패 검출: 입력 1 bit 바꾸면 FAIL이 나는지.
- 불일치 시 첫 위치 (토큰, 원소, got / exp) 출력.

**Gate 2 보고**: T1~T5 표, 처음에 어긋났던 곳과 원인 (있다면), PS 시간 (x86 참고).

### Phase 3 — BB 흐름 (`mlp_ops.c`)
- `mlp_fc1_tile`, `mlp_gelu_tile`, `mlp_fc2_call` (4.4절 순서 그대로), 2절 enum / `PROF_OPS` 변경.
- 현준의 x86 하드웨어 모델이 있으면 그걸로 `vit_main --mlp` 전체 실행. 없으면 명령 64bit 값을 로그로 찍어 **필드 해석표**(op, L2 c, n, L1/WMEM/v_row)를 만들고 4.3 / 4.4절과 대조.

**Gate 3 보고**: 함수별 명령 수 / BB 호출 수 (4.4절 규모와 일치?), 대조 결과, 변경 파일 표.

### Phase 4 — 검증 연결 (`dbg_mlp.c`, `vit_main`, `vit_dbg`)
- `vit_dbg --op mlp --tile J`: FC1 tile J + GELU tile J를 호출별 검사 (C1 CDMA, C2 BB 입력 = X2 / W1 tile, vector 입력 = h tile, C3 CYCLES 식, C4 출력 == golden + guard 줄, C5 inject, C6 PS 양자화).
- `vit_dbg --op fc2 --n N`: H4 plane 4개를 L2에 올리고 (n, 0..3) 호출별 검사 + 누산 C6 + 그 64열의 Residual 2 C6.
- `vit_main`: attention 뒤 MLP 순차 실행, 최종 검사 (H→G 회수 == `g_golden`, partial == `p_golden`, X2 / H4 / Y2 / R2 == 파일), 시간 표에 MLP 행 추가. `--tiles N`이면 FC1 tile 0..N−1만 (빠른 확인용).

**Gate 4 보고**: 보드에서 JH가 돌릴 명령 목록, 예상 출력 (검사 항목 수), 빌드 확인 결과.

### Phase 5 — 보드 실행 (JH가 실행, Claude Code는 로그 분석)
- 순서: `vit_dbg --op mlp --tile 0` → `--tile 47` → `--op fc2 --n 0` → `vit_main --mlp`.
- 로그를 받아 FAIL 위치 분석. 고친 뒤 다시 Gate 4 형식으로 보고.

### (선택) Phase 6 — 겹치기
- A/B 버퍼로 FC1 j+1 (MAC)과 GELU j (vector), G j 회수 · W1 j+2 적재 (CDMA)를 겹친다. 규칙: MAC과 vector는 서로 다른 half, CDMA는 vector가 끝난 버퍼만. 순차 버전과 결과가 bit 단위로 같아야 한다. JH가 요청할 때만.

---

## 9. 보고 형식 (각 Gate 공통)

```
## Gate N 보고
- 결과: PASS a / FAIL b
- 표: (테스트 | 결과 | 비고)
- 만든/바꾼 파일: (경로 | 한 줄 설명)
- 빌드 / 실행법:
- 왜 이렇게 했나: (설계 판단 2~3개, 쉬운 말로)
- 발견한 문제: (없으면 "없음")
- JH 확인 필요: (TODO(JH) 목록)
```

---

## 10. 참고 숫자

| 항목 | 값 |
|---|---|
| 토큰 / d_model / MLP hidden | 197 / 768 / 3072 |
| 줄 크기 | 32 B (256 bit). 토큰당: FP4 768개 = 12줄, BF16 64개 = 4줄 |
| L1 / WMEM / Golden / vector 입력 | 2048 / 1024 / 256 / 2048줄 |
| MAC CYCLES | in + w + out + 9 |
| vector CYCLES2 | in + w + 3·beats + 6 |
| 현준 attention 블록 보드 결과 | 389.9 ms, 출력 검사 15개 PASS, PS가 Golden 제외 시간의 94% |

---

## 11. 미결 항목 — 추측하지 말고 `TODO(JH)`로 남길 것

1. **(해결)** `vit_golden_gen.py`: `LHJ/ViT-Base_C_261110/vit_golden_gen.py_261110`로 받음 (commit `55d6f24`).
2. **(해결)** LN2 규칙: 5절 (float64, 순서대로 합산, eps는 HF config).
3. **FC2 partial 누산**: 실제 MAC IP가 누산을 지원하면 BB golden은 k = 3에서 bias 포함 최종 Y2만 내고, PS 누산은 빠진다. 지금은 PS f32 누산 (임시). 누산을 IP가 하면 "이상적인 FC2"와 같아진다.
4. **GELU 정의**: 지금은 HF와 같은 exact erf. Nonlinear IP가 근사식을 쓰면 golden을 그 식으로 바꾼다.
5. **g6 사용 여부**: 현준 dbg 영역이라 비워 둠. 현준과 합의 필요.
6. **x86 하드웨어 모델**: 현준 문서 6.3절에 있다고 했지만 저장소에서 확인되지 않음.
7. **보드 `data/` 폴더**: 현준 파일 23개 + `meta.json`은 보드에만 있음. Phase 2 테스트에는 이 파일들(특히 `r_golden.bin`)이 필요.

---

## 12. JH가 Claude Code에 처음 줄 프롬프트 (예시)

```
C:\RTL_YJH\MLP_TASK.md 를 처음부터 끝까지 읽고, 0절의 파일들을 읽은 다음
Phase 0만 진행해줘. 끝나면 9절 형식으로 Gate 0 보고하고 멈춰.
```
