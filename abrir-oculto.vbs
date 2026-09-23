' Abre o Claude Overlay sem piscar janela de console.
' Usado pelo atalho da area de trabalho. Equivalente ao "Claude Overlay.cmd", so que silencioso.
Dim sh, pasta
Set sh = CreateObject("WScript.Shell")
pasta = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.CurrentDirectory = pasta
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & pasta & "overlay.ps1""", 0, False
