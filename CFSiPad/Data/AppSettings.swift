//
// AppSettings.swift
// 设置存储（M2）：UserDefaults 类型化封装
// 键名与默认值与安卓版 SharedPreferences 一一对应（ASR 相关设置已按决策整体砍掉）
// 作者: ZJ
//

import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    /// 单元测试可传入独立 suite 实现隔离
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 读取助手（object(forKey:) 判空以区分"未设置"与"设置为 0/false"）

    private func int(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func string(_ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    // MARK: - 连接设置（conn_*）

    var connAddress: String {
        get { string("conn_addr", "127.0.0.1") }
        set { defaults.set(newValue, forKey: "conn_addr") }
    }

    var connPort: Int {
        get { int("conn_port", Int(CFSConstants.defaultPort)) }
        set { defaults.set(newValue, forKey: "conn_port") }
    }

    var connRetry: Int {
        get { int("conn_retry", CFSConstants.defaultRetry) }
        set { defaults.set(newValue, forKey: "conn_retry") }
    }

    // MARK: - 服务器配置同步项（sync_* / input_type_open），opt=4 整包下发用

    var syncServerPort: Int {
        get { int("sync_server_port", 23333) }
        set { defaults.set(newValue, forKey: "sync_server_port") }
    }

    /// 服务器监听 IP，留空表示由服务器自动获取局域网地址
    var syncServerIp: String {
        get { string("sync_server_ip", "") }
        set { defaults.set(newValue, forKey: "sync_server_ip") }
    }

    /// 按键间隔（毫秒），过小会导致游戏丢键
    var syncInputDelay: Int {
        get { int("sync_input_delay", 25) }
        set { defaults.set(newValue, forKey: "sync_input_delay") }
    }

    /// "打开战备列表"键（键值字符串表见 server_api_6.md 附录）
    var syncInputOpen: String {
        get { string("sync_input_open", "ctrl_left") }
        set { defaults.set(newValue, forKey: "sync_input_open") }
    }

    /// "打开战备列表"键的按法：hold/press/long_press/tap/double_tap
    var syncInputOpenType: String {
        get { string("input_type_open", "hold") }
        set { defaults.set(newValue, forKey: "input_type_open") }
    }

    var syncInputUp: String {
        get { string("sync_input_up", "w") }
        set { defaults.set(newValue, forKey: "sync_input_up") }
    }

    var syncInputDown: String {
        get { string("sync_input_down", "s") }
        set { defaults.set(newValue, forKey: "sync_input_down") }
    }

    var syncInputLeft: String {
        get { string("sync_input_left", "a") }
        set { defaults.set(newValue, forKey: "sync_input_left") }
    }

    var syncInputRight: String {
        get { string("sync_input_right", "d") }
        set { defaults.set(newValue, forKey: "sync_input_right") }
    }

    var syncAuthEnabled: Bool {
        get { bool("sync_auth", true) }
        set { defaults.set(newValue, forKey: "sync_auth") }
    }

    /// 服务器端认证记录有效期（天）
    var syncAuthTimeout: Int {
        get { int("sync_auth_timeout", 3) }
        set { defaults.set(newValue, forKey: "sync_auth_timeout") }
    }

    var syncDebug: Bool {
        get { bool("sync_debug", false) }
        set { defaults.set(newValue, forKey: "sync_debug") }
    }

    /// 由同步设置项组装 opt=4 的完整配置包。
    /// records（服务器端认证记录）客户端不留存，恒发空数组——服务器整包替换后记录清零，
    /// 已认证连接不受影响，断线后重新走一次认证即可
    func syncConfigData() -> SyncConfigData {
        SyncConfigData(
            server: SyncConfigServerData(port: syncServerPort, ip: syncServerIp),
            input: SyncConfigInputData(
                delay: syncInputDelay,
                open: syncInputOpen,
                keytype: syncInputOpenType,
                up: syncInputUp,
                down: syncInputDown,
                left: syncInputLeft,
                right: syncInputRight
            ),
            auth: SyncConfigAuthData(enabled: syncAuthEnabled, timeout: syncAuthTimeout),
            debug: syncDebug,
            records: []
        )
    }

    /// 备份导入时把配置包写回各同步设置项
    func applySyncConfigData(_ config: SyncConfigData) {
        syncServerPort = config.server.port
        syncServerIp = config.server.ip
        syncInputDelay = config.input.delay
        syncInputOpen = config.input.open
        syncInputOpenType = config.input.keytype
        syncInputUp = config.input.up
        syncInputDown = config.input.down
        syncInputLeft = config.input.left
        syncInputRight = config.input.right
        syncAuthEnabled = config.auth.enabled
        syncAuthTimeout = config.auth.timeout
        syncDebug = config.debug
    }

    // MARK: - 控制设置（ctrl_*）

    /// 简化模式：Play 页仅保留网格点击发宏
    var ctrlSimplified: Bool {
        get { bool("ctrl_simplified", false) }
        set { defaults.set(newValue, forKey: "ctrl_simplified") }
    }

    /// 简化模式网格图标尺寸（pt）
    var ctrlStratagemSize: Int {
        get { int("ctrl_stratagem_size", 100) }
        set { defaults.set(newValue, forKey: "ctrl_stratagem_size") }
    }

    /// fastboot：首页点击编组直接进 Play 页
    var ctrlFastboot: Bool {
        get { bool("ctrl_fastboot", false) }
        set { defaults.set(newValue, forKey: "ctrl_fastboot") }
    }

    var ctrlSfx: Bool {
        get { bool("ctrl_sfx", false) }
        set { defaults.set(newValue, forKey: "ctrl_sfx") }
    }

    /// 滑动距离阈值（pt）
    var ctrlSwipeDistanceThreshold: Int {
        get { int("ctrl_sdt", 100) }
        set { defaults.set(newValue, forKey: "ctrl_sdt") }
    }

    /// 滑动速度阈值
    var ctrlSwipeVelocityThreshold: Int {
        get { int("ctrl_svt", 50) }
        set { defaults.set(newValue, forKey: "ctrl_svt") }
    }

    /// 战备名语言：auto / en / zh-CN
    var ctrlLang: String {
        get { string("ctrl_lang", "auto") }
        set { defaults.set(newValue, forKey: "ctrl_lang") }
    }

    // MARK: - 战备数据库设置（db_*）

    /// 数据库频道：0 = HD2，1 = HD1，2 = 自定义 URL
    var dbChannel: Int {
        get { int("db_channel", 0) }
        set { defaults.set(newValue, forKey: "db_channel") }
    }

    var dbCustomURL: String {
        get { string("db_custom", "") }
        set { defaults.set(newValue, forKey: "db_custom") }
    }

    /// 当前战备库版本（远程 index.json 的 date 字段），"0" 表示仅有内置种子数据
    var dbVersion: String {
        get { string("db_version", "0") }
        set { defaults.set(newValue, forKey: "db_version") }
    }

    /// 当前战备库标识名（编组的 dbName 与其比对，切库时告警）
    var dbName: String {
        get { string("db_name", "hd2_db") }
        set { defaults.set(newValue, forKey: "db_name") }
    }

    var dbNameEn: String {
        get { string("db_name_en", "") }
        set { defaults.set(newValue, forKey: "db_name_en") }
    }

    var dbNameZh: String {
        get { string("db_name_zh", "") }
        set { defaults.set(newValue, forKey: "db_name_zh") }
    }
}
