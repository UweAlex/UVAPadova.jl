@echo off
chcp 65001 >nul
echo ================================================
echo UVAPadova.jl - Push Script (korrigiert)
echo ================================================

cd /d "%~dp0"

echo.
echo 1. Alle Änderungen werden hinzugefügt...
git add .

echo.
set /p commitmsg="Commit-Nachricht (ENTER = Standard): "
if "%commitmsg%"=="" set commitmsg=README.md verbessert + Validierung und Projektbeschreibung aktualisiert

echo.
echo 2. Commit wird erstellt...
git commit -m "%commitmsg%"

echo.
echo 3. Branch-Probleme beheben (master → main)...
git branch -M main

echo.
echo 4. Push auf GitHub...
git push -u origin main

echo.
echo ================================================
echo ✅ Push abgeschlossen!
echo Repository: https://github.com/UweAlex/UVAPadova.jl
echo ================================================
pause