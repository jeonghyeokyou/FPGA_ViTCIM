@echo off
REM ==========================================================
REM  Blackbox Phase 3 : PS-interface system top (REG, S1~S6)
REM  DUT = l2_noc_bb_bd_wrapper, TB = AXI4 / AXI-Lite master
REM  result : last line "PASS (errors=0)" / "FAIL (errors=N)"
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%
set PY=%XILINX_VIVADO%\tps\win64\python-3.8.3\python.exe

cd /d "%~dp0"

echo ===== [0/3] vectors (seed 1..4) =====
for %%s in (1 2 3 4) do (
    "%PY%" gen_vectors.py --seed %%s --out ../vectors/seed%%s
    if errorlevel 1 goto :fail
)

if not exist work_top mkdir work_top
cd work_top
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.wdb 2>nul

echo ===== [1/3] xvlog =====
call xvlog -sv --nolog -f ..\files_bb_sim.f ..\..\tb\bb_pkg.sv ..\..\tb\tb_l2_noc_bb_top.sv
if errorlevel 1 goto :fail

echo ===== [2/3] xelab =====
call xelab work.tb_l2_noc_bb_top -s bb_top_snap -O1 --debug typical --timescale 1ns/1ps --nolog
if errorlevel 1 goto :fail

echo ===== [3/3] xsim =====
call xsim bb_top_snap --tclbatch ../run_nowave.tcl --log bb_top.log
if errorlevel 1 goto :fail

findstr /C:"PASS (errors=0)" bb_top.log >nul
if errorlevel 1 goto :fail
echo.
echo ##########  Phase 3 : PASS   (log: %cd%\bb_top.log)  ##########
exit /b 0

:fail
echo.
echo !!!!!!  Phase 3 : FAILED - see output above  !!!!!!
exit /b 1
