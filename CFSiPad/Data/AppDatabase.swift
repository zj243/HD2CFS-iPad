//
// AppDatabase.swift
// 数据层入口（M2）：数据库文件定位、种子库首启拷贝、GRDB 队列与各 Store 组装
// 作者: ZJ
//

import Foundation
import GRDB

/// 数据层错误
enum DataError: Error, LocalizedError {
    case seedDatabaseMissing

    var errorDescription: String? {
        switch self {
        case .seedDatabaseMissing:
            return "应用包内缺少战备种子数据库 stratagem_db.db"
        }
    }
}

/// [Int] 与 JSON 数组文本的互转。与安卓版 Room TypeConverter（Gson）的存储格式一致（如 "[1,2,3]"），
/// 战备表的 steps 列与编组表的 list 列共用
enum JSONIntList {
    static func encode(_ list: [Int]) -> String {
        guard let data = try? JSONEncoder().encode(list),
              let text = String(data: data, encoding: .utf8) else {
            return "[]" // [Int] 编码实际不会失败，兜底仅为满足类型安全
        }
        return text
    }

    static func decode(_ text: String) -> [Int] {
        (try? JSONDecoder().decode([Int].self, from: Data(text.utf8))) ?? []
    }
}

/// 数据库组装，持有两个独立的 SQLite 文件（与安卓版分库思路一致，便于独立重建战备库）：
/// - stratagem_db.db：战备库。首次启动从应用包拷贝种子文件（内含默认战备，保证离线可用，
///   对应安卓版 Room createFromAsset）；M3 数据库更新时只清空重建其中的 stratagem_table；
/// - app.db：编组等用户数据，本工程自建表，无历史迁移包袱。
final class AppDatabase {
    let stratagemStore: StratagemStore
    let groupStore: GroupStore

    /// 数据根目录，图标缓存等文件后续模块也放在此目录的子目录下
    let directory: URL

    static let shared: AppDatabase = {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return try AppDatabase(directory: support.appendingPathComponent("CFS", isDirectory: true))
        } catch {
            // 数据库打不开属于不可恢复故障，带明确原因终止便于定位（正常安装不会触发）
            fatalError("数据层初始化失败：\(error)")
        }
    }()

    /// - Parameters:
    ///   - directory: 数据目录（单元测试传入临时目录实现隔离）
    ///   - seedBundle: 种子数据库所在 Bundle，默认主应用包
    init(directory: URL, seedBundle: Bundle = .main) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 战备库：本地不存在时从应用包拷贝种子文件
        let stratagemURL = directory.appendingPathComponent("stratagem_db.db")
        if !FileManager.default.fileExists(atPath: stratagemURL.path) {
            guard let seedURL = seedBundle.url(forResource: "stratagem_db", withExtension: "db") else {
                throw DataError.seedDatabaseMissing
            }
            try FileManager.default.copyItem(at: seedURL, to: stratagemURL)
        }
        let stratagemQueue = try DatabaseQueue(path: stratagemURL.path)
        try Self.ensureStratagemSchema(stratagemQueue)
        stratagemStore = StratagemStore(queue: stratagemQueue)

        // 用户数据库：编组表（列结构与安卓版 group_table 对齐，list 存 JSON 数组文本）
        let appQueue = try DatabaseQueue(path: directory.appendingPathComponent("app.db").path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-group") { db in
            try db.create(table: "group_table") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull().defaults(to: "")
                t.column("list", .text).notNull().defaults(to: "[]")
                t.column("dbName", .text).notNull().defaults(to: "")
                t.column("idx", .integer).notNull().defaults(to: 0)
            }
        }
        try migrator.migrate(appQueue)
        groupStore = GroupStore(queue: appQueue)
    }

    /// 确保战备表结构为 v2（含 idx 列）。
    /// 种子文件是安卓 Room v1 结构（无 idx 列），安卓端打开时靠 AutoMigration 1→2 补列；
    /// 这里等价执行：表缺失则按 v2 建表，表存在但缺 idx 列则 ALTER TABLE 补列（幂等）
    private static func ensureStratagemSchema(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            guard try db.tableExists("stratagem_table") else {
                try db.create(table: "stratagem_table") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("name", .text).notNull().defaults(to: "")
                    t.column("nameZh", .text).notNull().defaults(to: "")
                    t.column("icon", .text).notNull().defaults(to: "")
                    t.column("steps", .text).notNull().defaults(to: "[]")
                    t.column("idx", .integer).notNull().defaults(to: 0)
                }
                return
            }
            let columns = try db.columns(in: "stratagem_table").map(\.name)
            if !columns.contains("idx") {
                try db.execute(sql: "ALTER TABLE stratagem_table ADD COLUMN idx INTEGER NOT NULL DEFAULT 0")
            }
        }
    }
}
