//
// BackupFile.swift
// 备份文件（M2）：cfs_backup.json（ver=1），与安卓版 BackupFileData.kt 结构一致，双端互通。
// iOS 版不做语音识别：导入时忽略 asr 设置与 keywords 关键词；导出时保留这两个字段并填中性默认值，
// 使 iOS 导出的备份仍可被安卓端完整导入（安卓端 Gson 对缺失字段不安全，不能省略）。
// 作者: ZJ
//

import Foundation

enum BackupError: Error, LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let ver):
            return "不支持的备份文件版本：\(ver)（当前仅支持 ver=1）"
        }
    }
}

// MARK: - 结构定义（字段名与安卓版 JSON 完全一致）
// 自定义解码放在扩展中实现（保留 memberwise init），所有字段缺失时取默认值，容忍手工编辑过的备份

struct BackupFile: Codable {
    var ver: Int = 1
    var sync: SyncConfigData = SyncConfigData()
    var settings: BackupSettings = BackupSettings()
    var groups: [BackupGroup] = []
    /// 语音关键词：iOS 不使用，解码保留、导出恒为空数组
    var keywords: [BackupAsrKeyword] = []
}

struct BackupSettings: Codable {
    var conn: BackupSettingsConn = BackupSettingsConn()
    var ctrl: BackupSettingsCtrl = BackupSettingsCtrl()
    /// 语音设置：iOS 不使用，仅为安卓端导入兼容而保留字段
    var asr: BackupSettingsAsr = BackupSettingsAsr()
    var db: BackupSettingsDb = BackupSettingsDb()
}

struct BackupSettingsConn: Codable {
    var addr: String = "127.0.0.1"
    var port: Int = 23333
    var retry: Int = 5
}

struct BackupSettingsCtrl: Codable {
    var simplified: Bool = false
    var stratagemSize: Int = 100
    var fastboot: Bool = false
    var sfx: Bool = false
    /// 震动开关：iPad 无震动马达，导入忽略、导出恒为 false
    var vibrator: Bool = false
    var sdt: Int = 100
    var svt: Int = 50
    var lang: String = "auto"
}

struct BackupSettingsAsr: Codable {
    var model: Int = -1
    var custom: String = ""
    var enabled: Bool = false
    var similarity: Int = 50
    var gpu: Bool = true
    var activate: [String] = []
    var autoKeywords: Bool = true
}

struct BackupSettingsDb: Codable {
    var channel: Int = 0
    var custom: String = ""
}

struct BackupGroup: Codable {
    var id: Int = 0
    var title: String = ""
    var list: [Int] = []
    var dbName: String = ""
    var idx: Int = Int(Int32.max)
}

struct BackupAsrKeyword: Codable {
    var dbName: String = ""
    var stratagem: Int = 0
    var keywords: [String] = []
}

// MARK: - 容错解码

extension BackupFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ver = try container.decodeIfPresent(Int.self, forKey: .ver) ?? 1
        sync = try container.decodeIfPresent(SyncConfigData.self, forKey: .sync) ?? SyncConfigData()
        settings = try container.decodeIfPresent(BackupSettings.self, forKey: .settings) ?? BackupSettings()
        groups = try container.decodeIfPresent([BackupGroup].self, forKey: .groups) ?? []
        keywords = try container.decodeIfPresent([BackupAsrKeyword].self, forKey: .keywords) ?? []
    }
}

extension BackupSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conn = try container.decodeIfPresent(BackupSettingsConn.self, forKey: .conn) ?? BackupSettingsConn()
        ctrl = try container.decodeIfPresent(BackupSettingsCtrl.self, forKey: .ctrl) ?? BackupSettingsCtrl()
        asr = try container.decodeIfPresent(BackupSettingsAsr.self, forKey: .asr) ?? BackupSettingsAsr()
        db = try container.decodeIfPresent(BackupSettingsDb.self, forKey: .db) ?? BackupSettingsDb()
    }
}

extension BackupGroup {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        list = try container.decodeIfPresent([Int].self, forKey: .list) ?? []
        dbName = try container.decodeIfPresent(String.self, forKey: .dbName) ?? ""
        idx = try container.decodeIfPresent(Int.self, forKey: .idx) ?? Int(Int32.max)
    }
}

// MARK: - 导入 / 导出

extension BackupFile {
    /// 解析备份文件并校验版本
    static func decode(_ data: Data) throws -> BackupFile {
        let file = try JSONDecoder().decode(BackupFile.self, from: data)
        guard file.ver == 1 else {
            throw BackupError.unsupportedVersion(file.ver)
        }
        return file
    }

    /// 序列化为 JSON（导出文件名沿用安卓版惯例 cfs_backup.json）
    func encodeJSON() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// 导入：设置项覆盖写入，编组追加插入（id 重新生成、保留 idx 排序）。
    /// asr 设置、keywords 关键词与 ctrl.vibrator 按 iOS 版决策忽略
    func apply(settings: AppSettings, groupStore: GroupStore) throws {
        settings.applySyncConfigData(sync)

        settings.connAddress = self.settings.conn.addr
        settings.connPort = self.settings.conn.port
        settings.connRetry = self.settings.conn.retry

        settings.ctrlSimplified = self.settings.ctrl.simplified
        settings.ctrlStratagemSize = self.settings.ctrl.stratagemSize
        settings.ctrlFastboot = self.settings.ctrl.fastboot
        settings.ctrlSfx = self.settings.ctrl.sfx
        settings.ctrlSwipeDistanceThreshold = self.settings.ctrl.sdt
        settings.ctrlSwipeVelocityThreshold = self.settings.ctrl.svt
        settings.ctrlLang = self.settings.ctrl.lang

        settings.dbChannel = self.settings.db.channel
        settings.dbCustomURL = self.settings.db.custom

        for group in groups {
            try groupStore.insert(
                StratagemGroup(title: group.title, list: group.list, dbName: group.dbName, idx: group.idx)
            )
        }
    }

    /// 导出：收集当前设置与全部编组。
    /// asr 块填中性默认值、keywords 为空数组、vibrator 恒 false——字段必须存在，安卓端才能导入
    static func export(settings: AppSettings, groups: [StratagemGroup]) -> BackupFile {
        var file = BackupFile()
        file.ver = 1
        file.sync = settings.syncConfigData()
        file.settings.conn = BackupSettingsConn(
            addr: settings.connAddress,
            port: settings.connPort,
            retry: settings.connRetry
        )
        file.settings.ctrl = BackupSettingsCtrl(
            simplified: settings.ctrlSimplified,
            stratagemSize: settings.ctrlStratagemSize,
            fastboot: settings.ctrlFastboot,
            sfx: settings.ctrlSfx,
            vibrator: false,
            sdt: settings.ctrlSwipeDistanceThreshold,
            svt: settings.ctrlSwipeVelocityThreshold,
            lang: settings.ctrlLang
        )
        file.settings.db = BackupSettingsDb(channel: settings.dbChannel, custom: settings.dbCustomURL)
        file.groups = groups.map { group in
            BackupGroup(
                id: Int(group.id ?? 0),
                title: group.title,
                list: group.list,
                dbName: group.dbName,
                idx: group.idx
            )
        }
        return file
    }
}
