@echo off
REM  Open the ch1_wgt integration sim in the Vivado XSim GUI (waves pre-loaded)
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou 2>nul

call xvlog --sv --nolog -f ..\..\l2\l2_files_ramfix.f
if errorlevel 1 goto :fail
call xvlog --nolog -f ..\..\noc\noc_files_integ.f
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\noc_ch1_wgt_adapter.sv
if errorlevel 1 goto :fail
call xvlog --sv --nolog ..\tb\tb_l2_noc_ch1_wgt.sv
if errorlevel 1 goto :fail

call xelab work.tb_l2_noc_ch1_wgt -s integ_wgt_gui -O0 --debug all --timescale 1ns/1ps
if errorlevel 1 goto :fail

call xsim integ_wgt_gui -gui -tclbatch ../wave_setup_integ_wgt.tcl -wdb integ_wgt.wdb
exit /b 0

:fail
echo.
echo !!!!!!  build failed - read errors above  !!!!!!
exit /b 1
