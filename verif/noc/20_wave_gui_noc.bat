@echo off
REM  Open the NOC standalone sim in the Vivado XSim GUI (waves pre-loaded)
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou 2>nul

call xvlog --nolog -f ..\noc_files_fix.f
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_noc_fifo_intf.sv
if errorlevel 1 goto :fail
call xelab work.tb_noc_fifo_intf -s noc_gui -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail
call xsim noc_gui -gui -tclbatch ../wave_setup_noc.tcl -wdb noc_tb.wdb
exit /b 0
:fail
echo.
echo !!!!!!  build failed  !!!!!!
exit /b 1
