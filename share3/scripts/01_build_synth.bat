@echo off
REM ==========================================================
REM  share3 (bb256) : OOC synthesis + place + route, ZCU102
REM  usage : 01_build_synth.bat            (100 MHz              -> build\)
REM          01_build_synth.bat 200        (200 MHz              -> build_200MHz\)
REM          01_build_synth.bat 200u       (200 MHz + 0.15 ns    -> build_200MHz_u150\)
REM  result : build*\timing_route.rpt (WNS), util_route.rpt, ram_route.rpt   (~20 min each)
REM ==========================================================
set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
cd /d "%~dp0"

set OUT=build
set ARGS=
if "%1"=="200"  set OUT=build_200MHz
if "%1"=="200"  set ARGS=-tclargs 5.0
if "%1"=="200u" set OUT=build_200MHz_u150
if "%1"=="200u" set ARGS=-tclargs 5.0 0.15

if not exist %OUT% mkdir %OUT%
call "%XILINX_VIVADO%\bin\vivado.bat" -mode batch -source build_synth.tcl -log %OUT%\vivado.log -journal %OUT%\vivado.jou %ARGS%
