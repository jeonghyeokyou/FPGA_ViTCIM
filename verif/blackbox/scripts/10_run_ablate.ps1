# =============================================================================
#  10_run_ablate.ps1  -  수정 하나씩 되돌려 보기 (FIX_SUMMARY.md "하나씩 빼 본 실험")
#
#  각 줄 = (되돌린 수정, 돌릴 테스트 묶음). 결과로 실패한 테스트 이름을 출력한다.
#    orig     : 수정 전 조합 전체 (files_bb_sim_orig.f + -d BB_ORIG_MUX)
#    wgt_noC  : rtl/fix/cmd_decoder_channel_1_wgt.sv 의 (C) 를 원래대로
#    c2_noE1/2/3 : rtl/fix/cmd_decoder_channel_2_in.sv 의 (E1)/(E2)/(E3) 를 원래대로
#  실행: powershell -ExecutionPolicy Bypass -File 10_run_ablate.ps1   (scripts 폴더에서, 약 15분)
#  작업 폴더 work_ab_*, 변형 파일은 work_ablate\ 에 만든다 (둘 다 .gitignore).
# =============================================================================
$ErrorActionPreference = "Continue"
$env:PATH = "C:\Xilinx\Vivado\2024.2\bin;" + $env:PATH
$S   = Split-Path -Parent $MyInvocation.MyCommand.Path
$A   = Join-Path $S "work_ablate"
$FIX = (Resolve-Path (Join-Path $S "..\rtl\fix")).Path
New-Item -ItemType Directory -Force $A | Out-Null

# ---- one-fix-reverted variants of the fixed copies ---------------------------------
function Make-Variant($name, $src, $from, $to) {
    $txt = [IO.File]::ReadAllText((Join-Path $FIX $src))
    if (-not $txt.Contains($from)) { throw "pattern not found for $name" }
    [IO.File]::WriteAllText((Join-Path $A "$name.sv"), $txt.Replace($from, $to))
}
Make-Variant "wgt_noC" "cmd_decoder_channel_1_wgt.sv" `
    "assign o_sram_control_mode= 1'b0;" "assign o_sram_control_mode= r_control_mode[0];"
Make-Variant "c2_noE1" "cmd_decoder_channel_2_in.sv" `
    "assign o_sram_control_mode    = 1'b0;" "assign o_sram_control_mode    = r_control_mode[0];"
Make-Variant "c2_noE2" "cmd_decoder_channel_2_in.sv" `
    "if(r_sram_write_done==1'b1) begin   // FIX (E2)" "if(1'b0) begin   // (E2 reverted)"
# (E4) removed the store-state gating, so reverting E3 = put back the BURST_STORE-only gate
Make-Variant "c2_noE3" "cmd_decoder_channel_2_in.sv" `
    "assign w_fifo_sram_write_addr_17b_1 = w_width+w_height*r_data_width+w_channel*r_data_channel;" `
    "assign w_fifo_sram_write_addr_17b_1 = (current_state==BURST_STORE) ? w_width+w_height*r_data_width+w_channel*r_data_channel : 17'd0;"

$runs = @(
  @{n="orig";    only="W"; list="$S\files_bb_sim_orig.f"; def="-d BB_ORIG_MUX"},
  @{n="orig";    only="O"; list="$S\files_bb_sim_orig.f"; def="-d BB_ORIG_MUX"},
  @{n="wgt_noC"; only="W"; sub="cmd_decoder_channel_1_wgt.sv"},
  @{n="c2_noE1"; only="O"; sub="cmd_decoder_channel_2_in.sv"},
  @{n="c2_noE2"; only="O"; sub="cmd_decoder_channel_2_in.sv"},
  @{n="c2_noE3"; only="O"; sub="cmd_decoder_channel_2_in.sv"}
)
foreach ($r in $runs) {
  # same depth as work_integ : the TB opens ../../vectors
  $d = "$S\work_ab_$($r.n)_$($r.only)"; New-Item -ItemType Directory -Force $d | Out-Null; Set-Location $d
  if ($r.sub) {
    (Get-Content "$S\files_bb_sim.f") | ForEach-Object {
        if ($_ -like "*rtl/fix/$($r.sub)") { (Join-Path $A "$($r.n).sv") -replace '\\','/' } else { $_ } } |
        Set-Content -Encoding ascii list.f
    $list = "list.f"; $def = ""
  } else { $list = $r.list; $def = $r.def }
  cmd /c "xvlog -sv --nolog $def -f $list ..\..\tb\bb_pkg.sv ..\..\tb\tb_l2_noc_bb.sv" | Select-String "ERROR"
  cmd /c "xelab work.tb_l2_noc_bb -s s -O1 --timescale 1ns/1ps --nolog" | Select-String "ERROR"
  cmd /c "xsim s --testplusarg `"ONLY=$($r.only)`" --tclbatch ../run_nowave.tcl --log r.log" | Out-Null
  $fails = (Select-String -Path r.log -Pattern "\| FAIL \|" | ForEach-Object { ($_.Line -split '\|')[0].Trim() }) -join ', '
  $tot = (Select-String -Path r.log -Pattern "PASS \d+ / FAIL \d+").Line
  "{0,-9} ONLY={1} : {2}   FAIL: {3}" -f $r.n, $r.only, $tot.Trim(), $fails
}
Set-Location $S
