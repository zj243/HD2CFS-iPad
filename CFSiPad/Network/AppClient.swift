//
// AppClient.swift
// 客户端连接状态机（M1）：连接 → 状态查询 → 认证换令牌 → 心跳保活/断线重连
// 逐段对照安卓版 network/AppClient.kt 复刻，行为差异均以注释标明
// 作者: ZJ
//

import Foundation

/// 客户端事件，供 UI 连接状态条使用，与安卓版 AppClientEvent 对应；
/// retrying 直接携带次数，省去安卓版 retriedTimes() 的二次查询
enum AppClientEvent: Equatable, Sendable {
    case connecting
    case retrying(attempt: Int, limit: Int)
    case connected
    case disconnected
    case failed
    case sent(opt: Int)
    case authing
    case authFailed
    case apiMismatch
    case serverError
}

/// 全局网络客户端（对应安卓版 object AppClient 单例）。
/// actor 隔离天然保证内部状态串行访问；安卓版的两把互斥锁语义用两个布尔标志复刻：
/// - isConnecting（connectingLock）：连接流程进行中，其他调用方放弃触发重连；
/// - isNetworkBusy（networkLock）：一次收发进行中，实时指令（宏/单键）直接丢弃不排队——
///   这是刻意行为：游戏中输入过时即无效，排队重放反而危险。
actor AppClient {
    static let shared = AppClient()

    // MARK: - 连接参数与状态

    private var address = "127.0.0.1"
    private var port: UInt16 = CFSConstants.defaultPort
    private var sid = "NULL"
    private var token = "NULL"
    private var retryLimit = CFSConstants.defaultRetry
    private var timeout = CFSConstants.defaultTimeout

    private var connection: LineFramedConnection?
    private var connected = false
    private var retriedCount = 0
    private var isConnecting = false
    private var isNetworkBusy = false

    private var clientTask: Task<Void, Never>?
    private var eventListener: (@Sendable (AppClientEvent) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool { connected }

    // MARK: - 生命周期

    /// 注册事件回调（UI 层负责切回主线程）。传 nil 取消监听
    func setEventListener(_ listener: (@Sendable (AppClientEvent) -> Void)?) {
        eventListener = listener
    }

    /// 启动客户端：连接 + 认证，成功后进入心跳保活。重复调用会先丢弃旧连接再按新参数启动。
    /// 与安卓版 initClient 的差异：这里不清空事件回调，调用方无需每次重新注册
    func start(
        address: String,
        port: UInt16,
        sid: String,
        retry: Int = CFSConstants.defaultRetry,
        timeout: TimeInterval = CFSConstants.defaultTimeout
    ) {
        clientTask?.cancel()
        connection?.close()
        connection = nil
        connected = false
        isConnecting = false
        isNetworkBusy = false

        self.address = address
        self.port = port
        self.sid = sid
        self.retryLimit = retry
        self.timeout = timeout

        clientTask = Task {
            await setupSocket()
            await keepAlive()
        }
    }

    /// 关闭客户端并通知 UI（对应安卓版 closeClient，同样会清空事件回调）
    func stop() {
        clientTask?.cancel()
        clientTask = nil
        connection?.close()
        connection = nil
        connected = false
        emit(.disconnected)
        eventListener = nil
    }

    // MARK: - 连接流程

    /// 连接 + 状态检查，失败则按 retryLimit 重试（间隔 2 秒），对应安卓版 setupSocket
    private func setupSocket() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        retriedCount = 0
        emit(.connecting)
        await connectOnce()
        await checkStatus()

        while !connected && retriedCount < retryLimit && !Task.isCancelled {
            emit(.retrying(attempt: retriedCount + 1, limit: retryLimit))
            try? await Task.sleep(for: .seconds(CFSConstants.retryInterval))
            if Task.isCancelled { break }
            retriedCount += 1
            emit(.connecting)
            await connectOnce()
            await checkStatus()
        }
    }

    /// 建立一次 TCP 连接。连接实例一次性使用，每次重连都新建（与安卓版每次 new Socket 一致）；
    /// 连接失败不在此处发事件，统一由 checkStatus 判定并通知
    private func connectOnce() async {
        connection?.close()
        let conn = LineFramedConnection(readTimeout: timeout)
        connection = conn
        do {
            try await conn.connect(host: address, port: port, timeout: timeout)
        } catch {
            // 留给 checkStatus 通过 isReady 判定为 FAILED
        }
    }

    /// 状态查询与认证，对应安卓版 optCheckStatus。
    /// flag 含义沿用安卓版：0 通信失败 / 1 已连接 / 2 版本不符 / 3 认证被拒 / 4 服务器状态异常
    private func checkStatus() async {
        guard let conn = connection, conn.isReady else {
            connected = false
            emit(.failed)
            return
        }
        guard !isNetworkBusy else { return }
        isNetworkBusy = true
        defer { isNetworkBusy = false }

        var flag = 0
        do {
            try await send(RequestStatusPacket(api: CFSConstants.apiVersion), over: conn)
            let status: ReceiveStatusData = try decode(from: try await conn.receiveMessage())
            if status.api != CFSConstants.apiVersion {
                flag = 2
            } else {
                switch status.status {
                case 0:
                    // 服务器就绪（认证已通过或服务器关闭了认证）
                    flag = 1
                case 1:
                    flag = 2
                case 2:
                    // 未认证：用 sid 换本连接的 token。
                    // 新 sid 需要用户在 PC 控制台按 y 确认，期间关闭读超时无限等待
                    emit(.authing)
                    try await send(RequestAuthPacket(sid: sid), over: conn)
                    conn.setReadTimeoutEnabled(false)
                    let auth: ReceiveAuthData = try decode(from: try await conn.receiveMessage())
                    conn.setReadTimeoutEnabled(true)
                    if auth.auth {
                        token = auth.token
                        flag = 1
                    } else {
                        flag = 3
                    }
                default:
                    flag = 4
                }
            }
        } catch {
            flag = 0 // 收发超时 / 连接中断 / JSON 解析失败，统一按通信失败处理
        }

        connected = flag == 1
        switch flag {
        case 1: emit(.connected)
        case 2: emit(.apiMismatch)
        case 3: emit(.authFailed)
        case 4: emit(.serverError)
        default: emit(.failed)
        }
    }

    /// 心跳保活：每 10 秒探活一次，发现断线且当前不在连接流程中时自动重连，对应安卓版 keepAlive
    private func keepAlive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(CFSConstants.heartbeatInterval))
            if Task.isCancelled { break }
            if connected && !isConnecting {
                await checkStatus()
                if !connected && !isConnecting {
                    await setupSocket()
                }
            }
        }
    }

    // MARK: - 业务指令（fire-and-forget，服务器无回包）

    /// 激活战备宏（opt=1），对应安卓版 optMacro
    func activateMacro(_ data: StratagemMacroData) async {
        guard await ensureConnectedForRealtime() else { return }
        await sendGuarded(RequestMacroPacket(macro: data, token: token))
    }

    /// 发送单键输入（opt=2，自由输入模式），对应安卓版 optInput
    func sendInput(_ data: StratagemInputData) async {
        guard await ensureConnectedForRealtime() else { return }
        await sendGuarded(RequestInputPacket(input: data, token: token))
    }

    /// 下发服务器配置（opt=4），发送成功后发 sent 事件供设置页提示"去 PC 端确认"，对应安卓版 optSync
    func syncConfig(_ data: SyncConfigData) async {
        guard await ensureConnectedForRealtime() else { return }
        await sendGuarded(RequestSyncPacket(config: data, token: token), sentOpt: 4)
    }

    /// 发送前置检查：未连接时尝试一次重连；连接流程已在进行中则直接放弃本次指令
    private func ensureConnectedForRealtime() async -> Bool {
        if connected { return true }
        if isConnecting { return false }
        await setupSocket()
        return connected
    }

    /// 受 isNetworkBusy 保护的发送：忙碌时直接丢弃（实时指令不排队）；
    /// 发送失败不上抛，与安卓版一致交由心跳发现断线并重连
    private func sendGuarded<T: Encodable>(_ packet: T, sentOpt: Int? = nil) async {
        guard let conn = connection, !isNetworkBusy else { return }
        isNetworkBusy = true
        defer { isNetworkBusy = false }
        do {
            try await send(packet, over: conn)
            if let opt = sentOpt {
                emit(.sent(opt: opt))
            }
        } catch {
            // 静默失败：下一次心跳会判定断线并触发重连
        }
    }

    // MARK: - 编解码与事件

    private func send<T: Encodable>(_ packet: T, over conn: LineFramedConnection) async throws {
        let data = try encoder.encode(packet)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ConnectionError.sendFailed("报文编码为 UTF-8 字符串失败")
        }
        try await conn.send(json)
    }

    private func decode<T: Decodable>(from message: String) throws -> T {
        try decoder.decode(T.self, from: Data(message.utf8))
    }

    private func emit(_ event: AppClientEvent) {
        eventListener?(event)
    }

    // MARK: - 设备标识 sid

    /// 读取持久化的 sid，不存在则生成 16 位随机字母数字串并保存。
    /// 服务器按 sid 记忆认证记录，因此 sid 必须稳定不变（对应安卓版 MainActivity 首启生成逻辑）
    static func loadOrCreateSid(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: CFSConstants.sidKey), !existing.isEmpty {
            return existing
        }
        let generated = randomSid()
        defaults.set(generated, forKey: CFSConstants.sidKey)
        return generated
    }

    /// 生成随机 sid（字母大小写 + 数字）
    static func randomSid(length: Int = CFSConstants.sidLength) -> String {
        let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }
}
