# 합성/구현 결과 — `l2_noc_fpga_top` on ZCU102 (xczu9eg-ffvb1156-2-e)

실행: `verif/fpga/build_synth.tcl` (synth_design → opt_design → place_design →
route_design, non-project batch mode). 리포트 원본: `verif/fpga/build/`.

## 결과 요약

| 단계 | 결과 |
|---|---|
| `synth_design` | **성공**, 0 Errors, 0 Critical Warnings |
| `place_design` / `route_design` | **성공**, 0 Errors, 100% fully routed |
| 타이밍 (100MHz, `create_clock -period 10`) | **전부 만족** — WNS = **+3.117 ns**, WHS = **+0.014 ns**, TNS/THS = 0 |
| DRC | Critical Warning 2건 — **둘 다 예상된 것** (아래 참고) |

> "All user specified timing constraints are met." (route 후 공식 `report_timing_summary`)

## 자원 사용량 (post-route, `util_route.rpt`)

| 자원 | 사용 | 전체 | 사용률 |
|---|---|---|---|
| CLB LUT | 46,461 | 274,080 | 17.0% |
| CLB Register | 31,889 | 548,160 | 5.8% |
| Block RAM Tile | 158 (RAMB36×156 + RAMB18×4) | 912 | 17.3% |
| URAM | 0 (디바이스에 없음) | 0 | — |
| DSP | 0 | 2,520 | 0% |

**자원은 전혀 빠듯하지 않음** — GROUPS=8/BLOCKS=16/ADDRESS_ROW=256(256KB) 축소판
기준이고, LUT/BRAM 다 20% 미만이라 원래 크기(4MB, GROUPS=8/BLOCKS=32/ADDRESS_ROW=2048)로
키워도 BRAM 쪽은 넉넉히 여유 있어 보임(정확한 수치는 재합성해서 확인 필요).

## `ram_style="ultra"` 처리 (ZU9EG에는 UltraRAM 없음)

경고 17건 발생, 전부 동일 패턴:
```
WARNING: [Synth 8-12187] The ram_style = "ultra" set on RAM "...ram_mimic:/ram_reg"
is ignored because there is no UltraRAM on the device.
```
**에러 아님** — Vivado가 자동으로 일반 BRAM(RAMB36E2/RAMB18E2)으로 대체해서
합성/배치/배선까지 전부 정상 완료됨. `ram_mimic.sv`(L2)와 `sram_mimic_fpga.v`(NOC)의
`(* ram_style = "ultra" *)` 속성은 이 보드에서는 사실상 무시되는 것으로 취급하면 됨 —
당장 수정 안 해도 빌드 되지만, "의도"를 명확히 하려면 ZCU102 전용으로 속성을 빼거나
`"block"`으로 바꾸는 것도 고려할 만함(선택사항, 기능엔 영향 없음).

## DRC Critical Warning 2건 — 둘 다 "보드 확정 안 된 상태라 당연한" 것

| Rule | 내용 |
|---|---|
| NSTD-1 | `i_clk, i_rst_n, o_led_done, o_led_pass, o_mismatch_count[2:0]` 7개 포트에 IOSTANDARD 미지정 |
| UCIO-1 | 위 포트들 핀 위치(LOC) 미지정 |

`constraints.xdc` 가 지금은 클럭 주기·false-path만 잡아놓은 placeholder라서 그렇다 —
**`write_bitstream` 전에는 반드시 실제 ZCU102 핀맵으로 채워야 함** (보드파일
`xilinx.com:zcu102:part0:3.4` 설치돼 있으니 `set_property board_part`로 붙이고
LED/버튼/오실레이터 핀을 거기서 가져오면 됨). `synth_design`/`place_design`/
`route_design` 자체는 이 상태로도 전부 통과함 — 이번 목적(자원·타이밍 확인)엔 문제 없음.

## 결론

**GROUPS=8/BLOCKS=16/ADDRESS_ROW=256 축소판 `l2_noc_fpga_top` 은 ZCU102 에서
합성·배치·배선·타이밍 전부 통과.** 남은 건 실제 하드웨어에 올리기 위한:
1. 실보드 XDC (핀맵 + IOSTANDARD)
2. `write_bitstream`
3. (선택) 원래 크기(GROUPS=8/BLOCKS=32/ADDRESS_ROW=2048)로 재합성해서 자원 여유 재확인
4. 물리 보드에서 `o_led_pass`/`o_mismatch_count` 확인 — 시뮬에서 이 BIST가 5/5 PASS
   났던 것과 같은 결과가 실물에서도 나오는지 (`FINDING_first_write_beat_timing.md` 4-b절 참고)
