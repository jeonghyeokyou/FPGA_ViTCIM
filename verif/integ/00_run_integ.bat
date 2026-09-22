@echo off
REM ==========================================================
REM  Phase 2 STEP 3 : L2 + NOC end-to-end integration (ch1_in)
REM  compile -> elaborate -> run (headless) -> work\integ.wdb
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.vcd *.wdb 2>nul

echo ===== [1/4] xvlog : L2 RTL (ram_mimic-fixed) =====
call xvlog --sv --nolog -f ..\..\l2\l2_files_ramfix.f
if errorlevel 1 goto :fail

echo ===== [2/4] xvlog : NOC RTL (renamed, STEP 1) =====
call xvlog --nolog -f ..\..\noc\noc_files_integ.f
if errorlevel 1 goto :fail

echo ===== [3/4] xvlog : adapter (STEP 2) + testbench =====
call xvlog --sv --nolog ..\noc_ch1_in_adapter.sv
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_l2_noc_ch1_in.sv
if errorlevel 1 goto :fail

echo.
echo ===== [4/4] xelab + xsim =====
call xelab work.tb_l2_noc_ch1_in -s integ_snap -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail
call xsim integ_snap --tclbatch ../../l2/sim_log_run.tcl --wdb integ.wdb --nolog
if errorlevel 1 goto :fail

echo.
echo ############################################################
echo #  DONE.  waveform : %cd%\integ.wdb
echo #  view  :  10_wave_gui_integ.bat
echo ############################################################
exit /b 0

:fail
echo.
echo !!!!!!  FAILED - read the errors above  !!!!!!
exit /b 1
