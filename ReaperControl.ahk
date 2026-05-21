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

; --- Globals ---
global midiOutHandle := 0
global activeBank := 1
global latchModeEnabled := true
global latchStates := {}
global physicalKeyStates := {}
global scriptGuiHwnd := 0

; --- Initialization ---
midiDeviceId := getMidiOutId(targetPort)
if (midiDeviceId != -1)
    DllCall("winmm\midiOutOpen", "Ptr*", midiOutHandle, "UInt", midiDeviceId, "Ptr", 0, "Ptr", 0, "UInt", 0)

AHI := new AutoHotInterception()

; GUI Setup
Gui, +AlwaysOnTop -Caption +LastFound +Owner +E0x20 +HwndscriptGuiHwnd
Gui, Color, 000000
Gui, Font, s150 q5, Segoe UI Semibold
Gui, Add, Text, vOsdText cWhite Center w250 h250 x0 y0, % activeBank

configureTrayMenu()

; Key Subscriptions
Loop, 5 {
    deviceId := A_Index + 5
    AHI.SubscribeKey(deviceId, 59, true, Func("cycleBank")) ; F1
    AHI.SubscribeKey(deviceId, 60, true, Func("toggleLatchMode")) ; F2
    AHI.SubscribeKey(deviceId, 61, true, Func("resetBankLatchStates")) ; F3
    for keyIndex, code in keyCodes
        AHI.SubscribeKey(deviceId, code, true, Func("handleKeyEvent").Bind(keyIndex))
}
Return

; --- Functions ---
configureTrayMenu() {
    ; Set icon
    Menu, Tray, Icon, %A_ScriptDir%\white.ico

    ; Tooltip
    Menu, Tray, Tip, MIDI keyboard

    ; Remove default items 
    Menu, Tray, NoStandard

    ; Custom items
    Menu, Tray, Add, Cycle Bank, TrayCycleBank
    Menu, Tray, Add, Toggle Latch Mode, TrayToggleLatchMode
    Menu, Tray, Add, Reset Bank Latch States, TrayResetBankLatchStates

    Menu, Tray, Add
    Menu, Tray, Add, Open Config Folder, TrayOpenConfig
    Menu, Tray, Add, Restart Script, TrayRestart
    Menu, Tray, Add, Exit, TrayExit

    ; Default action (on double click)
    Menu, Tray, Default, Cycle Bank
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

TrayOpenConfig:
    Run, %A_ScriptDir%
Return

TrayRestart:
    Reload
Return

TrayExit:
ExitApp
Return

sendMidiMessage(cc, val) {
    global midiOutHandle
    if (midiOutHandle)
    {
        message := 0xB0 | (cc << 8) | (val << 16)
        DllCall("winmm\midiOutShortMsg", "Ptr", midiOutHandle, "UInt", message)
    }
}

handleKeyEvent(keyIndex, keyState) {
    global activeBank, latchStates, baseCC, keysPerBank, latchModeEnabled, physicalKeyStates

    if (keyState = physicalKeyStates["K" keyIndex])
        return

    physicalKeyStates["K" keyIndex] := keyState

    controlChange := baseCC + ((activeBank - 1) * keysPerBank) + (keyIndex - 1)

    if (latchModeEnabled)
    {
        if (keyState = 0)
            return

        value := latchStates[controlChange] := latchStates[controlChange] ? 0 : 127
    }
    else
    {
        value := (keyState = 1) ? 127 : 0
    }

    sendMidiMessage(controlChange, value)
}

cycleBank(state) {
    global activeBank, totalBanks

    if (state != 0)
        return

    activeBank := (activeBank >= totalBanks) ? 1 : activeBank + 1
    showOSD(activeBank)
}

toggleLatchMode(state) {
    global latchModeEnabled

    if (state != 0)
        return

    latchModeEnabled := !latchModeEnabled
    showOSD(latchModeEnabled ? "L" : "M")
}

resetBankLatchStates(state) {
    global latchStates, baseCC, keysPerBank, activeBank

    if (state != 0)
        return

    bankOffset := (activeBank - 1) * keysPerBank
    Loop, %keysPerBank% {
        cc := baseCC + bankOffset + (A_Index - 1)
        latchStates[cc] := 0
        sendMidiMessage(cc, 0)
    }
    showOSD("R")
}

showOSD(val) {
    GuiControl,, OsdText, % val
    Gui, Show, xCenter yCenter w250 h250 NoActivate
    SetTimer, HideOSD, -250
}

HideOSD:
    Gui, Hide
Return

getMidiOutId(name) {
    numDevices := DllCall("winmm\midiOutGetNumDevs")
    Loop, %numDevices% {
        deviceIndex := A_Index - 1
        VarSetCapacity(capsData, 84, 0)
        if (DllCall("winmm\midiOutGetDevCaps", "UInt", deviceIndex, "Ptr", &capsData, "UInt", 84) = 0)
        {
            if InStr(StrGet(&capsData + 8, 32, "UTF-16"), name)
                return deviceIndex
        }
    }
return -1
}

OnExit:
    if (midiOutHandle)
        DllCall("winmm\midiOutClose", "Ptr", midiOutHandle)
ExitApp