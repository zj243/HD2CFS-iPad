//
// DataStoreTests.swift
// M2 数据层测试：种子库读取、编组 CRUD 与排序
// 作者: ZJ
//

import XCTest
@testable import CFSiPad

final class DataStoreTests: XCTestCase {

    /// 每个用例独立的临时数据目录，互不污染
    private func makeTempDatabase() throws -> AppDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfs-test-\(UUID().uuidString)", isDirectory: true)
        return try AppDatabase(directory: dir)
    }

    /// 种子库能被拷贝、打开并读出默认战备；steps 的 JSON 文本列能解码为合法方向序列
    func testSeedDatabaseOpensAndReadsStratagems() throws {
        let database = try makeTempDatabase()
        let all = try database.stratagemStore.fetchAll()
        XCTAssertFalse(all.isEmpty, "种子库应包含默认战备（对应安卓版 createFromAsset 保底数据）")
        XCTAssertEqual(try database.stratagemStore.count(), all.count)

        let withSteps = all.filter { !$0.steps.isEmpty }
        XCTAssertFalse(withSteps.isEmpty, "至少应有战备带呼叫步骤")
        for stratagem in withSteps {
            for step in stratagem.steps {
                XCTAssertTrue((1...4).contains(step), "步骤方向只能是 1-4，实际 \(step)（\(stratagem.name)）")
            }
        }

        // 按 id 集合查询
        let ids = all.prefix(3).map(\.id)
        let dict = try database.stratagemStore.fetchDictionary(ids: ids)
        XCTAssertEqual(dict.count, ids.count)
        XCTAssertEqual(dict[ids[0]]?.id, ids[0])
    }

    /// replaceAll 整表重建（M3 数据库更新的核心路径）
    func testStratagemReplaceAll() throws {
        let database = try makeTempDatabase()
        let rebuilt = [
            Stratagem(id: 1, name: "Reinforce", nameZh: "增援", icon: "reinforce", steps: [1, 2, 4, 3, 1], idx: 0),
            Stratagem(id: 2, name: "Resupply", nameZh: "补给", icon: "resupply", steps: [2, 2, 1, 4], idx: 1),
        ]
        try database.stratagemStore.replaceAll(rebuilt)
        let all = try database.stratagemStore.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].nameZh, "增援")
        XCTAssertEqual(all[0].steps, [1, 2, 4, 3, 1])
    }

    /// 编组增删改查 + 拖拽排序落库
    func testGroupCRUDAndReorder() throws {
        let database = try makeTempDatabase()
        let store = database.groupStore

        // 新建两个组：新组 idx 为 Int32 上限，按插入顺序排在末尾
        let first = try store.insert(StratagemGroup(title: "常用", list: [1, 2, 3], dbName: "hd2_db"))
        let second = try store.insert(StratagemGroup(title: "反坦克", list: [5, 8], dbName: "hd2_db"))
        let firstId = try XCTUnwrap(first.id, "插入后应回填自增 id")
        let secondId = try XCTUnwrap(second.id)
        XCTAssertNotEqual(firstId, secondId)

        var ordered = try store.fetchAllOrdered()
        XCTAssertEqual(ordered.map(\.title), ["常用", "反坦克"])
        XCTAssertEqual(ordered[0].list, [1, 2, 3])

        // 更新组名与内容
        var updated = first
        updated.title = "常用改"
        updated.list = [1, 2, 3, 4]
        try store.update(updated)
        ordered = try store.fetchAllOrdered()
        XCTAssertEqual(ordered[0].title, "常用改")
        XCTAssertEqual(ordered[0].list, [1, 2, 3, 4])

        // 拖拽排序：反转顺序后按 idx 生效
        try store.saveOrder(ids: [secondId, firstId])
        ordered = try store.fetchAllOrdered()
        XCTAssertEqual(ordered.map(\.title), ["反坦克", "常用改"])

        // 删除
        try store.delete(id: firstId)
        ordered = try store.fetchAllOrdered()
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(ordered[0].title, "反坦克")
    }

    /// 显示名语言逻辑
    func testStratagemDisplayName() {
        let stratagem = Stratagem(id: 1, name: "Reinforce", nameZh: "增援", icon: "", steps: [1])
        XCTAssertEqual(stratagem.displayName(lang: "en"), "Reinforce")
        XCTAssertEqual(stratagem.displayName(lang: "zh-CN"), "增援")
        let noZh = Stratagem(id: 2, name: "Resupply", nameZh: "", icon: "", steps: [1])
        XCTAssertEqual(noZh.displayName(lang: "zh-CN"), "Resupply", "中文名缺失应回退英文名")
    }
}
