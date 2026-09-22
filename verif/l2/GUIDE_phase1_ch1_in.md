# Phase 1 학습 가이드 — L2 `ch1_in` load 기능 시뮬레이션

> 목적: 테스트벤치가 **무엇을** 확인하는지, **어떻게** 짜여 있는지, Vivado에서
> **어떤 파형을 어떻게** 봐야 하는지를 직접 따라 하며 익힌다.

---

## 0. 이번에 검증하려는 것 (한 문장)

> **"`ch1_in load` 커맨드를 하나 넣으면, `TOP_L2_cache` 가
> ① 내부 SRAM을 순서대로 읽고 ② 읽은 데이터를 NOC write 로 목적지 주소를
> 1씩 증가시키며 내보낸 뒤 ③ 스스로 IDLE 로 돌아오는가?"**

- 이번 단계(Phase 1)는 **자동 채점 없음**. 파형을 눈으로 보고 "맞게 도는지" 확인한다.
- NOC 반대편(진짜 `NOC_260902`)은 아직 안 붙인다. 대신 TB 안에 **아주 단순한 가짜 NOC**
  (항상 받아줌 + 1클럭 뒤 응답)를 둔다. 그래야 DUT 안의 FSM이 멈추지 않고 끝까지 돈다.

---

## 1. 배경: 커맨드가 DUT 안에서 흐르는 경로

```
i_command(64b) ─▶ CMD_dispatcher ─▶ (cmd_idx=1 이면 ch1_in 으로) ─▶ skid_buffer
      │                                                                  │
      │  cmd[62:60] = cmd_idx  (1 = ch1_In load)                          ▼
      │                                     cmd_decoder_SRAM_group_merge
      │                                        └ u_cmd_decoder_channel_1_in_wrapper
      │                                             └ u_cmd_decoder_channel_1_in  ← FSM 여기 있음
      ▼
  cmd[59:58] = ctrl_mode :  00 burst load / 01 handshake load / 10 burst store / 11 handshake store
```

### `ch1_in load` 커맨드 비트 필드 (발표자료 4쪽 = 실제 RTL)

| 비트 | 이름 | 이번 값 | 의미 |
|---|---|---|---|
| [63] | layer index | 0 | 레이어 번호 구분(무시 가능) |
| [62:60] | cmd index | `001` | ch1_In **load** |
| [59:58] | ctrl_mode | `00` | **burst** load |
| [57] | prec_mode | 0 | ch1에선 무시 |
| [56:40] | source_start_addr (17b) | 0 | L2 내부 SRAM 읽기 시작 주소 |
| [39:29] | source_read_addr (11b) | **4** | 전송 개수 − 1 → **5 beat** |
| [28:18] | destination_start_addr (11b) | 0 | L1 쪽 쓰기 시작 주소 |
| [17:15] | resize_step_addr (3b) | 0 | resize 안 함 |
| [14:7] | multicast (8b) | `0x01` | 어느 cluster로 보낼지 (one-hot) |
| [6:0] | opcode (7b) | 0 | - |

→ NOC write 주소 = `{multicast(8b), destination_start_addr(11b)}` = `{0x01, 0}` = **0x800**,
그다음 0x801, 0x802 … 0x804 (5개).

---

## 2. 테스트벤치 해부 — `tb/tb_l2_ch1_in.sv`

테스트벤치(TB)는 "DUT를 둘러싸는 가짜 회로"다. 순서대로 읽어보자.

### 2.1 파라미터 미러링
```systemverilog
localparam BW_CH1_IN = 512;
localparam DA_CH1_IN = 19;      // DESTINATION_ADDR_BIT_CHANNEL_1_IN
```
DUT 포트 `o_noc_write_addr_channel_1_in` 은 `[18:0]` (19비트), `o_noc_write_data_...` 는 512비트다.
TB에서 이 포트에 연결할 `wire` 를 **정확히 같은 폭**으로 선언해야 `xelab` 이 통과한다.
그래서 DUT 파라미터를 TB에도 똑같이 적어 둔다.

### 2.2 클럭 / 리셋
```systemverilog
localparam CLKP = 10;                       // 10 ns 주기 = 100 MHz
always #(CLKP/2) i_clk = ~i_clk;            // 5 ns 마다 토글
...
i_rstb = 1'b0;  repeat (10) @(posedge i_clk);   // 리셋 10클럭 유지 (active-low)
i_rstb = 1'b1;                                    // 리셋 해제
```
`i_rstb` 는 **active-low** (0일 때 리셋). RTL 전체가 `negedge i_rstn` 비동기 리셋을 쓴다.

### 2.3 신호 선언 규칙
- **TB가 값을 주는 신호** (DUT 입력) → `logic ... = 초기값;`  예) `i_command`, `i_noc_write_ready_...`
- **DUT가 내보내는 신호** (DUT 출력) → `wire`  예) `o_noc_write_valid_...`, `o_command_ready`

### 2.4 DUT 인스턴스
`TOP_L2_cache #(...) dut (...)` — 파라미터도 포트도 **이름으로** 연결(`.포트(신호)`).
안 쓰는 채널(ch2_in, ch1_wgt, ch2_wgt)도 **포트는 전부 연결**해야 한다.
입력은 안전한 고정값(`ready=1`, `valid=0`), 출력은 그냥 `wire` 로 받아만 둠.

### 2.5 ⭐ 가짜 NOC (BFM) — 이 파일에서 제일 중요한 부분
```systemverilog
// 채널1 입력의 NOC 쪽을 TB가 대신 연기한다
i_noc_write_ready_channel_1_in = 1'b1;     // NOC는 항상 받을 준비 됨 (backpressure 없음)

always @(posedge i_clk or negedge i_rstb)
  if (!i_rstb) ...
  else begin
    // write 핸드셰이크가 성사되면 1클럭 뒤 "응답" 펄스
    i_noc_write_response_channel_1_in <= o_noc_write_valid_channel_1_in
                                       & i_noc_write_ready_channel_1_in;
    if (o_noc_write_valid_channel_1_in & i_noc_write_ready_channel_1_in)
        $display("NOC WR ... addr=%h data=%h", ...);   // 콘솔에 찍기
  end
```
**왜 필요한가?** DUT의 FSM은 `if (i_noc_write_ready) ...` 로 다음 주소로 넘어간다.
TB가 `i_noc_write_ready` 를 안 주면 그 신호는 `z`(연결 안 됨) → 시뮬레이터가 `x` 취급 →
`if (x)` 는 거짓 → **FSM이 첫 beat에서 영원히 멈춘다.**
그래서 "NOC가 항상 받아준다"는 최소한의 모델을 TB가 제공한다.

read 경로도 같은 방식: `i_noc_read_ready=1`, 요청 1클럭 뒤 `i_noc_read_response` + `i_noc_read_data`(주소 패턴) 리턴.

### 2.6 커맨드 밀어넣기 `task send_cmd`
```systemverilog
task automatic send_cmd(input [63:0] c);
    @(negedge i_clk);
    i_command = c;  i_command_valid = 1'b1;   // valid 세우고
    @(posedge i_clk);
    while (!o_command_ready) @(posedge i_clk); // ready 뜰 때까지 대기 (valid/ready 핸드셰이크)
    @(negedge i_clk);
    i_command_valid = 1'b0;                    // 한 번 들어갔으면 내림
endtask
```
`CMD_dispatcher` 안의 커맨드 큐(FIFO)에 push 하는 표준 valid/ready 프로토콜.

### 2.7 자극 시나리오 `initial`
```systemverilog
cmd = 64'd0;
cmd[62:60] = 3'b001;   // ch1_In load
cmd[59:58] = 2'b00;    // burst load
cmd[39:29] = 11'd4;    // 5 beats
cmd[14:7]  = 8'h01;    // multicast
send_cmd(cmd);
repeat (400) @(posedge i_clk);   // 전송 끝날 때까지 시간 흘리기
$finish;
```

### 2.8 파형 기록 & 타임아웃
```systemverilog
$dumpfile("tb_l2_ch1_in.vcd");  $dumpvars(0, tb_l2_ch1_in);   // VCD 저장
initial begin #200000; $display("!! TIMEOUT !!"); $finish; end   // 200us 지나면 강제 종료(무한hang 방지)
```

---

## 3. Vivado 로 직접 돌리기

### 방법 0 — 원클릭 (가장 빠름, store→load 파형)

`cmd` 창에서:
```
C:\RTL_YJH\L2_verification\verif\l2\30_wave_gui_storeload.bat
```
- RTL(원본 + `fix/ram_mimic.sv`) + `tb_l2_ch1_in_storeload.sv` 를 compile/elab 하고
  **Vivado XSim 파형 GUI 를 자동으로 연다.**
- `wave_setup_storeload.tcl` 이 4·5절에서 볼 신호들을 divider 로 묶어 미리 추가하고
  760 ns 까지 실행해 둔다.
- GUI 에서 할 것:
  - **Zoom Fit** (단축키 `F`) 로 전체 보기
  - 버스 신호 우클릭 → **Radix → Hexadecimal**
  - 더 실행하려면 툴바 **Run All** (또는 `run 200ns` 를 Tcl Console 에)
  - 신호 추가: 왼쪽 **Scope** 트리 →
    `dut ▸ u_cmd_decoder_SRAM_group_merge ▸ u_cmd_decoder_channel_1_in_wrapper ▸ u_cmd_decoder_channel_1_in`
    → **Objects** 창에서 우클릭 → Add to Wave Window

### 방법 A — GUI 프로젝트 (Vivado 프로젝트 흐름을 익히고 싶을 때)

1. **cmd 창** 을 연다 (시작 메뉴 → `cmd`).
2. 프로젝트 생성 tcl 실행:
   ```
   cd C:\RTL_YJH\L2_verification\verif\l2
   "C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode gui -source make_vivado_project.tcl
   ```
   이 tcl이 하는 일:
   - `create_project l2_ch1_sim vivado/` — 빈 프로젝트
   - `add_files [glob .../L2_260901/*.sv]` — L2 RTL 34개 추가 (design source)
   - `add_files -fileset sim_1 tb/tb_l2_ch1_in.sv` — TB 추가 (simulation source)
   - `set_property top tb_l2_ch1_in [get_filesets sim_1]` — 시뮬 최상위 지정
   - `xsim.elaborate.debug_level = all` — 모든 신호 파형에서 보이게
3. Vivado GUI 가 뜬다. 왼쪽 **Flow Navigator → SIMULATION → Run Simulation → Run Behavioral Simulation**.
4. 잠시 후(30초~2분) **XSim 파형 창**이 열린다. 기본은 `tb_l2_ch1_in` 최상위 신호만 보임.
5. **콘솔(Tcl Console) 확인**: `NOC WR ch1_in #0 ... addr=0x00800` 같은 줄이 5개 찍혀 있으면 정상.
6. **신호 더 보기**:
   - 왼쪽 **Scope** 창에서 계층 펼치기:
     `tb_l2_ch1_in ▸ dut ▸ u_cmd_decoder_SRAM_group_merge ▸ u_cmd_decoder_channel_1_in_wrapper ▸ u_cmd_decoder_channel_1_in`
   - 가운데 **Objects** 창에서 신호 선택 → 우클릭 → **Add to Wave Window**
   - 아래 4-1 표의 신호들을 추가
7. **다시 실행**: 파형창 툴바에서 **Restart**(↻) → **Run All**(▶▶) (또는 `Run For` 5 us)
8. **파형 보기 조작**:
   - **Zoom Fit** (툴바 돋보기, 또는 단축키 `F`) — 전체 한눈에
   - 마우스 휠 = 확대/축소, 가운데 버튼 드래그 = 이동
   - 버스 신호 우클릭 → **Radix → Hexadecimal / Unsigned Decimal** 로 표시 형식 변경
   - 신호 우클릭 → **Name → Long/Short** 로 계층경로 표시 토글

### 방법 B — Tcl 명령 한 줄씩 (명령어 익히기용)

`cmd` 창에서 (먼저 `set PATH=C:\Xilinx\Vivado\2024.2\bin;%PATH%`):
```
cd C:\RTL_YJH\L2_verification\verif\l2\work
xvlog --sv -f ..\l2_files.f            &REM  RTL 34개 컴파일(분석)
xvlog --sv ..\tb\tb_l2_ch1_in.sv       &REM  TB 컴파일
xelab work.tb_l2_ch1_in -s snap --debug all   &REM  최상위부터 연결(elaborate)
xsim snap -gui                          &REM  파형 GUI 열기
```
XSim 이 열리면 **Tcl Console** 에 직접:
```
add_wave /tb_l2_ch1_in/i_command
add_wave /tb_l2_ch1_in/o_noc_write_valid_channel_1_in
add_wave /tb_l2_ch1_in/o_noc_write_addr_channel_1_in
add_wave /tb_l2_ch1_in/dut/u_cmd_decoder_SRAM_group_merge/u_cmd_decoder_channel_1_in_wrapper/u_cmd_decoder_channel_1_in/current_state
run 5 us
```
> `xsim snap -gui` 대신 `-tclbatch ..\wave_setup_storeload.tcl` 를 붙이면 신호까지 미리 올라온다
> (그게 방법 0 의 `30_...bat` 이 하는 일).

---

## 4. 어떤 파형을 봐야 하나

### 4-1. 파형에 올릴 신호

| Scope | 신호 | 뭘 보나 |
|---|---|---|
| `tb_l2_ch1_in` | `i_clk`, `i_rstb` | 클럭/리셋 |
| `tb_l2_ch1_in` | `i_command`, `i_command_valid`, `o_command_ready` | 커맨드 주입 시점 |
| `.../u_cmd_decoder_channel_1_in` | `current_state[2:0]` | **FSM 상태** (1 IDLE→2 DECODE→3 BURST_LOAD→7 DONE→1) |
| 〃 | `o_sram_read_valid`, `o_sram_read_addr` | 내부 SRAM 읽기 요청 |
| 〃 | `i_sram_read_response`, `i_sram_read_data` | SRAM 이 돌려준 데이터(내부) |
| 〃 | `o_noc_write_valid`, `o_noc_write_addr`, `o_noc_write_data` | **NOC 로 내보내는 write** |
| 〃 | `i_noc_write_ready` | 가짜 NOC 응답(항상 1) |
| 〃 | `r_noc_write_last_flag` | 마지막 beat 표시 |
| 〃 | `o_load_busy` | 커맨드 처리 중 |
| `tb_l2_ch1_in` | `o_busy_channel_1_in` | 채널1 전체 busy |

### 4-2. 시간순 스토리 (이렇게 흘러가면 정상)

| 대략 시각 | 일어나는 일 |
|---|---|
| 0 ~ 100 ns | `i_rstb = 0` (리셋 중), 모든 상태 초기값 |
| ~110 ns | `i_rstb : 0→1` 리셋 해제, `current_state = 1` (IDLE) |
| ~160 ns | `i_command_valid=1` 이고 `o_command_ready=1` → 커맨드가 큐에 들어감 (`CMD pushed` 콘솔 출력) |
| +몇 클럭 | dispatcher→skid_buffer→ch1_in 디코더 도착, `current_state : 1→2 (CMD_DECODE)→3 (BURST_LOAD)` |
| BURST_LOAD 중 | `o_sram_read_valid=1`, `o_sram_read_addr` = 0,1,2,3,4 로 증가 (내부 SRAM 5번 읽기) |
| 조금 뒤 | `i_sram_read_response=1` 로 데이터 도착 (지금은 `i_sram_read_data = x`) |
| ~305 ns 부터 | `o_noc_write_valid=1`, `o_noc_write_addr` = `0x800, 0x801, 0x802, 0x803, 0x804` (1씩 증가) |
| 〃 | `o_noc_write_data` = SRAM 에서 읽은 값 (**지금은 x** — 5절 참고) |
| 마지막 write 후 | `r_noc_write_last_flag=1` → `current_state : 3→7 (CMD_DONE)→1 (IDLE)` |
| 그 뒤 | `o_load_busy : 1→0`, `o_busy_channel_1_in : 1→0` (한가해짐) |

### 4-3. 합격 체크리스트

1. ☐ `o_noc_write_valid` 핸드셰이크가 정확히 **5번** 일어나는가? (source_read_addr=4 → 5)
2. ☐ `o_noc_write_addr` 가 **0x800 부터 1씩** 증가하는가?
3. ☐ FSM이 **IDLE(1) 로 복귀**하는가? (복귀 안 하고 멈추면 = 버그 또는 BFM 부족)
4. ☐ `o_load_busy` 가 끝에 **0** 으로 떨어지는가?
5. ☐ (다음 단계) `o_noc_write_data` 가 SRAM 에서 읽은 값과 일치하는가?

---

## 5. store → load 로 확장 → **버그 발견**

v1 에서 `o_noc_write_data` 가 `x` 였다. "SRAM에 아무것도 안 써서" 라고 생각하고
**store → load** 시나리오를 만들었다 → `tb/tb_l2_ch1_in_storeload.sv`,
`11_run_l2_ch1_in_storeload.bat`.

- STEP 1: `ch1_in burst store` — 가짜 NOC가 `0xA5A5_0000 + beat` 패턴을 5 beat 넣어줌.
  L2가 내부 SRAM에 쓰도록.
- STEP 2: `ch1_in burst load` — 방금 쓴 SRAM을 다시 읽어 `o_noc_write_data` 로 내보냄.
  TB가 "load 값 == store 패턴" 을 자동 비교.

결과: **STEP 2 가 전부 MISMATCH, load 값이 여전히 `x`.**  store 는 콘솔상 잘 도는데도.

### 원인 (실제 RTL 버그)

`rtl/L2_260901/ram_mimic.sv` (L2 내부 SRAM의 동작 모델):
```verilog
always @(posedge clka)
    if (ena) begin              // ← active-HIGH 로 취급 (Xilinx BRAM 스타일)
        if (wea) ram[addra] <= dia;
        else     doa        <= ram[addra];
    end
```
그런데 L2 나머지 설계는 SRAM 인터페이스를 **active-LOW** 로 몬다:
- `sram_controller.sv` 주석: `// SRAM Interface (Active-Low)`, `r_ceb <= 0` (access), `1` (idle)
- `SRAM_group_decoder.sv`: `ceb_merge`/`web_merge` 가 **0 = 접근/쓰기**

→ `ram_mimic` 의 `ena` 에는 접근 시 **0** 이 들어오는데 `if (ena)` = `if (0)` →
**메모리가 write 도 read 도 안 한다.** 시뮬레이션에서 L2 내부 SRAM은 늘 `x` 를 뱉는다.
(v1 의 `x` 도 사실 이 버그 때문이었다. "초기화 안 해서" 가 아니었음.)

### 고쳐서 확인

`verif/l2/fix/ram_mimic.sv` 에 polarity 를 뒤집은 버전을 두고 (같은 모듈명, 원본 대신 include):
```verilog
    if (!ena) begin
        if (!wea) ram[addra] <= dia;
        else      doa        <= ram[addra];
    end
```
→ `12_run_l2_ch1_in_storeload_ramfix.bat` 실행 → **RESULT : PASS (5/5)**,
`o_noc_write_data` 에 `0xA5A5_0000 … 0xA5A5_0004` 가 그대로 나온다.

### 이건 "테스트벤치가 뭔가를 찾아낸" 것 — 정상적인 검증 결과다

- **원본 RTL(`rtl/L2_260901/ram_mimic.sv`)은 건드리지 않았다.** `verif/l2/fix/` 에 사본만 둠.
- 선택:
  1. `rtl/L2_260901/ram_mimic.sv` 를 active-low 로 직접 고친다 (이 모듈은 실제 SRAM 매크로의
     "흉내(mimic)" 모델이므로 sim 정합성 맞추는 건 타당). 그러면 `l2_files.f` 하나로 통일.
  2. 설계자(조민영)에게 "sim mimic enable polarity" 로 보고하고, 그때까진 `l2_files_ramfix.f` 사용.

### 파형에서 볼 것 (store → load, ramfix 버전)

`21_open_wave_sl.bat` 또는 `xsim --gui work\l2_ch1_sl_fix.wdb`:
- STEP1: `.../u_cmd_decoder_channel_1_in` 의 `current_state = 5 (BURST_STORE)`,
  `o_noc_read_valid`, `o_noc_read_addr` = 0x800.., `i_noc_read_data` = `0xA5A5_000x`,
  `o_sram_write_valid` + `o_sram_write_data` (내부 SRAM 쓰기)
- STEP2: `current_state = 3 (BURST_LOAD)`, `o_sram_read_valid`/`addr`,
  몇 클럭 뒤 `i_sram_read_data` 에 `0xA5A5_000x` 등장 (← 여기가 v1과 달라진 곳),
  `o_noc_write_data` 로 전달
