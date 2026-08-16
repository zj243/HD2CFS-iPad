//
// Constants.swift
// 全局常量（M1 先收录网络相关，后续模块按需补充）
// 数值与安卓版 Constants.kt / AppClient.kt 保持一致
// 作者: ZJ
//

import Foundation

enum CFSConstants {
    /// 协议版本，随 opt=0 状态查询上报给服务器（服务器据此分流 API5/API6 处理逻辑）
    static let apiVersion = 6

    /// 服务器默认端口
    static let defaultPort: UInt16 = 23333

    /// 连接与单次收发的默认超时（秒），对应安卓版 soTimeout 5000ms
    static let defaultTimeout: TimeInterval = 5

    /// 心跳间隔（秒）：连接空闲时每 10 秒发一次 opt=0 探活
    static let heartbeatInterval: TimeInterval = 10

    /// 断线重连的默认重试次数与间隔（秒）
    static let defaultRetry = 5
    static let retryInterval: TimeInterval = 2

    /// 设备标识 sid：16 位随机字母数字串，首次生成后持久化，
    /// 服务器端按 sid 记忆认证记录（默认 3 天有效期）
    static let sidLength = 16
    static let sidKey = "sid"

    /// 战备数据库官方源（与安卓版 Constants.kt 一致；db_channel 2 时改用用户自定义 URL）
    static let urlDbHD2 = "https://cfsdb-hd2.wistefinch.site/index.json"
    static let urlDbHD = "https://cfsdb-hd.wistefinch.site/index.json"
}
