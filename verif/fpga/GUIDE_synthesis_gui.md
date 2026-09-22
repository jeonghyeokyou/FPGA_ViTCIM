# Vivado GUI로 직접 합성해보기 — 초보자 가이드

`build_synth.tcl` 이 자동으로 하던 것과 **똑같은 일**을, 이번엔 Vivado를 열어서
마우스로 하나씩 눌러가며 직접 해봅니다. 목표는 "됐다/안됐다"가 아니라
**각 단계에서 Vivado가 뭘 하는지 눈으로 보는 것**입니다.

---

## 0. 미리 알아둘 것

- 새로 만드는 프로젝트는 `verif/fpga/vivado_proj/` 안에 저장할 겁니다 (기존 `build/` 결과물과는 별개).
- 추가할 소스 파일 "정답 목록"은 이미 정리되어 있습니다 → [fpga_files.f](fpga_files.f)
  파일을 열어서 보면 총 48개 파일이 나열되어 있는데, **이게 오늘 프로젝트에 추가할 파일 전부**입니다.
- **원본 폴더 파일 중에 절대 넣으면 안 되는 것들**이 있습니다 (fix 사본으로 대체해야 함):
  - ❌ `rtl/L2_260901/ram_mimic.sv` → ⭕ `verif/l2/fix/ram_mimic.sv` 대신 넣기
  - ❌ `rtl/NOC_260902/sram_mimic.v` → ⭕ `verif/fpga/fpga_fix/sram_mimic_fpga.v` 대신 넣기
  - ❌ `rtl/NOC_260902/FIFO.v`, `FIFO_modified.v`, `FIFO_interface_handshake.v`,
    `FIFO_interface_on_fire.v`, `FIFO_interface.v`, `sram_controller.v`
    → ⭕ `verif/noc/rename/noc_*.v` (이름 앞에 `noc_` 붙은 사본) 대신 넣기
  - ❌ `rtl/NOC_260902/L1_FIFO_interface_on_fire.v`, `L1_Cache_Mimic.v`
    → ⭕ `verif/noc/rename/` 안의 동명 파일(내부만 수정된 사본) 대신 넣기
  - ⭕ `rtl/NOC_260902/L1_FIFO_interface.v`, `L1_FIFO_interface_handshake.v` 는
    수정 안 됐으니 원본 그대로 넣으면 됩니다.

  헷갈리면 그냥 **[fpga_files.f](fpga_files.f)에 적힌 경로 48개를 한 줄씩 그대로** 추가하면 됩니다 —
  이미 정답만 골라놓은 목록입니다.

---

## 1. Vivado 실행 + 새 프로젝트 만들기

1. Vivado 2024.2를 실행합니다 (시작 화면 "Quick Start" → **Create Project**).
2. 마법사 진행:
   - Project name: `l2_noc_fpga_synth`
   - Project location: `C:\RTL_YJH\L2_verification\verif\fpga\vivado_proj`
   - Project type: **RTL Project** 선택, 이번엔 **"Do not specify sources at this time"를 체크**해서
     Add Sources/Add Constraints 화면을 그냥 건너뜁니다 (48개 파일을 이 마법사에서 하나씩
     추가하는 대신, 다음 단계에서 Tcl Console로 한 번에 넣을 것이기 때문).
3. "Default Part" 화면에서:
   - 상단 탭을 **Parts**로 선택 (Boards 탭 아님 — 지금까지 검증한 게 정확히 이 파트 번호라서 그대로 맞춥니다)
   - 검색창에 `xczu9eg-ffvb1156-2-e` 입력 → 선택
4. **Finish** 눌러서 마법사를 끝냅니다. 소스가 하나도 없는 빈 프로젝트가 열립니다.

## 2. 파일 48개 한 번에 추가하기 (Tcl Console)

Vivado 창 맨 아래에 **Tcl Console** 탭이 있습니다 (없으면 상단 메뉴
**Window → Tcl Console**). 거기 클릭해서 아래 내용을 통째로 복사해 붙여넣고 Enter:

```tcl
set fh [open {C:/RTL_YJH/L2_verification/verif/fpga/fpga_files.f} r]
set flist {}
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    lappend flist $line
}
close $fh
add_files -norecurse $flist
add_files -fileset constrs_1 -norecurse {C:/RTL_YJH/L2_verification/verif/fpga/constraints.xdc}
set_property top l2_noc_fpga_top [current_fileset]
update_compile_order -fileset sources_1
```

이 명령이 하는 일은 **딱 "파일 추가" 그 자체**입니다 — 합성/구현은 전혀 안 건드립니다.
`fpga_files.f`에 이미 적혀 있는 48개 경로(원본 33개 + fix/rename 사본들)를 한 줄씩 읽어서
`add_files`로 넣고, constraints 파일도 넣고, top 모듈을 지정하는 것뿐입니다. 이후 과정
(Run Synthesis 클릭, 리포트 열어보기 등)은 전부 지금까지처럼 마우스로 진행합니다.

붙여넣고 나면 왼쪽 **Sources** 패널을 펼쳐서 `l2_noc_fpga_top`이 굵은 글씨(top으로 지정됨)로
보이는지, 파일들이 다 들어왔는지 확인하세요.

## 3. Synthesis 실행 — 진짜 "합성" 버튼

왼쪽 **Flow Navigator** 패널에서 **SYNTHESIS → Run Synthesis** 클릭.
- "Launch Runs" 팝업이 뜨면 기본값(Number of jobs 등) 그대로 두고 **OK**.
- 오른쪽 위 진행 표시줄이 도는 동안 기다립니다 (RTL을 게이트 단위 네트리스트로 바꾸는 중).

끝나면 **"Synthesis Completed"** 팝업이 뜹니다. 여기서:
- **Open Synthesized Design** → 합성된 회로를 실제로 볼 수 있음 (Schematic 메뉴로 구조 확인 가능)
- 팝업을 닫고 아래쪽 **Messages** 탭을 확인 — `ram_style = "ultra"` 관련 경고 17개가
  여기 보이면 정상입니다 (ZU9EG엔 UltraRAM이 없어서 자동으로 BRAM으로 대체된다는 뜻, 에러 아님).

## 4. 리포트 직접 열어보기

Synthesis가 끝나면 아래쪽 **Reports** 탭에 리포트 목록이 생깁니다. 더블클릭해서 열어보세요:
- **Report Utilization** — LUT/FF/BRAM 등 자원 사용량 표 (참고값: LUT 17%, FF 5.8%, BRAM 17.3%, DSP 0%)
- **Report Timing Summary** — 타이밍 (아직 배치/배선 전이라 추정치)

없으면 상단 메뉴 **Reports → Report Utilization / Report Timing Summary**로 직접 생성할 수 있습니다.

## 5. Implementation 실행 — 배치 + 배선

Flow Navigator → **IMPLEMENTATION → Run Implementation** 클릭.
(이 한 번의 클릭이 `opt_design` → `place_design` → `route_design` 세 단계를 순서대로 다 해줍니다.)

끝나면 팝업에서 **Open Implemented Design** 선택 가능. 이제:
- **Report Timing Summary**를 다시 열어보면 이번엔 실제 배선 지연이 반영된 진짜 숫자가 나옵니다
  (참고값: WNS +3.117ns — 양수면 타이밍 만족).
- 상단 메뉴 **Tools → Report → Report DRC...** 로 DRC 체크 — Critical Warning 2건
  (`NSTD-1`, `UCIO-1`, 핀 미지정) 나오면 정상입니다. 실제 보드 핀맵을 XDC에 채우기 전까지는
  항상 나오는 경고이고, `write_bitstream`(최종 파일 생성) 단계만 막습니다.

## 6. 여기서 멈추기

`Generate Bitstream`은 누르지 않아도 됩니다 — 아직 ZCU102 실물 핀맵이 없어서 어차피
DRC에서 막힙니다. 지금 목표(자원/타이밍 확인)는 Implementation까지로 충분합니다.

---

## 10. 실제 ZCU102 핀에 연결하기 (다음 단계)

지금까지는 클럭/리셋/LED 핀이 하나도 안 정해진 "추상적인" 버전이었습니다. 실제로 보드에
올리려면 `l2_noc_fpga_top`을 감싸는 보드 전용 래퍼가 하나 더 필요합니다 — 이미 만들어
놨습니다: [zcu102_wrapper.sv](zcu102_wrapper.sv) + [constraints_zcu102.xdc](constraints_zcu102.xdc).

**핀 값의 출처**: 사용자가 직접 다운로드한 실제 마스터 XDC
(`C:/RTL_YJH/FPGA_ZCU102/zcu102-schematic-xtp454_cluster/zcu102-xdc-rdf0405/zcu102_Rev1.0_U1_09152016.xdc`)와
Vivado에 이미 설치된 board part(`xilinx.com:zcu102:part0:3.4`)의 `part0_pins.xml`,
두 군데에서 뽑은 값이 완전히 일치함을 교차검증했습니다 (AG14/AF13/AE13/AJ14/AJ15,
AM13, AL8/AL7). `constraints_zcu102.xdc`는 그 마스터 XDC의 해당 줄들을 그대로
가져온 것입니다.

**왜 그냥 핀만 꽂으면 안 되는지**: 값은 정확해도, 그대로 못 꽂는 이유가 2개 있었습니다:
1. 리셋 버튼 `CPU_RESET`은 **active-high**인데 우리 top은 `i_rst_n`(active-**low**) 규칙 → 반전 필요
2. PL이 쓸 수 있는 유일한 클럭이 **300MHz 차동(differential)** 클럭(`USER_SI570_P/N`)이라
   단일 100MHz `i_clk`에 바로 못 물림 → Clocking Wizard IP(300→100MHz 변환)가 하나 더 필요

`zcu102_wrapper.sv`가 이 두 가지를 처리해서 `l2_noc_fpga_top`(검증 끝난 회로, 무수정)을 그대로 감쌉니다.

### 10-1. Clocking Wizard IP 만들기 (GUI)

1. 새 프로젝트를 만들 때(또는 기존 프로젝트에서) **Project Settings → General → Board Part**을
   "Zynq UltraScale+ ZCU102 Evaluation Board" (rev 3.4)로 지정합니다 — 이걸 해야 IP 설정
   화면에서 보드 클럭을 자동으로 골라줍니다.
2. Flow Navigator → **IP Catalog** → 검색창에 `Clocking Wizard` 입력 → 더블클릭.
3. IP 설정 창:
   - **Board** 탭(있으면) → Input Clock을 `user_si570_sysclk`(=USER_SI570_P/N) 선택 → 300MHz, 차동으로 자동 채워짐
   - **Output Clocks** 탭 → `clk_out1` 주파수를 `100` (MHz)로 설정
   - **Component Name**을 `clk_wiz_0` 으로 맞춥니다 (래퍼 코드가 이 이름을 그대로 인스턴스화하기 때문)
4. **OK** → **Generate** (또는 나중에 synthesis 때 자동 생성되도록 둬도 됨).

### 10-2. 소스/제약 추가

Tcl Console에:
```tcl
add_files -norecurse {C:/RTL_YJH/L2_verification/verif/fpga/zcu102_wrapper.sv}
add_files -fileset constrs_1 -norecurse {C:/RTL_YJH/L2_verification/verif/fpga/constraints_zcu102.xdc}
set_property top zcu102_wrapper [current_fileset]
```
(기존 `constraints.xdc`는 그대로 두고, 이번엔 `constraints_zcu102.xdc`를 추가로 넣는 것 — 둘 다
활성화돼 있으면 충돌하니 기존 것은 fileset에서 disable 하거나 remove 하세요: Sources 패널에서
`constraints.xdc` 우클릭 → Disable File.)

### 10-3. Synthesis/Implementation 재실행

Top이 `zcu102_wrapper`로 바뀌었으니 **Run Synthesis** → **Run Implementation**을 다시 클릭.
DRC(`Report DRC`)에서 이번엔 NSTD-1/UCIO-1이 사라져야 정상입니다 (핀이 다 채워졌으므로).

### 10-4. Bitstream + 실제 보드

- **Generate Bitstream** 클릭
- ZCU102를 USB(JTAG) 케이블로 PC에 연결하고 전원 켬
- Flow Navigator → **Open Hardware Manager** → Open Target → Auto Connect → Program Device
  → 방금 만든 `.bit` 선택
- 프로그래밍되는 순간부터 회로가 바로 동작 (PS/소프트웨어 부팅 절차 없음, 순수 PL 로직)
- `GPIO_LED_0/1` (done/pass) 켜지는지, `GPIO_LED_2~4`로 mismatch_count 3비트 읽기

**참고**: 이 이후 단계(실제 케이블 연결, 전원, LED 육안 확인)는 물리적 보드가 있어야 해서
저는 여기까지만 같이 준비할 수 있습니다. 진행하다 IP 설정 화면이 다르게 보이거나 에러 나면
캡처해서 알려주세요.

---

## 다음에 또 열 때

Vivado 시작 화면에서 **Open Project** → `verif/fpga/vivado_proj/l2_noc_fpga_synth.xpr`
선택하면 소스 추가부터 다시 안 해도 이어서 볼 수 있습니다.
