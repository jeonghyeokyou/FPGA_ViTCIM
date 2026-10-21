@echo off
REM ==========================================================
REM  bb256 : 256b blackbox_ip system, PS-interface TB (T0~T9)
REM  DUT = l2_system_bd_wrapper, TB = AXI4 / AXI-Lite (BB, CMD) master
REM  result : last line "PASS (errors=0)" / "FAIL (errors=N)"
REM  usage  : 00_run_sim.bat          (no waveform)
REM           00_run_sim.bat wave     (log all signals to bb256.wdb)
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%
set TCL=../run_nowave.tcl
if /i "%1"=="wave" set TCL=../run_wave.tcl

cd /d "%~dp0"
if not exist work_sim mkdir work_sim
cd work_sim
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.wdb 2>nul

echo ===== [1/3] xvlog =====
call xvlog -sv --nolog -f ..\files_sim.f ..\..\tb\bb256_pkg.sv ..\..\tb\tb_bb256_system.sv
if errorlevel 1 goto :fail

echo ===== [2/3] xelab =====
call xelab work.tb_bb256_system -s bb256_snap -O1 --debug typical --timescale 1ns/1ps --nolog
if errorlevel 1 goto :fail

echo ===== [3/3] xsim =====
call xsim bb256_snap --tclbatch %TCL% --log bb256.log
if errorlevel 1 goto :fail

findstr /C:"PASS (errors=0)" bb256.log >nul
if errorlevel 1 goto :fail
echo.
echo ##########  bb256 : PASS   (log: %cd%\bb256.log)  ##########
exit /b 0

:fail
echo.
echo !!!!!!  bb256 : FAILED - see output above  !!!!!!
exit /b 1
