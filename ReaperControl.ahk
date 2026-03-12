#Persistent
#SingleInstance Force
#Include Lib\AutoHotInterception.ahk

TargetPortName := "LoopMIDI Port"
BaseCCs := [90, 100, 110]
Codes := [347, 57, 348, 336, 284, 2, 7, 12, 327, 55]

global hMidiOut := 0
global ActiveGroup := 2
global KeyStates := {}
global AltMode := true

MidiID := GetMidiOutId(TargetPortName)
if (MidiID != -1)
    DllCall("winmm\midiOutOpen", "Ptr*", hMidiOut, "UInt", MidiID, "Ptr", 0, "Ptr", 0, "UInt", 0)

AHI := new AutoHotInterception()

Gui, +AlwaysOnTop -Caption +LastFound +Owner +E0x20
Gui, Color, 000000
Gui, Font, s150 q5, Segoe UI Semibold
Gui, Add, Text, vModeText cWhite Center w250 h250 x0 y0, 1

Loop, 5 {
    DevID := A_Index + 5
    AHI.SubscribeKey(DevID, 59, true, Func("ShiftGroup"))
	AHI.SubscribeKey(DevID, 88, true, Func("ToggleAltMode"))
    for index, sCode in Codes
        AHI.SubscribeKey(DevID, sCode, true, Func("SendMidi").Bind(index))
}


Return

SendMidi(KeyIndex, State) {
    global hMidiOut, ActiveGroup, KeyStates, BaseCCs, AltMode
    if (State = KeyStates[KeyIndex])
        return
    KeyStates[KeyIndex] := State
    if (hMidiOut) {
        group := AltMode ? ActiveGroup : 1
        currentCC := BaseCCs[group] + (KeyIndex - 1)
        val := State ? 127 : 0
        msg := 0xB0 | (currentCC << 8) | (val << 16)
        DllCall("winmm\midiOutShortMsg", "Ptr", hMidiOut, "UInt", msg)
    }
}

ShiftGroup(State) {
    global ActiveGroup
    if (State = 1)
        return
    ActiveGroup := (ActiveGroup = 2) ? 1 : ActiveGroup + 1
    UpdateStatus(false)
}

ToggleAltMode(State) {
    global AltMode
    if (State = 1)
        return
    AltMode := !AltMode
	UpdateStatus(true)
}

UpdateStatus(ShowAltMode) {
    global ActiveGroup, AltMode
    if (ShowAltMode)
        Text := AltMode ? "T" : "F"
    else
        Text := ActiveGroup
    GuiControl,, ModeText, % Text
    Gui, Show, xCenter yCenter w250 h250 NoActivate
    SetTimer, RemoveOSD, -250
}

RemoveOSD:
    Gui, Hide
Return

GetMidiOutId(PortName) {
    NumDevs := DllCall("winmm\midiOutGetNumDevs")
    Loop, %NumDevs% {
        DeviceID := A_Index - 1
        VarSetCapacity(Caps, 84, 0)
        if (DllCall("winmm\midiOutGetDevCaps", "UInt", DeviceID, "Ptr", &Caps, "UInt", 84) = 0) {
            if InStr(StrGet(&Caps + 8, 32, "UTF-16"), PortName)
                return DeviceID
        }
    }
    return -1
}

OnExit:
if (hMidiOut)
    DllCall("winmm\midiOutClose", "Ptr", hMidiOut)
ExitApp