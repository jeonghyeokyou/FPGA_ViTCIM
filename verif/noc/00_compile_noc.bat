@echo off
REM ==========================================================
REM  NOC STEP 0 : compile + elaborate  FIFO_intf  (no TB)
REM  uses noc_files_fix.f  (3 sim fixes, originals untouched)
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

cd /d "%~dp0"
if not exist work mkdir work
cd work
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou 2>nul

echo ===== [1/2] xvlog =====
call xvlog --nolog -f ..\noc_files_fix.f
if errorlevel 1 goto :fail

echo ===== [2/2] xelab  FIFO_intf =====
call xelab work.FIFO_intf -s noc_snap -O0 --debug typical
if errorlevel 1 goto :fail

echo.
echo ############################################################
echo #  NOC STEP 0 PASSED : FIFO_intf compiles + elaborates
echo ############################################################
exit /b 0
:fail
echo.
echo !!!!!!  FAILED - read the VRFC errors above  !!!!!!
exit /b 1
