#Persistent
#SingleInstance Force
#NoEnv
SetBatchLines, -1
Process, Priority,, High
#Include Lib\AutoHotInterception.ahk

; --- Device Target Info ---
targetVID := "0566"
targetPID := "3107"
targetVIDNumber := "0x" . targetVID
targetPIDNumber := "0x" . targetPID

; --- Configuration ---
targetPort := "LoopMIDI Port"
baseCC := 90
keysPerBank := 10
totalBanks := 2
keyCodes := [347, 57, 348, 336, 284, 2, 7, 12, 327, 55]
deviceScanFastMs := 250
deviceScanIdleMs := 1000
comboKeyCodes := [61, 63, 64, 65, 66]

; --- Globals ---
global midiOutHandle := 0
global activeBank := 1
global latchStates := {}
global momentaryModes := {} ; 1 = Momentary, 0/unset = Toggle (Latch)
global physicalKeyStates := {}
global scriptGuiHwnd := 0
global latchGuiHwnd := 0
global latchOSDVisible := false
global latchRows := 2
global msgGuiHwnd := 0
global escapeHeld := false
global boundDeviceId := 0
global targetVIDNumber, targetPIDNumber, deviceScanFastMs, deviceScanIdleMs
global comboKeyCodes

MidiID := getMidiOutId(targetPort)
if (MidiID != -1){
    DllCall("winmm\midiOutOpen", "Ptr*", midiOutHandle, "UInt", MidiID, "Ptr", 0, "Ptr", 0, "UInt", 0)
}

AHI := new AutoHotInterception()
configureTrayMenu()

; --- Message OSD (separate from Latch OSD) ---
Gui, Msg:New, +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, Msg:Color, 000000
Gui, Msg:Font, s150 q5 cWhite, Segoe UI Semibold
Gui, Msg:Add, Text, vMsgText Center w250 h250 x0 y0
Gui, Msg:Hide

; Poll for plug/unplug events; interval changes based on connection state.
SetTimer, MonitorDeviceConnection, %deviceScanFastMs%
GoSub, MonitorDeviceConnection
Return

MonitorDeviceConnection:
    currentDevId := safeGetKeyboardId(AHI, targetVIDNumber, targetPIDNumber)

    ; If target keyboard is not detected or unplugged
    if (!currentDevId) {
        if (boundDeviceId) {
            unsubscribeDevice(boundDeviceId)
        }
        boundDeviceId := 0
        SetTimer, MonitorDeviceConnection, %deviceScanFastMs%
        return
    }

    ; Device is connected; bind if not already bound to this active ID slot
    if (boundDeviceId != currentDevId) {
        if (boundDeviceId != 0) {
            unsubscribeDevice(boundDeviceId)
        }

        boundDeviceId := currentDevId
        physicalKeyStates := {}
        subscribeDevice(currentDevId)
    }
    SetTimer, MonitorDeviceConnection, %deviceScanIdleMs%
Return

; Robust device scanner designed for composite HID devices
safeGetKeyboardId(AHI_Instance, vid, pid) {
    try {
        devList := AHI_Instance.GetDeviceList()
        for i, dev in devList {
            if (dev.IsMouse)
                continue
            if (dev.Vid = vid && dev.Pid = pid) {
                return dev.Id
            }
        }
    } catch {
        return 0
    }
return 0
}

subscribeDevice(deviceId) {
    global AHI, keyCodes

    ; Combo launcher keys: F3 (61) + F5..F8 (63..66).
    AHI.SubscribeKey(deviceId, 61, true, Func("handleEscapeState"))
    AHI.SubscribeKey(deviceId, 63, true, Func("handleEscFunctionCombo").Bind("cycleBank"))
    AHI.SubscribeKey(deviceId, 64, true, Func("handleEscFunctionCombo").Bind("resetAllKeysToToggle"))
    AHI.SubscribeKey(deviceId, 65, true, Func("handleEscFunctionCombo").Bind("resetBankLatchStates"))
    AHI.SubscribeKey(deviceId, 66, true, Func("handleEscFunctionCombo").Bind("toggleLatchOSD"))

    for keyIndex, code in keyCodes {
        AHI.SubscribeKey(deviceId, code, true, Func("handleKeyEvent").Bind(keyIndex))
    }
}

unsubscribeDevice(deviceId) {
    global AHI, keyCodes, comboKeyCodes

    for keyIndex, code in comboKeyCodes {
        AHI.UnsubscribeKey(deviceId, code)
    }
    for keyIndex, code in keyCodes {
        AHI.UnsubscribeKey(deviceId, code)
    }
}

; ----------------------------
; Functions
; ----------------------------

handleEscapeState(state) {
    global escapeHeld
    escapeHeld := (state = 1)
}

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
    Menu, Tray, Add, Reset All Keys to Toggle Mode, TrayResetAllKeysToToggle
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

TrayResetAllKeysToToggle:
    resetAllKeysToToggle(0)
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

sendMidiMessage(cc, val) {
    global midiOutHandle
    if (midiOutHandle) {
        message := 0xB0 | (cc << 8) | (val << 16)
        DllCall("winmm\midiOutShortMsg", "Ptr", midiOutHandle, "UInt", message)
    }
}

handleKeyEvent(keyIndex, keyState) {
    global activeBank, latchStates, momentaryModes, baseCC, keysPerBank, physicalKeyStates, latchOSDVisible, escapeHeld

    if (keyState = physicalKeyStates[keyIndex]) {
        return
    }

    physicalKeyStates[keyIndex] := keyState
    cc := baseCC + ((activeBank - 1) * keysPerBank) + (keyIndex - 1)

    ; --- ESC / F3 Combo Check ---
    ; If Esc (F3) is held down, pressing a pad key toggles THAT pad's mode (Toggle <-> Momentary)
    if (escapeHeld) {
        if (keyState = 1) { ; On key down only
            momentaryModes[cc] := !momentaryModes[cc]
            showOSD(momentaryModes[cc] ? "M" : "T")
            if (latchOSDVisible) {
                showLatchOSD()
            }
        }
        return
    }

    ; --- Standard Pad Execution ---
    isMomentary := momentaryModes[cc]

    if (isMomentary) {
        ; Momentary mode: On when pressed (127), Off when released (0)
        value := latchStates[cc] := (keyState = 1) ? 127 : 0
    } else {
        ; Toggle mode: Flip state on key down (1), ignore key up (0)
        if (keyState = 0) {
            return
        }
        value := latchStates[cc] := latchStates[cc] ? 0 : 127
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
    showOSD(activeBank)
    showLatchOSD()
}

; Reset all keys in the current bank to standard Toggle mode
resetAllKeysToToggle(state) {
    global momentaryModes, baseCC, keysPerBank, activeBank, latchOSDVisible
    if (state != 0) {
        return
    }

    bankOffset := (activeBank - 1) * keysPerBank
    Loop, %keysPerBank% {
        cc := baseCC + bankOffset + (A_Index - 1)
        momentaryModes[cc] := 0 ; Force all back to Toggle mode
    }

    showOSD("T") ; Shortened to single letter to fit standard OSD box
    if (latchOSDVisible) {
        showLatchOSD()
    }
}

resetBankLatchStates(state) {
    global latchStates, baseCC, keysPerBank, activeBank, latchOSDVisible
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
    global latchGuiHwnd, latchRows, baseCC, activeBank, keysPerBank, latchStates, momentaryModes

    rows := latchRows
    rows := rows > 0 ? rows : 1
    totalKeys := keysPerBank
    cols := Ceil(totalKeys / rows)
    dot := Chr(0x25CF)
    dotSize := 28
    spacing := 2
    statusHeight := 20

    width := cols * (dotSize + spacing) + 12
    height := rows * (dotSize + spacing) + 6 + statusHeight

    Gui, Latch:Destroy
    Gui, Latch:New, +AlwaysOnTop -Caption +ToolWindow +Owner +E0x20 +HwndlatchGuiHwnd, Latch
    Gui, Latch:Color, 000000

    Gui, Latch:Font, s12, Segoe UI Semibold
    statusText := "Bank: " activeBank
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
        isMomentary := momentaryModes[cc]

        ; Color Logic:
        ; Active / On  -> Green (00FF00)
        ; Inactive     -> Yellow (FFFF00) if Momentary mode, Red (FF0000) if Toggle mode
        if (isOn) {
            clr := "00FF00"
        } else if (isMomentary) {
            clr := "FFFF00" ; Yellow for Momentary switches
        } else {
            clr := "FF0000" ; Red for standard Toggle switches
        }

        Gui, Latch:Add, Text, x%x% y%y% w%dotSize% h%dotSize% hwndhCtrl c%clr% Center, %dot%
    }

    xpos := Floor((A_ScreenWidth - width) / 2)
    ypos := 20
    Gui, Latch:Show, x%xpos% y%ypos% w%width% h%height% NoActivate
}

showOSD(val) {
    Gui, Msg:Default
    GuiControl,, MsgText, % val
    Gui, Msg:Show, xCenter yCenter w250 h250 NoActivate
    SetTimer, HideMsgOSD, -350
}

HideMsgOSD:
    Gui, Msg:Hide
Return

getMidiOutId(name) {
    numDevices := DllCall("winmm\midiOutGetNumDevs")
    Loop, %numDevices% {
        deviceIndex := A_Index - 1
        VarSetCapacity(capsData, 84, 0)
        if (DllCall("winmm\midiOutGetDevCaps", "UInt", deviceIndex, "Ptr", &capsData, "UInt", 84) = 0) {
            if (InStr(StrGet(&capsData + 8, 32, "UTF-16"), name)) {
                return deviceIndex
            }
        }
    }
return -1
}

OnExit:
    if (midiOutHandle) {
        DllCall("winmm\midiOutClose", "Ptr", midiOutHandle)
    }
ExitApp