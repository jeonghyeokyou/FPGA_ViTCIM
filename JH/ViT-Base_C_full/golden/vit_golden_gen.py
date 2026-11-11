# =============================================================================
#  vit_golden_gen.py  (MXFP4)  -  ViT-Base block 0 : attention 블록 + MLP 블록 (Encoder 1 layer) 시험 데이터
#                                  (ZCU102, share3 + ch0remap + ch2lin)
#
#  원본: LHJ/ViT-Base_C_261110/vit_golden_gen.py_261110 (55d6f24)
#  바꾼 것 (JH, 2026-11-10, MLP_TASK.md 5 / 6절): LN2 -> FC1 -> GELU -> FC2 -> Residual 2 파일 17개 추가.
#    기존 23개 파일의 계산 / 난수 순서는 그대로 (build() 는 고치지 않음, MLP 는 build_mlp() 가 r 바이트에서 시작).
#    MLP 흐름 (R = r_golden.bin, Residual 1 결과)
#      PS     : LN2(R) -> BF16 -> MXFP4 = X2                    (토큰마다 float64, i = 0..767 순서대로 합)
#      MAC BB : X2 x W1 tile j + b1 -> H (BF16, tile 48개)
#      vec BB : GELU(H) (exact erf, float64) -> G (BF16)
#      PS     : G -> MXFP4, plane k = 열 768k..768k+767 (= H4, x.bin 배치)
#      MAC BB : H4 plane k x W2 (n, k) -> partial (n, k) (BF16, bias 없음)   ※ 임시 (11절 ③)
#      PS     : Y2 = BF16( float32 누산 : b2 + p(n,0) + .. + p(n,3) )      ※ 임시 (11절 ③)
#      PS     : R2 = BF16( f32(R) + f32(Y2) ) = layer 0 출력
#  --full (JH, 2026-11-11, VIT_FULL_TASK.md 4 / 5절): 이미지 -> patch embedding -> layer 0..11 -> 마지막 LN -> head.
#    --full 이 없으면 위 동작과 byte 단위로 같다 (기존 함수는 고치지 않고 main_full() 이하를 새로 둠).
#    PS : h0 = embed(pixels) , layer l : x_l = MXFP4(LN1_l(h_l)) -> build() -> build_mlp() -> h_{l+1} = R2_l
#    PS : lnc = LN_f(h_12[CLS]) (BF16) -> logits = head(lnc) (float32) -> top-1
#
#  Colab : !python vit_golden_gen.py                (모델 카드 예시 이미지)
#          !python vit_golden_gen.py --image a.jpg
#          --mock : 모델 없이 같은 크기의 무작위 텐서로 형식만 시험
#
#  흐름 (BB 는 Golden 을 그대로 내보내므로, 각 단계의 입력 = 앞 단계의 Golden)
#    X(MXFP4) x W_QKV(MXFP4) + b -> Q,K,V (BF16)                              MAC BB
#    PS : Q,K -> MXFP4 (토큰마다 64개 = 2블록), V -> MXFP4 + 전치 (토큰 방향 블록)
#    Q_h . K_h -> S (BF16, 행 197 + 0 padding 11 = 208 열)                     MAC BB
#    softmax(S / 8) -> A (BF16, 같은 208 열, padding 0)                        vector BB
#    PS : A -> MXFP4 (행 197 + 0 padding 59 = 256 칸 = 8블록)
#    A . V -> O_h (BF16 [197 x 64])                                            MAC BB
#    PS : O_0..O_11 -> 이어 붙인 토큰 순서 (줄 12t + h) + MXFP4
#    O_concat x W_O^T + b_O -> Y (BF16, 출력 열 64개 tile 12개)                MAC BB
#    PS : residual  R = 블록 입력 + Y  -> attention 블록 출력 (BF16)
#
#  MXFP4 (OCP MX v1.0)
#    블록 = 누산 방향으로 연속한 32개. 블록마다 scale 1개 (E8M0 : 2^X, byte = X + 127)
#    원소 = FP4 E2M1 : 부호 1 + 지수 2 + 가수 1 -> 크기 {0, 0.5, 1, 1.5, 2, 3, 4, 6}
#    X = floor(log2(블록 max|v|)) - 2   (E2M1 최대 지수 2) , [-127, 127] 로 제한 , 모두 0 이면 X = -127
#    원소 = v / 2^X 를 E2M1 로 round-to-nearest-even (동률이면 가수 bit 0 쪽) , |값| > 6 은 6 (포화)
#    코드 4bit : [3] 부호 , [2:0] 크기 번호 (0:0 1:0.5 2:1 3:1.5 4:2 5:3 6:4 7:6) , -0 은 쓰지 않음
#  내적 (MAC 동작 정의)
#    블록 b 마다 : 정수 합 sum_32 (2a)(2b)  (E2M1 x 2 는 정수 0,1,2,3,4,6,8,12)
#                 x 2^(X_a + X_b - 2)   (float64)  -> 블록 순서대로 float64 누산 -> (+bias) -> float32 -> BF16 RNE
#  packing : 원소 2개 = 1 byte, 앞 원소 [3:0], 뒤 원소 [7:4] / scale 은 블록 순서대로 1 byte 씩 (*_scale.bin)
#            L2 한 줄 = 32 B = 원소 64개 = 블록 2개 -> 줄마다 scale 2 byte
#  BF16 little-endian. 아래 파일은 모두 32 B 단위로 L2 줄 순서와 같다
# =============================================================================
import argparse, hashlib, json, os, re, sys
import numpy as np

N_TOK, D, HEADS, HD = 197, 768, 12, 64
PROJ = ("Q", "K", "V")
LINE_B = 32
BLK = 32
S_STRIDE = 208                                # S, A 한 행의 저장 열 (197 + 11) = 13 줄
AV_K = 256                                    # A 한 행 / V^T 한 열의 FP4 칸 (197 + 59) = 4 줄 = 8 블록

X_BYTES      = N_TOK * D // 2                 # 75,648
W_TILE_BYTES = HD * D // 2                    # 24,576
W_HEAD_BYTES = 3 * W_TILE_BYTES               # 73,728
Y_TILE_BYTES = N_TOK * HD * 2                 # 25,216
Y_HEAD_BYTES = 3 * Y_TILE_BYTES               # 75,648
GOLD_CALL_TOK = 64

# MLP (JH)
MLP_H = 3072
FC1_TILES = MLP_H // HD                       # 48 tile (출력 열 64개)
FC2_TILES = D // HD                           # 12 tile n
FC2_K = MLP_H // D                            # 4 조각 k (입력 768 씩)

FP4_MAG = np.array([0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0])
FP4_2X  = np.array([0, 1, 2, 3, 4, 6, 8, 12], dtype=np.int64)   # 2 x 크기 (정수)


# ----------------------------------------------------------------------------- 입력 얻기
def get_tensors_hf(image_path):
    """x, h_in [197,768] / W {Q,K,V,O}: [768 out, 768 in] / b {Q,K,V,O}: [768] / ref (HF 값)"""
    import torch
    from PIL import Image
    from transformers import ViTImageProcessor, ViTForImageClassification

    mid = "google/vit-base-patch16-224"
    proc = ViTImageProcessor.from_pretrained(mid)
    model = ViTForImageClassification.from_pretrained(mid).eval()
    if image_path is None:
        import requests
        url = "http://images.cocodataset.org/val2017/000000039769.jpg"
        img = Image.open(requests.get(url, stream=True).raw).convert("RGB")
        img_name = url
    else:
        img = Image.open(image_path).convert("RGB")
        img_name = os.path.basename(image_path)

    mods = dict(model.named_modules())
    names = None
    for cand in (("query", "key", "value"), ("q_proj", "k_proj", "v_proj")):
        hits = [(n, m) for n, m in model.named_modules()
                if all(isinstance(getattr(m, c, None), torch.nn.Linear) for c in cand)]
        if hits:
            names = cand
            sa_name, sa = hits[0]
            break
    if names is None:
        raise RuntimeError("query/key/value Linear 를 찾지 못함 : 아래 모듈 이름 목록을 보내 주세요\n" + "\n".join(mods))
    m = re.match(r"^(.*?\.(?:layer|layers|blocks)\.0)(?:\.|$)", sa_name)
    if not m:
        raise RuntimeError(f"block 0 경로를 찾지 못함 : {sa_name}")
    lp = m.group(1)
    qkv_mods = [getattr(sa, n) for n in names]
    oc = [(n, mm) for n, mm in model.named_modules()
          if n.startswith(lp + ".") and isinstance(mm, torch.nn.Linear)
          and mm.in_features == D and mm.out_features == D and all(mm is not q for q in qkv_mods)]
    if len(oc) != 1:
        raise RuntimeError("output projection 후보가 1개가 아님 : " + ", ".join(n for n, _ in oc))
    o_name, o_mod = oc[0]
    lns = [(n, mm) for n, mm in model.named_modules()
           if n.startswith(lp + ".") and isinstance(mm, torch.nn.LayerNorm)]
    print(f"block 0 = {lp} : qkv {sa_name} {names}, out proj {o_name}, LayerNorm {[n for n, _ in lns]}")

    # MLP (JH) : 이름이 아니라 in/out 크기로 찾는다 (D -> 4D Linear 1개, 4D -> D Linear 1개, LN1 이 아닌 LN 1개)
    lin = [(n, mm) for n, mm in model.named_modules() if n.startswith(lp + ".") and isinstance(mm, torch.nn.Linear)]
    f1 = [(n, mm) for n, mm in lin if mm.in_features == D and mm.out_features == MLP_H]
    f2 = [(n, mm) for n, mm in lin if mm.in_features == MLP_H and mm.out_features == D]
    if len(f1) != 1 or len(f2) != 1:
        raise RuntimeError("FC1 / FC2 후보가 1개씩이 아님 : " + ", ".join(n for n, _ in f1 + f2))
    (f1_name, f1_mod), (f2_name, f2_mod) = f1[0], f2[0]
    blk = mods[lp]

    cap, hooks = {}, []
    hooks.append(blk.register_forward_hook(
        lambda mm, i, o: cap.__setitem__("blk", (o[0] if isinstance(o, (tuple, list)) else o).detach())))
    hooks.append(getattr(sa, names[0]).register_forward_hook(lambda mm, i, o: cap.__setitem__("x", i[0].detach())))
    hooks.append(o_mod.register_forward_hook(lambda mm, i, o: cap.__setitem__("ao", o.detach())))
    for n, ln in lns:
        hooks.append(ln.register_forward_hook(
            lambda mm, i, o, n=n: cap.__setitem__("ln:" + n, (i[0].detach(), o.detach()))))
    with torch.no_grad():
        logits = model(**proc(images=img, return_tensors="pt")).logits
    for hk in hooks:
        hk.remove()

    x = cap["x"][0].float().numpy()
    h_in = None
    for n, _ in lns:
        li, lo = cap["ln:" + n]
        if np.allclose(lo[0].float().numpy(), x, atol=1e-6):
            h_in = li[0].float().numpy()
            ln1 = n
    if h_in is None:
        raise RuntimeError("QKV 입력과 같은 출력을 내는 LayerNorm 을 찾지 못함")
    W = {p: getattr(sa, n).weight.detach().float().numpy() for p, n in zip(PROJ, names)}
    b = {p: getattr(sa, n).bias.detach().float().numpy() for p, n in zip(PROJ, names)}
    W["O"] = o_mod.weight.detach().float().numpy()
    b["O"] = o_mod.bias.detach().float().numpy()
    ref = {"r_hf": h_in.astype(np.float64) + cap["ao"][0].double().numpy()}
    # MLP (JH)
    ln2 = [(n, mm) for n, mm in lns if n != ln1]
    if len(ln2) != 1:
        raise RuntimeError("LN2 후보가 1개가 아님 : " + ", ".join(n for n, _ in ln2))
    ln2_name, ln2_mod = ln2[0]
    W["FC1"], b["FC1"] = f1_mod.weight.detach().float().numpy(), f1_mod.bias.detach().float().numpy()
    W["FC2"], b["FC2"] = f2_mod.weight.detach().float().numpy(), f2_mod.bias.detach().float().numpy()
    W["LN2"], b["LN2"] = ln2_mod.weight.detach().float().numpy(), ln2_mod.bias.detach().float().numpy()
    eps = float(model.config.layer_norm_eps)
    if abs(float(ln2_mod.eps) - eps) > 0:
        raise RuntimeError(f"LN2 eps {ln2_mod.eps} != config.layer_norm_eps {eps}")
    act = getattr(model.config, "hidden_act", None)
    if act != "gelu":   # TODO(JH): exact erf GELU 가 아니면 golden 의 GELU 식을 바꿔야 함 (11절 ④)
        raise RuntimeError(f"hidden_act = {act} : exact erf GELU ('gelu') 가 아님")
    ref["r2_hf"] = cap["blk"][0].double().numpy()
    top1 = model.config.id2label[int(logits.argmax(-1))]
    import transformers
    info = {"model": mid, "image": img_name, "pred_top1": top1, "module": sa_name, "out_proj": o_name,
            "ln1": ln1, "transformers": transformers.__version__, "torch": torch.__version__,
            "fc1": f1_name, "fc2": f2_name, "ln2": ln2_name, "layer_norm_eps": eps, "hidden_act": act}
    return x, h_in, W, b, ref, info


def get_tensors_mock(seed=0):
    rng = np.random.default_rng(seed)
    x = rng.standard_normal((N_TOK, D)).astype(np.float32)
    W = {p: (rng.standard_normal((D, D)) * 0.05).astype(np.float32) for p in PROJ}
    b = {p: (rng.standard_normal(D) * 0.1).astype(np.float32) for p in PROJ}
    r2 = np.random.default_rng(seed + 1)
    h_in = r2.standard_normal((N_TOK, D)).astype(np.float32)
    W["O"] = (r2.standard_normal((D, D)) * 0.05).astype(np.float32)
    b["O"] = (r2.standard_normal(D) * 0.1).astype(np.float32)
    # MLP (JH) : 기존 난수 순서를 바꾸지 않도록 별도 generator
    r3 = np.random.default_rng(seed + 2)
    W["LN2"] = (1.0 + r3.standard_normal(D) * 0.1).astype(np.float32)
    b["LN2"] = (r3.standard_normal(D) * 0.1).astype(np.float32)
    W["FC1"] = (r3.standard_normal((MLP_H, D)) * 0.05).astype(np.float32)
    b["FC1"] = (r3.standard_normal(MLP_H) * 0.1).astype(np.float32)
    W["FC2"] = (r3.standard_normal((D, MLP_H)) * 0.025).astype(np.float32)
    b["FC2"] = (r3.standard_normal(D) * 0.1).astype(np.float32)
    return x, h_in, W, b, {}, {"model": "MOCK (random)", "image": None, "pred_top1": None,
                               "layer_norm_eps": 1e-12, "hidden_act": "gelu"}


# ----------------------------------------------------------------------------- BF16
def bf16_bits(f32):
    f = np.ascontiguousarray(f32, dtype=np.float32)
    if not np.isfinite(f).all():
        raise ValueError("non-finite value in BF16 conversion")
    u = f.view(np.uint32).astype(np.uint64)
    return ((u + 0x7FFF + ((u >> 16) & 1)) >> 16).astype(np.uint16)


def bf16_to_f32(bits):
    return (np.asarray(bits, dtype=np.uint16).astype(np.uint32) << 16).view(np.float32)


def softmax_bf16(s_bits):
    """S (BF16 [197,197]) -> softmax(S/8) -> BF16. float64 로 계산 후 float32 -> BF16"""
    z = bf16_to_f32(s_bits).astype(np.float64) / 8.0
    z -= z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return bf16_bits((e / e.sum(axis=1, keepdims=True)).astype(np.float32))


# ----------------------------------------------------------------------------- MXFP4
def fp4_encode(v):
    """float64 (이미 2^X 로 나눈 값) -> E2M1 코드 0..15. RNE, 포화, -0 없음"""
    m = np.abs(v)
    c = np.select([m <= 0.25, m < 0.75, m <= 1.25, m < 1.75, m <= 2.5, m < 3.5, m <= 5.0],
                  [0, 1, 2, 3, 4, 5, 6], default=7).astype(np.int64)
    c = np.where((v < 0) & (c != 0), c | 8, c)
    return c.astype(np.uint8)


def fp4_value2(c):
    """코드 -> 2 x 값 (정수)"""
    c = np.asarray(c, dtype=np.int64)
    return np.where(c & 8, -FP4_2X[c & 7], FP4_2X[c & 7])


def mx_quant(v):
    """v [..., n] (n = 32 의 배수), 마지막 축을 32개씩 블록 -> (코드 [..., n] uint8, X [..., n/32] int)"""
    v = np.asarray(v, dtype=np.float64)
    if not np.isfinite(v).all():
        raise ValueError("non-finite value in MXFP4 quantization")
    b = v.reshape(*v.shape[:-1], -1, BLK)
    amax = np.abs(b).max(-1)
    with np.errstate(divide="ignore"):
        X = np.where(amax > 0, np.floor(np.log2(np.where(amax > 0, amax, 1.0))) - 2, -127)
    X = np.clip(X, -127, 127).astype(np.int64)
    codes = fp4_encode(np.ldexp(b, -X[..., None]))
    return codes.reshape(v.shape), X


def mx_dot(ca, Xa, cb, Xb):
    """ca [M, n] / Xa [M, n/32] , cb [N, n] / Xb [N, n/32] -> [M, N] float64 (블록 순서대로 누산)"""
    M, n = ca.shape
    N = cb.shape[0]
    nb = n // BLK
    ia = fp4_value2(ca).reshape(M, nb, BLK)
    ib = fp4_value2(cb).reshape(N, nb, BLK)
    acc = np.zeros((M, N), dtype=np.float64)
    for k in range(nb):
        blk = ia[:, k, :] @ ib[:, k, :].T                              # 정수
        acc += np.ldexp(blk.astype(np.float64), (Xa[:, k][:, None] + Xb[:, k][None, :] - 2))
    return acc


def pack4(c):
    c = (np.asarray(c).reshape(-1).astype(np.uint8) & 0xF)
    assert c.size % 2 == 0
    return (c[0::2] | (c[1::2] << 4)).astype(np.uint8).tobytes()


def unpack4(buf):
    a = np.frombuffer(buf, dtype=np.uint8)
    out = np.empty(a.size * 2, dtype=np.uint8)
    out[0::2], out[1::2] = a & 0xF, a >> 4
    return out


def e8m0(X):
    return (np.asarray(X, dtype=np.int64).reshape(-1) + 127).astype(np.uint8).tobytes()


def mx_of_bf16(bits):
    """PS 규칙 : BF16 -> float64 -> MXFP4 (마지막 축 블록)"""
    return mx_quant(bf16_to_f32(bits).astype(np.float64))


# ----------------------------------------------------------------------------- 생성
def build(x, h_in, W, b):
    out, ex = {}, {}
    # ---- QKV
    cx, Xx = mx_quant(x)                                               # [197,768] / [197,24]
    Wall = np.concatenate([W[p] for p in PROJ], 0)                     # [2304, 768]
    ball = np.concatenate([b[p] for p in PROJ], 0)
    cw, Xw = mx_quant(Wall)                                            # [2304,768] / [2304,24]
    yb = bf16_bits((mx_dot(cx, Xx, cw, Xw) + ball.astype(np.float64)[None, :]).astype(np.float32))
    out["x"], out["x_scale"] = pack4(cx), e8m0(Xx)
    wp, ws, yp = [], [], []
    for h in range(HEADS):
        for pi in range(3):
            rows = slice(pi * D + h * HD, pi * D + (h + 1) * HD)
            wp.append(pack4(cw[rows])); ws.append(e8m0(Xw[rows]))
            yp.append(np.ascontiguousarray(yb[:, rows]).astype("<u2").tobytes())
    out["w"], out["w_scale"], out["y"] = b"".join(wp), b"".join(ws), b"".join(yp)
    ex.update(cx=cx, Xx=Xx, cw=cw, Xw=Xw, yb=yb)
    # ---- attention (head 마다)
    keys = ("q", "q_scale", "k", "k_scale", "vt", "vt_scale", "s", "a", "a4", "a4_scale", "o")
    parts = {k: [] for k in keys}
    o_heads = []
    for h in range(HEADS):
        Qb, Kb, Vb = (np.ascontiguousarray(yb[:, pi * D + h * HD: pi * D + (h + 1) * HD]) for pi in range(3))
        cq, Xq = mx_of_bf16(Qb)                                        # 토큰마다 2블록
        ck, Xk = mx_of_bf16(Kb)
        vt_v = np.zeros((HD, AV_K)); vt_v[:, :N_TOK] = bf16_to_f32(Vb).astype(np.float64).T
        cvt, Xvt = mx_quant(vt_v)                                      # 출력 열 d 마다 토큰 256칸 = 8블록
        S = bf16_bits(mx_dot(cq, Xq, ck, Xk).astype(np.float32))       # [197,197]
        A = softmax_bf16(S)
        a_v = np.zeros((N_TOK, AV_K)); a_v[:, :N_TOK] = bf16_to_f32(A).astype(np.float64)
        ca, Xa = mx_quant(a_v)                                         # 행마다 8블록
        O = bf16_bits(mx_dot(ca, Xa, cvt, Xvt).astype(np.float32))     # [197,64]
        o_heads.append(O)
        pad = lambda mm: np.pad(mm, ((0, 0), (0, S_STRIDE - N_TOK))).astype("<u2").tobytes()
        for k, v in (("q", pack4(cq)), ("q_scale", e8m0(Xq)), ("k", pack4(ck)), ("k_scale", e8m0(Xk)),
                     ("vt", pack4(cvt)), ("vt_scale", e8m0(Xvt)), ("s", pad(S)), ("a", pad(A)),
                     ("a4", pack4(ca)), ("a4_scale", e8m0(Xa)), ("o", O.astype("<u2").tobytes())):
            parts[k].append(v)
    out.update({k: b"".join(v) for k, v in parts.items()})
    # ---- concat + out proj
    ocat = np.concatenate(o_heads, axis=1)                             # BF16 [197,768] , 줄 12t+h
    coc, Xoc = mx_of_bf16(ocat)
    cwo, Xwo = mx_quant(W["O"])                                        # [768 out, 768 in]
    Y = bf16_bits((mx_dot(coc, Xoc, cwo, Xwo) + b["O"].astype(np.float64)[None, :]).astype(np.float32))
    hb = bf16_bits(h_in.astype(np.float32))
    R = bf16_bits(bf16_to_f32(hb) + bf16_to_f32(Y))
    out["oc"], out["oc_scale"] = pack4(coc), e8m0(Xoc)
    out["wo"] = b"".join(pack4(cwo[j * HD:(j + 1) * HD]) for j in range(HEADS))
    out["wo_scale"] = b"".join(e8m0(Xwo[j * HD:(j + 1) * HD]) for j in range(HEADS))
    out["yo"] = b"".join(np.ascontiguousarray(Y[:, j * HD:(j + 1) * HD]).astype("<u2").tobytes() for j in range(HEADS))
    out["h_in"], out["r"] = hb.astype("<u2").tobytes(), R.astype("<u2").tobytes()
    return out, ex


# ----------------------------------------------------------------------------- MLP (JH)
def ln2_bf16(r_bits, gamma, beta, eps):
    """LN2 (5절) : 토큰마다 float64, 합은 i = 0..767 순서대로 (numpy sum 의 pairwise 합을 쓰지 않음),
    y = ((x - mean) / sqrt(var + eps)) * g + b (float64) -> float32 -> BF16 RNE.  C ps_ln2_mx 와 같은 식"""
    x = bf16_to_f32(r_bits).astype(np.float64)                         # [197,768]
    s = np.zeros(x.shape[0])
    for i in range(x.shape[1]):
        s = s + x[:, i]
    mean = s / x.shape[1]
    d = x - mean[:, None]
    q = np.zeros(x.shape[0])
    for i in range(x.shape[1]):
        q = q + d[:, i] * d[:, i]
    var = q / x.shape[1]
    sd = np.sqrt(var + eps)
    y = (d / sd[:, None]) * gamma.astype(np.float64)[None, :] + beta.astype(np.float64)[None, :]
    return bf16_bits(y.astype(np.float32))


def gelu_bf16(h_bits):
    """GELU (5절) : h = float64(BF16), 0.5 h (1 + erf(h / sqrt 2)) (float64, math.erf) -> float32 -> BF16.
    BF16 값은 65,536 가지뿐이므로 서로 다른 값마다 한 번씩 계산"""
    import math
    u, inv = np.unique(np.asarray(h_bits, dtype=np.uint16), return_inverse=True)
    hv = bf16_to_f32(u).astype(np.float64)
    g = np.array([0.5 * v * (1.0 + math.erf(v / math.sqrt(2.0))) for v in hv.tolist()], dtype=np.float64)
    return bf16_bits(g.astype(np.float32))[inv].reshape(np.shape(h_bits))


def fc2_acc_bf16(parts, b2):
    """partial 누산 (5절, 임시) : acc = float32(b2) ; k 순서대로 acc += f32(partial_k) (float32) -> BF16"""
    acc = np.broadcast_to(b2.astype(np.float32), parts[0].shape).copy()
    for p in parts:
        acc = (acc + bf16_to_f32(p)).astype(np.float32)
    return bf16_bits(acc)


def build_mlp(r_bytes, W, b, eps):
    """R (r_golden.bin 바이트) -> MLP 파일들. 각 단계의 입력 = 앞 단계의 Golden (BB 는 Golden 을 그대로 냄)"""
    out, ex = {}, {}
    R = np.frombuffer(r_bytes, dtype="<u2").reshape(N_TOK, D)
    # ---- LN2 (PS) -> X2 MXFP4
    x2b = ln2_bf16(R, W["LN2"], b["LN2"], eps)
    cx2, Xx2 = mx_of_bf16(x2b)
    out["ln2_w"], out["ln2_b"] = W["LN2"].astype("<f4").tobytes(), b["LN2"].astype("<f4").tobytes()
    out["x2"], out["x2_scale"] = pack4(cx2), e8m0(Xx2)
    # ---- FC1 (MAC BB) : 48 tile, W 패킹은 wo.bin 과 같음
    cw1, Xw1 = mx_quant(W["FC1"])                                      # [3072 out, 768 in]
    H = bf16_bits((mx_dot(cx2, Xx2, cw1, Xw1) + b["FC1"].astype(np.float64)[None, :]).astype(np.float32))
    tiles = lambda M, n: b"".join(np.ascontiguousarray(M[:, j * HD:(j + 1) * HD]).astype("<u2").tobytes() for j in range(n))
    out["w1"] = b"".join(pack4(cw1[j * HD:(j + 1) * HD]) for j in range(FC1_TILES))
    out["w1_scale"] = b"".join(e8m0(Xw1[j * HD:(j + 1) * HD]) for j in range(FC1_TILES))
    out["b1"] = b["FC1"].astype("<f4").tobytes()
    out["h"] = tiles(H, FC1_TILES)
    # ---- GELU (vector BB)
    G = gelu_bf16(H)
    out["g"] = tiles(G, FC1_TILES)
    # ---- G -> MXFP4 (PS), plane k = 열 768k..
    cg, Xg = mx_of_bf16(G)                                             # [197,3072] / [197,96]
    out["h4"] = b"".join(pack4(cg[:, k * D:(k + 1) * D]) for k in range(FC2_K))
    out["h4_scale"] = b"".join(e8m0(Xg[:, k * 24:(k + 1) * 24]) for k in range(FC2_K))
    # ---- FC2 (MAC BB) : tile i = 4n + k , partial 은 bias 없음
    cw2, Xw2 = mx_quant(W["FC2"])                                      # [768 out, 3072 in]
    wp, ws, pp, Y2 = [], [], [], np.zeros((N_TOK, D), dtype=np.uint16)
    for n in range(FC2_TILES):
        rows, parts = slice(n * HD, (n + 1) * HD), []
        for k in range(FC2_K):
            cols, sc = slice(k * D, (k + 1) * D), slice(k * 24, (k + 1) * 24)
            wp.append(pack4(cw2[rows, cols])); ws.append(e8m0(Xw2[rows, sc]))
            P = bf16_bits(mx_dot(cg[:, cols], Xg[:, sc], cw2[rows, cols], Xw2[rows, sc]).astype(np.float32))
            parts.append(P); pp.append(P.astype("<u2").tobytes())
        Y2[:, rows] = fc2_acc_bf16(parts, b["FC2"][rows])
    out["w2"], out["w2_scale"], out["b2"] = b"".join(wp), b"".join(ws), b["FC2"].astype("<f4").tobytes()
    out["p"], out["y2"] = b"".join(pp), tiles(Y2, FC2_TILES)
    # ---- Residual 2 (PS)
    R2 = bf16_bits(bf16_to_f32(R) + bf16_to_f32(Y2))
    out["r2"] = R2.astype("<u2").tobytes()
    ex.update(cg=cg, Xg=Xg, cw2=cw2, Xw2=Xw2, Y2=Y2, R2=R2)
    return out, ex


# ----------------------------------------------------------------------------- 파일 목록
FILES = [  # (파일, key, 크기, 설명)
    ("x.bin", "x", X_BYTES, "X MXFP4 코드, token t : 줄 12t+k (k = 채널 64k..)"),
    ("x_scale.bin", "x_scale", N_TOK * 24, "X E8M0, token*24 + 블록"),
    ("w.bin", "w", HEADS * W_HEAD_BYTES, "W_QKV MXFP4, h*73728 + P*24576, 출력 열마다 768 입력 (12줄)"),
    ("w_scale.bin", "w_scale", HEADS * 3 * HD * 24, "W_QKV E8M0, (h*3+P)*1536 + col*24 + 블록"),
    ("y_golden.bin", "y", HEADS * Y_HEAD_BYTES, "Q,K,V BF16, h*75648 + P*25216 + token*128"),
    ("q_fp4.bin", "q", HEADS * N_TOK * HD // 2, "Q MXFP4, h*6304 + token*32"),
    ("q_scale.bin", "q_scale", HEADS * N_TOK * 2, "Q E8M0, h*394 + token*2 + 블록"),
    ("k_fp4.bin", "k", HEADS * N_TOK * HD // 2, "K MXFP4 (토큰 순서, 전치 없음)"),
    ("k_scale.bin", "k_scale", HEADS * N_TOK * 2, "K E8M0"),
    ("vt_fp4.bin", "vt", HEADS * HD * AV_K // 2, "V^T MXFP4, h*8192 + d*128 (토큰 197 + 0 59)"),
    ("vt_scale.bin", "vt_scale", HEADS * HD * 8, "V^T E8M0, h*512 + d*8 + 블록"),
    ("s_golden.bin", "s", HEADS * N_TOK * S_STRIDE * 2, "S BF16, h*81952 + row*416"),
    ("a_golden.bin", "a", HEADS * N_TOK * S_STRIDE * 2, "A BF16, 같은 배치"),
    ("a_fp4.bin", "a4", HEADS * N_TOK * AV_K // 2, "A MXFP4, h*25216 + row*128 (197 + 0 59)"),
    ("a_scale.bin", "a4_scale", HEADS * N_TOK * 8, "A E8M0, h*1576 + row*8 + 블록"),
    ("o_golden.bin", "o", HEADS * N_TOK * HD * 2, "O BF16, h*25216 + token*128"),
    ("oc_fp4.bin", "oc", X_BYTES, "O concat MXFP4, x.bin 과 같은 배치 (줄 12t+h)"),
    ("oc_scale.bin", "oc_scale", N_TOK * 24, "O concat E8M0, token*24 + 블록"),
    ("wo.bin", "wo", HEADS * HD * D // 2, "W_O MXFP4, tile j*24576 (출력 열 64j.. x 768 입력)"),
    ("wo_scale.bin", "wo_scale", D * 24, "W_O E8M0, j*1536 + col*24 + 블록"),
    ("yo_golden.bin", "yo", HEADS * N_TOK * HD * 2, "Y BF16, tile j*25216 + token*128"),
    ("h_in.bin", "h_in", N_TOK * D * 2, "블록 입력 (LN1 입력) BF16, token*1536"),
    ("r_golden.bin", "r", N_TOK * D * 2, "R = h_in + Y BF16, token*1536"),
]
N_FILES_ATTN = len(FILES)                     # 23 : 원본 생성기와 byte 단위로 같아야 하는 파일
FILES += [  # MLP (JH, MLP_TASK.md 6절)
    ("ln2_w.bin", "ln2_w", D * 4, "LN2 gamma float32 LE (layernorm_after)"),
    ("ln2_b.bin", "ln2_b", D * 4, "LN2 beta float32 LE"),
    ("x2_fp4.bin", "x2", X_BYTES, "X2 = LN2(R) MXFP4, x.bin 과 같은 배치"),
    ("x2_scale.bin", "x2_scale", N_TOK * 24, "X2 E8M0, token*24 + 블록"),
    ("w1.bin", "w1", FC1_TILES * W_TILE_BYTES, "W1 MXFP4, tile j*24576 (출력 열 64j.. x 768 입력), wo.bin 과 같은 packing"),
    ("w1_scale.bin", "w1_scale", MLP_H * 24, "W1 E8M0, j*1536 + col*24 + 블록"),
    ("b1.bin", "b1", MLP_H * 4, "FC1 bias float32 LE"),
    ("h_golden.bin", "h", FC1_TILES * Y_TILE_BYTES, "H = FC1 BF16, tile j*25216 + token*128"),
    ("g_golden.bin", "g", FC1_TILES * Y_TILE_BYTES, "G = GELU(H) BF16, 같은 배치"),
    ("h4_fp4.bin", "h4", FC2_K * X_BYTES, "G MXFP4 plane k*75648 (열 768k..), plane 안은 x.bin 배치 (줄 12t + j%12)"),
    ("h4_scale.bin", "h4_scale", FC2_K * N_TOK * 24, "H4 E8M0, k*4728 + token*24 + 블록"),
    ("w2.bin", "w2", FC2_TILES * FC2_K * W_TILE_BYTES, "W2 MXFP4, tile i=4n+k : i*24576 (출력 열 64n.. x 입력 768k..)"),
    ("w2_scale.bin", "w2_scale", D * (MLP_H // BLK), "W2 E8M0, i*1536 + col*24 + 블록 (조각 k 의 24 블록)"),
    ("b2.bin", "b2", D * 4, "FC2 bias float32 LE (PS 누산에 사용)"),
    ("p_golden.bin", "p", FC2_TILES * FC2_K * Y_TILE_BYTES, "FC2 partial (n,k) BF16 (bias 없음), i=4n+k : i*25216 + token*128"),
    ("y2_golden.bin", "y2", FC2_TILES * Y_TILE_BYTES, "Y2 = BF16(f32 누산 b2 + p(n,0..3)), tile n*25216 + token*128"),
    ("r2_golden.bin", "r2", N_TOK * D * 2, "R2 = R + Y2 BF16 = layer 0 출력, token*1536"),
]


def md5(b): return hashlib.md5(b).hexdigest()


def ref_fp(x, h_in, W, b):
    x, h_in = x.astype(np.float64), h_in.astype(np.float64)
    q, k, v = (x @ W[p].astype(np.float64).T + b[p] for p in PROJ)
    o = []
    for h in range(HEADS):
        c = slice(h * HD, (h + 1) * HD)
        s = q[:, c] @ k[:, c].T / 8.0
        e = np.exp(s - s.max(1, keepdims=True))
        o.append((e / e.sum(1, keepdims=True)) @ v[:, c])
    y = np.concatenate(o, 1) @ W["O"].astype(np.float64).T + b["O"]
    return dict(Q=q, K=k, V=v, Y=y, R=h_in + y)


# ----------------------------------------------------------------------------- 검증 (파일만 읽어서, 다른 경로로)
def fp4_value_ref(c):
    """코드 -> 실수 (비트 정의대로 직접 계산 : 부호 / 지수 2b / 가수 1b, bias 1)"""
    c = np.asarray(c, dtype=np.int64)
    s, e, mnt = (c >> 3) & 1, (c >> 1) & 3, c & 1
    mag = np.where(e == 0, mnt * 0.5, (1 + mnt * 0.5) * 2.0 ** (e - 1))
    return np.where(s == 1, -mag, mag)


def dot_ref(ca, sa, cb, sb):
    """다른 경로 : 원소 실수값 x 2^X 로 풀어서 블록마다 float64 내적 후 블록 순서대로 합"""
    va = fp4_value_ref(ca).reshape(ca.shape[0], -1, BLK) * np.ldexp(1.0, sa.astype(np.int64) - 127)[..., None]
    vb = fp4_value_ref(cb).reshape(cb.shape[0], -1, BLK) * np.ldexp(1.0, sb.astype(np.int64) - 127)[..., None]
    acc = np.zeros((ca.shape[0], cb.shape[0]))
    for k in range(va.shape[1]):
        acc += va[:, k, :] @ vb[:, k, :].T
    return acc


def verify(out_dir, fp, hf_ref, b):
    rd = lambda n: open(os.path.join(out_dir, n), "rb").read()
    u8 = lambda n: np.frombuffer(rd(n), dtype=np.uint8)
    bf = lambda n, *s: np.frombuffer(rd(n), dtype="<u2").reshape(*s)
    ok = True

    def chk(name, cond, msg=""):
        nonlocal ok
        print(f"  [{'ok' if cond else 'FAIL'}] {name} {msg}")
        ok &= bool(cond)

    for n, _, sz, _ in FILES:
        chk(f"{n} size", len(rd(n)) == sz, f"{len(rd(n))}")

    # (0) MXFP4 규칙 자체 : 동률 / 포화 / 0 / 부호
    t = np.array([0.25, 0.75, 1.25, 1.75, 2.5, 3.5, 5.0, 5.01, 7.9, -0.25, -0.3, -6.5, 0.0])
    e = np.array([0, 2, 2, 4, 4, 6, 6, 7, 7, 0, 9, 15, 0])
    chk("E2M1 동률(가수 0 쪽) / 포화 / -0 없음", np.array_equal(fp4_encode(t), e), f"{fp4_encode(t).tolist()}")
    chk("E2M1 표 = 비트 정의", np.array_equal(fp4_value2(np.arange(16)) / 2.0, fp4_value_ref(np.arange(16))))

    # (1) QKV
    cx = unpack4(rd("x.bin")).reshape(N_TOK, D); sx = u8("x_scale.bin").reshape(N_TOK, 24)
    cw = unpack4(rd("w.bin")).reshape(HEADS, 3, HD, D); sw = u8("w_scale.bin").reshape(HEADS, 3, HD, 24)
    y = bf("y_golden.bin", HEADS, 3, N_TOK, HD)
    bad = 0
    for h in range(HEADS):
        for pi, p in enumerate(PROJ):
            yy = bf16_bits((dot_ref(cx, sx, cw[h, pi], sw[h, pi]) + b[p][h * HD:(h + 1) * HD].astype(np.float64)).astype(np.float32))
            bad += int(not np.array_equal(yy, y[h, pi]))
    chk("QKV : 파일 -> 재계산 (36 tile)", bad == 0, f"mismatch {bad}")
    sizes = [min(GOLD_CALL_TOK, N_TOK - GOLD_CALL_TOK * k) * HD * 2 for k in range(4)]
    chk("BB 호출 4번 크기", sizes == [8192, 8192, 8192, 640], f"{sizes}")
    # scale 규칙 : 블록 max 가 [4, 8) x 2^X 에 들어감 (0 블록 제외)
    vx = fp4_value_ref(cx).reshape(N_TOK, 24, BLK)
    mx = np.abs(vx).max(-1)
    chk("X 블록 max 원소 = 4 또는 6 (0 블록 제외)", np.all((mx == 0) | (mx >= 4)), "")

    # (2) attention
    q = unpack4(rd("q_fp4.bin")).reshape(HEADS, N_TOK, HD); qs = u8("q_scale.bin").reshape(HEADS, N_TOK, 2)
    k = unpack4(rd("k_fp4.bin")).reshape(HEADS, N_TOK, HD); ks = u8("k_scale.bin").reshape(HEADS, N_TOK, 2)
    vt = unpack4(rd("vt_fp4.bin")).reshape(HEADS, HD, AV_K); vs = u8("vt_scale.bin").reshape(HEADS, HD, 8)
    S = bf("s_golden.bin", HEADS, N_TOK, S_STRIDE); A = bf("a_golden.bin", HEADS, N_TOK, S_STRIDE)
    a4 = unpack4(rd("a_fp4.bin")).reshape(HEADS, N_TOK, AV_K); a4s = u8("a_scale.bin").reshape(HEADS, N_TOK, 8)
    O = bf("o_golden.bin", HEADS, N_TOK, HD)
    e = dict.fromkeys(["q", "k", "vt", "s", "spad", "a", "apad", "a4", "a4pad", "o"], 0)
    for h in range(HEADS):
        for nm, pi, cc, ss in (("q", 0, q[h], qs[h]), ("k", 1, k[h], ks[h])):
            c2, X2 = mx_of_bf16(y[h, pi])
            e[nm] += int(not (np.array_equal(c2, cc) and np.array_equal(X2 + 127, ss)))
        vv = np.zeros((HD, AV_K)); vv[:, :N_TOK] = bf16_to_f32(y[h, 2]).astype(np.float64).T
        c2, X2 = mx_quant(vv)
        e["vt"] += int(not (np.array_equal(c2, vt[h]) and np.array_equal(X2 + 127, vs[h])))
        e["s"] += int(not np.array_equal(bf16_bits(dot_ref(q[h], qs[h], k[h], ks[h]).astype(np.float32)), S[h][:, :N_TOK]))
        e["spad"] += int(np.any(S[h][:, N_TOK:]))
        e["a"] += int(not np.array_equal(softmax_bf16(S[h][:, :N_TOK]), A[h][:, :N_TOK]))
        e["apad"] += int(np.any(A[h][:, N_TOK:]))
        av = np.zeros((N_TOK, AV_K)); av[:, :N_TOK] = bf16_to_f32(A[h][:, :N_TOK]).astype(np.float64)
        c2, X2 = mx_quant(av)
        e["a4"] += int(not (np.array_equal(c2, a4[h]) and np.array_equal(X2 + 127, a4s[h])))
        e["a4pad"] += int(np.any(a4[h][:, N_TOK:]))
        e["o"] += int(not np.array_equal(bf16_bits(dot_ref(a4[h], a4s[h], vt[h], vs[h]).astype(np.float32)), O[h]))
    for kk, v in e.items():
        chk(f"{kk:6s} (12 head)", v == 0, f"mismatch heads {v}")
    rs = max(float(np.abs(bf16_to_f32(A[h][:, :N_TOK]).astype(np.float64).sum(1) - 1).max()) for h in range(HEADS))
    chk("A 행 합 = 1 (BF16 반올림 이내)", rs < 2e-2, f"max |sum-1| {rs:.2e}")
    a4v = np.abs(fp4_value_ref(a4[:, :, :N_TOK]))
    z = float((a4v == 0).mean())
    print(f"  (info) A MXFP4 에서 0 이 된 비율 {z:.1%}")

    # (3) concat + out proj + residual
    oc = unpack4(rd("oc_fp4.bin")).reshape(N_TOK, D); ocs = u8("oc_scale.bin").reshape(N_TOK, 24)
    ocat = np.concatenate([O[h] for h in range(HEADS)], axis=1)
    c2, X2 = mx_of_bf16(ocat)
    chk("O concat MXFP4 (줄 12t+h = head h 토큰 t)", np.array_equal(c2, oc) and np.array_equal(X2 + 127, ocs))
    wo = unpack4(rd("wo.bin")).reshape(D, D); wos = u8("wo_scale.bin").reshape(D, 24)
    yo = bf("yo_golden.bin", HEADS, N_TOK, HD)
    Yt = np.concatenate([yo[j] for j in range(HEADS)], axis=1)
    yy = bf16_bits((dot_ref(oc, ocs, wo, wos) + b["O"].astype(np.float64)[None, :]).astype(np.float32))
    chk("Y (out proj, 12 tile)", np.array_equal(yy, Yt))
    hb = bf("h_in.bin", N_TOK, D); rg = bf("r_golden.bin", N_TOK, D)
    chk("R = h_in + Y (float32 -> BF16)", np.array_equal(bf16_bits(bf16_to_f32(hb) + bf16_to_f32(Yt)), rg))

    # (4) 참고 : FP32 원본 대비
    rel = lambda a_, b_: np.linalg.norm(a_ - b_) / max(np.linalg.norm(b_), 1e-12)
    for pi, p in enumerate(PROJ):
        yf = np.concatenate([bf16_to_f32(y[h, pi]) for h in range(HEADS)], 1).astype(np.float64)
        print(f"  (info) {p}: FP32 대비 상대오차 {rel(yf, fp[p]):.3%}")
    print(f"  (info) Y (attention 출력): FP32 대비 상대오차 {rel(bf16_to_f32(Yt).astype(np.float64), fp['Y']):.3%}")
    print(f"  (info) R (블록 출력): FP32 대비 상대오차 {rel(bf16_to_f32(rg).astype(np.float64), fp['R']):.3%}")
    if hf_ref:
        d = rel(fp["R"], hf_ref["r_hf"])
        chk("FP32 기준 계산 == HF attention 블록 출력 (head 분할 / concat 순서 확인)", d < 1e-5, f"상대오차 {d:.2e}")
    return ok


# ----------------------------------------------------------------------------- MLP 기준 / 검증 (JH)
def ref_fp_mlp(r, W, b, eps):
    """float64 기준 (양자화 없음) : R -> LN2 -> FC1 -> exact GELU -> FC2 -> + R"""
    import math
    r = np.asarray(r, dtype=np.float64)
    mu = r.mean(1, keepdims=True)
    x2 = (r - mu) / np.sqrt(((r - mu) ** 2).mean(1, keepdims=True) + eps) * W["LN2"] + b["LN2"]
    h = x2 @ W["FC1"].astype(np.float64).T + b["FC1"]
    g = 0.5 * h * (1.0 + np.vectorize(math.erf)(h / math.sqrt(2.0)))
    y2 = g @ W["FC2"].astype(np.float64).T + b["FC2"]
    return dict(Y2=y2, R2=r + y2)


def verify_mlp(out_dir, fp, fp_mlp, hf_ref, W, b, eps):
    import math
    rd = lambda n: open(os.path.join(out_dir, n), "rb").read()
    u8 = lambda n: np.frombuffer(rd(n), dtype=np.uint8)
    bf = lambda n, *s: np.frombuffer(rd(n), dtype="<u2").reshape(*s)
    f4 = lambda n: np.frombuffer(rd(n), dtype="<f4")
    ok = True

    def chk(name, cond, msg=""):
        nonlocal ok
        print(f"  [{'ok' if cond else 'FAIL'}] {name} {msg}")
        ok &= bool(cond)

    rg = bf("r_golden.bin", N_TOK, D)
    g_w, g_b, b1, b2 = f4("ln2_w.bin"), f4("ln2_b.bin"), f4("b1.bin"), f4("b2.bin")
    chk("ln2_w / ln2_b / b1 / b2 == 모델 값 (float32)",
        all(np.array_equal(a_, c_.astype(np.float32)) for a_, c_ in
            ((g_w, W["LN2"]), (g_b, b["LN2"]), (b1, b["FC1"]), (b2, b["FC2"]))))

    # (5) LN2 : 다른 경로 (python float 로 토큰마다 순서대로 합) -> BF16 -> MXFP4
    x2v = np.empty((N_TOK, D), dtype=np.float64)
    gl, bl = g_w.astype(np.float64).tolist(), g_b.astype(np.float64).tolist()
    for t, row in enumerate(bf16_to_f32(rg).astype(np.float64).tolist()):
        s = 0.0
        for v in row:
            s += v
        mean = s / D
        q = 0.0
        for v in row:
            q += (v - mean) * (v - mean)
        sd = math.sqrt(q / D + eps)
        x2v[t] = [((v - mean) / sd) * gg + bb for v, gg, bb in zip(row, gl, bl)]
    x2 = unpack4(rd("x2_fp4.bin")).reshape(N_TOK, D); x2s = u8("x2_scale.bin").reshape(N_TOK, 24)
    c2, X2 = mx_of_bf16(bf16_bits(x2v.astype(np.float32)))
    chk("X2 = LN2(R) MXFP4 (python float 경로)", np.array_equal(c2, x2) and np.array_equal(X2 + 127, x2s))

    # (6) FC1 -> GELU -> H4
    w1 = unpack4(rd("w1.bin")).reshape(MLP_H, D); w1s = u8("w1_scale.bin").reshape(MLP_H, 24)
    hg = bf("h_golden.bin", FC1_TILES, N_TOK, HD); gg_ = bf("g_golden.bin", FC1_TILES, N_TOK, HD)
    Ht = np.concatenate(list(hg), axis=1); Gt = np.concatenate(list(gg_), axis=1)
    hh = bf16_bits((dot_ref(x2, x2s, w1, w1s) + b1.astype(np.float64)[None, :]).astype(np.float32))
    bad = sum(int(not np.array_equal(hh[:, j * HD:(j + 1) * HD], hg[j])) for j in range(FC1_TILES))
    chk("H (FC1, 48 tile) : 파일 -> 재계산", bad == 0, f"mismatch tiles {bad}")
    chk("G = GELU(H) (48 tile)", np.array_equal(gelu_bf16(Ht), Gt))
    h4 = unpack4(rd("h4_fp4.bin")).reshape(FC2_K, N_TOK, D); h4s = u8("h4_scale.bin").reshape(FC2_K, N_TOK, 24)
    c2, X2 = mx_of_bf16(Gt)
    bad = sum(int(not (np.array_equal(c2[:, k * D:(k + 1) * D], h4[k]) and
                       np.array_equal(X2[:, k * 24:(k + 1) * 24] + 127, h4s[k]))) for k in range(FC2_K))
    chk("H4 plane 4개 (G MXFP4, 줄 12t + j%12)", bad == 0, f"mismatch planes {bad}")

    # (7) FC2 partial -> 누산 -> Residual 2
    w2 = unpack4(rd("w2.bin")).reshape(FC2_TILES, FC2_K, HD, D)
    w2s = u8("w2_scale.bin").reshape(FC2_TILES, FC2_K, HD, 24)
    p = bf("p_golden.bin", FC2_TILES, FC2_K, N_TOK, HD)
    y2 = bf("y2_golden.bin", FC2_TILES, N_TOK, HD)
    bad = 0
    for n in range(FC2_TILES):
        for k in range(FC2_K):
            pp = bf16_bits(dot_ref(h4[k], h4s[k], w2[n, k], w2s[n, k]).astype(np.float32))
            bad += int(not np.array_equal(pp, p[n, k]))
    chk("FC2 partial (48 = 12 n x 4 k)", bad == 0, f"mismatch {bad}")
    acc_bad = 0
    for n in range(FC2_TILES):
        acc = b2[n * HD:(n + 1) * HD].astype(np.float32)[None, :].repeat(N_TOK, 0)
        for k in range(FC2_K):
            acc = acc + bf16_to_f32(p[n, k])                           # float32 + float32
        acc_bad += int(not np.array_equal(bf16_bits(acc), y2[n]))
    chk("Y2 = BF16(f32 b2 + p0 + p1 + p2 + p3) (12 tile)", acc_bad == 0, f"mismatch tiles {acc_bad}")
    Y2t = np.concatenate(list(y2), axis=1)
    r2 = bf("r2_golden.bin", N_TOK, D)
    chk("R2 = R + Y2 (float32 -> BF16)", np.array_equal(bf16_bits(bf16_to_f32(rg) + bf16_to_f32(Y2t)), r2))

    # (8) 참고 : 이상적인 FC2 (입력 3072 를 한 번에 float64 누산 + bias) 와 Y2 의 차이 (판정 아님)
    h4f = np.concatenate(list(h4), axis=1); h4sf = np.concatenate(list(h4s), axis=1)
    w2f = np.concatenate([np.concatenate(list(w2[n]), axis=1) for n in range(FC2_TILES)], axis=0)
    w2sf = np.concatenate([np.concatenate(list(w2s[n]), axis=1) for n in range(FC2_TILES)], axis=0)
    yi = bf16_bits((dot_ref(h4f, h4sf, w2f, w2sf) + b2.astype(np.float64)[None, :]).astype(np.float32))
    diff = yi != Y2t
    ad = np.abs(bf16_to_f32(yi).astype(np.float64) - bf16_to_f32(Y2t).astype(np.float64))
    rel = lambda a_, b_: np.linalg.norm(a_ - b_) / max(np.linalg.norm(b_), 1e-12)
    print(f"  (info) Y2 vs 이상적 FC2 : 다른 원소 {int(diff.sum())} / {diff.size} ({diff.mean():.2%}),"
          f" 최대 |차| {ad.max():.4g}, 상대오차 {rel(bf16_to_f32(Y2t).astype(np.float64), bf16_to_f32(yi).astype(np.float64)):.3%}")
    print(f"  (info) Y2 (MLP 출력): FP64 대비 상대오차 {rel(bf16_to_f32(Y2t).astype(np.float64), fp_mlp['Y2']):.3%}")
    print(f"  (info) R2 (layer 출력): FP64 대비 상대오차 {rel(bf16_to_f32(r2).astype(np.float64), fp_mlp['R2']):.3%}")
    if hf_ref:
        d = rel(fp_mlp["R2"], hf_ref["r2_hf"])
        chk("FP64 기준 계산 == HF block 0 출력 (LN2 / GELU / FC 순서 확인)", d < 1e-5, f"상대오차 {d:.2e}")
        a_ = bf16_to_f32(r2).astype(np.float64).ravel(); b_ = hf_ref["r2_hf"].ravel()
        cos = float(a_ @ b_ / (np.linalg.norm(a_) * np.linalg.norm(b_)))
        print(f"  (info) R2 vs HF block 0 출력 : cosine {cos:.6f}, 최대 |차| {np.abs(a_ - b_).max():.4g},"
              f" 상대오차 {rel(a_, b_):.3%}")
    return ok


# ----------------------------------------------------------------------------- 12 layer (--full, JH, VIT_FULL_TASK.md)
IMG, PATCH = 224, 16
GRID = IMG // PATCH                           # 14 -> 196 패치
N_PATCH = GRID * GRID

FILES_LN1 = [
    ("ln1_w.bin", "ln1_w", D * 4, "LN1 gamma float32 LE (layernorm_before)"),
    ("ln1_b.bin", "ln1_b", D * 4, "LN1 beta float32 LE"),
]
FILES_LAYER = FILES + FILES_LN1               # lXX/ : 지금의 40개 + LN1 2개


def _layer_of(name):
    """모듈 이름 -> (layer 경로, 번호). '.layer.N' / '.layers.N' / '.blocks.N' 구조"""
    m = re.match(r"^(.*?\.(?:layer|layers|blocks)\.(\d+))(?:\.|$)", name)
    return (m.group(1), int(m.group(2))) if m else (None, None)


def get_tensors_hf_full(image_path):
    """12 layer 전부 + patch embedding / CLS / position / 마지막 LN / classifier. 이름이 아니라 크기 · 구조로 찾는다.
    HF hook (transformers 5.x 구조 기준, 4.x 도 같은 방식으로 찾힘) : embedding 출력, layer l 출력, 마지막 LN 출력, logits"""
    import torch
    import transformers
    from PIL import Image
    from transformers import ViTImageProcessor, ViTForImageClassification

    mid = "google/vit-base-patch16-224"
    proc = ViTImageProcessor.from_pretrained(mid)
    model = ViTForImageClassification.from_pretrained(mid).eval()
    if image_path is None:
        import requests
        url = "http://images.cocodataset.org/val2017/000000039769.jpg"
        img = Image.open(requests.get(url, stream=True).raw).convert("RGB")
        img_name = url
    else:
        img = Image.open(image_path).convert("RGB")
        img_name = os.path.basename(image_path)
    pv = proc(images=img, return_tensors="pt")["pixel_values"]          # [1,3,224,224] float32
    if tuple(pv.shape) != (1, 3, IMG, IMG):
        raise RuntimeError(f"pixel_values 크기 {tuple(pv.shape)}")

    named = list(model.named_modules())
    mods = dict(named)
    names, hits = None, []
    for cand in (("query", "key", "value"), ("q_proj", "k_proj", "v_proj")):
        hits = [(n, m) for n, m in named if all(isinstance(getattr(m, c, None), torch.nn.Linear) for c in cand)]
        if hits:
            names = cand
            break
    if names is None:
        raise RuntimeError("query/key/value Linear 를 찾지 못함 : 모듈 목록\n" + "\n".join(mods))
    by_l = {}
    for n, sa in hits:
        lp, li = _layer_of(n)
        if lp is None or li in by_l:
            raise RuntimeError(f"attention 모듈의 layer 구조를 알 수 없음 : {n}")
        by_l[li] = (lp, n, sa)
    NL = len(by_l)
    if sorted(by_l) != list(range(NL)):
        raise RuntimeError(f"layer 번호가 0..{NL - 1} 연속이 아님 : {sorted(by_l)}")

    per = []
    for l in range(NL):
        lp, sa_name, sa = by_l[l]
        inside = [(n, mm) for n, mm in named if n.startswith(lp + ".")]
        lin = [(n, mm) for n, mm in inside if isinstance(mm, torch.nn.Linear)]
        qkv = [getattr(sa, c) for c in names]
        oc = [(n, mm) for n, mm in lin if mm.in_features == D and mm.out_features == D and all(mm is not q for q in qkv)]
        f1 = [(n, mm) for n, mm in lin if mm.in_features == D and mm.out_features == MLP_H]
        f2 = [(n, mm) for n, mm in lin if mm.in_features == MLP_H and mm.out_features == D]
        lns = [(n, mm) for n, mm in inside if isinstance(mm, torch.nn.LayerNorm)]
        if len(oc) != 1 or len(f1) != 1 or len(f2) != 1 or len(lns) != 2:
            raise RuntimeError(f"layer {l} ({lp}) : out proj {len(oc)}, FC1 {len(f1)}, FC2 {len(f2)}, LN {len(lns)} 개")
        per.append(dict(lp=lp, sa_name=sa_name, sa=sa, qkv=qkv, o=oc[0], f1=f1[0], f2=f2[0], lns=lns, blk=mods[lp]))

    lps = [p["lp"] for p in per]
    in_layer = lambda n: any(n == lp or n.startswith(lp + ".") for lp in lps)
    outside = [(n, mm) for n, mm in named if n and not in_layer(n)]
    convs = [(n, mm) for n, mm in outside if isinstance(mm, torch.nn.Conv2d)]
    lnf = [(n, mm) for n, mm in outside if isinstance(mm, torch.nn.LayerNorm)]
    hd = [(n, mm) for n, mm in outside if isinstance(mm, torch.nn.Linear) and mm.in_features == D]
    params = [(n, p) for n, p in model.named_parameters() if not in_layer(n)]
    cls = [(n, p) for n, p in params if tuple(p.shape) == (1, 1, D)]
    pos = [(n, p) for n, p in params if tuple(p.shape) == (1, N_TOK, D)]
    if len(convs) != 1 or len(lnf) != 1 or len(hd) != 1 or len(cls) != 1 or len(pos) != 1:
        raise RuntimeError(f"layer 밖 : Conv2d {len(convs)}, LN {len(lnf)}, classifier {len(hd)}, CLS {len(cls)}, pos {len(pos)} 개")
    (cv_name, cv), (lnf_name, lnf_mod), (hd_name, hd_mod) = convs[0], lnf[0], hd[0]
    if (cv.in_channels, cv.out_channels, tuple(cv.kernel_size), tuple(cv.stride)) != (3, D, (PATCH, PATCH), (PATCH, PATCH)):
        raise RuntimeError(f"patch conv {cv_name} : {cv}")
    emb_name = cls[0][0].rsplit(".", 1)[0]
    if pos[0][0].rsplit(".", 1)[0] != emb_name:
        raise RuntimeError(f"CLS / position 이 같은 모듈이 아님 : {cls[0][0]}, {pos[0][0]}")

    cap, hooks = {}, []
    tens = lambda o: (o[0] if isinstance(o, (tuple, list)) else o).detach()
    hooks.append(mods[emb_name].register_forward_hook(lambda mm, i, o: cap.__setitem__("emb", tens(o))))
    hooks.append(lnf_mod.register_forward_hook(lambda mm, i, o: cap.__setitem__("lnf", tens(o))))
    for l, p in enumerate(per):
        hooks.append(p["blk"].register_forward_hook(lambda mm, i, o, l=l: cap.__setitem__(f"out{l}", tens(o))))
        hooks.append(p["qkv"][0].register_forward_hook(lambda mm, i, o, l=l: cap.__setitem__(f"x{l}", i[0].detach())))
        for n, ln in p["lns"]:
            hooks.append(ln.register_forward_hook(lambda mm, i, o, n=n: cap.__setitem__("ln:" + n, o.detach())))
    with torch.no_grad():
        logits = model(pixel_values=pv).logits
    for hk in hooks:
        hk.remove()

    eps = float(model.config.layer_norm_eps)
    act = getattr(model.config, "hidden_act", None)
    if act != "gelu":   # TODO(JH): exact erf GELU 가 아니면 golden 의 GELU 식을 바꿔야 함 (MLP_TASK.md 11절 ④)
        raise RuntimeError(f"hidden_act = {act} : exact erf GELU ('gelu') 가 아님")
    f32 = lambda t: t.detach().float().numpy()
    layers, lnames = [], []
    for l, p in enumerate(per):
        xin = cap[f"x{l}"][0].float().numpy()
        ln1 = [(n, mm) for n, mm in p["lns"] if np.allclose(cap["ln:" + n][0].float().numpy(), xin, atol=1e-6)]
        if len(ln1) != 1:
            raise RuntimeError(f"layer {l} : QKV 입력과 같은 출력을 내는 LayerNorm 이 1개가 아님")
        ln2 = [(n, mm) for n, mm in p["lns"] if n != ln1[0][0]]
        for n, mm in p["lns"]:
            if float(mm.eps) != eps:
                raise RuntimeError(f"{n} eps {mm.eps} != config.layer_norm_eps {eps}")
        W = {pp: f32(q.weight) for pp, q in zip(PROJ, p["qkv"])}
        b = {pp: f32(q.bias) for pp, q in zip(PROJ, p["qkv"])}
        for k, (n, mm) in (("O", p["o"]), ("FC1", p["f1"]), ("FC2", p["f2"]), ("LN1", ln1[0]), ("LN2", ln2[0])):
            W[k], b[k] = f32(mm.weight), f32(mm.bias)
        layers.append((W, b))
        lnames.append({"layer": p["lp"], "qkv": p["sa_name"], "out_proj": p["o"][0], "fc1": p["f1"][0], "fc2": p["f2"][0],
                       "ln1": ln1[0][0], "ln2": ln2[0][0]})
    if float(lnf_mod.eps) != eps:
        raise RuntimeError(f"{lnf_name} eps {lnf_mod.eps} != {eps}")
    id2label = [model.config.id2label[i] for i in range(hd_mod.out_features)]
    lg = logits[0].double().numpy()
    top5 = [int(i) for i in np.argsort(-lg, kind="stable")[:5]]
    T = dict(pixels=f32(pv[0]), patch_w=f32(cv.weight).reshape(D, -1), patch_b=f32(cv.bias),
             cls=f32(cls[0][1]).reshape(D), pos=f32(pos[0][1]).reshape(N_TOK, D), layers=layers,
             lnf_w=f32(lnf_mod.weight), lnf_b=f32(lnf_mod.bias), head_w=f32(hd_mod.weight), head_b=f32(hd_mod.bias),
             id2label=id2label)
    ref = {"h0": cap["emb"][0].double().numpy(), "out": [cap[f"out{l}"][0].double().numpy() for l in range(NL)],
           "lnf_cls": cap["lnf"][0, 0].double().numpy(), "logits": lg, "top5": top5}
    info = {"model": mid, "image": img_name, "transformers": transformers.__version__, "torch": torch.__version__,
            "layer_norm_eps": eps, "hidden_act": act, "n_layers": NL, "embeddings": emb_name, "patch_conv": cv_name,
            "cls_token": cls[0][0], "position_embeddings": pos[0][0], "final_ln": lnf_name, "classifier": hd_name,
            "qkv_names": list(names), "layer_modules": lnames,
            "hf_top1": top5[0], "hf_top1_label": id2label[top5[0]], "hf_top5": top5,
            "hf_top5_labels": [id2label[i] for i in top5]}
    return T, ref, info


def get_tensors_mock_full(seed=0, n_layers=12):
    """같은 크기의 무작위 텐서 (12 layer). layer 마다 다른 generator (seed + 2000 + l)"""
    r = np.random.default_rng(seed + 1000)
    T = dict(pixels=r.standard_normal((3, IMG, IMG)).astype(np.float32),
             patch_w=(r.standard_normal((D, D)) * 0.03).astype(np.float32),
             patch_b=(r.standard_normal(D) * 0.1).astype(np.float32),
             cls=(r.standard_normal(D) * 0.5).astype(np.float32),
             pos=(r.standard_normal((N_TOK, D)) * 0.1).astype(np.float32))
    layers = []
    for l in range(n_layers):
        g = np.random.default_rng(seed + 2000 + l)
        W = {p: (g.standard_normal((D, D)) * 0.05).astype(np.float32) for p in PROJ}
        b = {p: (g.standard_normal(D) * 0.1).astype(np.float32) for p in PROJ}
        W["O"], b["O"] = (g.standard_normal((D, D)) * 0.02).astype(np.float32), (g.standard_normal(D) * 0.05).astype(np.float32)
        for k in ("LN1", "LN2"):
            W[k], b[k] = (1.0 + g.standard_normal(D) * 0.1).astype(np.float32), (g.standard_normal(D) * 0.1).astype(np.float32)
        W["FC1"], b["FC1"] = (g.standard_normal((MLP_H, D)) * 0.05).astype(np.float32), (g.standard_normal(MLP_H) * 0.1).astype(np.float32)
        W["FC2"], b["FC2"] = (g.standard_normal((D, MLP_H)) * 0.01).astype(np.float32), (g.standard_normal(D) * 0.05).astype(np.float32)
        layers.append((W, b))
    T.update(layers=layers, lnf_w=(1.0 + r.standard_normal(D) * 0.1).astype(np.float32),
             lnf_b=(r.standard_normal(D) * 0.1).astype(np.float32),
             head_w=(r.standard_normal((1000, D)) * 0.05).astype(np.float32),
             head_b=(r.standard_normal(1000) * 0.1).astype(np.float32),
             id2label=[f"mock_{i}" for i in range(1000)])
    info = {"model": "MOCK (random)", "image": None, "layer_norm_eps": 1e-12, "hidden_act": "gelu", "n_layers": n_layers}
    return T, {}, info


# ---- PS 규칙 (VIT_FULL_TASK.md 4절) : 합은 인덱스 오름차순으로 하나씩 (float64), 곱은 float32 x float32 -> float64 (정확)
def patch_vectors(px):
    """pixels [3,224,224] -> [196, 768] , 패치 t = (t/14, t%14), 원소 i = (ch, kh, kw) = conv weight 를 [768,768] 로 펼친 순서"""
    return np.ascontiguousarray(px.reshape(3, GRID, PATCH, GRID, PATCH).transpose(1, 3, 0, 2, 4).reshape(N_PATCH, -1))


def embed_bf16(px, pw, pb, cls, pos):
    """h0 [197,768] BF16 : 패치 t -> 토큰 1+t , acc = sum_i (순서대로) p[i] w[o][i] ; v = acc + b[o] + pos[1+t][o] -> f32 -> BF16.
    CLS : BF16(f32(cls[o] + pos[0][o]))"""
    P = patch_vectors(px).astype(np.float64)
    Wd = pw.astype(np.float64)
    acc = np.zeros((N_PATCH, D))
    for i in range(D):
        acc = acc + P[:, i:i + 1] * Wd[None, :, i]
    h = np.empty((N_TOK, D), dtype=np.uint16)
    h[1:] = bf16_bits(((acc + pb.astype(np.float64)[None, :]) + pos[1:].astype(np.float64)).astype(np.float32))
    h[0] = bf16_bits((cls.astype(np.float64) + pos[0].astype(np.float64)).astype(np.float32))
    return h


def head_f32(lnc_bits, hw, hb):
    """logits[o] = f32( sum_i (순서대로) lnc[i] Wh[o][i] + bh[o] ) (float64)"""
    x = bf16_to_f32(lnc_bits).astype(np.float64).reshape(-1)
    Wd = hw.astype(np.float64)
    acc = np.zeros(hw.shape[0])
    for i in range(D):
        acc = acc + x[i] * Wd[:, i]
    return (acc + hb.astype(np.float64)).astype(np.float32)


# ---- FP64 기준 (양자화 없음) : 구조 확인용
def ln_f64(x, g, b, eps):
    mu = x.mean(-1, keepdims=True)
    return (x - mu) / np.sqrt(((x - mu) ** 2).mean(-1, keepdims=True) + eps) * g.astype(np.float64) + b.astype(np.float64)


def ref_fp_full(T, eps):
    h = patch_vectors(T["pixels"]).astype(np.float64) @ T["patch_w"].astype(np.float64).T + T["patch_b"]
    h = np.concatenate([T["cls"].astype(np.float64)[None, :], h], 0) + T["pos"].astype(np.float64)
    h0, outs = h, []
    for W, b in T["layers"]:
        fp = ref_fp(ln_f64(h, W["LN1"], b["LN1"], eps), h, W, b)
        h = ref_fp_mlp(fp["R"], W, b, eps)["R2"]
        outs.append(h)
    lnc = ln_f64(h[0], T["lnf_w"], T["lnf_b"], eps)
    return dict(h0=h0, out=outs, lnc=lnc, logits=lnc @ T["head_w"].astype(np.float64).T + T["head_b"])


# ---- 검증 (파일만 읽어서, 다른 경로로)
def ln_pyfloat(rows, g, b, eps):
    """LN 을 python float 로 (토큰마다 순서대로 합) -> float64 [n, 768]"""
    import math
    gl, bl = np.asarray(g, np.float64).tolist(), np.asarray(b, np.float64).tolist()
    out = np.empty((len(rows), D))
    for t, row in enumerate(rows):
        s = 0.0
        for v in row:
            s += v
        mean = s / D
        q = 0.0
        for v in row:
            q += (v - mean) * (v - mean)
        sd = math.sqrt(q / D + eps)
        out[t] = [((v - mean) / sd) * gg + bb for v, gg, bb in zip(row, gl, bl)]
    return out


def verify_full(out, NL, eps, id2label):
    ok = True

    def chk(name, cond, msg=""):
        nonlocal ok
        print(f"  [{'ok' if cond else 'FAIL'}] {name} {msg}")
        ok &= bool(cond)

    rd = lambda *p: open(os.path.join(out, *p), "rb").read()
    f4 = lambda *p: np.frombuffer(rd(*p), dtype="<f4")
    bf = lambda *p: np.frombuffer(rd(*p), dtype="<u2")
    for sub, lst in (("embed", FILES_EMBED), ("head", FILES_HEAD)):
        for n, _, sz, _ in lst:
            chk(f"{sub}/{n} size", len(rd(sub, n)) == sz, f"{len(rd(sub, n))}")
    for l in range(NL):
        bad = [n for n, _, sz, _ in FILES_LAYER if len(rd(f"l{l:02d}", n)) != sz]
        chk(f"l{l:02d}/ 42개 파일 크기", not bad, ",".join(bad))

    # (E) embed : patch 벡터를 index 계산으로 직접 모으고 (reshape 와 다른 경로), 합은 np.cumsum (순차 누적)
    px = f4("embed", "pixels.bin").reshape(3, IMG, IMG)
    pw = f4("embed", "patch_w.bin").reshape(D, D).astype(np.float64)
    pb, pos = f4("embed", "patch_b.bin").astype(np.float64), f4("embed", "pos.bin").reshape(N_TOK, D).astype(np.float64)
    cls = f4("embed", "cls.bin").astype(np.float64)
    t, i = np.arange(N_PATCH)[:, None], np.arange(D)[None, :]
    ch, kh, kw = i // (PATCH * PATCH), (i // PATCH) % PATCH, i % PATCH
    P = px[ch, (t // GRID) * PATCH + kh, (t % GRID) * PATCH + kw].astype(np.float64)
    acc = np.empty((N_PATCH, D))
    for t0 in range(0, N_PATCH, 4):
        acc[t0:t0 + 4] = np.cumsum(P[t0:t0 + 4, None, :] * pw[None, :, :], axis=-1)[..., -1]
    h0 = bf("embed", "h0_golden.bin").reshape(N_TOK, D)
    e1 = bf16_bits(((acc + pb[None, :]) + pos[1:]).astype(np.float32))
    e0 = bf16_bits(np.array([float(c) + float(p) for c, p in zip(cls.tolist(), pos[0].tolist())], dtype=np.float64).astype(np.float32))
    chk("h0 패치 토큰 (index 경로 + cumsum)", np.array_equal(e1, h0[1:]), f"mismatch {int((e1 != h0[1:]).sum())}")
    chk("h0 CLS = cls + pos[0] (python float)", np.array_equal(e0, h0[0]))

    # (L) layer 연결 + LN1 (python float 경로)
    chk("l00/h_in == embed/h0_golden", rd("l00", "h_in.bin") == rd("embed", "h0_golden.bin"))
    bad_c, bad_x = [], []
    for l in range(NL):
        d = f"l{l:02d}"
        if l + 1 < NL and rd(f"l{l + 1:02d}", "h_in.bin") != rd(d, "r2_golden.bin"):
            bad_c.append(l)
        hin = bf16_to_f32(bf(d, "h_in.bin").reshape(N_TOK, D)).astype(np.float64).tolist()
        xv = ln_pyfloat(hin, f4(d, "ln1_w.bin"), f4(d, "ln1_b.bin"), eps)
        c2, X2 = mx_of_bf16(bf16_bits(xv.astype(np.float32)))
        if not (np.array_equal(pack4(c2), rd(d, "x.bin")) and np.array_equal(e8m0(X2), rd(d, "x_scale.bin"))):
            bad_x.append(l)
    chk(f"l(l+1)/h_in == l(l)/r2_golden ({NL - 1} 연결)", not bad_c, f"{bad_c}")
    chk(f"x.bin / x_scale.bin == MXFP4(LN1(h_in)) ({NL} layer, python float)", not bad_x, f"{bad_x}")

    # (H) 마지막 LN (CLS) + head (python float 로 순서대로 합)
    last = bf16_to_f32(bf(f"l{NL - 1:02d}", "r2_golden.bin").reshape(N_TOK, D)[0]).astype(np.float64).tolist()
    lnc = bf("head", "lnc_golden.bin")
    lv = ln_pyfloat([last], f4("head", "lnf_w.bin"), f4("head", "lnf_b.bin"), eps)
    chk("lnc = LN_f(h_12 CLS) BF16 (python float)", np.array_equal(bf16_bits(lv.astype(np.float32))[0], lnc))
    hw, hb = f4("head", "head_w.bin").reshape(-1, D), f4("head", "head_b.bin")
    xl = bf16_to_f32(lnc).astype(np.float64).tolist()
    lg_ref = np.empty(hw.shape[0], dtype=np.float32)
    for o, row in enumerate(hw.astype(np.float64).tolist()):
        s = 0.0
        for a_, w_ in zip(xl, row):
            s += a_ * w_
        lg_ref[o] = np.float32(s + float(hb[o]))
    lg = f4("head", "logits_golden.bin")
    chk("logits (python float, 순서대로 합) bit-exact", lg_ref.tobytes() == lg.tobytes(), f"mismatch {int((lg_ref != lg).sum())}")
    return ok, lg


FILES_EMBED = [
    ("pixels.bin", "pixels", 3 * IMG * IMG * 4, "HF ViTImageProcessor 출력 float32 [3][224][224]"),
    ("patch_w.bin", "patch_w", D * D * 4, "patch conv W float32 [768 out][768 = (ch, kh, kw)]"),
    ("patch_b.bin", "patch_b", D * 4, "patch conv bias float32"),
    ("cls.bin", "cls", D * 4, "CLS 토큰 float32"),
    ("pos.bin", "pos", N_TOK * D * 4, "position embedding float32 [197][768]"),
    ("h0_golden.bin", "h0", N_TOK * D * 2, "h0 BF16 [197][768] (토큰 0 = CLS, 1+t = 패치 t)"),
]
FILES_HEAD = [
    ("lnf_w.bin", "lnf_w", D * 4, "마지막 LN gamma float32"),
    ("lnf_b.bin", "lnf_b", D * 4, "마지막 LN beta float32"),
    ("head_w.bin", "head_w", 1000 * D * 4, "classifier W float32 [1000][768]"),
    ("head_b.bin", "head_b", 1000 * 4, "classifier bias float32"),
    ("lnc_golden.bin", "lnc", D * 2, "LN_f(h_12[CLS]) BF16 [768]"),
    ("logits_golden.bin", "logits", 1000 * 4, "logits float32 [1000]"),
]


def _write(d, lst, files, extra=None):
    os.makedirs(d, exist_ok=True)
    for n, k, _, _ in lst:
        open(os.path.join(d, n), "wb").write(files[k])
    meta = {**(extra or {}), "files": {n: {"bytes": len(files[k]), "md5": md5(files[k]), "layout": ds} for n, k, _, ds in lst}}
    json.dump(meta, open(os.path.join(d, "meta.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    return meta


def cosine(a_, b_):
    a_, b_ = np.asarray(a_, np.float64).ravel(), np.asarray(b_, np.float64).ravel()
    return float(a_ @ b_ / (np.linalg.norm(a_) * np.linalg.norm(b_)))


def main_full(a):
    import time
    t_start = time.time()
    T, hf, info = get_tensors_mock_full() if a.mock else get_tensors_hf_full(a.image)
    NL, eps = len(T["layers"]), float(info["layer_norm_eps"])
    rel = lambda a_, b_: float(np.linalg.norm(np.ravel(a_) - np.ravel(b_)) / max(np.linalg.norm(np.ravel(b_)), 1e-12))
    print(f"model={info['model']}  image={info['image']}  layers={NL}  eps={eps}  -> {a.out}/")
    ok = True

    # ---- embed (PS)
    h = embed_bf16(T["pixels"], T["patch_w"], T["patch_b"], T["cls"], T["pos"])
    fe = {k: T[k].astype("<f4").tobytes() for k in ("pixels", "patch_w", "patch_b", "cls", "pos")}
    fe["h0"] = h.astype("<u2").tobytes()
    meta_e = _write(os.path.join(a.out, "embed"), FILES_EMBED, fe)

    # ---- layer 0..NL-1 : 각 layer 는 지금의 build() / build_mlp() 그대로 (입력만 x_l = LN1 PS, h_in = h_l)
    lay_meta, times, hmax = [], [], []
    our_out = []
    for l, (W, b) in enumerate(T["layers"]):
        t0 = time.time()
        d = os.path.join(a.out, f"l{l:02d}")
        xb = ln2_bf16(h, W["LN1"], b["LN1"], eps)                          # LN 식은 LN2 와 같음 (파라미터만 LN1)
        xf, hf32 = bf16_to_f32(xb).astype(np.float64), bf16_to_f32(h)
        files, _ = build(xf, hf32, W, b)
        files_mlp, _ = build_mlp(files["r"], W, b, eps)
        files.update(files_mlp)
        files["ln1_w"], files["ln1_b"] = W["LN1"].astype("<f4").tobytes(), b["LN1"].astype("<f4").tobytes()
        extra = {k: v for k, v in info.items() if k not in ("layer_modules", "hf_top5", "hf_top5_labels")}
        extra.update(layer=l, h_in="embed/h0_golden.bin" if l == 0 else f"l{l - 1:02d}/r2_golden.bin",
                     x_rule="x = MXFP4( BF16( LN1(h_in) ) ) : ps_ln2_mx rule with ln1_w / ln1_b (VIT_FULL_TASK.md 4)")
        if hf:
            extra["modules"] = info["layer_modules"][l]
        lay_meta.append(_write(d, FILES_LAYER, files, extra))
        print(f"  ---- layer {l:2d} : files written ({time.time() - t0:.1f} s)")
        fp = ref_fp(xf, hf32, W, b)
        okl = verify(d, fp, {}, b)
        okl = verify_mlp(d, fp, ref_fp_mlp(fp["R"], W, b, eps), {}, W, b, eps) and okl
        ok &= okl
        h = np.frombuffer(files["r2"], dtype="<u2").reshape(N_TOK, D).copy()
        hv = bf16_to_f32(h)
        if not np.isfinite(hv).all():
            raise ValueError(f"layer {l} 출력에 non-finite 값")
        our_out.append(hv.astype(np.float64))
        hmax.append(float(np.abs(hv).max()))
        times.append(time.time() - t0)
        print(f"  layer {l:2d} : {'ok' if okl else 'FAIL'}  max|R2| {hmax[-1]:.4g}  ({times[-1]:.1f} s)")

    # ---- 마지막 LN (CLS) + head (PS)
    lnc = ln2_bf16(h[0:1], T["lnf_w"], T["lnf_b"], eps)[0]
    lg = head_f32(lnc, T["head_w"], T["head_b"])
    fh = {k: T[k].astype("<f4").tobytes() for k in ("lnf_w", "lnf_b", "head_w", "head_b")}
    fh["lnc"], fh["logits"] = lnc.astype("<u2").tobytes(), lg.astype("<f4").tobytes()
    meta_h = _write(os.path.join(a.out, "head"), FILES_HEAD, fh)
    top1 = int(np.argmax(lg))
    lab = T["id2label"]

    print("  ---- 앞뒤 단계 / 연결 검증 (파일만 읽어서, 다른 경로로)")
    okf, lg_file = verify_full(a.out, NL, eps, lab)
    ok &= okf
    chk_top = top1 == int(np.argmax(lg_file))
    print(f"  [{'ok' if chk_top else 'FAIL'}] top-1 = argmax(logits_golden) {top1}")
    ok &= chk_top

    # ---- 비교 (보고용, 판정 아님)
    ref = ref_fp_full(T, eps)
    rows = []
    for l in range(NL):
        row = {"layer": l, "cos_fp64": cosine(our_out[l], ref["out"][l]), "rel_fp64": rel(our_out[l], ref["out"][l]),
               "max_abs": hmax[l]}
        if hf:
            row.update(cos_hf=cosine(our_out[l], hf["out"][l]), rel_hf=rel(our_out[l], hf["out"][l]),
                       fp64_vs_hf=rel(ref["out"][l], hf["out"][l]))
        rows.append(row)
    print("  ---- (info) layer 별 R2_l (BF16 golden) 비교")
    print("   l   cos vs HF   rel vs HF   cos vs FP64   rel vs FP64   FP64 vs HF   max|R2|")
    for r_ in rows:
        print(f"  {r_['layer']:2d}   {r_.get('cos_hf', float('nan')):9.6f}   {r_.get('rel_hf', float('nan')):8.3%}"
              f"   {r_['cos_fp64']:11.6f}   {r_['rel_fp64']:10.3%}   {r_.get('fp64_vs_hf', float('nan')):10.2e}   {r_['max_abs']:7.4g}")
    h0v = bf16_to_f32(np.frombuffer(fe["h0"], dtype="<u2").reshape(N_TOK, D)).astype(np.float64)
    summ = {"top1": top1, "top1_label": lab[top1], "logits_cos_fp64": cosine(lg, ref["logits"]),
            "fp64_top1": int(np.argmax(ref["logits"])), "h0_cos_fp64": cosine(h0v, ref["h0"])}
    print(f"  (info) h0 vs FP64 : cosine {summ['h0_cos_fp64']:.6f}")
    print(f"  (info) logits vs FP64 : cosine {summ['logits_cos_fp64']:.6f}, FP64 top-1 {summ['fp64_top1']} {lab[summ['fp64_top1']]}")
    if hf:
        d_e = rel(ref["h0"], hf["h0"])
        d_l = rel(ref["logits"], hf["logits"])
        print(f"  [{'ok' if d_e < 1e-5 else 'FAIL'}] FP64 embed == HF embedding 출력 (patch 순서 / CLS / pos 확인) 상대오차 {d_e:.2e}")
        print(f"  [{'ok' if d_l < 1e-4 else 'FAIL'}] FP64 12 layer + LN + head == HF logits (구조 확인) 상대오차 {d_l:.2e}")
        ok &= d_e < 1e-5 and d_l < 1e-4
        summ.update(logits_cos_hf=cosine(lg, hf["logits"]), hf_top1=hf["top5"][0], hf_top1_label=lab[hf["top5"][0]],
                    hf_top5=hf["top5"], top1_in_hf_top5=top1 in hf["top5"], top1_eq_hf=top1 == hf["top5"][0])
        print(f"  (info) logits vs HF : cosine {summ['logits_cos_hf']:.6f}")
        print(f"  (info) top-1 : ours {top1} '{lab[top1]}'  /  HF {hf['top5'][0]} '{lab[hf['top5'][0]]}'"
              f"  -> {'같음' if summ['top1_eq_hf'] else '다름'}, HF top-5 {hf['top5']} 안에 {'있음' if summ['top1_in_hf_top5'] else '없음'}")
        print(f"  (info) HF top-5 : " + ", ".join(f"{i} '{lab[i]}'" for i in hf["top5"]))
    else:
        print(f"  (info) top-1 (mock) : {top1} '{lab[top1]}'")
    elapsed = time.time() - t_start
    top = {**info, "mode": "full", "summary": summ, "layers": rows, "layer_seconds": times, "elapsed_seconds": elapsed,
           "embed_files": meta_e["files"], "head_files": meta_h["files"],
           "layer_files_md5": [{n: v["md5"] for n, v in m["files"].items()} for m in lay_meta],
           "id2label": lab,
           "rule_full": {
               "embed": "patch t = (t/14, t%14), element i = (ch, kh, kw) ; acc = sum_{i in order} f64(p[i]) f64(W[o][i]) ;"
                        " v = acc + f64(b[o]) + f64(pos[1+t][o]) -> f32 -> BF16 = h0[1+t] ; h0[0] = BF16(f32(cls + pos[0]))",
               "ln1": "same as ln2 rule with layernorm_before -> BF16 -> MXFP4 = x.bin",
               "final_ln": "same LN rule on the CLS token only -> BF16 (no quantization) = lnc",
               "head": "logits[o] = f32( sum_{i in order} f64(lnc[i]) f64(Wh[o][i]) + f64(bh[o]) ) ; top-1 = first argmax",
               "link": "h_{l+1} = R2_l (BF16)"}}
    json.dump(top, open(os.path.join(a.out, "meta.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    tot = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(a.out) for f in fs)
    print(f"  (info) 출력 {tot / 1e6:.1f} MB, 실행 {elapsed:.0f} s (layer 평균 {np.mean(times):.1f} s)")
    print("PASS" if ok else "FAIL")
    if not ok:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="vit_l0_mx")
    ap.add_argument("--image", default=None)
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--full", action="store_true")
    a, _ = ap.parse_known_args()
    if a.full:
        return main_full(a)

    x, h_in, W, b, hf_ref, info = get_tensors_mock() if a.mock else get_tensors_hf(a.image)
    assert x.shape == (N_TOK, D) and h_in.shape == (N_TOK, D)
    files, _ = build(x, h_in, W, b)
    eps = float(info["layer_norm_eps"])
    files_mlp, _ = build_mlp(files["r"], W, b, eps)
    files.update(files_mlp)
    os.makedirs(a.out, exist_ok=True)
    for n, k, _, _ in FILES:
        open(os.path.join(a.out, n), "wb").write(files[k])
    meta = {
        **info,
        "format": "OCP MX v1.0 MXFP4 : block 32 along the reduction axis, E8M0 scale (byte = X + 127), E2M1 elements",
        "rule": {
            "scale": "X = floor(log2(block max|v|)) - 2, clip [-127,127], all-zero block -> -127",
            "element": "E2M1 RNE (tie -> mantissa 0), saturate |v| > 6 -> 6, code [3]=sign [2:0]=magnitude index, no -0",
            "magnitude_index": "0:0 1:0.5 2:1 3:1.5 4:2 5:3 6:4 7:6",
            "dot": "per block : int sum (2a)(2b) x 2^(Xa+Xb-2) (float64), blocks accumulated in order (float64), + bias, -> f32 -> BF16 RNE",
            "ps_quant": "BF16 -> float64 -> MXFP4 (same rule) : Q,K (2 blocks per token), V^T (8 blocks per d, token axis), A (8 blocks per row), O concat (24 per token)",
            "s": "S = Q.K over d (2 blocks), f32 -> BF16, row stride 208 (pad 0)",
            "a": "A = softmax(S/8) over 197, float64 -> f32 -> BF16, row stride 208 (pad 0)",
            "r": "R = BF16( f32(h_in_bf16) + f32(Y) )",
            "ln2": "per token, x = f64(BF16 R) : mean = sum_{i=0..767 in order} x / 768, var = sum_{in order} (x-mean)^2 / 768,"
                   " y = ((x-mean)/sqrt(var+eps))*g + b (f64) -> f32 -> BF16 RNE -> MXFP4 (24 blocks per token) = X2",
            "fc1": "H = dot(X2, W1) + b1 (f64) -> f32 -> BF16, 48 tiles of 64 output columns",
            "gelu": "G = 0.5 h (1 + erf(h / sqrt 2)), h = f64(BF16 H), f64 (math.erf) -> f32 -> BF16",
            "h4": "G [197,3072] -> MXFP4 (96 blocks per token), plane k = columns 768k..768k+767",
            "fc2_partial": "P(n,k) = dot(H4 plane k, W2 rows 64n.., columns 768k..) (no bias) -> f32 -> BF16  [provisional]",
            "fc2_acc": "acc = f32(b2) ; for k = 0..3 : acc = f32(acc + f32(P(n,k))) ; Y2 = BF16 RNE(acc)  [provisional]",
            "r2": "R2 = BF16( f32(R) + f32(Y2) )",
            "pack": "element 2i -> byte[3:0], 2i+1 -> byte[7:4] ; scale 1 byte per block, block order",
        },
        "b_qkv": {p: b[p].astype(np.float64).tolist() for p in PROJ},
        "b_o": b["O"].astype(np.float64).tolist(),
        "files": {n: {"bytes": len(files[k]), "md5": md5(files[k]), "layout": d} for n, k, _, d in FILES},
    }
    json.dump(meta, open(os.path.join(a.out, "meta.json"), "w"), indent=1, ensure_ascii=False)
    print(f"model={info['model']}  image={info['image']}  top1={info['pred_top1']}  files -> {a.out}/")
    fp = ref_fp(x, h_in, W, b)
    ok = verify(a.out, fp, hf_ref, b)
    print("  ---- MLP (LN2 -> FC1 -> GELU -> FC2 -> Residual 2)")
    ok = verify_mlp(a.out, fp, ref_fp_mlp(fp["R"], W, b, eps), hf_ref, W, b, eps) and ok
    print("PASS" if ok else "FAIL")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
