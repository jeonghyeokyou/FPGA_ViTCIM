@echo off
REM ==========================================================
REM  Phase 1 (v2) : ch1_in  STORE -> LOAD  functional sim
REM  TB top : tb_l2_ch1_in_storeload
REM  waveform DB : work\l2_ch1_sl.wdb   (open with 21_open_wave_sl.bat)
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.vcd *.wdb 2>nul

echo ===== [1/3] xvlog : RTL + testbench =====
call xvlog --sv --nolog -f ..\l2_files.f
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_l2_ch1_in_storeload.sv
if errorlevel 1 goto :fail

echo.
echo ===== [2/3] xelab =====
call xelab work.tb_l2_ch1_in_storeload -s l2_ch1_sl_snap -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail

echo.
echo ===== [3/3] xsim : run + record waveform =====
call xsim l2_ch1_sl_snap --tclbatch ../sim_log_run.tcl --wdb l2_ch1_sl.wdb --nolog
if errorlevel 1 goto :fail

echo.
echo ############################################################
echo #  SIM DONE.  waveform DB : %cd%\l2_ch1_sl.wdb
echo #  view it:  21_open_wave_sl.bat
echo ############################################################
exit /b 0

:fail
echo.
echo !!!!!!  SIM FAILED - read the errors above  !!!!!!
exit /b 1
