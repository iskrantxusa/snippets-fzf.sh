#Requires AutoHotkey v2.0
#SingleInstance Force

; Global Windows picker. Change ^i to another AutoHotkey chord if needed.
^i::
{
    activeWindow := WinExist("A")
    picker := A_ScriptDir "\snippets.ps1"
    outputFile := A_Temp "\snippets-fzf-selection-" A_TickCount ".txt"
    command := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' picker '" pick "' outputFile '"'

    RunWait command, , "Normal"
    if !FileExist(outputFile)
        return

    selected := RTrim(FileRead(outputFile, "UTF-8"), "`r`n")
    FileDelete outputFile
    if (selected = "")
        return

    previousClipboard := ClipboardAll()
    A_Clipboard := ""
    A_Clipboard := selected
    if ClipWait(1) {
        WinActivate "ahk_id " activeWindow
        Sleep 150
        Send "^v"
        Sleep 150
    }
    A_Clipboard := previousClipboard
}
