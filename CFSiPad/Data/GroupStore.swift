//
// GroupStore.swift
// 战备编组模型与读写（M2）
// 列结构与安卓版 group_table 对齐（list 存 JSON 数组文本，dbName 记录建组时所用战备库）
// 作者: ZJ
//

import Foundation
import GRDB

/// 战备编组（group_table 一行）。id 为自增主键，插入后回填。
/// Hashable/Identifiable 供 SwiftUI 导航与列表使用
struct StratagemGroup: Codable, Equatable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "group_table"

    var id: Int64?
    var title: String
    private var listRaw: String
    var dbName: String
    var idx: Int

    enum CodingKeys: String, CodingKey {
        case id, title, dbName, idx
        case listRaw = "list"
    }

    /// 组内战备 id 列表（有序）
    var list: [Int] {
        get { JSONIntList.decode(listRaw) }
        set { listRaw = JSONIntList.encode(newValue) }
    }

    /// idx 默认取 Int32 上限：新组排在末尾，首次拖拽排序后写入真实序号（与安卓版一致）
    init(id: Int64? = nil, title: String, list: [Int], dbName: String, idx: Int = Int(Int32.max)) {
        self.id = id
        self.title = title
        self.listRaw = JSONIntList.encode(list)
        self.dbName = dbName
        self.idx = idx
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 编组读写
final class GroupStore {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// 按主键取单个编组（编辑保存后浏览页重载用）
    func fetch(id: Int64) throws -> StratagemGroup? {
        try queue.read { db in
            try StratagemGroup.fetchOne(db, key: id)
        }
    }

    /// 全部编组，按 idx、id 排序（新建组 idx 为 Int32 上限，自然排在末尾）
    func fetchAllOrdered() throws -> [StratagemGroup] {
        try queue.read { db in
            try StratagemGroup.order(Column("idx"), Column("id")).fetchAll(db)
        }
    }

    /// 插入编组，返回带自增 id 的副本
    @discardableResult
    func insert(_ group: StratagemGroup) throws -> StratagemGroup {
        try queue.write { db in
            var copy = group
            try copy.insert(db)
            return copy
        }
    }

    func update(_ group: StratagemGroup) throws {
        try queue.write { db in
            try group.update(db)
        }
    }

    func delete(id: Int64) throws {
        _ = try queue.write { db in
            try StratagemGroup.deleteOne(db, key: id)
        }
    }

    /// 拖拽排序落库：按传入数组的顺序重写各组 idx（对应安卓版列表页 onPause 写回）
    func saveOrder(ids: [Int64]) throws {
        try queue.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE group_table SET idx = ? WHERE id = ?", arguments: [index, id])
            }
        }
    }
}
