#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"       ; 提高进程优先级，减少延迟

; ==============================================================================
;  NoFsPopup v1.0
;  功能: 阻止 Chrome/Edge 全屏模式下鼠标触顶弹出的 "X" 提示条。
;  原理: 当鼠标移动到屏幕最顶端 Y=0 时，自动将其限制在安全区域，避免触发弹窗。
;  更新: v1.0 初始版本发布。
; ==============================================================================

; --- DPI 感知设置 ---
try {
    DllCall("SetThreadDpiAwarenessContext", "Ptr", -4) ; Per-Monitor V2
} catch {
    try {
        DllCall("Shcore\SetProcessDpiAwareness", "Int", 2) ; Per-Monitor
    } catch {
        DllCall("SetProcessDPIAware") ; System
    }
}
SetWinDelay 0

; --- 目标窗口设置 ---
ChromiumWindowClasses := ["Chrome_WidgetWin_1", "Chrome_WidgetWin_0"]

; ==============================================================================
;  初始化
; ==============================================================================
SetTimer BlockTopEdgeInFullscreen, 5
OnExit( (*) => DllCall("ClipCursor", "Ptr", 0) )

; ==============================================================================
;  核心逻辑
; ==============================================================================

BlockTopEdgeInFullscreen() {
    static IsTrapped := false
    static LastRect := Buffer(16, 0)
    global ChromiumWindowClasses

    CoordMode "Mouse", "Screen"
    MouseGetPos(&mx, &my, &hw)

    ; 1. 获取根窗口
    try {
        if (root := DllCall("GetAncestor", "Ptr", hw, "UInt", 2, "Ptr"))
            hw := root
    }

    shouldTrap := false

    if (hw && WinExist("ahk_id " . hw)) {
        try {
            cls := WinGetClass("ahk_id " . hw)
            isChromium := false
            for c in ChromiumWindowClasses {
                if (cls = c) {
                    isChromium := true
                    break
                }
            }

            if (isChromium) {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hw)
                hMonitor := DllCall("MonitorFromWindow", "Ptr", hw, "UInt", 2, "Ptr")

                if (hMonitor) {
                    ; --- DPI 缩放检测 ---
                    dpiX := 96
                    try {
                        DllCall("Shcore\GetDpiForMonitor", "Ptr", hMonitor, "Int", 0, "UInt*", &dpiX, "UInt*", 0)
                    }

                    ; --- 统一硬限制计算 (根据用户指定映射) ---
                    ; 250% (240 DPI) -> 8px
                    ; 200-225% (192-216 DPI) -> 7px
                    ; 175% (168 DPI) -> 6px
                    ; 150% (144 DPI) -> 5px
                    ; 100-125% (96-120 DPI) -> 4px

                    if (dpiX >= 240) {
                        TopMargin := 8
                    } else if (dpiX >= 192) {
                        TopMargin := 7
                    } else if (dpiX >= 168) {
                        TopMargin := 6
                    } else if (dpiX >= 144) {
                        TopMargin := 5
                    } else {
                        TopMargin := 4
                    }

                    NumPut("UInt", 40, mi := Buffer(40))
                    DllCall("GetMonitorInfo", "Ptr", hMonitor, "Ptr", mi)
                    monLeft := NumGet(mi, 4, "Int")
                    monTop := NumGet(mi, 8, "Int")
                    monRight := NumGet(mi, 12, "Int")
                    monBottom := NumGet(mi, 16, "Int")

                    ; 判定全屏
                    if (wx <= monLeft && wy <= monTop && ww >= (monRight - monLeft) && wh >= (monBottom - monTop)) {
                        shouldTrap := true

                        ; 计算限制区域 (单一硬限制 + 无限延伸)
                        limitTop := monTop + TopMargin
                        limitLeft := monLeft - 50000
                        limitRight := monRight + 50000
                        limitBottom := monBottom + 50000

                        ; 应用限制 (防抖)
                        if (!IsTrapped || NumGet(LastRect, 4, "Int") != limitTop) {
                            Rect := Buffer(16)
                            NumPut("Int", limitLeft, Rect, 0)
                            NumPut("Int", limitTop, Rect, 4)
                            NumPut("Int", limitRight, Rect, 8)
                            NumPut("Int", limitBottom, Rect, 12)

                            DllCall("ClipCursor", "Ptr", Rect)

                            NumPut("Int", limitLeft, LastRect, 0)
                            NumPut("Int", limitTop, LastRect, 4)
                            NumPut("Int", limitRight, LastRect, 8)
                            NumPut("Int", limitBottom, LastRect, 12)
                            IsTrapped := true
                        }
                    }
                }
            }
        }
    }

    ; 释放限制
    if (!shouldTrap && IsTrapped) {
        DllCall("ClipCursor", "Ptr", 0)
        IsTrapped := false
        NumPut("Int64", 0, LastRect, 0)
        NumPut("Int64", 0, LastRect, 8)
    }
}
