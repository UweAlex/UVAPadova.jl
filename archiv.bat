@echo off
setlocal enabledelayedexpansion

echo Erstelle archiv.txt ...
> archiv.txt (
    for /r %%F in (*.*) do (
        set "fname=%%~nxF"
        set "dirpath=%%~dpF"
        
        REM === Ausschluss von Ordnern, die mit einem Punkt beginnen (z. B. .git, .vscode, .idea, __pycache__ usw.) ===
        if "!dirpath:\.=!" == "!dirpath!" (
            
            REM Nur Dateien verarbeiten, die nicht archiv.bat oder archiv.txt heißen
            if /i not "!fname!"=="archiv.bat" if /i not "!fname!"=="archiv.txt" (
                
                echo.
                echo ========================================================
                echo === Datei: %%F ===
                echo ========================================================
                echo.
                
                REM Nur .md und .jl komplett ausgeben – alles andere nur als "vorhanden" listen
                if /i "%%~xF"==".md" (
                    type "%%F"
                ) else if /i "%%~xF"==".jl" (
                    type "%%F"
                ) else (
                    echo [Nur als vorhanden gelistet - Inhalt wird nicht angezeigt]
                )
                
                echo.
                echo ========================================================
                echo.
            )
        )
    )
)

echo.
echo Fertig! archiv.txt wurde erstellt.
pause