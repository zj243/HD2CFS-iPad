//
// StratagemStore.swift
// 战备数据模型与读写（M2）
// 列结构与安卓版 Room schema v2（stratagem_table）完全一致
// 作者: ZJ
//

import Foundation
import GRDB

/// 战备（stratagem_table 一行）。steps 列在库中为 JSON 数组文本，对外使用 [Int] 计算属性
struct Stratagem: Codable, Equatable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "stratagem_table"

    var id: Int
    var name: String
    var nameZh: String
    var icon: String
    private var stepsRaw: String
    var idx: Int

    enum CodingKeys: String, CodingKey {
        case id, name, nameZh, icon, idx
        case stepsRaw = "steps"
    }

    /// 呼叫步骤序列：1上 2下 3左 4右
    var steps: [Int] {
        get { JSONIntList.decode(stepsRaw) }
        set { stepsRaw = JSONIntList.encode(newValue) }
    }

    init(id: Int, name: String, nameZh: String, icon: String, steps: [Int], idx: Int = 0) {
        self.id = id
        self.name = name
        self.nameZh = nameZh
        self.icon = icon
        self.stepsRaw = JSONIntList.encode(steps)
        self.idx = idx
    }

    /// 按战备名语言设置取显示名（对应安卓版 ctrl_lang 逻辑）：
    /// zh-CN 用中文名（缺失回退英文名）、en 用英文名、auto 跟随系统语言
    func displayName(lang: String) -> String {
        switch lang {
        case "zh-CN":
            return nameZh.isEmpty ? name : nameZh
        case "en":
            return name
        default:
            let prefersChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
            return prefersChinese && !nameZh.isEmpty ? nameZh : name
        }
    }
}

/// 战备库读写。查询在调用线程同步执行（全库仅几十行，无性能压力）
final class StratagemStore {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// 全部战备，按 idx、id 排序
    func fetchAll() throws -> [Stratagem] {
        try queue.read { db in
            try Stratagem.order(Column("idx"), Column("id")).fetchAll(db)
        }
    }

    /// 按 id 集合查询，返回 id → 战备 字典（编组渲染用；不存在的 id 由调用方显示占位）
    func fetchDictionary(ids: [Int]) throws -> [Int: Stratagem] {
        try queue.read { db in
            let rows = try Stratagem.filter(ids.contains(Column("id"))).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        }
    }

    func count() throws -> Int {
        try queue.read { db in
            try Stratagem.fetchCount(db)
        }
    }

    /// 数据库更新（M3 使用）：清空后整表重建，单事务保证原子性，
    /// 对应安卓版 deleteAll + 远程 JSON 重新插入的行为
    func replaceAll(_ stratagems: [Stratagem]) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM stratagem_table")
            for item in stratagems {
                try item.insert(db)
            }
        }
    }
}
