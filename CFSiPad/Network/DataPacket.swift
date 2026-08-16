//
// DataPacket.swift
// 协议报文定义（API 6）：字段名与服务器 JSON 完全一致，禁止改名（见 PLAN.md 3.1 节）
// 对照安卓版 network/DataPacket.kt 与 server_api_6.md
// 作者: ZJ
//

import Foundation

// MARK: - opt 0 状态查询

/// 查询服务器状态（也用作 10 秒心跳），携带客户端协议版本
struct RequestStatusPacket: Codable {
    var api: Int
    var opt: Int = 0
}

/// 状态查询响应；status: 0 就绪 / 1 版本不符 / 2 未认证
struct ReceiveStatusData: Codable {
    var status: Int
    var api: Int
}

// MARK: - opt 1 战备宏

/// 战备宏：steps 为方向序列，1上 2下 3左 4右
struct StratagemMacroData: Codable {
    var name: String
    var steps: [Int]
}

/// 激活战备宏（服务器按配置连按方向键，无回包）
struct RequestMacroPacket: Codable {
    var macro: StratagemMacroData
    var token: String
    var opt: Int = 1
}

// MARK: - opt 2 单键输入（自由输入模式）

/// 单键输入：type 0点击/1按下/2释放/3自由输入开始(按住打开战备列表键)/4自由输入结束；
/// step 0打开战备列表/1上/2下/3左/4右
struct StratagemInputData: Codable {
    var step: Int
    var type: Int
}

/// 发送单键输入（无回包）
struct RequestInputPacket: Codable {
    var input: StratagemInputData
    var token: String
    var opt: Int = 2
}

// MARK: - opt 3 获取服务器配置

/// 请求服务器当前配置；注意该响应末尾没有换行符（分帧层已兼容）
struct RequestConfigPacket: Codable {
    var token: String
    var opt: Int = 3
}

// MARK: - opt 4 下发服务器配置

/// 服务器完整配置。下发时必须整包发送（服务器整体替换），默认值与安卓版一致
struct SyncConfigData: Codable {
    var server: SyncConfigServerData = SyncConfigServerData()
    var input: SyncConfigInputData = SyncConfigInputData()
    var auth: SyncConfigAuthData = SyncConfigAuthData()
    var debug: Bool = false
    var records: [Int] = []
}

struct SyncConfigServerData: Codable {
    var port: Int = 23333
    var ip: String = ""
}

struct SyncConfigAuthData: Codable {
    var enabled: Bool = true
    var timeout: Int = 3
}

/// 按键映射：open 为"打开战备列表"键，keytype 为其按法（hold/press/long_press/tap/double_tap），
/// 键值字符串表见 server_api_6.md 附录
struct SyncConfigInputData: Codable {
    var delay: Int = 25
    var open: String = "ctrl_left"
    var keytype: String = "hold"
    var up: String = "w"
    var down: String = "s"
    var left: String = "a"
    var right: String = "d"
}

/// 下发配置（需 PC 控制台人工确认，客户端须用长超时；无回包）
struct RequestSyncPacket: Codable {
    var config: SyncConfigData
    var token: String
    var opt: Int = 4
}

// MARK: - opt 5 认证

/// 用设备 sid 换取本连接的令牌；新 sid 需 PC 控制台人工按 y 确认，等待期间必须关闭读超时
struct RequestAuthPacket: Codable {
    var sid: String
    var opt: Int = 5
}

/// 认证响应；auth 为 false 时 token 无意义
struct ReceiveAuthData: Codable {
    var auth: Bool
    var token: String
}

// MARK: - 扫码连接

/// 服务器启动时在控制台打印的连接二维码内容；注意字段名是 add 而非 addr/address
struct AddressData: Codable {
    var add: String
    var port: Int
}
