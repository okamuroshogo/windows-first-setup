#Requires AutoHotkey v2.0

; =============================================================================
; Win+Space IME Toggle Script
; =============================================================================
; Overrides Win+Space to toggle the Japanese IME on and off.
;   - IME OFF: alphanumeric (direct) input
;   - IME ON:  hiragana input
;
; This replaces the default Windows Win+Space language-switcher behaviour with
; a single-key toggle that is faster and more predictable for daily use.
;
; Safe to reload at any time (idempotent).
; =============================================================================

; ---------------------------------------------------------------------------
; Script settings
; ---------------------------------------------------------------------------
#SingleInstance Force          ; Only one instance; reload replaces the old one
A_MenuMaskKey := "vkFF"       ; Suppress the Start-menu flash on Win hotkeys

; ---------------------------------------------------------------------------
; Constants for the IME messages
; ---------------------------------------------------------------------------

; WM_IME_CONTROL message
WM_IME_CONTROL := 0x0283

; IMC_GETOPENSTATUS / IMC_SETOPENSTATUS sub-commands
IMC_GETOPENSTATUS := 0x0005
IMC_SETOPENSTATUS := 0x0006

; WM_IME_NOTIFY and its sub-command for conversion mode
WM_IME_NOTIFY := 0x0282

; IME conversion-mode constants (used with ImmSetConversionStatus)
IME_CMODE_NATIVE    := 0x0001   ; Japanese / native script
IME_CMODE_FULLSHAPE := 0x0008   ; full-width characters

; ---------------------------------------------------------------------------
; Hotkey: Win+Space  ->  Toggle IME
; ---------------------------------------------------------------------------
#space::
{
    ; Get the handle of the currently focused window / control
    hwnd := WinGetID("A")

    ; Get the default IME window for the target window
    hIME := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")

    ; Query the current open/closed state of the IME
    imeStatus := SendMessage(WM_IME_CONTROL, IMC_GETOPENSTATUS, 0, hIME)

    if (imeStatus) {
        ; IME is currently ON -> turn it OFF (alphanumeric input)
        SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, 0, hIME)
    } else {
        ; IME is currently OFF -> turn it ON
        SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, 1, hIME)

        ; After opening the IME, force hiragana mode by setting the
        ; conversion mode to Native (Kana) input.
        SetIMEConversionMode(hwnd, IME_CMODE_NATIVE)
    }
}

; ---------------------------------------------------------------------------
; Helper: set the IME conversion mode for a given window
; ---------------------------------------------------------------------------
SetIMEConversionMode(hwnd, mode) {
    ; Obtain the input context for the window
    hIMC := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if (!hIMC)
        return

    ; Retrieve the current conversion and sentence modes
    convMode := 0
    sentMode := 0
    DllCall("imm32\ImmGetConversionStatus", "Ptr", hIMC
        , "UInt*", &convMode
        , "UInt*", &sentMode)

    ; Set the conversion mode to the requested value, keeping sentence mode
    DllCall("imm32\ImmSetConversionStatus", "Ptr", hIMC
        , "UInt", mode
        , "UInt", sentMode)

    ; Release the input context
    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", hIMC)
}
