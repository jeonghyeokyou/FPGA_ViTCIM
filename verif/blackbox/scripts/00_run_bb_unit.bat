@echo off
REM ==========================================================
REM  Blackbox Phase 1 : blackbox_pe unit test (U1~U7)
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

if not exist work_unit mkdir work_unit
cd work_unit
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.wdb 2>nul

echo ===== [1/3] xvlog =====
call xvlog -sv --nolog -f ..\files_bb_unit.f
if errorlevel 1 goto :fail

echo ===== [2/3] xelab =====
call xelab work.tb_blackbox_pe -s bb_unit_snap -O0 --debug typical --timescale 1ns/1ps --nolog
if errorlevel 1 goto :fail

echo ===== [3/3] xsim =====
call xsim bb_unit_snap --tclbatch ../run_all.tcl --wdb bb_unit.wdb --log bb_unit.log
if errorlevel 1 goto :fail

findstr /C:"PASS (errors=0)" bb_unit.log >nul
if errorlevel 1 goto :fail
echo.
echo ##########  Phase 1 : PASS   (log: %cd%\bb_unit.log)  ##########
exit /b 0

:fail
echo.
echo !!!!!!  Phase 1 : FAILED - see output above  !!!!!!
exit /b 1
