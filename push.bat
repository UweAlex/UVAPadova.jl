@echo off
chcp 65001 >nul
echo ================================================
echo UVAPadova.jl - FINAL Push Script
echo ================================================

cd /d "%~dp0"

echo.
echo 1. Alles hinzufügen...
git add .

echo.
set /p commitmsg="Commit-Nachricht (ENTER = Standard): "
if "%commitmsg%"=="" set commitmsg=Initial full upload - README.md stark verbessert

echo.
echo 2. Commit...
git commit -m "%commitmsg%"

echo.
echo 3. Branch auf main umbenennen...
git branch -M main

echo.
echo 4. Mit Remote zusammenführen...
git pull origin main --allow-unrelated-histories

echo.
echo 5. Push...
git push -u origin main

echo.
echo ================================================
echo Fertig! 
echo Schau jetzt auf https://github.com/UweAlex/UVAPadova.jl
echo ================================================
pause