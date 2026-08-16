//
// BackupFileTests.swift
// M2 备份文件测试：解析安卓端导出的备份、导入落库、导出结构保持安卓可导入
// 作者: ZJ
//

import XCTest
@testable import CFSiPad

final class BackupFileTests: XCTestCase {

    /// 模拟安卓端导出的完整备份（含 asr 设置与 keywords，iOS 侧应能解析并忽略）
    private let androidBackupJSON = #"""
    {
      "ver": 1,
      "sync": {
        "server": {"port": 23333, "ip": ""},
        "input": {"delay": 30, "open": "ctrl_left", "keytype": "hold", "up": "w", "down": "s", "left": "a", "right": "d"},
        "auth": {"enabled": true, "timeout": 3},
        "debug": false,
        "records": [123456]
      },
      "settings": {
        "conn": {"addr": "192.168.1.8", "port": 23334, "retry": 3},
        "ctrl": {"simplified": true, "stratagemSize": 120, "fastboot": true, "sfx": true, "vibrator": true, "sdt": 90, "svt": 40, "lang": "zh-CN"},
        "asr": {"model": 1, "custom": "", "enabled": true, "similarity": 60, "gpu": false, "activate": ["注意"], "autoKeywords": true},
        "db": {"channel": 2, "custom": "https://example.com/index.json"}
      },
      "groups": [
        {"id": 3, "title": "常用", "list": [1, 2, 3], "dbName": "hd2_db", "idx": 0},
        {"id": 7, "title": "重装", "list": [9, 12], "dbName": "hd2_db", "idx": 1}
      ],
      "keywords": [
        {"dbName": "hd2_db", "stratagem": 1, "keywords": ["增援"]}
      ]
    }
    """#

    private func makeTempEnvironment() throws -> (AppSettings, AppDatabase) {
        let suiteName = "cfs.test.backup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfs-backup-test-\(UUID().uuidString)", isDirectory: true)
        return (AppSettings(defaults: defaults), try AppDatabase(directory: dir))
    }

    /// 解析安卓备份：结构完整读入，asr/keywords 字段不阻碍解析
    func testDecodeAndroidBackup() throws {
        let file = try BackupFile.decode(Data(androidBackupJSON.utf8))
        XCTAssertEqual(file.ver, 1)
        XCTAssertEqual(file.sync.input.delay, 30)
        XCTAssertEqual(file.settings.conn.addr, "192.168.1.8")
        XCTAssertEqual(file.settings.ctrl.lang, "zh-CN")
        XCTAssertEqual(file.settings.db.channel, 2)
        XCTAssertEqual(file.groups.count, 2)
        XCTAssertEqual(file.groups[0].list, [1, 2, 3])
        XCTAssertEqual(file.keywords.count, 1, "keywords 应能解析（虽然 iOS 不使用）")
    }

    /// 版本不符必须明确报错
    func testUnsupportedVersionThrows() {
        let json = #"{"ver": 2}"#
        XCTAssertThrowsError(try BackupFile.decode(Data(json.utf8))) { error in
            guard case BackupError.unsupportedVersion(let ver) = error else {
                return XCTFail("应抛出 unsupportedVersion，实际 \(error)")
            }
            XCTAssertEqual(ver, 2)
        }
    }

    /// 导入：设置覆盖写入、编组追加插入（保序），asr 与 vibrator 被忽略
    func testApplyBackup() throws {
        let (settings, database) = try makeTempEnvironment()
        let file = try BackupFile.decode(Data(androidBackupJSON.utf8))
        try file.apply(settings: settings, groupStore: database.groupStore)

        XCTAssertEqual(settings.connAddress, "192.168.1.8")
        XCTAssertEqual(settings.connPort, 23334)
        XCTAssertEqual(settings.connRetry, 3)
        XCTAssertEqual(settings.syncInputDelay, 30)
        XCTAssertTrue(settings.ctrlSimplified)
        XCTAssertEqual(settings.ctrlStratagemSize, 120)
        XCTAssertEqual(settings.ctrlSwipeDistanceThreshold, 90)
        XCTAssertEqual(settings.ctrlSwipeVelocityThreshold, 40)
        XCTAssertEqual(settings.ctrlLang, "zh-CN")
        XCTAssertEqual(settings.dbChannel, 2)
        XCTAssertEqual(settings.dbCustomURL, "https://example.com/index.json")

        let groups = try database.groupStore.fetchAllOrdered()
        XCTAssertEqual(groups.map(\.title), ["常用", "重装"])
        XCTAssertEqual(groups[0].list, [1, 2, 3])
        XCTAssertEqual(groups[0].idx, 0)
    }

    /// 导出：完整结构（含 asr 中性默认值与空 keywords），保证安卓端可导入；再解码回读一致
    func testExportRoundTripAndAndroidCompatibility() throws {
        let (settings, database) = try makeTempEnvironment()
        settings.connAddress = "10.0.0.2"
        settings.ctrlSfx = true
        try database.groupStore.insert(StratagemGroup(title: "出口", list: [1, 4], dbName: "hd2_db", idx: 0))

        let exported = BackupFile.export(settings: settings, groups: try database.groupStore.fetchAllOrdered())
        let data = try exported.encodeJSON()

        // 结构核对：安卓端 Gson 对缺失字段不安全，asr/keywords/vibrator 必须存在
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["ver", "sync", "settings", "groups", "keywords"])
        let settingsObject = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertNotNil(settingsObject["asr"], "asr 块必须保留，安卓端导入才不会崩")
        let ctrlObject = try XCTUnwrap(settingsObject["ctrl"] as? [String: Any])
        XCTAssertEqual(ctrlObject["vibrator"] as? Bool, false)
        XCTAssertEqual((object["keywords"] as? [Any])?.count, 0)

        // 回读一致
        let reloaded = try BackupFile.decode(data)
        XCTAssertEqual(reloaded.settings.conn.addr, "10.0.0.2")
        XCTAssertTrue(reloaded.settings.ctrl.sfx)
        XCTAssertEqual(reloaded.groups.count, 1)
        XCTAssertEqual(reloaded.groups[0].list, [1, 4])
    }

    /// 设置默认值抽查：必须与安卓版一致（来源见 AppSettings 注释）
    func testSettingsDefaultsMatchAndroid() throws {
        let suiteName = "cfs.test.defaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.connAddress, "127.0.0.1")
        XCTAssertEqual(settings.connPort, 23333)
        XCTAssertEqual(settings.connRetry, 5)
        XCTAssertEqual(settings.syncInputDelay, 25)
        XCTAssertEqual(settings.syncInputOpen, "ctrl_left")
        XCTAssertEqual(settings.syncInputOpenType, "hold")
        XCTAssertTrue(settings.syncAuthEnabled)
        XCTAssertEqual(settings.syncAuthTimeout, 3)
        XCTAssertFalse(settings.ctrlSimplified)
        XCTAssertEqual(settings.ctrlStratagemSize, 100)
        XCTAssertFalse(settings.ctrlSfx)
        XCTAssertEqual(settings.ctrlSwipeDistanceThreshold, 100)
        XCTAssertEqual(settings.ctrlSwipeVelocityThreshold, 50)
        XCTAssertEqual(settings.ctrlLang, "auto")
        XCTAssertEqual(settings.dbChannel, 0)
        XCTAssertEqual(settings.dbVersion, "0")
        XCTAssertEqual(settings.dbName, "hd2_db")

        // 同步配置包组装
        let config = settings.syncConfigData()
        XCTAssertEqual(config.server.port, 23333)
        XCTAssertEqual(config.input.keytype, "hold")
        XCTAssertEqual(config.records, [])
    }
}
