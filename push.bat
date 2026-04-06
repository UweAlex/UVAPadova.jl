@echo off
chcp 65001 >nul
echo ================================================
echo UVAPadova.jl - Git Setup + Push
echo ================================================

cd /d "%~dp0"

:: Prüfen, ob es schon ein Git-Repository ist
if not exist ".git" (
    echo.
    echo Dies ist das erste Mal. Git-Repository wird initialisiert...
    git init
    echo.
)

echo.
echo 1. Alle Änderungen werden hinzugefügt...
git add .

echo.
echo 2. Commit wird erstellt...
git commit -m "README.md stark verbessert + Validierungsergebnisse aktualisiert" 2>nul || (
    echo Keine neuen Änderungen oder bereits committet.
)

echo.
set /p remoteurl="GitHub-Repository-URL eingeben (z.B. https://github.com/deinname/UVAPadova.jl.git): "

if not "%remoteurl%"=="" (
    git remote remove origin 2>nul
    git remote add origin %remoteurl%
    echo Remote 'origin' auf %remoteurl% gesetzt.
)

echo.
echo 3. Push auf GitHub...
git push -u origin master 2>nul || git push -u origin main

echo.
echo ================================================
echo ✅ Fertig!
echo ================================================
pause