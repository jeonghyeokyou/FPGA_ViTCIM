# JH — ViT-Base PS C 코드 (현준 `LHJ/ViT-Base_C_261110/` 기반)

작업: 유정혁 (JH). 현준 코드 (`LHJ/`, 55d6f24) 는 수정하지 않고, 복사본을 이 폴더에서 확장한다.

| 폴더 | 내용 | 상태 |
|---|---|---|
| [ViT-Base_C_mlp/](ViT-Base_C_mlp/) | layer 0 **attention + MLP** (LN2 → FC1 → GELU → FC2 → Residual 2). 지시서 `MLP_TASK.md` | **완료본 — 앞으로 수정하지 않음.** PC x86 모델 + 실제 HF 데이터 PASS, 보드 미실행 |
| [ViT-Base_C_full/](ViT-Base_C_full/) | 12 layer 전체로 확장. 지시서 `VIT_FULL_TASK.md` | 진행 중 (각 폴더 README 의 상태 표) |

어디부터 볼지: 각 폴더의 `README.md` (상태 · 빌드 · 실행 · 예상값) → `CHANGES.md` (현준 파일에서 바꾼 곳) → 지시서.

## 데이터는 git 에 없다

`.bin` 데이터, zip, Python venv, 실행 파일, 로그는 올리지 않는다 (`JH/.gitignore`). 데이터를 얻는 방법:

1. JH 가 만든 zip: `C:\RTL_YJH\data_l0_mx.zip` (layer 0, `.bin` 40개 + `meta.json`, md5 목록 `data_l0_mx.md5`) — 필요하면 JH 에게 요청.
2. 직접 생성: `ViT-Base_C_mlp/golden/vit_golden_gen.py` (HF `google/vit-base-patch16-224`).
   절차는 [ViT-Base_C_mlp/README.md](ViT-Base_C_mlp/README.md) "데이터" 절. **torchvision 을 꼭 설치**해야 현준 데이터와 같은 입력이 나온다
   (x `dddb8f19…`, w `de09914f…`, y_golden `f68a852a…`). Windows 에서는 `PYTHONUTF8=1`.

## 보드 빌드 주의

```
cd ~/vit_base/<새 폴더>      # 현준 ~/vit_base/vit_c 와 다른 폴더에 소스 복사
make OUT=.                   # 실행 파일을 이 폴더에 만든다
```
Makefile 의 기본 `OUT` 은 `..` 이라서 **그냥 `make` 하면 `~/vit_base/vit_main`, `vit_dbg` (현준 실행 파일) 를 덮어쓴다.**
데이터도 기존 `~/vit_base/data` 와 다른 폴더 (예: `~/vit_base/data_l0`) 에 풀고 `--data` 로 지정한다.

## git 규칙

- 커밋 · push 는 JH 가 요청할 때만. push 전 `git pull --rebase`, **강제 push (`--force`) 금지.**
- `LHJ/` 는 수정하지 않는다. 다른 사람 폴더 (`share2/`, `verif/` 등) 의 변경은 커밋에 섞지 않는다.
