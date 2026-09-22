@echo off
REM ==========================================================
REM  Phase 1 : channel-1-input functional simulation
REM  DUT top  : TOP_L2_cache        TB top : tb_l2_ch1_in
REM
REM  v1 : LOAD only, no data preload  (load data shows X - see GUIDE 5).
REM  compile -> elaborate -> run (headless) -> work\l2_ch1.wdb
REM
REM  To SEE this waveform:   cd work  &  xsim --gui l2_ch1.wdb
REM  For the STORE->LOAD demo with real data, use 30_wave_gui_storeload.bat
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
call xvlog --sv --nolog ..\tb\tb_l2_ch1_in.sv
if errorlevel 1 goto :fail

echo.
echo ===== [2/3] xelab : elaborate tb_l2_ch1_in =====
call xelab work.tb_l2_ch1_in -s l2_ch1_snap -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail

echo.
echo ===== [3/3] xsim : run and record waveform =====
call xsim l2_ch1_snap --tclbatch ../sim_log_run.tcl --wdb l2_ch1.wdb --nolog
if errorlevel 1 goto :fail

echo.
echo ############################################################
echo #  SIM DONE.
echo #  waveform DB : %cd%\l2_ch1.wdb
echo #  view:  cd work  ^&  xsim --gui l2_ch1.wdb
echo ############################################################
exit /b 0

:fail
echo.
echo !!!!!!  SIM FAILED - read the errors above  !!!!!!
exit /b 1
