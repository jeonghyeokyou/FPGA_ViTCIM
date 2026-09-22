@echo off
REM ==========================================================
REM  Open the ch1_in STORE->LOAD sim in the Vivado XSim GUI
REM  with a curated waveform already populated.
REM
REM  RTL = original + verif\l2\fix\ram_mimic.sv  (polarity fix)
REM  When the GUI opens you should see the waveform up to ~760 ns.
REM  Toolbar:  Zoom Fit (F) ,  Run All to continue to $finish.
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou 2>nul

echo ===== [1/3] xvlog =====
call xvlog --sv --nolog -f ..\l2_files_ramfix.f
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_l2_ch1_in_storeload.sv
if errorlevel 1 goto :fail

echo ===== [2/3] xelab (debug all - every signal probeable) =====
call xelab work.tb_l2_ch1_in_storeload -s l2_sl_gui -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail

echo ===== [3/3] xsim GUI =====
call xsim l2_sl_gui -gui -tclbatch ../wave_setup_storeload.tcl -wdb l2_ch1_sl_fix.wdb
exit /b 0

:fail
echo.
echo !!!!!!  build failed - read errors above  !!!!!!
exit /b 1
