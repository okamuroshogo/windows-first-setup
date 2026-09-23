#Requires AutoHotkey v2.0

; =============================================================================
; Windows / IME key bindings (single owner of the Win key)
; =============================================================================
; This script is the ONLY script that should hook the Win key. Keeping every
; Win-key behaviour in one AutoHotkey instance avoids the multi-process
; conflict that previously broke Win+Space (two instances both hooking Win).
;
;   Win+Space   -> toggle the Japanese IME (OFF = alphanumeric, ON = hiragana)
;   Ctrl+Space  -> open the Start menu
;   Win+Ctrl+[  -> previous tab (CapsLock is Ctrl, see 12-configure-keyboard.ps1)
;   Win+Ctrl+]  -> next tab
;   Win (alone) -> do nothing (does NOT open the Start menu)
;   Win + <key> -> normal Windows shortcuts still work (Win+E, Win+R, ...)
;
; Safe to reload at any time (idempotent).
; =============================================================================

#SingleInstance Force          ; Only one instance; reload replaces the old one
A_MenuMaskKey := "vkFF"        ; Suppress the Start-menu flash on Win hotkeys

; ---------------------------------------------------------------------------
; Constants for the IME messages
; ---------------------------------------------------------------------------
WM_IME_CONTROL    := 0x0283
IMC_GETOPENSTATUS := 0x0005
IMC_SETOPENSTATUS := 0x0006
IME_CMODE_NATIVE    := 0x0001   ; Japanese / native script
IME_CMODE_FULLSHAPE := 0x0008   ; full-width characters

; ---------------------------------------------------------------------------
; Win+Space  ->  Toggle IME (alphanumeric <-> hiragana)
; ---------------------------------------------------------------------------
#space::
{
    ; WinGetID / SendMessage are throwing functions: no active window, a window
    ; without an IME window (consoles), a hung window, or an elevated window
    ; (UIPI) all raise an exception. Unhandled, that pops an error dialog
    ; (usually hidden behind other windows) and the hotkey looks dead until
    ; the script is reloaded — so guard everything and always survive.
    try {
        hwnd := WinExist("A")
        if (!hwnd)
            return
        hIME := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if (!hIME)
            throw Error("window has no default IME window")
        ; timeout 500ms so a hung window can't block the hotkey for 5s (default)
        imeStatus := SendMessage(WM_IME_CONTROL, IMC_GETOPENSTATUS, 0, hIME, , , , , 500)
        if (imeStatus) {
            ; IME is currently ON -> turn it OFF (alphanumeric input)
            SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, 0, hIME, , , , , 500)
        } else {
            ; IME is currently OFF -> turn it ON and force hiragana mode
            SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, 1, hIME, , , , , 500)
            SetIMEConversionMode(hwnd, IME_CMODE_NATIVE)
        }
    } catch {
        ; Windows the IMM API cannot reach: fall back to the hankaku/zenkaku
        ; key (sc029), which toggles the IME the native way. Send releases the
        ; held Win modifier automatically, so this is not sent as Win+sc029.
        Send "{sc029}"
    }
}

; ---------------------------------------------------------------------------
; Ctrl+Space  ->  Open the Start menu
; ---------------------------------------------------------------------------
;   Ctrl+Esc is the Windows built-in "open Start" shortcut. Sending {LWin}
;   would be auto-masked by AHK and would not open the menu, so use Ctrl+Esc.
^Space::Send "^{Esc}"

; ---------------------------------------------------------------------------
; Win (alone)  ->  do NOT open the Start menu (combos still work)
; ---------------------------------------------------------------------------
;   Inject a dummy key (vkFF = unassigned) on Win key-down so that releasing
;   Win by itself is not seen as a lone Win press. The `~` prefix keeps the
;   native Win modifier active, so Win+E / Win+R / Win+Space still work.
~LWin::Send "{Blind}{vkFF}"
~RWin::Send "{Blind}{vkFF}"


; ---------------------------------------------------------------------------
; Win+Ctrl+[ / ]  ->  previous / next tab, in whatever app is in front
; ---------------------------------------------------------------------------
;   CapsLock is remapped to left Ctrl by the Scancode Map, so in practice this
;   is Win + CapsLock + [ / ].
;
;   Every app spells "next tab" differently, so the hotkey only provides the
;   trigger: TabSwitch() looks up the active window's exe and sends that app's
;   own shortcut. Unknown apps fall back to Ctrl+Tab / Ctrl+Shift+Tab, which is
;   what most tabbed Windows apps use.
;
;   Scancodes (not the characters "[" / "]") are used so the hotkey is immune
;   to the IME state. sc01A / sc01B are the two keys right of P on a US
;   keyboard, matching HardwareKeyboardLayout = "US" in config\local.psd1.
;   On a JIS 106/109 board they would be sc01B / sc02B instead.
;
;   To add an app: run "C:\Program Files\AutoHotkey\WindowSpy.ahk", read the exe
;   name off the active window and add a lowercase entry below. To apply, just
;   re-run this file -- #SingleInstance Force replaces the running copy. (There
;   is deliberately no Ctrl+Alt+R here: emacs-keys.ahk already owns that.)
; ---------------------------------------------------------------------------

#^sc01A::TabSwitch(1)   ; Win+Ctrl+[ : previous tab
#^sc01B::TabSwitch(2)   ; Win+Ctrl+] : next tab

TabSwitch(dir) {
    ; [prev, next] per exe. Keys are lowercase; the lookup lowercases too.
    static apps := Map(
        ; browsers: Ctrl+PgUp/PgDn walks tabs in order, while Ctrl+Tab is
        ; most-recently-used in some of them (repeated presses bounce)
        "chrome.exe",           ["^{PgUp}", "^{PgDn}"],
        "msedge.exe",           ["^{PgUp}", "^{PgDn}"],
        "firefox.exe",          ["^{PgUp}", "^{PgDn}"],
        "brave.exe",            ["^{PgUp}", "^{PgDn}"],
        "vivaldi.exe",          ["^{PgUp}", "^{PgDn}"],
        ; editors: Ctrl+PgUp/PgDn is previous/next editor
        "cursor.exe",           ["^{PgUp}", "^{PgDn}"],
        "code.exe",             ["^{PgUp}", "^{PgDn}"],
        "code - insiders.exe",  ["^{PgUp}", "^{PgDn}"],
        "windsurf.exe",         ["^{PgUp}", "^{PgDn}"],
        "obsidian.exe",         ["^{PgUp}", "^{PgDn}"],
        ; terminals: Ctrl+Tab is Windows Terminal's own nextTab
        "windowsterminal.exe",  ["^+{Tab}", "^{Tab}"],
        "openconsole.exe",      ["^+{Tab}", "^{Tab}"],
        "wezterm-gui.exe",      ["^+{Tab}", "^{Tab}"],
        ; shell / built-ins
        "explorer.exe",         ["^+{Tab}", "^{Tab}"],
        "notepad.exe",          ["^+{Tab}", "^{Tab}"])
    static fallback := ["^+{Tab}", "^{Tab}"]

    ; WinGetProcessName throws when there is no active window, or when the
    ; window belongs to an elevated process (UIPI). Unhandled that pops an
    ; error dialog and the hotkey looks dead, so fall through to the default.
    exe := ""
    try exe := StrLower(WinGetProcessName("A"))

    keys := apps.Has(exe) ? apps[exe] : fallback
    ; Send releases the physically-held Win by itself, so this goes out as a
    ; plain Ctrl+<key> and not as Win+Ctrl+<key>.
    Send keys[dir]
}
; ---------------------------------------------------------------------------
; Helper: set the IME conversion mode for a given window
; ---------------------------------------------------------------------------
SetIMEConversionMode(hwnd, mode) {
    hIMC := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if (!hIMC)
        return

    convMode := 0
    sentMode := 0
    DllCall("imm32\ImmGetConversionStatus", "Ptr", hIMC
        , "UInt*", &convMode
        , "UInt*", &sentMode)

    DllCall("imm32\ImmSetConversionStatus", "Ptr", hIMC
        , "UInt", mode
        , "UInt", sentMode)

    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", hIMC)
}
