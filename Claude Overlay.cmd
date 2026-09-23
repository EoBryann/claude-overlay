@echo off
rem Abre o Claude Overlay sem janela de console. Para abrir com o Windows, crie um atalho deste .cmd em shell:startup.
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0overlay.ps1"
