@echo off
REM ==========================================================
REM  Open the L2+NOC integration sim in the Vivado XSim GUI
REM  with a curated waveform already populated (STEP A / STEP B).
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou 2>nul

echo ===== xvlog : L2 (ram_mimic-fixed) =====
call xvlog --sv --nolog -f ..\..\l2\l2_files_ramfix.f
if errorlevel 1 goto :fail
echo ===== xvlog : NOC (renamed, STEP 1) =====
call xvlog --nolog -f ..\..\noc\noc_files_integ.f
if errorlevel 1 goto :fail
echo ===== xvlog : adapter (STEP 2) + testbench =====
call xvlog --sv --nolog ..\noc_ch1_in_adapter.sv
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_l2_noc_ch1_in.sv
if errorlevel 1 goto :fail

echo ===== xelab =====
call xelab work.tb_l2_noc_ch1_in -s integ_gui -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail

echo ===== xsim GUI =====
call xsim integ_gui -gui -tclbatch ../wave_setup_integ.tcl -wdb integ.wdb
exit /b 0

:fail
echo.
echo !!!!!!  build failed - read errors above  !!!!!!
exit /b 1
