# run_gen_win.py - Windows 에서 vit_golden_gen.py 를 돌리기 위한 실행기 (Linux / Colab 에서는 필요 없음)
#
#   python run_gen_win.py vit_golden_gen.py --mock --out DIR
#
# Windows 용 numpy 1.x 의 np.ldexp 는 지수로 int32 (C long) 만 받고 int64 는 TypeError 를 낸다.
# 생성기의 지수는 모두 |e| < 300 이므로 int32 로 바꿔도 결과는 bit 단위로 같다.
# 생성기 자체는 고치지 않고 np.ldexp 만 감싼 뒤 그대로 실행한다.
import runpy
import sys

import numpy as np

_ldexp = np.ldexp


def _ldexp_i32(x, e, *a, **k):
    e = np.asarray(e)
    if e.dtype.kind in "iu" and e.dtype.itemsize > 4:
        if e.size and int(np.abs(e).max()) >= 2 ** 31:
            raise OverflowError("ldexp exponent out of int32 range")
        e = e.astype(np.int32)
    return _ldexp(x, e, *a, **k)


np.ldexp = _ldexp_i32

if len(sys.argv) < 2:
    sys.exit("usage: python run_gen_win.py vit_golden_gen.py [args]")
script = sys.argv[1]
sys.argv = sys.argv[1:]
runpy.run_path(script, run_name="__main__")
