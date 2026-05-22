#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
Persistent

; ============================================================
; AutoRecorder Lite v1.1
; AHK v2 单文件版：录制普通软件 / 网页操作，并支持立即回放、循环回放、定时回放、拖拽轨迹、按住时长、连点器。
; 第一版坐标采用“窗口相对坐标”。后续可扩展为屏幕绝对坐标 / 客户区相对坐标。
; ============================================================

SetWorkingDir(A_ScriptDir)
SetTitleMatchMode(2)
SendMode("Input")
CoordMode("Mouse", "Screen")

global APP_NAME := "AutoRecorder Lite v1.1"
global MACRO_DIR := A_ScriptDir "\macros"

global gGui := ""
global gNameEdit := ""
global gMacroList := ""
global gStatusText := ""
global gEventCountText := ""
global gRecordTextCheck := ""
global gRecordDragCheck := ""
global gRecordMouseHoldCheck := ""
global gModeOnce := ""
global gModeCount := ""
global gModeDuration := ""
global gPlaybackMode := "once"
global gCountEdit := ""
global gDurationEdit := ""
global gSpeedDDL := ""
global gScheduleEnable := ""
global gScheduleTimeEdit := ""

global gClickerActionDDL := ""
global gClickerSendEdit := ""
global gClickerIntervalEdit := ""
global gClickerStatusText := ""
global gClickerRunning := false

global gHintGui := ""
global gHintText := ""

global gMacroIndex := Map()
global gCurrentMacro := Map()
global gEvents := []
global gBaseWindow := Map()
global gInputHook := ""

global gIsRecording := false
global gIsPlaying := false
global gStopRequested := false
global gLastTick := 0
global gRecordingName := ""
global gRecordingStartedAt := ""
global gLastScheduleKey := ""
global gLastPlaybackImeKey := ""

global gMouseDown := Map()
global gDragTimerRunning := false
global DRAG_SAMPLE_MS := 30
global DRAG_MIN_MOVE := 2

Main()

; ============================================================
; 初始化
; ============================================================

Main() {
    global MACRO_DIR

    DirCreate(MACRO_DIR)
    SetupTray()
    SetupHotkeys()
    BuildMainGui()
    RefreshMacroList()
    SetTimer(CheckSchedule, 1000)

    SetStatus("空闲。F7 开始/停止录制，F8 紧急停止，F9 立即回放，F10 启停连点器。")
}

SetupTray() {
    global APP_NAME

    A_IconTip := APP_NAME
    A_TrayMenu.Delete()
    A_TrayMenu.Add("显示主窗口", ShowMainWindow)
    A_TrayMenu.Add("开始/停止录制  F7", ToggleRecording)
    A_TrayMenu.Add("立即回放  F9", PlaySelected)
    A_TrayMenu.Add("启动/停止连点器  F10", ToggleClicker)
    A_TrayMenu.Add("紧急停止  F8", EmergencyStop)
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", ExitAppHandler)
    A_TrayMenu.Default := "显示主窗口"
}

SetupHotkeys() {
    Hotkey("F7", ToggleRecording, "On")
    Hotkey("F8", EmergencyStop, "On")
    Hotkey("F9", PlaySelected, "On")
    Hotkey("F10", ToggleClicker, "On")

    ; 鼠标按钮采用 Down / Up 成对记录，这样可以记录按住时长和拖拽轨迹。
    for _, btn in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
        Hotkey("~*" btn, RecordMouseDown.Bind(btn), "On")
        Hotkey("~*" btn " Up", RecordMouseUp.Bind(btn), "On")
    }

    ; 滚轮没有按住时长，单独作为 wheel 事件记录。
    for _, wheel in ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"] {
        Hotkey("~*" wheel, RecordWheelHotkey.Bind(wheel), "On")
    }
}

; ============================================================
; GUI
; ============================================================

BuildMainGui() {
    global APP_NAME
    global gGui, gNameEdit, gMacroList, gStatusText, gEventCountText
    global gRecordTextCheck, gRecordDragCheck, gRecordMouseHoldCheck
    global gModeOnce, gModeCount, gModeDuration, gCountEdit, gDurationEdit, gSpeedDDL
    global gScheduleEnable, gScheduleTimeEdit
    global gClickerActionDDL, gClickerSendEdit, gClickerIntervalEdit, gClickerStatusText

    gGui := Gui("+Resize +MinSize620x640", APP_NAME)
    gGui.SetFont("s9", "Microsoft YaHei UI")

    gGui.Add("GroupBox", "x15 y10 w590 h135", "录制管理")
    gGui.Add("Text", "x30 y40 w70", "录制名称：")
    gNameEdit := gGui.Add("Edit", "x100 y36 w280 h24", "我的录制")
    gGui.Add("Button", "x395 y34 w90 h28", "开始录制").OnEvent("Click", StartRecording)
    gGui.Add("Button", "x495 y34 w90 h28", "停止录制").OnEvent("Click", StopRecording)

    gGui.Add("Button", "x100 y72 w120 h28", "保存录制").OnEvent("Click", SaveRecording)
    gEventCountText := gGui.Add("Text", "x240 y78 w330", "已记录：0 步")

    gRecordTextCheck := gGui.Add("CheckBox", "x30 y110 w180 Checked", "文字按文本保存")
    gRecordDragCheck := gGui.Add("CheckBox", "x220 y110 w150 Checked", "记录拖拽轨迹")
    gRecordMouseHoldCheck := gGui.Add("CheckBox", "x380 y110 w180 Checked", "记录鼠标按住时长")

    gGui.Add("GroupBox", "x15 y155 w590 h95", "已保存录制")
    gMacroList := gGui.Add("DropDownList", "x30 y185 w350 h200")
    gGui.Add("Button", "x395 y183 w90 h28", "加载").OnEvent("Click", LoadSelectedMacro)
    gGui.Add("Button", "x495 y183 w90 h28", "删除").OnEvent("Click", DeleteSelectedMacro)
    gGui.Add("Text", "x30 y220 w560", "提示：v1.1 用窗口相对坐标。回放前请尽量保持目标窗口已打开。")

    gGui.Add("GroupBox", "x15 y260 w590 h125", "回放设置")

    ; 注意：三个 Radio 必须连续创建，否则中间插入 Edit/Text 后，AHK 可能不会把它们当成同一组。
    gModeOnce := gGui.Add("Radio", "x35 y290 w100 Checked Group", "回放一次")
    gModeCount := gGui.Add("Radio", "x150 y290 w100", "循环次数")
    gModeDuration := gGui.Add("Radio", "x35 y325 w100", "循环时长")

    ; 额外加一层手动互斥，防止 GUI 分组异常。
    gModeOnce.OnEvent("Click", PlaybackModeChanged.Bind("once"))
    gModeCount.OnEvent("Click", PlaybackModeChanged.Bind("count"))
    gModeDuration.OnEvent("Click", PlaybackModeChanged.Bind("duration"))

    gCountEdit := gGui.Add("Edit", "x245 y287 w60 Number", "10")
    gGui.Add("Text", "x310 y292 w30", "次")

    gDurationEdit := gGui.Add("Edit", "x125 y322 w60 Number", "30")
    gGui.Add("Text", "x190 y327 w40", "分钟")

    gGui.Add("Text", "x255 y327 w70", "回放速度：")
    gSpeedDDL := gGui.Add("DropDownList", "x325 y323 w90 Choose1", ["1.0x", "1.25x", "1.5x", "2.0x"])

    gGui.Add("Button", "x430 y317 w75 h30", "立即回放").OnEvent("Click", PlaySelected)
    gGui.Add("Button", "x515 y317 w70 h30", "停止").OnEvent("Click", EmergencyStop)
    gGui.Add("Text", "x35 y355 w530", "说明：三种回放模式是互斥单选，不会同时生效。")

    gGui.Add("GroupBox", "x15 y395 w590 h95", "连点器 / 连按器")
    gGui.Add("Text", "x30 y425 w70", "动作：")
    gClickerActionDDL := gGui.Add("DropDownList", "x80 y421 w115 Choose1", ["鼠标左键", "鼠标右键", "鼠标中键", "按键/组合键"])
    gGui.Add("Text", "x210 y425 w85", "按键内容：")
    gClickerSendEdit := gGui.Add("Edit", "x280 y421 w120 h24", "{Space}")
    gGui.Add("Text", "x415 y425 w75", "间隔ms：")
    gClickerIntervalEdit := gGui.Add("Edit", "x480 y421 w55 h24 Number", "100")
    gGui.Add("Button", "x30 y455 w85 h28", "启动 F10").OnEvent("Click", StartClicker)
    gGui.Add("Button", "x125 y455 w85 h28", "停止").OnEvent("Click", StopClicker)
    gClickerStatusText := gGui.Add("Text", "x225 y461 w350", "连点器状态：未运行。F10 启停，F8 紧急停止。")

    gGui.Add("GroupBox", "x15 y500 w590 h65", "定时设置")
    gScheduleEnable := gGui.Add("CheckBox", "x35 y527 w120", "启用定时回放")
    gGui.Add("Text", "x170 y530 w70", "开始时间：")
    gScheduleTimeEdit := gGui.Add("Edit", "x240 y526 w70 h24", FormatTime(A_Now, "HH:mm"))
    gGui.Add("Text", "x320 y530 w260", "格式 HH:mm，例如 18:30。软件需保持运行。")

    gGui.Add("Button", "x30 y585 w120 h28", "最小化到托盘").OnEvent("Click", MinimizeToTray)
    gStatusText := gGui.Add("Text", "x165 y591 w430", "状态：初始化中...")

    gGui.OnEvent("Close", HandleGuiClose)
    gGui.Show("w620 h630")
}

ShowMainWindow(*) {
    global gGui
    if IsObject(gGui) {
        gGui.Show()
        WinActivate("ahk_id " gGui.Hwnd)
    }
}

HandleGuiClose(guiObj) {
    guiObj.Hide()
    TrayTip("程序仍在通知栏运行。右键托盘图标可以退出。", APP_NAME)
}

MinimizeToTray(*) {
    global gGui
    gGui.Hide()
    TrayTip("已最小化到通知栏。F8 可紧急停止。", APP_NAME)
}

ExitAppHandler(*) {
    global gInputHook

    StopClicker()
    StopDragTimer()
    try {
        if IsObject(gInputHook)
            gInputHook.Stop()
    }
    ExitApp()
}

SetStatus(text) {
    global gStatusText

    if IsObject(gStatusText)
        gStatusText.Value := "状态：" text
}

UpdateEventCount() {
    global gEventCountText, gEvents

    if IsObject(gEventCountText)
        gEventCountText.Value := "已记录：" gEvents.Length " 步"
}

; ============================================================
; 录制模块
; ============================================================

ToggleRecording(*) {
    global gIsRecording

    if gIsRecording
        StopRecording()
    else
        StartRecording()
}

StartRecording(*) {
    global gIsRecording, gIsPlaying, gStopRequested, gClickerRunning
    global gEvents, gLastTick, gRecordingName, gRecordingStartedAt, gBaseWindow, gMouseDown
    global gNameEdit

    if gIsPlaying {
        MsgBox("正在回放中，不能开始录制。请先按 F8 停止。", APP_NAME, "Icon!")
        return
    }

    if gClickerRunning {
        MsgBox("连点器正在运行。为了避免录制混乱，请先停止连点器。", APP_NAME, "Icon!")
        return
    }

    name := Trim(gNameEdit.Value)
    if name = ""
        name := "未命名_" FormatTime(A_Now, "yyyyMMdd_HHmmss")

    gEvents := []
    gMouseDown := Map()
    gRecordingName := name
    gRecordingStartedAt := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    gBaseWindow := GetWindowMeta(WinExist("A"))
    gLastTick := A_TickCount
    gStopRequested := false
    gIsRecording := true

    StartKeyboardHook()
    UpdateEventCount()
    ShowHint("● 录制中`nF7 停止录制 / F8 紧急停止`n已记录：0 步")
    SetStatus("录制中：" name)
    TrayTip("录制已开始。按 F7 停止录制，按 F8 紧急停止。", APP_NAME)
}

StopRecording(*) {
    global gIsRecording, gEvents, gMouseDown

    if !gIsRecording {
        SetStatus("当前没有录制任务。")
        return
    }

    gIsRecording := false
    gMouseDown := Map()
    StopDragTimer()
    StopKeyboardHook()
    ShowHint("■ 录制已停止`n可以点击“保存录制”`n已记录：" gEvents.Length " 步")
    SetStatus("录制已停止，已记录 " gEvents.Length " 步。")
    TrayTip("录制已停止。记得点击“保存录制”。", APP_NAME)
}

StartKeyboardHook() {
    global gInputHook

    try {
        if IsObject(gInputHook)
            gInputHook.Stop()
    }

    ; V = 让按键继续传递给当前软件；N = 对指定按键启用通知。
    ; OnChar 用于记录“实际输入出来的文字”，可避免中文/英文输入法状态不同导致回放结果不一致。
    gInputHook := InputHook("V")
    gInputHook.KeyOpt("{All}", "N")
    gInputHook.OnKeyDown := RecordKeyDown
    gInputHook.OnChar := RecordChar
    gInputHook.Start()
}

StopKeyboardHook() {
    global gInputHook

    try {
        if IsObject(gInputHook)
            gInputHook.Stop()
    }
}

RecordChar(ih, char) {
    global gIsRecording, gIsPlaying

    if !gIsRecording || gIsPlaying
        return

    if !IsTextRecordingEnabled()
        return

    if char = ""
        return

    ; Enter / 换行由 RecordKeyDown 记录为 key 事件，这里不要重复记录成 text。
    if char = "`r" || char = "`n" || char = "`r`n"
        return

    activeHwnd := WinExist("A")
    if IsInternalWindow(activeHwnd)
        return

    ; 中文/日文/韩文 IME 的 OnChar 常常只能拿到拼音/罗马字母，不是最终上屏文字。
    ; 这类输入交给物理按键 + IME 状态回放来复现。
    if ShouldRecordPhysicalTyping(activeHwnd)
        return

    evt := Map(
        "type", "text",
        "text", char,
        "delay", GetAndResetDelay(),
        "win", GetWindowMeta(activeHwnd),
        "ime", GetImeSnapshot(activeHwnd)
    )

    RecordEvent(evt)
}

RecordKeyDown(ih, vk, sc) {
    global gIsRecording, gIsPlaying

    if !gIsRecording || gIsPlaying
        return

    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if keyName = ""
        return

    if IsIgnoredRecordKey(keyName)
        return

    if IsPureModifierKey(keyName)
        return

    activeHwnd := WinExist("A")
    if IsInternalWindow(activeHwnd)
        return

    ; 文本模式下，普通字符键由 RecordChar 记录为最终文本；快捷键、功能键仍按物理键记录。
    if ShouldSkipPhysicalKeyForText(keyName, activeHwnd)
        return

    sendText := BuildSendText(vk, sc, keyName)
    evt := Map(
        "type", "key",
        "key", keyName,
        "vk", vk,
        "sc", sc,
        "send", sendText,
        "delay", GetAndResetDelay(),
        "win", GetWindowMeta(activeHwnd),
        "ime", GetImeSnapshot(activeHwnd)
    )

    RecordEvent(evt)
}

RecordMouseDown(button, *) {
    global gIsRecording, gIsPlaying, gMouseDown, gLastTick

    if !gIsRecording || gIsPlaying
        return

    ctx := GetMouseContext()
    hwnd := ctx["hwnd"]

    if IsInternalWindow(hwnd)
        return

    if gMouseDown.Has(button)
        return

    nowTick := A_TickCount
    delay := nowTick - gLastTick
    if delay < 0
        delay := 0

    state := Map(
        "button", button,
        "downTick", nowTick,
        "delay", delay,
        "win", GetWindowMeta(hwnd),
        "start", ctx,
        "path", []
    )

    AddDragPoint(state, ctx, 0, true)
    gMouseDown[button] := state

    if IsDragRecordingEnabled()
        StartDragTimer()
}

RecordMouseUp(button, *) {
    global gIsRecording, gIsPlaying, gMouseDown, gLastTick

    if !gIsRecording || gIsPlaying
        return

    if !gMouseDown.Has(button)
        return

    state := gMouseDown[button]
    upTick := A_TickCount
    duration := upTick - state["downTick"]
    if duration < 0
        duration := 0

    ctx := GetMouseContext(state["start"])
    if IsDragRecordingEnabled()
        AddDragPoint(state, ctx, duration, true)

    if !IsMouseHoldRecordingEnabled()
        duration := 50

    path := IsDragRecordingEnabled() ? state["path"] : []
    start := state["start"]

    evt := Map(
        "type", "mouse_button",
        "button", NormalizeMouseButton(button),
        "rawButton", button,
        "x", start["x"],
        "y", start["y"],
        "screenX", start["screenX"],
        "screenY", start["screenY"],
        "endX", ctx["x"],
        "endY", ctx["y"],
        "endScreenX", ctx["screenX"],
        "endScreenY", ctx["screenY"],
        "duration", duration,
        "delay", state["delay"],
        "path", path,
        "win", state["win"]
    )

    gMouseDown.Delete(button)
    RecordEvent(evt)
    gLastTick := upTick

    if gMouseDown.Count = 0
        StopDragTimer()
}

RecordWheelHotkey(wheel, *) {
    global gIsRecording, gIsPlaying

    if !gIsRecording || gIsPlaying
        return

    ctx := GetMouseContext()
    hwnd := ctx["hwnd"]

    if IsInternalWindow(hwnd)
        return

    evt := Map(
        "type", "wheel",
        "button", wheel,
        "rawButton", wheel,
        "x", ctx["x"],
        "y", ctx["y"],
        "screenX", ctx["screenX"],
        "screenY", ctx["screenY"],
        "delay", GetAndResetDelay(),
        "win", GetWindowMeta(hwnd)
    )

    RecordEvent(evt)
}

TrackDragPath() {
    global gMouseDown

    if gMouseDown.Count = 0 {
        StopDragTimer()
        return
    }

    if !IsDragRecordingEnabled()
        return

    nowTick := A_TickCount
    for _, state in gMouseDown {
        elapsed := nowTick - state["downTick"]
        if elapsed < 0
            elapsed := 0

        ctx := GetMouseContext(state["start"])
        AddDragPoint(state, ctx, elapsed, false)
    }
}

StartDragTimer() {
    global gDragTimerRunning, DRAG_SAMPLE_MS

    if gDragTimerRunning
        return

    gDragTimerRunning := true
    SetTimer(TrackDragPath, DRAG_SAMPLE_MS)
}

StopDragTimer() {
    global gDragTimerRunning

    if !gDragTimerRunning
        return

    SetTimer(TrackDragPath, 0)
    gDragTimerRunning := false
}

AddDragPoint(state, ctx, elapsed, force := false) {
    global DRAG_MIN_MOVE

    path := state["path"]

    if !force && path.Length > 0 {
        last := path[path.Length]
        if Abs(ctx["screenX"] - last["screenX"]) < DRAG_MIN_MOVE && Abs(ctx["screenY"] - last["screenY"]) < DRAG_MIN_MOVE
            return
    }

    path.Push(Map(
        "t", elapsed,
        "x", ctx["x"],
        "y", ctx["y"],
        "screenX", ctx["screenX"],
        "screenY", ctx["screenY"]
    ))
}

GetMouseContext(baseCtx := "") {
    MouseGetPos(&sx, &sy, &hwnd)
    if !hwnd
        hwnd := WinExist("A")

    if IsObject(baseCtx) && baseCtx.Has("winX") && baseCtx.Has("winY") {
        wx := baseCtx["winX"]
        wy := baseCtx["winY"]
    } else {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        } catch {
            wx := 0
            wy := 0
        }
    }

    return Map(
        "hwnd", hwnd,
        "screenX", sx,
        "screenY", sy,
        "x", sx - wx,
        "y", sy - wy,
        "winX", wx,
        "winY", wy
    )
}

RecordEvent(evt) {
    global gEvents

    gEvents.Push(evt)
    UpdateEventCount()
    ShowHint("● 录制中`nF7 停止录制 / F8 紧急停止`n已记录：" gEvents.Length " 步")
}

GetAndResetDelay() {
    global gLastTick

    nowTick := A_TickCount
    delay := nowTick - gLastTick
    if delay < 0
        delay := 0

    gLastTick := nowTick
    return delay
}

IsIgnoredRecordKey(keyName) {
    ; 避免把控制本软件的热键录进去。
    ignored := Map("F7", true, "F8", true, "F9", true, "F10", true)
    return ignored.Has(keyName)
}

IsPureModifierKey(keyName) {
    modifiers := Map(
        "LControl", true, "RControl", true,
        "LShift", true, "RShift", true,
        "LAlt", true, "RAlt", true,
        "LWin", true, "RWin", true
    )
    return modifiers.Has(keyName)
}

ShouldSkipPhysicalKeyForText(keyName, hwnd := 0) {
    if !IsTextRecordingEnabled()
        return false

    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        return false

    if ShouldRecordPhysicalTyping(hwnd)
        return false

    return !IsNonTextKey(keyName)
}

ShouldRecordPhysicalTyping(hwnd := 0) {
    if !IsTextRecordingEnabled()
        return false

    snapshot := GetImeSnapshot(hwnd)
    if !IsObject(snapshot)
        return false

    if MapGet(snapshot, "open", 0)
        return true

    return IsCjkKeyboardLayout(MapGet(snapshot, "hkl", 0))
}

IsNonTextKey(keyName) {
    if RegExMatch(keyName, "^F\d{1,2}$")
        return true

    nonText := Map(
        "Enter", true, "Tab", true, "Backspace", true, "Delete", true, "Escape", true,
        "Up", true, "Down", true, "Left", true, "Right", true,
        "Home", true, "End", true, "PgUp", true, "PgDn", true,
        "Insert", true, "CapsLock", true, "NumLock", true, "ScrollLock", true,
        "PrintScreen", true, "Pause", true, "AppsKey", true,
        "Browser_Back", true, "Browser_Forward", true, "Browser_Refresh", true,
        "Volume_Up", true, "Volume_Down", true, "Volume_Mute", true,
        "Media_Play_Pause", true, "Media_Stop", true, "Media_Next", true, "Media_Prev", true
    )

    return nonText.Has(keyName)
}

BuildSendText(vk, sc, keyName) {
    mods := ""

    if GetKeyState("Ctrl", "P") && !InStr(keyName, "Control")
        mods .= "^"
    if GetKeyState("Alt", "P") && !InStr(keyName, "Alt")
        mods .= "!"
    if GetKeyState("Shift", "P") && !InStr(keyName, "Shift")
        mods .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) && !InStr(keyName, "Win")
        mods .= "#"

    ; 使用 vk/sc 发送，兼容大部分键位和不同键盘布局。
    return mods "{vk" Format("{:02X}", vk) "sc" Format("{:03X}", sc) "}"
}

NormalizeMouseButton(button) {
    switch button {
        case "LButton":
            return "Left"
        case "RButton":
            return "Right"
        case "MButton":
            return "Middle"
        case "XButton1":
            return "X1"
        case "XButton2":
            return "X2"
        default:
            return button
    }
}

AhkMouseButtonName(rawButton) {
    switch rawButton {
        case "LButton":
            return "LButton"
        case "RButton":
            return "RButton"
        case "MButton":
            return "MButton"
        case "XButton1":
            return "XButton1"
        case "XButton2":
            return "XButton2"
        default:
            return "LButton"
    }
}

IsTextRecordingEnabled() {
    global gRecordTextCheck
    return !IsObject(gRecordTextCheck) || gRecordTextCheck.Value
}

IsDragRecordingEnabled() {
    global gRecordDragCheck
    return IsObject(gRecordDragCheck) && gRecordDragCheck.Value
}

IsMouseHoldRecordingEnabled() {
    global gRecordMouseHoldCheck
    return IsObject(gRecordMouseHoldCheck) && gRecordMouseHoldCheck.Value
}

; ============================================================
; 回放模块
; ============================================================

PlaySelected(*) {
    global gIsRecording, gIsPlaying, gStopRequested, gClickerRunning
    global gCurrentMacro, gEvents

    if gIsRecording {
        MsgBox("正在录制中，不能回放。请先停止录制。", APP_NAME, "Icon!")
        return
    }

    if gClickerRunning {
        MsgBox("连点器正在运行。为了避免冲突，请先停止连点器。", APP_NAME, "Icon!")
        return
    }

    if gIsPlaying {
        MsgBox("已经在回放中。按 F8 可以紧急停止。", APP_NAME, "Icon!")
        return
    }

    if !EnsureMacroLoaded()
        return

    if gEvents.Length = 0 {
        MsgBox("当前录制内容为空，无法回放。", APP_NAME, "Icon!")
        return
    }

    gStopRequested := false
    gIsPlaying := true

    try {
        CountdownBeforePlay()
        if gStopRequested
            return

        mode := GetPlaybackMode()
        speed := GetPlaybackSpeed()

        switch mode["type"] {
            case "once":
                SetStatus("正在回放一次。")
                PlayOnePass(speed, 1, 1)

            case "count":
                count := mode["count"]
                Loop count {
                    if gStopRequested
                        break
                    PlayOnePass(speed, A_Index, count)
                }

            case "duration":
                durationMs := mode["minutes"] * 60000
                endTick := A_TickCount + durationMs
                pass := 0
                while !gStopRequested && A_TickCount < endTick {
                    pass += 1
                    PlayOnePass(speed, pass, 0, endTick)
                }
        }
    } catch as err {
        MsgBox("回放时发生错误：`n" err.Message, APP_NAME, "Iconx")
    } finally {
        gIsPlaying := false
        gStopRequested := false
        HideHint()
        SetStatus("回放结束或已停止。")
    }
}

CountdownBeforePlay() {
    global gStopRequested

    Loop 3 {
        remain := 4 - A_Index
        ShowHint("▶ 即将开始自动操作`n" remain " 秒后开始`nF8 紧急停止")
        SmartSleep(1000)
        if gStopRequested
            break
    }
}

PlayOnePass(speed, passIndex, totalPass := 0, endTick := 0) {
    global gEvents, gStopRequested, gLastPlaybackImeKey

    total := gEvents.Length
    gLastPlaybackImeKey := ""

    for idx, evt in gEvents {
        if gStopRequested
            return false

        delay := MapGet(evt, "delay", 0)
        adjustedDelay := Round(delay / speed)
        SmartSleep(adjustedDelay)
        if gStopRequested
            return false

        if totalPass > 0 {
            title := "第 " passIndex "/" totalPass " 轮"
        } else if endTick > 0 {
            remainMs := Max(0, endTick - A_TickCount)
            title := "第 " passIndex " 轮，剩余约 " FormatMs(remainMs)
        } else {
            title := "第 " passIndex " 轮"
        }

        ShowHint("▶ 自动操作中`n" title "`n步骤：" idx "/" total "，F8 停止")
        SetStatus("回放中：" title "，步骤 " idx "/" total)

        ExecuteEvent(evt, speed)
    }

    return true
}

ExecuteEvent(evt, speed := 1.0) {
    if !IsObject(evt)
        return

    evtType := MapGet(evt, "type", "")

    if evtType = "mouse_button" {
        ExecuteMouseButtonEvent(evt, speed)
    } else if evtType = "wheel" {
        ExecuteWheelEvent(evt)
    } else if evtType = "mouse" {
        ExecuteLegacyMouseEvent(evt)
    } else if evtType = "key" {
        winMeta := MapGet(evt, "win", "")
        hwnd := ActivateEventWindow(winMeta)
        ApplyImeSnapshotIfNeeded(MapGet(evt, "ime", ""), hwnd)

        sendText := MapGet(evt, "send", "")
        if sendText != ""
            SendEvent(sendText)
    } else if evtType = "text" {
        winMeta := MapGet(evt, "win", "")
        ActivateEventWindow(winMeta)

        textValue := MapGet(evt, "text", "")
        if textValue != ""
            SafeSendText(textValue)
    }
}

SafeSendText(textValue) {
    if textValue = ""
        return

    ; Enter / 换行由 key 事件处理，避免重复换行。
    if textValue = "`r" || textValue = "`n" || textValue = "`r`n"
        return

    ; 中文、符号、特殊字符用剪贴板粘贴最稳，不依赖当前输入法状态。
    PasteTextByClipboard(textValue)
}

PasteTextByClipboard(textValue) {
    clipSaved := ClipboardAll()

    try {
        A_Clipboard := ""
        Sleep(20)

        A_Clipboard := textValue

        if !ClipWait(1) {
            ; 剪贴板失败时，最后再尝试 SendText。
            Send("{Text}" textValue)
            return
        }

        Send("^v")
        Sleep(40)
    } finally {
        A_Clipboard := clipSaved
        clipSaved := ""
    }
}

ExecuteMouseButtonEvent(evt, speed := 1.0) {
    global gStopRequested

    winMeta := MapGet(evt, "win", "")
    ActivateEventWindow(winMeta)

    start := ResolveScreenPoint(winMeta, MapGet(evt, "x", 0), MapGet(evt, "y", 0), MapGet(evt, "screenX", 0), MapGet(evt, "screenY", 0))
    MouseMove(start["x"], start["y"], 0)
    SmartSleep(20)

    rawButton := MapGet(evt, "rawButton", "LButton")
    ahkButton := AhkMouseButtonName(rawButton)

    Send("{" ahkButton " Down}")

    duration := MapGet(evt, "duration", 50)
    if duration < 0
        duration := 0

    path := MapGet(evt, "path", [])
    prevT := 0

    if IsObject(path) && path.Length > 1 {
        ; 第一个点通常就是按下点，从第二个点开始移动。
        moveCount := path.Length - 1
        Loop moveCount {
            point := path[A_Index + 1]
            t := MapGet(point, "t", 0)
            waitMs := Round((t - prevT) / speed)
            if waitMs > 0
                SmartSleep(waitMs)
            if gStopRequested
                break

            p := ResolveScreenPoint(winMeta, MapGet(point, "x", 0), MapGet(point, "y", 0), MapGet(point, "screenX", 0), MapGet(point, "screenY", 0))
            MouseMove(p["x"], p["y"], 0)
            prevT := t
        }

        remain := Round((duration - prevT) / speed)
        if remain > 0
            SmartSleep(remain)
    } else {
        SmartSleep(Round(duration / speed))

        ; 没有轨迹时，至少移动到释放点，支持简单拖拽。
        endX := MapGet(evt, "endX", MapGet(evt, "x", 0))
        endY := MapGet(evt, "endY", MapGet(evt, "y", 0))
        endScreenX := MapGet(evt, "endScreenX", MapGet(evt, "screenX", 0))
        endScreenY := MapGet(evt, "endScreenY", MapGet(evt, "screenY", 0))
        endPoint := ResolveScreenPoint(winMeta, endX, endY, endScreenX, endScreenY)
        MouseMove(endPoint["x"], endPoint["y"], 0)
    }

    Send("{" ahkButton " Up}")
}

ExecuteWheelEvent(evt) {
    winMeta := MapGet(evt, "win", "")
    ActivateEventWindow(winMeta)

    p := ResolveScreenPoint(winMeta, MapGet(evt, "x", 0), MapGet(evt, "y", 0), MapGet(evt, "screenX", 0), MapGet(evt, "screenY", 0))
    MouseMove(p["x"], p["y"], 0)
    SmartSleep(20)
    Click(MapGet(evt, "button", "WheelDown"))
}

ExecuteLegacyMouseEvent(evt) {
    winMeta := MapGet(evt, "win", "")
    ActivateEventWindow(winMeta)

    p := ResolveScreenPoint(winMeta, MapGet(evt, "x", 0), MapGet(evt, "y", 0), MapGet(evt, "screenX", 0), MapGet(evt, "screenY", 0))
    MouseMove(p["x"], p["y"], 0)
    SmartSleep(30)
    Click(MapGet(evt, "button", "Left"))
}

ActivateEventWindow(winMeta) {
    hwnd := FindWindowByMeta(winMeta)
    if hwnd {
        try {
            WinActivate("ahk_id " hwnd)
            WinWaitActive("ahk_id " hwnd, , 0.5)
        }
    }
    return hwnd
}

ApplyImeSnapshotIfNeeded(snapshot, hwnd := 0) {
    global gLastPlaybackImeKey

    if !IsObject(snapshot)
        return

    key := hwnd "|"
        . MapGet(snapshot, "hkl", 0) "|"
        . MapGet(snapshot, "open", "") "|"
        . MapGet(snapshot, "conversion", "") "|"
        . MapGet(snapshot, "sentence", "")

    if key = gLastPlaybackImeKey
        return

    ApplyImeSnapshot(snapshot, hwnd)
    gLastPlaybackImeKey := key
}

GetImeSnapshot(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")

    hkl := GetKeyboardLayoutForWindow(hwnd)
    langId := hkl ? (hkl & 0xFFFF) : 0
    snapshot := Map(
        "available", false,
        "hkl", hkl,
        "langId", langId
    )

    imeHwnd := GetDefaultImeWindow(hwnd)
    if !imeHwnd
        return snapshot

    snapshot["available"] := true

    ; WM_IME_CONTROL: 记录输入法开关、转换模式和句子模式，给物理键回放兜底。
    try snapshot["open"] := ImeSendMessage(imeHwnd, 0x0005, 0)
    try snapshot["conversion"] := ImeSendMessage(imeHwnd, 0x0001, 0)
    try snapshot["sentence"] := ImeSendMessage(imeHwnd, 0x0003, 0)

    return snapshot
}

ApplyImeSnapshot(snapshot, hwnd := 0) {
    if !IsObject(snapshot)
        return

    hkl := MapGet(snapshot, "hkl", 0)
    if hkl
        ActivateKeyboardLayoutForWindow(hkl, hwnd)

    try {
        imeHwnd := GetDefaultImeWindow(hwnd)
        if !imeHwnd
            return

        if snapshot.Has("open")
            ImeSendMessage(imeHwnd, 0x0006, snapshot["open"])
        if snapshot.Has("conversion")
            ImeSendMessage(imeHwnd, 0x0002, snapshot["conversion"])
        if snapshot.Has("sentence")
            ImeSendMessage(imeHwnd, 0x0004, snapshot["sentence"])
        Sleep(20)
    }
}

GetKeyboardLayoutForWindow(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd
        return 0

    try {
        threadId := DllCall("user32\GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        if !threadId
            return 0
        return DllCall("user32\GetKeyboardLayout", "UInt", threadId, "Ptr")
    }

    return 0
}

IsCjkKeyboardLayout(hkl) {
    if !hkl
        return false

    ; LANG_CHINESE = 0x04, LANG_JAPANESE = 0x11, LANG_KOREAN = 0x12.
    langId := hkl & 0xFFFF
    primaryLang := langId & 0x03FF
    return primaryLang = 0x04 || primaryLang = 0x11 || primaryLang = 0x12
}

ActivateKeyboardLayoutForWindow(hkl, hwnd := 0) {
    if !hkl
        return

    try DllCall("user32\ActivateKeyboardLayout", "Ptr", hkl, "UInt", 0, "Ptr")

    if hwnd {
        ; WM_INPUTLANGCHANGEREQUEST lets the target app switch to the recorded layout.
        try DllCall("user32\PostMessageW", "Ptr", hwnd, "UInt", 0x0050, "Ptr", 0, "Ptr", hkl, "Int")
        Sleep(60)
    }
}

ImeSendMessage(imeHwnd, command, value := 0) {
    if !imeHwnd
        return 0

    return DllCall("user32\SendMessageW", "Ptr", imeHwnd, "UInt", 0x0283, "Ptr", command, "Ptr", value, "Ptr")
}

GetDefaultImeWindow(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd
        return 0

    try return DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    return 0
}

ResolveScreenPoint(winMeta, relX, relY, fallbackX, fallbackY) {
    hwnd := FindWindowByMeta(winMeta)

    if hwnd {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            return Map("x", wx + relX, "y", wy + relY)
        }
    }

    return Map("x", fallbackX, "y", fallbackY)
}

PlaybackModeChanged(mode, *) {
    global gModeOnce, gModeCount, gModeDuration, gPlaybackMode

    gPlaybackMode := mode

    gModeOnce.Value := mode = "once"
    gModeCount.Value := mode = "count"
    gModeDuration.Value := mode = "duration"
}

GetPlaybackMode() {
    global gPlaybackMode, gCountEdit, gDurationEdit

    if gPlaybackMode = "count" {
        count := gCountEdit.Value + 0
        if count < 1
            count := 1

        return Map("type", "count", "count", count)
    }

    if gPlaybackMode = "duration" {
        minutes := gDurationEdit.Value + 0
        if minutes < 1
            minutes := 1

        return Map("type", "duration", "minutes", minutes)
    }

    return Map("type", "once")
}

GetPlaybackSpeed() {
    global gSpeedDDL

    speedText := gSpeedDDL.Text
    speedText := StrReplace(speedText, "x", "")
    speed := speedText + 0
    if speed <= 0
        speed := 1.0

    return speed
}

SmartSleep(ms) {
    global gStopRequested

    if ms <= 0
        return

    endTick := A_TickCount + ms
    while !gStopRequested && A_TickCount < endTick {
        remain := endTick - A_TickCount
        Sleep(Min(50, remain))
    }
}

EmergencyStop(*) {
    global gIsRecording, gIsPlaying, gStopRequested, gMouseDown

    gStopRequested := true
    StopClicker()

    if gIsRecording {
        gIsRecording := false
        gMouseDown := Map()
        StopDragTimer()
        StopKeyboardHook()
        SetStatus("已紧急停止录制。")
    }

    if gIsPlaying {
        SetStatus("已请求停止回放。")
    } else if !gIsRecording {
        SetStatus("已执行紧急停止。")
    }

    ShowHint("■ 已停止`n当前没有自动操作运行")
    SetTimer(HideHint, -1200)
}

; ============================================================
; 连点器模块
; ============================================================

ToggleClicker(*) {
    global gClickerRunning

    if gClickerRunning
        StopClicker()
    else
        StartClicker()
}

StartClicker(*) {
    global gClickerRunning, gClickerIntervalEdit, gClickerStatusText
    global gIsRecording, gIsPlaying

    if gIsRecording || gIsPlaying {
        MsgBox("录制或回放时不启动连点器，避免互相干扰。", APP_NAME, "Icon!")
        return
    }

    interval := GetClickerInterval()
    gClickerRunning := true
    SetTimer(ClickerTick, interval)

    if IsObject(gClickerStatusText)
        gClickerStatusText.Value := "连点器状态：运行中，间隔 " interval " ms。F10 暂停，F8 停止。"

    ShowHint("● 连点器运行中`nF10 暂停 / F8 停止`n间隔：" interval " ms")
    SetStatus("连点器运行中。")
}

StopClicker(*) {
    global gClickerRunning, gClickerStatusText

    if !gClickerRunning {
        if IsObject(gClickerStatusText)
            gClickerStatusText.Value := "连点器状态：未运行。F10 启停，F8 紧急停止。"
        return
    }

    SetTimer(ClickerTick, 0)
    gClickerRunning := false

    if IsObject(gClickerStatusText)
        gClickerStatusText.Value := "连点器状态：已停止。F10 启停，F8 紧急停止。"

    HideHint()
    SetStatus("连点器已停止。")
}

ClickerTick() {
    global gClickerRunning, gClickerActionDDL, gClickerSendEdit

    if !gClickerRunning
        return

    action := IsObject(gClickerActionDDL) ? gClickerActionDDL.Text : "鼠标左键"

    switch action {
        case "鼠标左键":
            Click("Left")
        case "鼠标右键":
            Click("Right")
        case "鼠标中键":
            Click("Middle")
        case "按键/组合键":
            sendText := IsObject(gClickerSendEdit) ? Trim(gClickerSendEdit.Value) : ""
            if sendText != ""
                Send(sendText)
    }
}

GetClickerInterval() {
    global gClickerIntervalEdit

    interval := 100
    if IsObject(gClickerIntervalEdit)
        interval := gClickerIntervalEdit.Value + 0

    if interval < 10
        interval := 10
    if interval > 600000
        interval := 600000

    return interval
}

; ============================================================
; 定时模块
; ============================================================

CheckSchedule() {
    global gScheduleEnable, gScheduleTimeEdit, gLastScheduleKey
    global gIsRecording, gIsPlaying, gClickerRunning

    if !IsObject(gScheduleEnable)
        return

    if !gScheduleEnable.Value
        return

    if gIsRecording || gIsPlaying || gClickerRunning
        return

    target := Trim(gScheduleTimeEdit.Value)
    if !RegExMatch(target, "^\d{1,2}:\d{2}$")
        return

    parts := StrSplit(target, ":")
    hh := parts[1] + 0
    mm := parts[2] + 0
    if hh < 0 || hh > 23 || mm < 0 || mm > 59
        return

    nowHM := FormatTime(A_Now, "HH:mm")
    runKey := FormatTime(A_Now, "yyyyMMdd") "-" Format("{:02d}:{:02d}", hh, mm)

    if nowHM = Format("{:02d}:{:02d}", hh, mm) && gLastScheduleKey != runKey {
        gLastScheduleKey := runKey
        SetStatus("定时任务触发，准备回放。")
        PlaySelected()
    }
}

; ============================================================
; 文件模块
; ============================================================

SaveRecording(*) {
    global gEvents, gRecordingName, gRecordingStartedAt, gBaseWindow
    global gNameEdit, gCurrentMacro

    if gEvents.Length = 0 {
        MsgBox("当前没有可保存的录制内容。", APP_NAME, "Icon!")
        return
    }

    name := Trim(gNameEdit.Value)
    if name = ""
        name := gRecordingName
    if name = ""
        name := "未命名_" FormatTime(A_Now, "yyyyMMdd_HHmmss")

    macro := Map(
        "appVersion", APP_NAME,
        "name", name,
        "createdAt", gRecordingStartedAt != "" ? gRecordingStartedAt : FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"),
        "coordMode", "window",
        "recordingOptions", Map(
            "textMode", IsTextRecordingEnabled(),
            "dragPath", IsDragRecordingEnabled(),
            "mouseHold", IsMouseHoldRecordingEnabled()
        ),
        "targetWindow", gBaseWindow,
        "events", gEvents
    )

    safeName := SanitizeFileName(name)
    file := MACRO_DIR "\" safeName ".json"

    if FileExist(file) {
        result := MsgBox("同名录制已存在，是否覆盖？`n`n" safeName ".json", APP_NAME, "YesNo Icon?")
        if result != "Yes" {
            file := MACRO_DIR "\" safeName "_" FormatTime(A_Now, "yyyyMMdd_HHmmss") ".json"
        }
    }

    try {
        FileDelete(file)
    }

    try {
        FileAppend(JsonDump(macro), file, "UTF-8")
        gCurrentMacro := macro
        RefreshMacroList(file)
        SetStatus("已保存：" file)
        TrayTip("录制已保存：" safeName ".json", APP_NAME)
    } catch as err {
        MsgBox("保存失败：`n" err.Message, APP_NAME, "Iconx")
    }
}

RefreshMacroList(selectFile := "") {
    global MACRO_DIR, gMacroList, gMacroIndex

    if !IsObject(gMacroList)
        return

    gMacroIndex := Map()
    items := []

    Loop Files MACRO_DIR "\*.json", "F" {
        display := RegExReplace(A_LoopFileName, "\.json$")
        gMacroIndex[display] := A_LoopFileFullPath
        items.Push(display)
    }

    gMacroList.Delete()
    if items.Length > 0 {
        gMacroList.Add(items)

        chooseIndex := 1
        if selectFile != "" {
            selectedDisplay := RegExReplace(SplitPathName(selectFile), "\.json$")
            for i, item in items {
                if item = selectedDisplay {
                    chooseIndex := i
                    break
                }
            }
        }

        gMacroList.Choose(chooseIndex)
    }
}

LoadSelectedMacro(*) {
    global gMacroList, gMacroIndex

    if !IsObject(gMacroList) || gMacroList.Text = "" {
        MsgBox("请先选择一个录制文件。", APP_NAME, "Icon!")
        return false
    }

    display := gMacroList.Text
    if !gMacroIndex.Has(display) {
        MsgBox("找不到对应的录制文件。", APP_NAME, "Icon!")
        return false
    }

    return LoadMacroFromFile(gMacroIndex[display])
}

EnsureMacroLoaded() {
    global gEvents

    if gEvents.Length > 0
        return true

    return LoadSelectedMacro()
}

LoadMacroFromFile(file) {
    global gCurrentMacro, gEvents, gNameEdit

    try {
        text := FileRead(file, "UTF-8")
        macro := JsonLoad(text)

        if !IsObject(macro) || !macro.Has("events") {
            MsgBox("文件格式不正确，缺少 events。", APP_NAME, "Icon!")
            return false
        }

        gCurrentMacro := macro
        gEvents := macro["events"]

        if macro.Has("name")
            gNameEdit.Value := macro["name"]

        UpdateEventCount()
        SetStatus("已加载：" MapGet(macro, "name", SplitPathName(file)) "，共 " gEvents.Length " 步。")
        return true
    } catch as err {
        MsgBox("加载失败：`n" err.Message, APP_NAME, "Iconx")
        return false
    }
}

DeleteSelectedMacro(*) {
    global gMacroList, gMacroIndex, gEvents, gCurrentMacro

    if !IsObject(gMacroList) || gMacroList.Text = "" {
        MsgBox("请先选择一个录制文件。", APP_NAME, "Icon!")
        return
    }

    display := gMacroList.Text
    if !gMacroIndex.Has(display) {
        MsgBox("找不到对应的录制文件。", APP_NAME, "Icon!")
        return
    }

    file := gMacroIndex[display]
    result := MsgBox("确定删除这个录制文件吗？`n`n" display, APP_NAME, "YesNo Icon?")
    if result != "Yes"
        return

    try {
        FileDelete(file)
        gEvents := []
        gCurrentMacro := Map()
        RefreshMacroList()
        UpdateEventCount()
        SetStatus("已删除：" display)
    } catch as err {
        MsgBox("删除失败：`n" err.Message, APP_NAME, "Iconx")
    }
}

SanitizeFileName(name) {
    name := Trim(name)
    name := RegExReplace(name, '[\\/:*?"<>|]', "_")
    name := RegExReplace(name, "\s+", " ")
    if name = ""
        name := "未命名_" FormatTime(A_Now, "yyyyMMdd_HHmmss")
    return name
}

SplitPathName(path) {
    SplitPath(path, &name)
    return name
}

; ============================================================
; 窗口定位
; ============================================================

GetWindowMeta(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")

    meta := Map("hwnd", hwnd, "title", "", "class", "", "process", "")

    try meta["title"] := WinGetTitle("ahk_id " hwnd)
    try meta["class"] := WinGetClass("ahk_id " hwnd)
    try meta["process"] := WinGetProcessName("ahk_id " hwnd)

    return meta
}

FindWindowByMeta(meta) {
    if !IsObject(meta)
        return 0

    hwnd := MapGet(meta, "hwnd", 0)
    if hwnd {
        try {
            if WinExist("ahk_id " hwnd)
                return hwnd
        }
    }

    title := MapGet(meta, "title", "")
    cls := MapGet(meta, "class", "")
    exe := MapGet(meta, "process", "")

    candidates := []

    if title != "" && cls != "" && exe != ""
        candidates.Push(title " ahk_class " cls " ahk_exe " exe)
    if cls != "" && exe != ""
        candidates.Push("ahk_class " cls " ahk_exe " exe)
    if exe != ""
        candidates.Push("ahk_exe " exe)
    if title != ""
        candidates.Push(title)

    for _, query in candidates {
        try {
            found := WinExist(query)
            if found
                return found
        }
    }

    return 0
}

; ============================================================
; 提示窗口
; ============================================================

BuildHintGui() {
    global gHintGui, gHintText

    gHintGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    gHintGui.BackColor := "202020"
    gHintGui.SetFont("s11 cWhite", "Microsoft YaHei UI")
    gHintText := gHintGui.Add("Text", "x12 y10 w280 h80 Center", "")
}

ShowHint(text) {
    global gHintGui, gHintText

    if !IsObject(gHintGui)
        BuildHintGui()

    gHintText.Value := text
    x := A_ScreenWidth - 330
    y := 50
    gHintGui.Show("x" x " y" y " w305 h100 NoActivate")
}

HideHint(*) {
    global gHintGui

    if IsObject(gHintGui)
        gHintGui.Hide()
}

FormatMs(ms) {
    totalSec := Floor(ms / 1000)
    h := Floor(totalSec / 3600)
    m := Floor(Mod(totalSec, 3600) / 60)
    s := Mod(totalSec, 60)

    if h > 0
        return Format("{:02d}:{:02d}:{:02d}", h, m, s)

    return Format("{:02d}:{:02d}", m, s)
}

MapGet(mapObj, key, defaultValue := "") {
    if IsObject(mapObj) {
        try {
            if mapObj.Has(key)
                return mapObj[key]
        }
    }

    return defaultValue
}

IsInternalWindow(hwnd) {
    global gGui, gHintGui

    if !hwnd
        return false

    if IsObject(gGui) && hwnd = gGui.Hwnd
        return true

    if IsObject(gHintGui) && hwnd = gHintGui.Hwnd
        return true

    return false
}

; ============================================================
; JSON：轻量 Dump / Load
; 说明：只用于本工具保存的宏文件。支持 Map / Array / String / Number / true / false / null。
; ============================================================

JsonDump(value, indent := 2) {
    return JsonDumpValue(value, 0, indent)
}

JsonDumpValue(value, level, indent) {
    t := Type(value)

    if t = "Map" {
        pieces := []
        for k, v in value {
            pieces.Push(JsonQuote(k) ": " JsonDumpValue(v, level + 1, indent))
        }

        if pieces.Length = 0
            return "{}"

        pad := Spaces((level + 1) * indent)
        endPad := Spaces(level * indent)
        return "{`n" pad Join(pieces, ",`n" pad) "`n" endPad "}"
    }

    if t = "Array" {
        pieces := []
        for _, v in value {
            pieces.Push(JsonDumpValue(v, level + 1, indent))
        }

        if pieces.Length = 0
            return "[]"

        pad := Spaces((level + 1) * indent)
        endPad := Spaces(level * indent)
        return "[`n" pad Join(pieces, ",`n" pad) "`n" endPad "]"
    }

    if t = "Integer" || t = "Float"
        return String(value)

    if t = "String"
        return JsonQuote(value)

    ; true / false 在 AHK 中通常也是 1 / 0，这里兜底转为字符串。
    return JsonQuote(String(value))
}

JsonQuote(str) {
    BS := Chr(92)
    DQ := Chr(34)
    out := DQ

    Loop Parse str {
        ch := A_LoopField
        code := Ord(ch)

        switch ch {
            case DQ:
                out .= BS DQ
            case BS:
                out .= BS BS
            case "`b":
                out .= BS "b"
            case "`f":
                out .= BS "f"
            case "`n":
                out .= BS "n"
            case "`r":
                out .= BS "r"
            case "`t":
                out .= BS "t"
            default:
                if code < 32
                    out .= BS "u" Format("{:04X}", code)
                else
                    out .= ch
        }
    }

    out .= DQ
    return out
}

Spaces(count) {
    if count <= 0
        return ""

    s := ""
    Loop count
        s .= " "
    return s
}

Join(arr, sep) {
    out := ""
    for i, v in arr {
        if i > 1
            out .= sep
        out .= v
    }
    return out
}

JsonLoad(text) {
    reader := JsonReader(text)
    return reader.Parse()
}

class JsonReader {
    __New(text) {
        this.text := text
        this.pos := 1
        this.len := StrLen(text)
    }

    Parse() {
        this.SkipWs()
        value := this.ParseValue()
        this.SkipWs()
        return value
    }

    ParseValue() {
        this.SkipWs()
        ch := this.Peek()

        if ch = "{"
            return this.ParseObject()

        if ch = "["
            return this.ParseArray()

        if ch = Chr(34)
            return this.ParseString()

        if ch = "-" || RegExMatch(ch, "\d")
            return this.ParseNumber()

        if this.MatchLiteral("true")
            return true

        if this.MatchLiteral("false")
            return false

        if this.MatchLiteral("null")
            return ""

        throw Error("JSON 解析失败：未知值，位置 " this.pos)
    }

    ParseObject() {
        obj := Map()
        this.Expect("{")
        this.SkipWs()

        if this.Peek() = "}" {
            this.pos += 1
            return obj
        }

        Loop {
            this.SkipWs()
            key := this.ParseString()
            this.SkipWs()
            this.Expect(":")
            value := this.ParseValue()
            obj[key] := value
            this.SkipWs()

            ch := this.Peek()
            if ch = "}" {
                this.pos += 1
                break
            }

            this.Expect(",")
        }

        return obj
    }

    ParseArray() {
        arr := []
        this.Expect("[")
        this.SkipWs()

        if this.Peek() = "]" {
            this.pos += 1
            return arr
        }

        Loop {
            value := this.ParseValue()
            arr.Push(value)
            this.SkipWs()

            ch := this.Peek()
            if ch = "]" {
                this.pos += 1
                break
            }

            this.Expect(",")
        }

        return arr
    }

    ParseString() {
        BS := Chr(92)
        DQ := Chr(34)

        this.Expect(DQ)
        out := ""

        while this.pos <= this.len {
            ch := SubStr(this.text, this.pos, 1)
            this.pos += 1

            if ch = DQ
                return out

            if ch = BS {
                if this.pos > this.len
                    throw Error("JSON 字符串转义不完整。")

                esc := SubStr(this.text, this.pos, 1)
                this.pos += 1

                switch esc {
                    case DQ:
                        out .= DQ
                    case BS:
                        out .= BS
                    case "/":
                        out .= "/"
                    case "b":
                        out .= Chr(8)
                    case "f":
                        out .= Chr(12)
                    case "n":
                        out .= "`n"
                    case "r":
                        out .= "`r"
                    case "t":
                        out .= "`t"
                    case "u":
                        hex := SubStr(this.text, this.pos, 4)
                        if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                            throw Error("JSON unicode 转义无效。")
                        this.pos += 4
                        out .= Chr("0x" hex)
                    default:
                        throw Error("JSON 字符串转义无效：\" esc)
                }
            } else {
                out .= ch
            }
        }

        throw Error("JSON 字符串缺少结束引号。")
    }

    ParseNumber() {
        start := this.pos

        while this.pos <= this.len {
            ch := SubStr(this.text, this.pos, 1)
            if !RegExMatch(ch, "[0-9eE+\-.]")
                break
            this.pos += 1
        }

        token := SubStr(this.text, start, this.pos - start)
        if token = ""
            throw Error("JSON 数字为空。")

        return token + 0
    }

    SkipWs() {
        while this.pos <= this.len {
            ch := SubStr(this.text, this.pos, 1)
            if ch != " " && ch != "`t" && ch != "`r" && ch != "`n"
                break
            this.pos += 1
        }
    }

    Peek() {
        if this.pos > this.len
            return ""
        return SubStr(this.text, this.pos, 1)
    }

    Expect(expected) {
        actual := this.Peek()
        if actual != expected
            throw Error("JSON 解析失败：期望 " expected "，实际 " actual "，位置 " this.pos)
        this.pos += 1
    }

    MatchLiteral(lit) {
        len := StrLen(lit)
        if SubStr(this.text, this.pos, len) = lit {
            this.pos += len
            return true
        }
        return false
    }
}
