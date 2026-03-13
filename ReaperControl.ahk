#Persistent
#SingleInstance Force
#NoEnv
SetBatchLines, -1
Process, Priority,, High
#Include Lib\AutoHotInterception.ahk

; --- Configuration ---
TargetPortName := "LoopMIDI Port"
BaseStartCC := 90
NumKeys := 10
TotalBanks := 2
Codes := [347, 57, 348, 336, 284, 2, 7, 12, 327, 55]

; --- Globals ---
global hMidiOut := 0
global ActiveBank := 1
global IsLatchMode := true
global LatchStates := {}
global PhysicalKeys := {}

; --- Initialization ---
MidiID := GetMidiOutId(TargetPortName)
if (MidiID != -1)
    DllCall("winmm\midiOutOpen", "Ptr*", hMidiOut, "UInt", MidiID, "Ptr", 0, "Ptr", 0, "UInt", 0)

AHI := new AutoHotInterception()

; GUI Setup
Gui, +AlwaysOnTop -Caption +LastFound +Owner +E0x20
Gui, Color, 000000
Gui, Font, s150 q5, Segoe UI Semibold
Gui, Add, Text, vModeText cWhite Center w250 h250 x0 y0, % ActiveBank

; Key Subscriptions
Loop, 5 {
    devID := A_Index + 5
    AHI.SubscribeKey(devID, 61, true, Func("ShiftGroup")) ; F3
    AHI.SubscribeKey(devID, 65, true, Func("ToggleMode")) ; F7
    AHI.SubscribeKey(devID, 87, true, Func("GlobalReset")) ; F11
    for i, code in Codes
        AHI.SubscribeKey(devID, code, true, Func("SendMidi").Bind(i))
}
Return

; --- Functions ---

MidiMsg(cc, val) {
    global hMidiOut
    if (hMidiOut)
    {
        msg := 0xB0 | (cc << 8) | (val << 16)
        DllCall("winmm\midiOutShortMsg", "Ptr", hMidiOut, "UInt", msg)
    }
}

SendMidi(idx, state) {
    global ActiveBank, LatchStates, BaseStartCC, NumKeys, IsLatchMode, PhysicalKeys

    if (state = PhysicalKeys["K" idx]) 
        return

    PhysicalKeys["K" idx] := state

    cc := BaseStartCC + ((ActiveBank - 1) * NumKeys) + (idx - 1)

    if (IsLatchMode) 
    {
        if (state = 0) 
            return

        val := LatchStates[cc] := LatchStates[cc] ? 0 : 127
    } 
    else 
    {
        val := (state = 1) ? 127 : 0
    }

    MidiMsg(cc, val)
}

ShiftGroup(state) {
    global ActiveBank, TotalBanks

    if (state != 0) 
        return

    ActiveBank := (ActiveBank >= TotalBanks) ? 1 : ActiveBank + 1
    ShowGui(ActiveBank)
}

ToggleMode(state) {
    global IsLatchMode

    if (state != 0) 
        return

    IsLatchMode := !IsLatchMode
    ShowGui(IsLatchMode ? "L" : "M")
}

GlobalReset(state) {
    global LatchStates, BaseStartCC, NumKeys, TotalBanks

    if (state != 0) 
        return

    Loop, %TotalBanks% {
        bankOffset := (A_Index - 1) * NumKeys
        Loop, %NumKeys% {
            cc := BaseStartCC + bankOffset + (A_Index - 1)
            LatchStates[cc] := 0
            MidiMsg(cc, 0)
        }
    }
    ShowGui("R")
}

ShowGui(val) {
    GuiControl,, ModeText, % val
    Gui, Show, xCenter yCenter w250 h250 NoActivate
    SetTimer, RemoveOSD, -250
}

RemoveOSD:
    Gui, Hide
Return

GetMidiOutId(name) {
    numDevs := DllCall("winmm\midiOutGetNumDevs")
    Loop, %numDevs% {
        uID := A_Index - 1
        VarSetCapacity(caps, 84, 0)
        if (DllCall("winmm\midiOutGetDevCaps", "UInt", uID, "Ptr", &caps, "UInt", 84) = 0)
        {
            if InStr(StrGet(&caps + 8, 32, "UTF-16"), name)
                return uID
        }
    }
return -1
}

OnExit:
    if (hMidiOut) 
        DllCall("winmm\midiOutClose", "Ptr", hMidiOut)
ExitApp