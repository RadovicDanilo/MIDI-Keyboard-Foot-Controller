#Persistent
#SingleInstance Force
#NoEnv
SetBatchLines, -1
Process, Priority,, High
#Include Lib\AutoHotInterception.ahk

; --- Configuration ---
targetPort := "LoopMIDI Port"
baseCC := 90
keysPerBank := 10
totalBanks := 2
keyCodes := [347, 57, 348, 336, 284, 2, 7, 12, 327, 55]
maxKeyboardIds := 10
connectedKeyboardCount := 5

; --- Globals ---
global midiOutHandle := 0
global activeBank := 1
global latchModeEnabled := true
global latchStates := {}
global physicalKeyStates := {}
global scriptGuiHwnd := 0
global latchGuiHwnd := 0
global latchOSDVisible := false
global latchRows := 2
global msgGuiHwnd := 0
global escapeHeld := false

; Initialize AutoHotInterception instance before subscriptions
AHI := new AutoHotInterception()
configureTrayMenu()

; --- Message OSD (separate from Latch OSD) ---
; Small centered message overlay used for brief feedback (bank/mode/reset)
Gui, Msg:New, +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, Msg:Color, 000000
Gui, Msg:Font, s150 q5 cWhite, Segoe UI Semibold
Gui, Msg:Add, Text, vMsgText Center w250 h250 x0 y0
Gui, Msg:Hide

Loop, % maxKeyboardIds - connectedKeyboardCount {
    deviceId := connectedKeyboardCount + A_Index

    ; Combo launcher keys: Esc + F5..F8
    ; Esc alone and F5..F8 alone do nothing.
    AHI.SubscribeKey(deviceId, 1, true, Func("handleEscapeState"))
    AHI.SubscribeKey(deviceId, 63, true, Func("handleEscFunctionCombo").Bind("cycleBank"))
    AHI.SubscribeKey(deviceId, 64, true, Func("handleEscFunctionCombo").Bind("toggleLatchMode"))
    AHI.SubscribeKey(deviceId, 65, true, Func("handleEscFunctionCombo").Bind("resetBankLatchStates"))
    AHI.SubscribeKey(deviceId, 66, true, Func("handleEscFunctionCombo").Bind("toggleLatchOSD"))

    for keyIndex, code in keyCodes {
        AHI.SubscribeKey(deviceId, code, true, Func("handleKeyEvent").Bind(keyIndex))
    }
}
Return

; ----------------------------
; Functions
; ----------------------------

; Track Esc state per device so combos only fire while Esc is held.
handleEscapeState(state) {
    global escapeHeld
    escapeHeld := (state = 1)
}

; Trigger assigned action on F-key down only when Esc is held.
handleEscFunctionCombo(actionName, state) {
    global escapeHeld
    if (state != 0 || !escapeHeld) {
        return
    }

    Func(actionName).Call(0)
}

configureTrayMenu() {
    Menu, Tray, Icon, %A_ScriptDir%\white.ico
    Menu, Tray, Tip, MIDI keyboard
    Menu, Tray, NoStandard

    Menu, Tray, Add, Cycle Bank, TrayCycleBank
    Menu, Tray, Add, Toggle Latch Mode, TrayToggleLatchMode
    Menu, Tray, Add, Reset Bank Latch States, TrayResetBankLatchStates
    Menu, Tray, Add, Toggle Latch OSD, TrayToggleLatchOSD

    Menu, Tray, Add
    Menu, Tray, Add, Open Config Folder, TrayOpenConfig
    Menu, Tray, Add, Restart Script, TrayRestart
    Menu, Tray, Add, Exit, TrayExit

    Menu, Tray, Default, Toggle Latch OSD
}

TrayCycleBank:
    cycleBank(0)
Return

TrayToggleLatchMode:
    toggleLatchMode(0)
Return

TrayResetBankLatchStates:
    resetBankLatchStates(0)
Return

TrayToggleLatchOSD:
    toggleLatchOSD(0)
Return

TrayOpenConfig:
    Run, %A_ScriptDir%
Return

TrayRestart:
    Reload
Return

TrayExit:
ExitApp
Return

; Send a MIDI message
sendMidiMessage(cc, val) {
    global midiOutHandle
    if (midiOutHandle) {
        message := 0xB0 | (cc << 8) | (val << 16)
        DllCall("winmm\\midiOutShortMsg", "Ptr", midiOutHandle, "UInt", message)
    }
}

; Handle physical key events and update latch state
handleKeyEvent(keyIndex, keyState) {
    global activeBank, latchStates, baseCC, keysPerBank, latchModeEnabled, physicalKeyStates, latchOSDVisible, latchRows

    if (keyState = physicalKeyStates["K" keyIndex]) {
        return
    }

    physicalKeyStates["K" keyIndex] := keyState
    cc := baseCC + ((activeBank - 1) * keysPerBank) + (keyIndex - 1)

    if (latchModeEnabled) {
        if (keyState = 0) {
            return
        }
        value := latchStates[cc] := latchStates[cc] ? 0 : 127
    } else {
        value := (keyState = 1) ? 127 : 0
    }

    sendMidiMessage(cc, value)
    if (latchOSDVisible) {
        showLatchOSD()
    }
}

; ----------------------
; Bank and mode controls
; ----------------------

cycleBank(state) {
    global activeBank, totalBanks
    if (state != 0) {
        return
    }
    activeBank := (activeBank >= totalBanks) ? 1 : activeBank + 1
    resetBankLatchStates(0)
    showOSD(activeBank)
}

toggleLatchMode(state) {
    global latchModeEnabled
    if (state != 0) {
        return
    }
    latchModeEnabled := !latchModeEnabled
    resetBankLatchStates(0)
    showOSD(latchModeEnabled ? "L" : "M")
}

resetBankLatchStates(state) {
    global latchStates, baseCC, keysPerBank, activeBank, latchOSDVisible, latchRows
    if (state != 0) {
        return
    }
    bankOffset := (activeBank - 1) * keysPerBank
    Loop, %keysPerBank% {
        cc := baseCC + bankOffset + (A_Index - 1)
        latchStates[cc] := 0
        sendMidiMessage(cc, 0)
    }
    showOSD("R")
    if (latchOSDVisible) {
        showLatchOSD()
    }
}

toggleLatchOSD(state) {
    global latchOSDVisible
    if (state != 0) {
        return
    }
    latchOSDVisible := !latchOSDVisible
    if (latchOSDVisible) {
        showLatchOSD()
    } else {
        Gui, Latch:Hide
    }
}

; Render the latch OSD: simple black box, colored dots per key.
showLatchOSD() {
    global latchGuiHwnd, latchRows, baseCC, activeBank, keysPerBank, latchStates

    rows := latchRows
    rows := rows > 0 ? rows : 1
    totalKeys := keysPerBank
    cols := Ceil(totalKeys / rows)
    dot := "●"
    dotSize := 28
    spacing := 2
    statusHeight := 20

    width := cols * (dotSize + spacing) + 12
    height := rows * (dotSize + spacing) + 6 + statusHeight

    Gui, Latch:Destroy
    Gui, Latch:New, +AlwaysOnTop -Caption +ToolWindow +Owner +E0x20 +HwndlatchGuiHwnd, Latch
    Gui, Latch:Color, 000000

    Gui, Latch:Font, s12, Segoe UI Semibold
    statusText := "Bank: " activeBank " | Mode: " (latchModeEnabled ? "L" : "M")
    Gui, Latch:Add, Text, x0 y6 w%width% h%statusHeight% cWhite Center, %statusText%

    Gui, Latch:Font, s14, Segoe UI Symbol
    Loop, %totalKeys% {
        idx := A_Index
        row := latchRows - Floor((idx-1) / cols) - 1
        col := Mod((idx-1), cols)

        x := col * (dotSize + spacing) + 6
        y := statusHeight + (row * (dotSize + spacing)) + 6

        cc := baseCC + ((activeBank - 1) * keysPerBank) + (idx - 1)
        isOn := (latchStates[cc] && latchStates[cc] != 0)
        clr := (isOn ? "00FF00" : "FF0000")

        Gui, Latch:Add, Text, x%x% y%y% w%dotSize% h%dotSize% hwndhCtrl c%clr% Center, %dot%
    }

    xpos := Floor((A_ScreenWidth - width) / 2)
    ypos := 20
    Gui, Latch:Show, x%xpos% y%ypos% w%width% h%height% NoActivate
}

; Brief center message OSD (small overlay)
showOSD(val) {
    Gui, Msg:Default
    GuiControl,, MsgText, % val
    Gui, Msg:Show, xCenter yCenter w250 h250 NoActivate
    SetTimer, HideMsgOSD, -350
}

HideMsgOSD:
    Gui, Msg:Hide
Return

; MIDI output device helper
getMidiOutId(name) {
    numDevices := DllCall("winmm\\midiOutGetNumDevs")
    Loop, %numDevices% {
        deviceIndex := A_Index - 1
        VarSetCapacity(capsData, 84, 0)
        if (DllCall("winmm\\midiOutGetDevCaps", "UInt", deviceIndex, "Ptr", &capsData, "UInt", 84) = 0) {
            if (InStr(StrGet(&capsData + 8, 32, "UTF-16"), name)) {
                return deviceIndex
            }
        }
    }
return -1
}

OnExit:
    if (midiOutHandle) {
        DllCall("winmm\\midiOutClose", "Ptr", midiOutHandle)
    }
ExitApp
