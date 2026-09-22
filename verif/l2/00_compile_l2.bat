@echo off
REM ==========================================================
REM  Phase 0 : compile + elaborate L2_260901 RTL (no testbench)
REM  Goal    : prove the RTL is syntactically clean and that
REM            every module/port/parameter resolves.
REM  Top     : TOP_L2_cache
REM ==========================================================

REM --- 1. put Vivado tools on PATH (edit version if needed) ---
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
set PATH=%XILINX_VIVADO%\bin;%PATH%

REM --- 2. go to this script's folder, make a scratch dir ------
cd /d "%~dp0"
if not exist work mkdir work
cd work

REM --- 3. clean previous run ---------------------------------
if exist xsim.dir rmdir /s /q xsim.dir
del /q *.log *.pb *.jou 2>nul

echo.
echo ===== [1/2] xvlog : analyzing SystemVerilog sources =====
call xvlog --sv --nolog -f ..\l2_files.f
if errorlevel 1 goto :fail

echo.
echo ===== [2/2] xelab : elaborating TOP_L2_cache ============
call xelab work.TOP_L2_cache -s l2_top_snap -O0 --debug typical
if errorlevel 1 goto :fail

echo.
echo ############################################################
echo #  PHASE 0 PASSED : L2 RTL compiles and elaborates clean  #
echo #  snapshot = l2_top_snap  (dir: %cd%\xsim.dir)           #
echo ############################################################
exit /b 0

:fail
echo.
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo !  PHASE 0 FAILED : read the VRFC error lines above        !
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
exit /b 1
