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
    hwnd := WinGetID("A")
    hIME := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    imeStatus := SendMessage(WM_IME_CONTROL, IMC_GETOPENSTATUS, 0, hIME)

    if (imeStatus) {
        ; IME is currently ON -> turn it OFF (alphanumeric input)
        SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, 0, hIME)
    } else {
        ; IME is currently OFF -> turn it ON and force hiragana mode
        SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, 1, hIME)
        SetIMEConversionMode(hwnd, IME_CMODE_NATIVE)
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
