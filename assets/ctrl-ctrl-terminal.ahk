#Requires AutoHotkey v2.0
#SingleInstance Force

; =============================================================================
; Ctrl double-tap -> dedicated hotkey PowerShell terminal (quake style)
; =============================================================================
;   Ctrl Ctrl (double-tap) -> show the dedicated terminal maximized + always
;                             on top. Double-tap again -> minimize to taskbar.
;   The window is identified by its exact title (TERM_TITLE), so normal
;   PowerShell / Windows Terminal windows are never touched.
;   If the shell was exited, the next double-tap relaunches it.
;
;   Note: PowerToys "Find My Mouse" also uses Ctrl double-tap by default.
;   12-configure-keyboard.ps1 disables it to avoid the conflict.
;
;   Reload script: Ctrl+Alt+R (shared convention with the other AHK scripts)
; =============================================================================

TERM_TITLE    := "HotkeyPS"
DOUBLE_TAP_MS := 350

~LControl up:: CtrlTap("LControl")
~RControl up:: CtrlTap("RControl")

CtrlTap(key) {
    static lastTap := 0
    ; If another key was pressed while Ctrl was held (Ctrl+C etc.), it is a
    ; combo, not a tap — reset so two quick combos don't trigger the toggle.
    if (A_PriorKey != key) {
        lastTap := 0
        return
    }
    if (A_TickCount - lastTap < DOUBLE_TAP_MS) {
        lastTap := 0
        ToggleTerminal()
    } else {
        lastTap := A_TickCount
    }
}

ToggleTerminal() {
    SetTitleMatchMode 3   ; exact title match only
    hwnd := WinExist(TERM_TITLE)
    if (!hwnd) {
        LaunchTerminal()
        hwnd := WinWait(TERM_TITLE, , 10)
        if (!hwnd)
            return
        ShowTerminal(hwnd)
        return
    }
    if WinActive(TERM_TITLE)
        HideTerminal(hwnd)
    else
        ShowTerminal(hwnd)
}

ShowTerminal(hwnd) {
    WinRestore(hwnd)
    WinActivate(hwnd)
    WinMaximize(hwnd)
    WinSetAlwaysOnTop(1, hwnd)
}

HideTerminal(hwnd) {
    WinSetAlwaysOnTop(0, hwnd)
    WinMinimize(hwnd)
}

LaunchTerminal() {
    pwsh  := "C:\Program Files\PowerShell\7\pwsh.exe"
    shell := FileExist(pwsh) ? pwsh : "powershell.exe"
    wt    := EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe"
    if FileExist(wt) {
        ; --suppressApplicationTitle keeps the window title fixed at TERM_TITLE
        Run Format('"{1}" -w hotkeyps --title {2} --suppressApplicationTitle "{3}"', wt, TERM_TITLE, shell)
    } else {
        Run Format('conhost.exe "{1}" -NoExit -Command "$Host.UI.RawUI.WindowTitle = `'{2}`'"', shell, TERM_TITLE)
    }
}

^!r::Reload   ; Ctrl+Alt+R : reload this script
