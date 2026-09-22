# 검증 이슈 보고 : `ram_mimic` chip/write enable polarity 불일치

| 항목 | 내용 |
|---|---|
| 파일 | `rtl/L2_260901/ram_mimic.sv` |
| 심각도 | High (시뮬레이션에서 L2 내부 SRAM 전체가 기능 정지) |
| 발견 경위 | L2 단독 기능검증 Phase 1 — `ch1_in` store→load 왕복 테스트 |
| 발견일 | 2026-09-02 |
| 검증 환경 | Vivado 2024.2 XSim, `TOP_L2_cache` (default params) |

---

## 1. 증상

`ch1_in` load 커맨드 실행 시 `o_noc_write_data_channel_1_in` 이 항상 `x`.
store 로 L2 내부 SRAM 에 데이터를 먼저 써 넣어도, 이어지는 load 가 `x` 를 읽음.
→ 시뮬레이션상 L2 내부 SRAM 이 **write / read 를 전혀 수행하지 않음.**

## 2. 원인

`ram_mimic.sv` 의 메모리 동작:

```verilog
always @(posedge clka) begin
    if (ena) begin              // active-HIGH 로 해석
        if (wea) ram[addra] <= dia;
        else     doa        <= ram[addra];
    end
end
```

그러나 상위 설계는 SRAM 인터페이스를 **active-LOW** 로 구동:

- `sram_controller.sv` L43 주석 `// SRAM Interface (Active-Low)`,
  L122/127 `r_ceb <= ... ? 1'b0 : 1'b1;` (접근 시 0)
- `SRAM_group_decoder.sv` L136-137, L199-200 :
  `ceb_merge` / `web_merge` = **0 일 때 접근 / write**
- `SRAM_group.sv` L30-31 : `ceb_merge`/`web_merge` 를 그대로 `ram_mimic.ena`/`.wea` 로 전달

결과적으로 `ram_mimic` 의 `ena` 에는 **접근 시 0** 이 인가되는데
`if (ena)` = `if (1'b0)` 이므로 항상 no-operation.

## 3. 재현

```
verif/l2/11_run_l2_ch1_in_storeload.bat   →  RESULT : CHECK (load 5/5 mismatch, 값 = x)
verif/l2/12_run_l2_ch1_in_storeload_ramfix.bat  →  RESULT : PASS  (5/5)
```
`12_` 는 `verif/l2/fix/ram_mimic.sv` (polarity 만 수정) 를 원본 대신 사용.

## 4. 제안 수정 (`ram_mimic.sv`)

```verilog
always @(posedge clka) begin
    if (!ena) begin                     // active-low chip enable
        if (!wea) ram[addra] <= dia;    // active-low write enable
        else      doa        <= ram[addra];
    end
end
```

## 5. 영향 범위

- `ram_mimic` 은 `SRAM_group` 에서만 인스턴스화되고, `SRAM_group` 은
  `SRAM_group_decoder` 에서만 사용됨. 폴러티 수정의 부작용 없음.
- 합성 시 실제 SRAM 매크로로 대체된다면 이 mimic 은 sim 전용이므로
  RTL 기능/타이밍에는 영향 없음. **단, 현재 상태로는 어떤 L2 기능 시뮬레이션도
  내부 SRAM 을 검증할 수 없음.**
- NOC_260902 의 `sram_mimic.v` 는 polarity 는 올바름(`i_ceb==0 && i_web==0` write /
  `==1` read). **다만 별개 이슈**: L29 `input wire [BIT_WIDTH-1:0] o_dout` 가
  `input` 으로 선언됨 (→ `output` 이어야 함). L43 `assign o_dout = r_dout;` 가
  input port 에 대입 → `L1_Cache_Mimic` 의 read data 가 구동되지 않음.
  NOC 쪽 Phase 0/1 진행 시 별도 처리 필요.
