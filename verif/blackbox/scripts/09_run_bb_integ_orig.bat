@echo off
REM ==========================================================
REM  Blackbox Phase 2 - ORIGINAL (unfixed) RTL : reproduces the FINDINGs (S4, S6 FAIL expected)
REM  vectors -> xvlog -> xelab -> xsim  (headless)
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

if not exist work_orig mkdir work_orig
cd work_orig
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.wdb 2>nul

echo ===== [1/3] xvlog =====
call xvlog -sv --nolog -d BB_ORIG_MUX -f ..\files_bb_sim_orig.f ..\..\tb\bb_pkg.sv ..\..\tb\tb_l2_noc_bb.sv
if errorlevel 1 goto :fail

echo ===== [2/3] xelab =====
call xelab work.tb_l2_noc_bb -s bb_orig_snap -O1 --debug typical --timescale 1ns/1ps --nolog
if errorlevel 1 goto :fail

echo ===== [3/3] xsim =====
call xsim bb_orig_snap --tclbatch ../run_nowave.tcl --log bb_orig.log
if errorlevel 1 goto :fail

findstr /C:"PASS (errors=0)" bb_orig.log >nul
if errorlevel 1 goto :fail
echo.
echo ##########  Phase 2 ORIG : PASS   (log: %cd%\bb_orig.log)  ##########
exit /b 0

:fail
echo.
echo !!!!!!  Phase 2 ORIG : FAILED (expected - see FINDING_*.md) - see output above  !!!!!!
exit /b 1
