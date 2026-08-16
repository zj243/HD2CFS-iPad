//
// KeyValues.swift
// 服务器按键映射的可选键值与按键类型（M6）
// 完整对照 server_api_6.md 附录，值必须原样发送给服务器，禁止改写
// 作者: ZJ
//

import Foundation

/// 一个可选键值：value 为协议值，label 为中文说明（无说明的按键直接显示值）
struct KeyOption: Identifiable {
    let value: String
    let label: String

    var id: String { value }

    /// 选择器显示文本
    var display: String {
        label.isEmpty ? value : "\(label)（\(value)）"
    }
}

enum KeyValues {
    /// 全部按键值（顺序与 server_api_6.md 附录一致：修饰键、方向、数字、字母、符号、功能键、小键盘、鼠标）
    static let keys: [KeyOption] = [
        KeyOption(value: "alt", label: "左Alt"),
        KeyOption(value: "alt_gr", label: "右Alt"),
        KeyOption(value: "ctrl_left", label: "左Ctrl"),
        KeyOption(value: "ctrl_right", label: "右Ctrl"),
        KeyOption(value: "shift_left", label: "左Shift"),
        KeyOption(value: "shift_right", label: "右Shift"),
        KeyOption(value: "up", label: "上箭头"),
        KeyOption(value: "down", label: "下箭头"),
        KeyOption(value: "left", label: "左箭头"),
        KeyOption(value: "right", label: "右箭头"),
        KeyOption(value: "1", label: ""), KeyOption(value: "2", label: ""),
        KeyOption(value: "3", label: ""), KeyOption(value: "4", label: ""),
        KeyOption(value: "5", label: ""), KeyOption(value: "6", label: ""),
        KeyOption(value: "7", label: ""), KeyOption(value: "8", label: ""),
        KeyOption(value: "9", label: ""), KeyOption(value: "0", label: ""),
        KeyOption(value: "a", label: ""), KeyOption(value: "b", label: ""),
        KeyOption(value: "c", label: ""), KeyOption(value: "d", label: ""),
        KeyOption(value: "e", label: ""), KeyOption(value: "f", label: ""),
        KeyOption(value: "g", label: ""), KeyOption(value: "h", label: ""),
        KeyOption(value: "i", label: ""), KeyOption(value: "j", label: ""),
        KeyOption(value: "k", label: ""), KeyOption(value: "l", label: ""),
        KeyOption(value: "m", label: ""), KeyOption(value: "n", label: ""),
        KeyOption(value: "o", label: ""), KeyOption(value: "p", label: ""),
        KeyOption(value: "q", label: ""), KeyOption(value: "r", label: ""),
        KeyOption(value: "s", label: ""), KeyOption(value: "t", label: ""),
        KeyOption(value: "u", label: ""), KeyOption(value: "v", label: ""),
        KeyOption(value: "w", label: ""), KeyOption(value: "x", label: ""),
        KeyOption(value: "y", label: ""), KeyOption(value: "z", label: ""),
        KeyOption(value: "`", label: ""), KeyOption(value: "-", label: ""),
        KeyOption(value: "=", label: ""), KeyOption(value: ";", label: ""),
        KeyOption(value: "'", label: ""), KeyOption(value: "\\", label: ""),
        KeyOption(value: ",", label: ""), KeyOption(value: ".", label: ""),
        KeyOption(value: "/", label: ""),
        KeyOption(value: "f1", label: ""), KeyOption(value: "f2", label: ""),
        KeyOption(value: "f3", label: ""), KeyOption(value: "f4", label: ""),
        KeyOption(value: "f5", label: ""), KeyOption(value: "f6", label: ""),
        KeyOption(value: "f7", label: ""), KeyOption(value: "f8", label: ""),
        KeyOption(value: "f9", label: ""), KeyOption(value: "f10", label: ""),
        KeyOption(value: "f11", label: ""), KeyOption(value: "f12", label: ""),
        KeyOption(value: "backspace", label: "退格"),
        KeyOption(value: "enter", label: "回车"),
        KeyOption(value: "delete", label: "Delete"),
        KeyOption(value: "caps_lock", label: "大写锁定"),
        KeyOption(value: "space", label: "空格"),
        KeyOption(value: "tab", label: "Tab"),
        KeyOption(value: "fn", label: "Fn"),
        KeyOption(value: "insert", label: "Insert"),
        KeyOption(value: "home", label: "Home"),
        KeyOption(value: "end", label: "End"),
        KeyOption(value: "esc", label: "Esc"),
        KeyOption(value: "page_down", label: "PageDown"),
        KeyOption(value: "page_up", label: "PageUp"),
        KeyOption(value: "print_screen", label: "PrintScreen"),
        KeyOption(value: "scroll_lock", label: "ScrollLock"),
        KeyOption(value: "num_lock", label: "NumLock"),
        KeyOption(value: "pause", label: "Pause"),
        KeyOption(value: "kp-", label: "小键盘 -"),
        KeyOption(value: "kp+", label: "小键盘 +"),
        KeyOption(value: "kp*", label: "小键盘 *"),
        KeyOption(value: "kp/", label: "小键盘 /"),
        KeyOption(value: "kp0", label: "小键盘 0"),
        KeyOption(value: "kp1", label: "小键盘 1"),
        KeyOption(value: "kp2", label: "小键盘 2"),
        KeyOption(value: "kp3", label: "小键盘 3"),
        KeyOption(value: "kp4", label: "小键盘 4"),
        KeyOption(value: "kp5", label: "小键盘 5"),
        KeyOption(value: "kp6", label: "小键盘 6"),
        KeyOption(value: "kp7", label: "小键盘 7"),
        KeyOption(value: "kp8", label: "小键盘 8"),
        KeyOption(value: "kp9", label: "小键盘 9"),
        KeyOption(value: "kp_delete", label: "小键盘 Delete"),
        KeyOption(value: "mouse_left", label: "鼠标左键"),
        KeyOption(value: "mouse_right", label: "鼠标右键"),
        KeyOption(value: "mouse_middle", label: "鼠标中键"),
        KeyOption(value: "mouse3", label: "鼠标侧键 1"),
        KeyOption(value: "mouse4", label: "鼠标侧键 2"),
        KeyOption(value: "mouse5", label: "鼠标侧键 3"),
        KeyOption(value: "wheel_up", label: "鼠标滚轮 上"),
        KeyOption(value: "wheel_down", label: "鼠标滚轮 下"),
    ]

    /// "打开战备列表"键的按法
    static let keyTypes: [KeyOption] = [
        KeyOption(value: "hold", label: "按住"),
        KeyOption(value: "press", label: "按下"),
        KeyOption(value: "long_press", label: "长按"),
        KeyOption(value: "tap", label: "点击"),
        KeyOption(value: "double_tap", label: "双击"),
    ]
}
