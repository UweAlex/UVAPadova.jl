@echo off
chcp 65001 >nul
echo ================================================
echo UVAPadova.jl - Push Script (FINAL)
echo ================================================

cd /d "%~dp0"

echo.
echo 1. Alle Änderungen werden hinzugefügt...
git add .

echo.
set /p commitmsg="Commit-Nachricht (ENTER = Standard): "
if "%commitmsg%"=="" set commitmsg=README.md stark verbessert + Validierung und Projektstruktur aktualisiert

echo.
echo 2. Commit wird erstellt...
git commit -m "%commitmsg%"

echo.
echo 3. Branch auf main umstellen...
git branch -M main

echo.
echo 4. Remote Änderungen holen und mergen (pull)...
git pull origin main --allow-unrelated-histories

echo.
echo 5. Push auf GitHub...
git push -u origin main

echo.
echo ================================================
echo ✅ Push sollte jetzt erfolgreich sein!
echo Repository: https://github.com/UweAlex/UVAPadova.jl
echo ================================================
pause