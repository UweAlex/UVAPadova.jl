@echo off
chcp 65001 >nul
echo ================================================
echo UVAPadova.jl - Push Script
echo ================================================

cd /d "%~dp0"

echo.
echo Aktueller Status:
git status --short

echo.
echo 1. Alle Änderungen werden hinzugefügt...
git add .

echo.
set /p commitmsg="Commit-Nachricht eingeben (ENTER = Standard-Nachricht): "

if "%commitmsg%"=="" (
    set commitmsg=README.md verbessert + Validierung und Projektbeschreibung aktualisiert
)

echo.
echo 2. Commit wird erstellt...
git commit -m "%commitmsg%"

echo.
echo 3. Push auf GitHub (main)...
git push -u origin main

echo.
echo ================================================
echo ✅ Push erfolgreich abgeschlossen!
echo Repository: https://github.com/UweAlex/UVAPadova.jl
echo ================================================
pause