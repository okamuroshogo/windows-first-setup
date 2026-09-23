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
gTermHwnd     := 0      ; handle of the terminal window; see FindTerminal()

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
    global gTermHwnd
    hwnd := FindTerminal()
    if (!hwnd) {
        LaunchTerminal()
        SetTitleMatchMode 3   ; exact title match only
        hwnd := WinWait(TERM_TITLE, , 10)
        if (!hwnd)
            return
        gTermHwnd := hwnd
        ShowTerminal(hwnd)
        return
    }
    ; A minimized window can stay "active" when Windows has nothing else to
    ; hand focus to, so also check it is not minimized — otherwise the next
    ; double-tap would minimize again instead of showing it.
    if (WinActive(hwnd) && WinGetMinMax(hwnd) != -1)
        HideTerminal(hwnd)
    else
        ShowTerminal(hwnd)
}

global gPrevHwnd := 0   ; window that had focus before the terminal was shown

; A Windows Terminal window is titled after its ACTIVE TAB, so as soon as a
; second tab is open in the hotkey terminal the window title is no longer
; TERM_TITLE. Looking the window up by title then reported the terminal as
; gone, LaunchTerminal() ran, and since it passes "-w hotkeyps" wt.exe dropped
; yet another tab into that very window, so every double-tap piled on one more
; tab. Remember the handle instead. The title search is kept only to re-attach
; to a terminal that outlived this script (reload / restart).
FindTerminal() {
    global gTermHwnd
    if (gTermHwnd && WinExist("ahk_id " gTermHwnd))
        return gTermHwnd
    SetTitleMatchMode 3   ; exact title match only
    return gTermHwnd := WinExist(TERM_TITLE)
}

ShowTerminal(hwnd) {
    global gPrevHwnd
    prev := WinExist("A")
    if (prev && prev != hwnd)
        gPrevHwnd := prev
    WinRestore(hwnd)
    WinActivate(hwnd)
    WinMaximize(hwnd)
    WinSetAlwaysOnTop(1, hwnd)
}

HideTerminal(hwnd) {
    WinSetAlwaysOnTop(0, hwnd)
    WinMinimize(hwnd)
    ; Explicitly move focus away so the terminal doesn't remain the
    ; foreground window while minimized.
    if (gPrevHwnd && WinExist(gPrevHwnd) && WinGetMinMax(gPrevHwnd) != -1)
        WinActivate(gPrevHwnd)
    else
        WinActivate("ahk_class Shell_TrayWnd")
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
