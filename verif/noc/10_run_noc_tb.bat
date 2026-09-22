@echo off
REM ==========================================================
REM  NOC STEP 0 : run  tb_noc_fifo_intf  (write 5 -> read 5)
REM  headless -> work\noc_tb.wdb   (view: 20_open_wave_noc.bat)
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou *.vcd *.wdb 2>nul

echo ===== xvlog =====
call xvlog --nolog -f ..\noc_files_fix.f
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_noc_fifo_intf.sv
if errorlevel 1 goto :fail

echo ===== xelab =====
call xelab work.tb_noc_fifo_intf -s noc_tb_snap -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail

echo ===== xsim =====
call xsim noc_tb_snap --tclbatch ../../l2/sim_log_run.tcl --wdb noc_tb.wdb --nolog
if errorlevel 1 goto :fail

echo.
echo ############################################################
echo #  DONE.  waveform : %cd%\noc_tb.wdb
echo #  view :  xsim --gui noc_tb.wdb   (from this work dir)
echo ############################################################
exit /b 0
:fail
echo.
echo !!!!!!  FAILED - read errors above  !!!!!!
exit /b 1
