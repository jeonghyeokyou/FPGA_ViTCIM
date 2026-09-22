# Phase 2 계획 — L2 ↔ NOC 통합 검증 (ch1_in 먼저)

## 0. 목표

L2 가 커맨드 하나로 **자기 내부 SRAM ↔ (NOC 경유) ↔ L1_Cache_Mimic** 사이에서
데이터를 실제로 옮기는지 end-to-end 로 확인 (파형 + 스코어보드).

```
  TOP_L2_cache                          noc_ch1_in_adapter        noc_top (renamed FIFO_intf)
  ─────────────                         ─────────────────         ────────────────────────────
  o_noc_write_valid ───────────────────▶ i_write_valid_M ────────▶
  o_noc_write_addr[18:0]  {mcast, a11} ─▶ i_write_addr_M = addr[10:0]
  o_noc_write_data[511:0] ─────────────▶ i_write_data_M           noc_FIFO_interface
  i_noc_write_ready  ◀───────────────── o_FIFO_write_ready_M          │
  i_noc_write_response ◀─────────────── o_write_ready_M           L1_FIFO_interface (i_pe_busy=0)
  o_noc_read_valid ───────────────────▶ i_read_valid_M               │
  o_noc_read_addr[18:0] ──────────────▶ i_read_addr_M = addr[10:0]  L1_Cache_Mimic (fixed)
  o_noc_read_data_ready ──────────────▶ i_data_fifo_ready_M           │
  i_noc_read_ready  ◀───────────────── o_FIFO_read_ready_M          sram_mimic x4 (fixed)
  i_noc_read_response ◀─────────────── o_read_ready_M
  i_noc_read_data[511:0] ◀──────────── o_read_data_M
  o_noc_control_mode ────────────────▶ i_control_mode
```

L2 ch1_in 동작 방향:
- **LOAD**  : L2 내부 SRAM → NOC **write** path  (adapter 의 `i_write_*_M` 사용)
- **STORE** : NOC **read** path → L2 내부 SRAM  (adapter 의 `i_read_*_M` 사용)
- 한 번에 read/write 둘 중 하나만 활성 → `FIFO_interface_on_fire` 의 mux 가 알아서 처리

---

## 준비 작업 (순서대로)

### STEP 0 — NOC 를 단독으로 먼저 돌린다  (NOC Phase 0 + Phase 1)

NOC 는 아직 한 번도 compile/sim 안 해봤다. L2 때와 똑같이:
1. `verif/noc/noc_files.f` 작성, top = `FIFO_intf`, `xelab` 통과 확인
2. `FIFO_intf` 마스터 포트를 직접 두드리는 간단 TB → `L1_Cache_Mimic` 에 write 후 read

**이때 반드시 고쳐야 하는 NOC 버그 (L2 ram_mimic 버그와 같은 종류):**

| 파일 | 줄 | 문제 | 수정 |
|---|---|---|---|
| `rtl/NOC_260902/sram_mimic.v` | 29 | `input wire [..] o_dout` | `output` |
| `rtl/NOC_260902/L1_Cache_Mimic.v` | 30 | `input wire [..] o_read_data` | `output` |

→ 안 고치면 NOC read data 경로가 죽어 있어서 통합해도 X 만 나온다.
L2 때처럼 `verif/noc/fix/` 에 사본 두고 `noc_files_fix.f` 사용 (원본 미수정).

또 `FIFO_intf.v` 는 `L1_FIFO_interface` 인스턴스에서 `i_pe_busy` 를 연결 안 한다
(→ 게이팅 로직이 X). 통합용 top 에서 `1'b0` 으로 묶어야 함.

### STEP 1 — 모듈 이름 충돌 해결

L2(.sv) 와 NOC(.v) 에 **같은 이름 / 다른 구현**:
`FIFO_interface`, `FIFO`, `FIFO_interface_handshake`, `FIFO_interface_on_fire`,
`FIFO_modified`, `sram_controller`

→ NOC 쪽 6개 파일을 `verif/noc/rename/` 에 복사하고 모듈명 + 내부 인스턴스 참조에
`noc_` 접두어. (예: `FIFO_interface` → `noc_FIFO_interface`,
그 안의 `FIFO_interface_on_fire` 인스턴스도 `noc_FIFO_interface_on_fire` 로.)
`FIFO_intf` / `L1_FIFO_interface*` / `L1_Cache_Mimic` / `sram_mimic` 는 L2 와 안 겹치니 그대로 둬도 됨
(단 위 STEP0 수정본 사용).

### STEP 2 — 어댑터 `noc_ch1_in_adapter.sv`

거의 배선만 하면 된다:
```systemverilog
module noc_ch1_in_adapter #(parameter DA_L2 = 19, ADDR_BW = 11, DW = 512) (
  // --- L2 side (TOP_L2_cache ch1_in) ---
  input              l2_noc_write_valid,  input  [DA_L2-1:0] l2_noc_write_addr,
  input  [DW-1:0]    l2_noc_write_data,   output             l2_noc_write_ready,
  output             l2_noc_write_response,
  input              l2_noc_read_valid,   input  [DA_L2-1:0] l2_noc_read_addr,
  input              l2_noc_read_data_ready, output           l2_noc_read_ready,
  output             l2_noc_read_response, output [DW-1:0]    l2_noc_read_data,
  input              l2_noc_control_mode,
  // --- NOC side (FIFO_intf master port) ---
  output             m_read_valid,   output [ADDR_BW-1:0] m_read_addr,
  input  [DW-1:0]    m_read_data,    input                m_read_ready,
  output             m_write_valid,  output [ADDR_BW-1:0] m_write_addr,
  output [DW-1:0]    m_write_data,   input                m_write_ready,
  output             m_control_mode, input  m_FIFO_read_ready, input m_FIFO_write_ready,
  output             m_data_fifo_ready
);
  assign m_write_valid       = l2_noc_write_valid;
  assign m_write_addr        = l2_noc_write_addr[ADDR_BW-1:0];   // drop multicast[18:11]
  assign m_write_data        = l2_noc_write_data;
  assign l2_noc_write_ready  = m_FIFO_write_ready;
  assign l2_noc_write_response = m_write_ready;

  assign m_read_valid        = l2_noc_read_valid;
  assign m_read_addr         = l2_noc_read_addr[ADDR_BW-1:0];
  assign m_data_fifo_ready   = l2_noc_read_data_ready;
  assign l2_noc_read_ready   = m_FIFO_read_ready;
  assign l2_noc_read_response = m_read_ready;
  assign l2_noc_read_data    = m_read_data;

  assign m_control_mode      = l2_noc_control_mode;
endmodule
```
> `FIFO_intf` 의 마스터 포트는 `FIFO_interface` 인터페이스에서 나온다. `FIFO_intf` 를 쓰면
> 이미 `L1_FIFO_interface` + `L1_Cache_Mimic` 까지 묶여 있음. 다만 `i_pe_busy`, control_mode
> polarity, ADDR_DEPTH 파라미터만 통합 top 에서 맞춰주면 됨.
>
> control_mode: L2 `o_noc_control_mode = r_control_mode[0]`. burst 모드(00/10)면 0 =
> fire-on-valid. NOC `i_control_mode==0` = on_fire. **burst 는 정합.** handshake(01/11) 는
> 나중에 별도 확인.

### STEP 3 — 통합 TB `tb_l2_noc_ch1_in.sv`

```
TOP_L2_cache  ──ch1_in──  noc_ch1_in_adapter  ──  noc_top(FIFO_intf renamed+fixed)  ──  L1_Cache_Mimic
       └ 내부 SRAM (ram_mimic, fix)                                                        └ sram_mimic (fix)
```
- ch2_in / wgt 채널은 tie-off (Phase 1 TB 처럼)
- 시나리오 A : L2 `ch1_in STORE` — L1_Cache_Mimic 초기값(또는 TB가 미리 채운 값)이
  NOC read 로 넘어와 L2 내부 SRAM 에 써지는지
- 시나리오 B : L2 `ch1_in LOAD` — L2 내부 SRAM 값이 NOC write 로 L1_Cache_Mimic 에 써지는지
- 스코어보드 : L1_Cache_Mimic 메모리 배열 ↔ L2 내부 SRAM 배열 hierarchical 비교

### STEP 4 — ch2_in 추가

ch2_in 은 **NOC read path 방향이 반대** (NOC 가 master: `i_noc_read_valid`/`addr[31:0]`/`data`
가 L2 입력, `o_noc_read_response`/`o_noc_read_ready` 가 L2 출력).
→ `FIFO_intf` 마스터 포트와 자연스럽게 안 맞음. ch2_in store 는 별도 어댑터(또는 BFM 유지)
필요. ch2_in load 는 ch1 과 유사.

---

## 제일 먼저 할 것

**STEP 0** — NOC 단독. `FIFO_intf` compile → 버그 2개 fix → write/read 되는지 TB.
L2 에서 한 `00_compile` → `TB` → `파형` 순서 그대로 반복.
