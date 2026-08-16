//
// LineFramedConnection.swift
// TCP 行分帧连接（M1）：NWConnection 封装 + 换行分帧缓冲
// 对应安卓版 AppSocket.kt；分帧规则见 PLAN.md 3.1 节"必守规则"
// 作者: ZJ
//

import Foundation
import Network

/// 连接层错误。错误信息面向调试与 UI 提示，用中文描述
enum ConnectionError: Error, LocalizedError {
    case connectTimeout
    case connectFailed(String)
    case notConnected
    case sendFailed(String)
    case receiveTimeout
    case remoteClosed
    case concurrentReceive

    var errorDescription: String? {
        switch self {
        case .connectTimeout: return "连接服务器超时"
        case .connectFailed(let reason): return "连接服务器失败：\(reason)"
        case .notConnected: return "连接未建立或已关闭"
        case .sendFailed(let reason): return "发送数据失败：\(reason)"
        case .receiveTimeout: return "等待服务器响应超时"
        case .remoteClosed: return "连接已被服务器关闭"
        case .concurrentReceive: return "已有接收操作在等待中（协议要求一问一答）"
        }
    }
}

/// 行分帧缓冲：纯逻辑、无网络依赖，供单元测试直接覆盖。
/// 报文提取规则：
/// 1) 按 \n 切分出整行（去掉行尾 \r 与空白，跳过空行）——服务器常规响应均以 \n 结尾；
/// 2) 剩余字节若已构成一个完整 JSON 对象也作为一条报文取出——兼容 opt=3 响应末尾无换行的服务器行为。
struct LineFrameBuffer {
    private var data = Data()

    mutating func append(_ chunk: Data) {
        data.append(chunk)
    }

    /// 取出当前已可判定完整的全部报文（可能为空数组）
    mutating func drainMessages() -> [String] {
        var messages: [String] = []
        // 规则 1：换行分帧
        while let newlineIndex = data.firstIndex(of: 0x0A) {
            let lineData = data.prefix(upTo: newlineIndex)
            // 用拷贝重建剩余数据，避免 Data 切片保留原索引导致的下标错乱
            data = Data(data.suffix(from: data.index(after: newlineIndex)))
            appendTrimmedLine(lineData, to: &messages)
        }
        // 规则 2：无换行但 JSON 已完整（opt=3 响应）
        if !data.isEmpty, Self.isCompleteJSONObject(data) {
            let rest = data
            data.removeAll()
            appendTrimmedLine(rest, to: &messages)
        }
        return messages
    }

    /// UTF-8 解码 + 去首尾空白后收入结果，空行丢弃（JSON 回落取走报文后残留的孤立 \n 会形成空行）
    private func appendTrimmedLine(_ lineData: Data, to messages: inout [String]) {
        guard let line = String(data: lineData, encoding: .utf8) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            messages.append(trimmed)
        }
    }

    /// 判断字节流是否恰好构成一个完整的顶层 JSON 对象（本协议全部报文均为对象，不考虑顶层数组）。
    /// 按字节扫描花括号配对，正确跳过字符串内容与转义符；
    /// UTF-8 多字节字符的后续字节均 >= 0x80，不会与 {}"\ 等 ASCII 冲突，逐字节扫描是安全的。
    static func isCompleteJSONObject(_ bytes: Data) -> Bool {
        var depth = 0
        var started = false
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C { // 反斜杠
                    escaped = true
                } else if byte == 0x22 { // 双引号
                    inString = false
                }
                continue
            }
            let isWhitespace = byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
            if !started {
                if isWhitespace { continue }
                if byte == 0x7B { // {
                    depth = 1
                    started = true
                    continue
                }
                return false // 首个非空白字符不是 {，不是 JSON 对象
            }
            if depth == 0 {
                if isWhitespace { continue }
                return false // 对象已闭合却还有内容，说明不是"恰好一个对象"
            }
            switch byte {
            case 0x22: inString = true
            case 0x7B: depth += 1
            case 0x7D: depth -= 1
            default: break
            }
        }
        return started && depth == 0 && !inString
    }
}

/// TCP 行分帧连接。一次性使用：连接失败或关闭后不可复用，重连需新建实例（与安卓版每次 new Socket 一致）。
/// 全部内部状态在专用串行队列上访问；对外提供 async 接口。
final class LineFramedConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.zj.cfsipad.connection")
    private var connection: NWConnection?
    private var frameBuffer = LineFrameBuffer()
    private var pendingMessages: [String] = []

    private var connectWaiter: CheckedContinuation<Void, Error>?
    private var connectTimeoutItem: DispatchWorkItem?
    private var receiveWaiter: CheckedContinuation<String, Error>?
    private var receiveTimeoutItem: DispatchWorkItem?

    private var ready = false
    private var closed = false

    /// 单次接收的超时时长（秒）；认证等待人工确认期间通过 setReadTimeoutEnabled(false) 临时关闭
    private let readTimeout: TimeInterval
    private var readTimeoutEnabled = true

    init(readTimeout: TimeInterval = CFSConstants.defaultTimeout) {
        self.readTimeout = readTimeout
    }

    /// 连接是否就绪可用
    var isReady: Bool {
        queue.sync { ready && !closed }
    }

    // MARK: - 连接

    /// 建立 TCP 连接。超时双保险：TCP 层 connectionTimeout + 队列定时器（防止 .waiting 状态悬挂）
    func connect(host: String, port: UInt16, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.connection == nil, !self.closed else {
                    continuation.resume(throwing: ConnectionError.connectFailed("连接实例不可复用，请新建"))
                    return
                }
                guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                    continuation.resume(throwing: ConnectionError.connectFailed("端口号无效：\(port)"))
                    return
                }
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.noDelay = true // 实时按键指令优先低延迟
                tcpOptions.connectionTimeout = Int(timeout)
                let params = NWParameters(tls: nil, tcp: tcpOptions)
                let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
                self.connection = conn
                self.connectWaiter = continuation

                let timeoutItem = DispatchWorkItem { [weak self] in
                    self?.failConnect(with: .connectTimeout)
                }
                self.connectTimeoutItem = timeoutItem
                self.queue.asyncAfter(deadline: .now() + timeout + 1, execute: timeoutItem)

                // start(queue:) 指定回调队列后，状态回调即运行在 self.queue 上
                conn.stateUpdateHandler = { [weak self] state in
                    self?.handleState(state)
                }
                conn.start(queue: self.queue)
            }
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            ready = true
            connectTimeoutItem?.cancel()
            connectTimeoutItem = nil
            if let waiter = connectWaiter {
                connectWaiter = nil
                waiter.resume()
            }
            startReceivePump()
        case .failed(let error):
            failConnect(with: .connectFailed(error.localizedDescription))
            teardown(error: .remoteClosed)
        case .cancelled:
            teardown(error: .remoteClosed)
        default:
            // .preparing / .waiting 等中间态：交给超时定时器兜底
            break
        }
    }

    /// 连接阶段失败：唤醒并抛错给 connect 调用方，同时关闭底层连接
    private func failConnect(with error: ConnectionError) {
        connectTimeoutItem?.cancel()
        connectTimeoutItem = nil
        guard let waiter = connectWaiter else { return }
        connectWaiter = nil
        closed = true
        connection?.cancel()
        waiter.resume(throwing: error)
    }

    /// 会话中断：标记关闭并唤醒等待中的接收方
    private func teardown(error: ConnectionError) {
        guard !closed else { return }
        closed = true
        ready = false
        receiveTimeoutItem?.cancel()
        receiveTimeoutItem = nil
        if let waiter = receiveWaiter {
            receiveWaiter = nil
            waiter.resume(throwing: error)
        }
    }

    // MARK: - 接收

    /// 常驻接收泵：持续读取字节流喂给分帧缓冲，解析出的完整报文按序入队
    private func startReceivePump() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            // 回调运行在 self.queue 上（start(queue:) 指定）
            if let data, !data.isEmpty {
                self.frameBuffer.append(data)
                self.pendingMessages.append(contentsOf: self.frameBuffer.drainMessages())
                self.deliverIfPossible()
            }
            if error != nil || isComplete {
                self.teardown(error: .remoteClosed)
                return
            }
            if !self.closed {
                self.startReceivePump()
            }
        }
    }

    private func deliverIfPossible() {
        guard let waiter = receiveWaiter, !pendingMessages.isEmpty else { return }
        receiveWaiter = nil
        receiveTimeoutItem?.cancel()
        receiveTimeoutItem = nil
        waiter.resume(returning: pendingMessages.removeFirst())
    }

    /// 接收一条完整报文。协议为一问一答，同一时刻只允许一个等待者；
    /// 默认受 readTimeout 约束，认证人工确认期间由调用方临时关闭超时
    func receiveMessage() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                if !self.pendingMessages.isEmpty {
                    continuation.resume(returning: self.pendingMessages.removeFirst())
                    return
                }
                guard self.ready, !self.closed else {
                    continuation.resume(throwing: ConnectionError.notConnected)
                    return
                }
                guard self.receiveWaiter == nil else {
                    continuation.resume(throwing: ConnectionError.concurrentReceive)
                    return
                }
                self.receiveWaiter = continuation
                if self.readTimeoutEnabled {
                    let timeoutItem = DispatchWorkItem { [weak self] in
                        guard let self, let waiter = self.receiveWaiter else { return }
                        self.receiveWaiter = nil
                        waiter.resume(throwing: ConnectionError.receiveTimeout)
                    }
                    self.receiveTimeoutItem = timeoutItem
                    self.queue.asyncAfter(deadline: .now() + self.readTimeout, execute: timeoutItem)
                }
            }
        }
    }

    /// 开关接收超时：等待服务器端人工确认（认证/配置下发）期间关闭，完成后恢复
    func setReadTimeoutEnabled(_ enabled: Bool) {
        queue.async {
            self.readTimeoutEnabled = enabled
            if !enabled {
                self.receiveTimeoutItem?.cancel()
                self.receiveTimeoutItem = nil
            }
        }
    }

    // MARK: - 发送

    /// 发送一条报文，自动追加协议要求的 \n 结尾
    func send(_ line: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let conn = self.connection, self.ready, !self.closed else {
                    continuation.resume(throwing: ConnectionError.notConnected)
                    return
                }
                let payload = Data((line + "\n").utf8)
                conn.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: ConnectionError.sendFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
    }

    // MARK: - 关闭

    /// 关闭连接并唤醒所有等待者（幂等）
    func close() {
        queue.async {
            self.ready = false
            self.closed = true
            self.connectTimeoutItem?.cancel()
            self.connectTimeoutItem = nil
            if let waiter = self.connectWaiter {
                self.connectWaiter = nil
                waiter.resume(throwing: ConnectionError.notConnected)
            }
            self.receiveTimeoutItem?.cancel()
            self.receiveTimeoutItem = nil
            if let waiter = self.receiveWaiter {
                self.receiveWaiter = nil
                waiter.resume(throwing: ConnectionError.notConnected)
            }
            self.connection?.cancel()
            self.connection = nil
        }
    }
}
