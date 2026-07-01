#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  Emacs-style key bindings for all of Windows
;  Toggle on/off:  Win+F12
;  Reload script:  Ctrl+Alt+R
;  Exit:           right-click tray icon -> Exit
; ============================================================

; Terminals are excluded: they need raw Ctrl keys (Ctrl+C, Ctrl+D)
; and PowerShell already has its own Emacs edit mode.
isTerminal() {
    for exe in [
        "WindowsTerminal.exe", "powershell.exe", "pwsh.exe",
        "cmd.exe", "conhost.exe", "wezterm-gui.exe",
        "alacritty.exe", "mintty.exe" ]
        if WinActive("ahk_exe " exe)
            return true
    return false
}

global gEnabled := true
#HotIf gEnabled && !isTerminal()

; --- cursor movement ---
^a::Send("{Home}")          ; beginning of line
^e::Send("{End}")           ; end of line
^b::Send("{Left}")          ; back one char
^f::Send("{Right}")         ; forward one char
^p::Send("{Up}")            ; previous line
^n::Send("{Down}")          ; next line
!f::Send("^{Right}")        ; Alt+f : forward one word
!b::Send("^{Left}")         ; Alt+b : back one word

; --- deleting ---
^h::Send("{BackSpace}")     ; delete char before cursor
^d::Send("{Delete}")        ; delete char under cursor
^k::Send("+{End}{Delete}")  ; kill to end of line
!d::Send("^+{Right}{Delete}") ; Alt+d : delete word forward

#HotIf

; --- control keys for the script itself ---
#F12:: {                    ; Win+F12 : toggle all bindings on/off
    global gEnabled := !gEnabled
    TrayTip("Emacs keys", gEnabled ? "ON" : "OFF", 1)
}
^!r::Reload                 ; Ctrl+Alt+R : reload this script
