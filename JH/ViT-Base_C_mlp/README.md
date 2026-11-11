# ViT-Base layer 0 — attention + MLP (Encoder 1 layer) on ZCU102, blackbox = Golden

작업: JH, 2026-11-10 · 기준: `LHJ/ViT-Base_C_261110/` (이현준, 55d6f24) · 지시서: [MLP_TASK.md](MLP_TASK.md) · 변경 목록: [CHANGES.md](CHANGES.md)

현준의 attention 블록 (QKV → … → out proj → Residual 1) 뒤에 **LN2 → FC1 → GELU → FC2 → Residual 2** 를 붙였다.
BB 는 계산하지 않고 Golden 을 그대로 내보낸다. 명령 순서 · L2 배치 · PS 코드는 실제 IP 가 와도 그대로 쓰는 것이 목표.

## 상태 (2026-11-11)

| Phase | 결과 | 확인 환경 |
|---|---|---|
| 0 준비 | 복사본 빌드 경고 0 (`-O2 -std=gnu11 -Wall -Wextra`, aarch64 GCC 13.3) | PC |
| 1 golden 생성기 | `--mock` PASS, 기존 23개 파일 원본과 byte 동일, 새 파일 17개 | PC (numpy 1.24) |
| 1 HF 실제 모델 | PASS, `FP64 기준 계산 == HF block 0 출력 [ok]`, x / w / y_golden md5 = 현준 문서 4.3절 값 | PC venv (아래 "데이터") |
| 2 PS 함수 | `test_mlp_ps` T1–T5 PASS (errors=0), mock · 실제 데이터 모두 | PC x86 |
| 3 BB 흐름 | `vit_main --mlp` 검사 23개 PASS, MLP 명령 720개 = 4.3/4.4절 (check_cmd_log PASS) | PC x86 모델 (`hw_sim.c`) |
| 4 검증 연결 | `vit_dbg --op mlp` / `--op fc2` PASS (mock · 실제 데이터 개수 같음), 고장 주입 6건 모두 검출 | PC x86 모델 |
| 5 보드 | **미실행** (JH 실행) | — |

x86 모델 (`hw_sim.c`) 은 현준 코드를 그대로 돌렸을 때 보드 결과와 같은 숫자를 낸다:
vit_main 검사 15개 PASS · 명령 588 · BB 504 · CDMA 218, dbg attn head 0 = C1 6 / C2 32 / C3 26 / C4 54 / C5 4 / C6 10,
dbg oproj tile 0 = C1 2 / C2 8 / C3 4 / C4 7 / C6 1 (현준 문서 7절과 같음).

### 실제 모델 데이터 결과 (2026-11-11, PC, `C:\RTL_YJH\data_l0_mx`)

| 항목 | 결과 |
|---|---|
| 생성기 | `PASS`, `FP64 기준 계산 == HF block 0 출력 [ok]` (상대오차 5.01e-07), top-1 = Egyptian cat |
| (info) R2 vs HF block 0 출력 | cosine 0.975498, 최대 \|차\| 2.766, 상대오차 22.19 % |
| (info) Y2 vs 이상적 FC2 | 다른 원소 51,691 / 151,296 (34.17 %), 최대 \|차\| 0.03125, 상대오차 0.235 % |
| `test_mlp_ps` | T1–T5 `PASS (errors=0)` |
| `vit_main_sim --mlp` | 23 PASS · 1308 / 1080 / 511 |
| `vit_dbg_sim` mlp tile 0 / 47, fc2 n 0 / 11 | PASS, C1–C6 개수 = mock 과 같음 (아래 예상 표) |
| aarch64 (GCC 13.3) | 경고 0, `mlp_ps.c` fmadd 0 (옵션 없으면 2). qemu 실행은 미실시 (WSL 없음) |

## 빌드

보드 — **`make OUT=.` 로 새 폴더 안에 만든다** (그냥 `make` 는 `../vit_main` 을 덮어써서 현준 실행 파일이 바뀐다):
```
make OUT=.                 # -> ./vit_main ./vit_dbg   (mlp_ps.c 는 -ffp-contract=off 로 따로 컴파일됨)
```
Makefile 없이 하려면:
```
gcc -O2 -std=gnu11 -Wall -Wextra -ffp-contract=off -c mlp_ps.c
gcc -O2 -std=gnu11 -Wall -Wextra -o ./vit_main vit_main.c vit_hw.c vit_ops.c attn_ops.c mlp_ops.c mxfp4.c mlp_ps.o -lm
gcc -O2 -std=gnu11 -Wall -Wextra -o ./vit_dbg  vit_dbg.c vit_hw.c vit_ops.c attn_ops.c mlp_ops.c mxfp4.c \
    dbg_common.c dbg_qkv.c dbg_attn.c dbg_mlp.c mlp_ps.o -lm
```
> `-ffp-contract=off` 를 빼면 aarch64 gcc 가 `ps_ln2_mx` 에 fmadd 2개를 만든다 (확인함). mock 데이터에서는 결과가 같았지만
> 규칙상 numpy 와 반올림이 달라질 수 있으므로 반드시 켠다.

PC (Windows, 보드 없이) — Vivado 동봉 MinGW gcc 9.5:
```
set PATH=C:\Xilinx\Vivado\2024.2\tps\mingw\10.0.0\win64.o\nt\bin;%PATH%
mingw32-make sim CC=gcc EXE=.exe      # vit_main_sim.exe vit_dbg_sim.exe test_mlp_ps.exe (MinGW 에는 cc 가 없음)
```

## 데이터 (golden/)

PC (mock, 형식 시험):
```
set PY=C:\Xilinx\Vitis\2024.2\tps\win64\python-3.8.3\python.exe
%PY% -m pip install --target pylib numpy==1.24.4          (한 번)
set PYTHONPATH=pylib & set PYTHONIOENCODING=utf-8
%PY% golden\run_gen_win.py golden\vit_golden_gen.py --mock --out vit_l0_mx_mock
```
`run_gen_win.py` 는 Windows numpy 의 `np.ldexp` (int64 지수 불가) 만 int32 로 바꿔 넘긴다 (지수 |e| < 300 → 결과 동일). Linux / Colab 에서는 필요 없음.

**PC (실제 모델, Windows)** — Vitis 동봉 Python 3.10 은 venv / pip 가 없어서 python.org NuGet 패키지 3.11.9 를 `C:\RTL_YJH\python311` 에 풀어 씀 (설치 / 레지스트리 / PATH 변경 없음):
```
C:\RTL_YJH\python311\python.exe -m venv C:\RTL_YJH\venv_golden
set VPY=C:\RTL_YJH\venv_golden\Scripts\python.exe
%VPY% -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
%VPY% -m pip install transformers pillow requests numpy
set PYTHONUTF8=1 & set PYTHONIOENCODING=utf-8
%VPY% golden\run_gen_win.py golden\vit_golden_gen.py --out C:\RTL_YJH\data_l0_mx
```
2026-11-11 실행 버전: Python 3.11.9, torch 2.15.0+cpu, torchvision 0.29.2+cpu, transformers 5.22.2, numpy 2.4.6, pillow 13.0.0.
> **torchvision 필수.** transformers 5.x 는 torchvision 이 없으면 `ViTImageProcessor` 대신 PIL 전처리로 바꾸고, 그러면 입력 x 가
> 달라져 attention 쪽 23개 중 19개 파일 (w, w_scale, wo, wo_scale 제외) md5 가 바뀐다. torchvision 을 넣으면 x `dddb8f19…`, w `de09914f…`,
> y_golden `f68a852a…` 로 현준 문서 4.3절 값과 같다.
> **`PYTHONUTF8=1` 필수.** 생성기가 `meta.json` 을 encoding 지정 없이 열어서, Windows 에서는 cp949 로 저장된다 (Linux / Colab 은 UTF-8).

**Colab (실제 모델, 다른 방법)**:
```
# golden/vit_golden_gen.py 업로드 후
!python vit_golden_gen.py --out vit_l0_mx         # 마지막 줄 PASS 확인
!zip -qr vit_l0_mx.zip vit_l0_mx                    # 다운로드 → 보드 ~/vit_base/data/ 에 40개 + meta.json
```
결과 확인:
1. 출력 끝이 `PASS`, `FP64 기준 계산 == HF block 0 출력 ... [ok]` (LN2 위치 / exact GELU / FC 순서 확인).
2. **기존 23개 파일이 보드의 현재 data 와 같은지** — 보드 `~/vit_base/data/meta.json` 과 새 `meta.json` 의 md5 비교:
   ```
   import json; a=json.load(open('old/meta.json'))['files']; b=json.load(open('vit_l0_mx/meta.json'))['files']
   print([n for n in a if a[n]['md5'] != b[n]['md5']])      # [] 이어야 함 (다르면 torch/transformers 버전 또는 이미지 차이)
   ```
3. `meta.json` 의 `layer_norm_eps` (HF ViT = 1e-12), `hidden_act` = `gelu`.
4. `(info) R2 vs HF block 0 출력 : cosine ...` 과 `Y2 vs 이상적 FC2` 줄을 JH 에게 보고.

## 실행 (Phase 5 순서, 보드)

기존 `~/vit_base/data`, `~/vit_base/vit_c`, `~/vit_base/vit_main` 은 건드리지 않는다. 전송 파일: `data_l0_mx.zip`, `data_l0_mx.md5`,
이 폴더의 `*.c *.h Makefile` (예: `~/vit_c_mlp_src/` 로).
```
mkdir -p ~/vit_base/data_l0 && cd ~/vit_base/data_l0
unzip -o ~/data_l0_mx.zip                  # 41개 (unzip 없으면: python3 -m zipfile -e ~/data_l0_mx.zip .)
md5sum -c ~/data_l0_mx.md5                 # 40개 OK
mkdir -p ~/vit_base/vit_c_mlp && cp ~/vit_c_mlp_src/*.c ~/vit_c_mlp_src/*.h ~/vit_c_mlp_src/Makefile ~/vit_base/vit_c_mlp/
cd ~/vit_base/vit_c_mlp && make OUT=.      # ./vit_main ./vit_dbg 를 이 폴더에 만든다

sudo ./vit_dbg  --data ~/vit_base/data_l0 --op mlp --tile 0
sudo ./vit_dbg  --data ~/vit_base/data_l0 --op mlp --tile 47
sudo ./vit_dbg  --data ~/vit_base/data_l0 --op fc2 --n 0
sudo ./vit_main --data ~/vit_base/data_l0 --mlp --tiles 3      # 빠른 확인 (FC2 생략)
sudo ./vit_main --data ~/vit_base/data_l0 --mlp                # layer 0 전체
sudo ./vit_main --data ~/vit_base/data_l0                      # (참고) --mlp 없이 = 현준 결과와 같은지
```

예상 결과 (x86 모델, mock 데이터와 같은 개수여야 함):

| 실행 | C1 | C2 | C3 | C4 | C5 | C6 | L2 명령 / BB / CDMA |
|---|---|---|---|---|---|---|---|
| `--op mlp --tile J` | 2 | 9 | 8 | 17 | 4 | 4 | 32 / 12 / 3 |
| `--op fc2 --n N` | 8 | 32 | 16 | 32 | 2 | 2 | 88 / 18 / 12 |

| 실행 | 출력 검사 | L2 명령 | BB 호출 | CDMA |
|---|---|---|---|---|
| `vit_main --mlp --tiles 3` | 15 + 3 = 18 PASS | 618 | 528 | 228 |
| `vit_main --mlp` | 15 + 8 = 23 PASS | 1308 | 1080 | 511 |
| `vit_main` (`--mlp` 없음) | 15 PASS | 588 | 504 | 218 |

C3 예상값 (보드에서도 정확히 같아야 함): FC1 / FC2 호출 #0–#2 = 768 + 768 + 256 + 9 = **1801**, #3 = 60 + 768 + 20 + 9 = **857**
(현준 out proj 보드 값과 같음). GELU CYCLES2 = 4nt + 12nt + 6 = **1030** (64 토큰) / **86** (5 토큰).

시간 예상 [추론, 현준 보드 수치에서 환산]: MLP 의 Golden 주입 줄 수 113,472 (attention 108,744 와 비슷) → Golden 약 280 ms,
PS (LN2 + G→H4 + 누산 + residual 2) 약 80 ms → MLP 전체 약 370 ms, layer 전체 약 760 ms.

## 검증 범위 (고장 주입, x86 모델 `HWSIM_FAULT_CMD` / `HWSIM_FAULT_LEN`)

| 고장 | vit_dbg | vit_main |
|---|---|---|
| FC1 X2 LOAD 주소 +1 | C2 FAIL | 못 잡음 (입력 — BB 가 입력을 쓰지 않음, 현준 설계와 같음) |
| FC1 STORE 주소 +1 | C2 / C4 FAIL | **못 잡음** — GELU 가 같은 자리에 788줄을 덮어써서 흔적이 사라짐 (현준 QKᵀ → softmax 와 같은 경우) |
| GELU ch2 LOAD 길이 −1 | C2 FAIL | 못 잡음 (입력) |
| GELU ch2 STORE 주소 +1 | C4 / C6 FAIL | G, H4 검사 FAIL |
| FC2 H4 LOAD 주소 +1 | C2 FAIL | 못 잡음 (입력) |
| FC2 W2 WLOAD 길이 −1 | C2 FAIL | — |

→ 입력 쪽과 FC1 출력은 **dbg 로만** 확인된다. 보드 dbg 는 tile 0 / 47 / n 0 만 계획되어 있으므로, 나머지 tile 은 main 출력 검사로 대신한다.

## 미결 (TODO(JH))
- 11절 ③ FC2 partial 누산을 IP 가 하는지 (지금 PS f32 누산, mock 에서 이상적 FC2 와 다른 원소 39.8 %, 최대 |차| 0.031, 상대오차 0.27 %).
- 11절 ④ Nonlinear IP 의 GELU 식 (지금 exact erf, Python `math.erf`).
- 11절 ⑤ g6 사용 — MLP main 은 g6 를 쓰지 않고, MLP dbg 는 현준 dbg 와 같은 g6 scratch (`DA_SCR_*`) 를 쓴다.
- 11절 ⑥ 현준 x86 하드웨어 모델은 저장소에 없음 → `hw_sim.c` 로 대신 (위 숫자로 보드와 같은 동작 확인).
