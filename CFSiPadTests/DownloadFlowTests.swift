//
// DownloadFlowTests.swift
// M3 资源下载测试：URL 拆分、index/dump 解析、完整更新流程（假抓取器，无外网依赖）
// 作者: ZJ
//

import XCTest
@testable import CFSiPad

/// 假抓取器：按 URL 返回预置文本，文件下载直接写入占位内容并记录调用
private final class FakeFetcher: RemoteFetcher {
    var strings: [String: String] = [:]
    private(set) var fileDownloads: [String] = []

    func fetchString(_ url: URL) async throws -> String {
        guard let body = strings[url.absoluteString] else {
            throw DownloadError.httpStatus(404)
        }
        return body
    }

    func downloadFile(_ url: URL, to destination: URL, progress: @escaping (Int64, Int64) -> Void) async throws {
        fileDownloads.append(url.absoluteString)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<svg/>".utf8).write(to: destination)
        progress(6, 6)
    }
}

final class DownloadFlowTests: XCTestCase {

    private let indexJSON = #"""
    {"name":"hd2_db","nameEn":"Helldivers 2","nameZh":"绝地潜兵2","date":"20260810","db_path":"db.json","icons_path":"icons/"}
    """#

    /// 第一行 6 元素（含 idx），第二行 5 元素（旧格式，idx 缺省取 0）
    private let dumpJSON = #"""
    {"objects":[{"name":"stratagem_table","rows":[
      [1,"Reinforce","增援","reinforce","[1,2,4,3,1]",0],
      [2,"Resupply","补给","resupply","[2,2,1,4]"]
    ]}]}
    """#

    /// URL 目录拆分的各种形态（对照安卓版 Utils.parseUrl 行为）
    func testParseUrlVariants() throws {
        XCTAssertEqual(
            try RemoteDatabase.parseUrl("https://cfsdb-hd2.wistefinch.site/index.json"),
            UrlParts(directory: "https://cfsdb-hd2.wistefinch.site/", fileName: "index.json")
        )
        XCTAssertEqual(
            try RemoteDatabase.parseUrl("https://example.com/db"),
            UrlParts(directory: "https://example.com/db/", fileName: "index.json"),
            "无扩展名的末段视为目录，文件名用默认值"
        )
        XCTAssertEqual(
            try RemoteDatabase.parseUrl("https://example.com/db/"),
            UrlParts(directory: "https://example.com/db/", fileName: "index.json")
        )
        XCTAssertEqual(
            try RemoteDatabase.parseUrl("https://example.com:8080/a/index.json"),
            UrlParts(directory: "https://example.com:8080/a/", fileName: "index.json"),
            "显式端口必须保留"
        )
        XCTAssertThrowsError(try RemoteDatabase.parseUrl("")) { error in
            guard case DownloadError.invalidURL = error else {
                return XCTFail("空地址应抛 invalidURL，实际 \(error)")
            }
        }
    }

    func testParseIndex() throws {
        let index = try RemoteDatabase.parseIndex(Data(indexJSON.utf8))
        XCTAssertEqual(index.name, "hd2_db")
        XCTAssertEqual(index.nameEn, "Helldivers 2")
        XCTAssertEqual(index.nameZh, "绝地潜兵2")
        XCTAssertEqual(index.date, "20260810")
        XCTAssertEqual(index.dbPath, "db.json")
        XCTAssertEqual(index.iconsPath, "icons/")
    }

    func testParseDatabaseDump() throws {
        let content = try RemoteDatabase.parseDatabaseDump(Data(dumpJSON.utf8))
        XCTAssertEqual(content.stratagems.count, 2)
        XCTAssertEqual(content.icons, ["reinforce", "resupply"])

        XCTAssertEqual(content.stratagems[0].id, 1)
        XCTAssertEqual(content.stratagems[0].nameZh, "增援")
        XCTAssertEqual(content.stratagems[0].steps, [1, 2, 4, 3, 1])
        XCTAssertEqual(content.stratagems[0].idx, 0)

        XCTAssertEqual(content.stratagems[1].steps, [2, 2, 1, 4])
        XCTAssertEqual(content.stratagems[1].idx, 0, "5 元素旧格式行 idx 应缺省为 0")

        // 结构不符必须明确报错
        XCTAssertThrowsError(try RemoteDatabase.parseDatabaseDump(Data(#"{"objects":[]}"#.utf8))) { error in
            guard case DownloadError.malformedDatabase = error else {
                return XCTFail("应抛 malformedDatabase，实际 \(error)")
            }
        }
    }

    /// 完整更新流程：index → dump 重建战备表 → 图标落盘 → 版本号收尾；二次更新跳过已存在图标
    func testUpdaterFullFlowAndSkipExisting() async throws {
        let suiteName = "cfs.test.download.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfs-dl-\(UUID().uuidString)", isDirectory: true)
        let database = try AppDatabase(directory: directory)

        let fetcher = FakeFetcher()
        fetcher.strings["https://example.com/data/index.json"] = indexJSON
        fetcher.strings["https://example.com/data/db.json"] = dumpJSON
        settings.dbCustomURL = "https://example.com/data/index.json"

        let updater = DatabaseUpdater(fetcher: fetcher, database: database, settings: settings)
        var events: [DatabaseUpdateEvent] = []
        let version = try await updater.update(channel: 2) { events.append($0) }

        // 版本与元数据
        XCTAssertEqual(version, "20260810")
        XCTAssertEqual(settings.dbVersion, "20260810", "全部完成后才写入正式版本号")
        XCTAssertEqual(settings.dbName, "hd2_db")
        XCTAssertEqual(settings.dbNameEn, "Helldivers 2")
        XCTAssertEqual(settings.dbNameZh, "绝地潜兵2")
        XCTAssertEqual(settings.dbChannel, 2)

        // 战备表整表重建
        let stratagems = try database.stratagemStore.fetchAll()
        XCTAssertEqual(stratagems.count, 2)
        XCTAssertEqual(stratagems.map(\.id), [1, 2])

        // 图标落盘（相对 index 目录的 icons/ 路径拼接）
        XCTAssertEqual(fetcher.fileDownloads, [
            "https://example.com/data/icons/reinforce.svg",
            "https://example.com/data/icons/resupply.svg",
        ])
        let iconFile = database.iconsDirectory(dbName: "hd2_db").appendingPathComponent("reinforce.svg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconFile.path))

        // 事件流以 finished 收尾
        guard case .finished(let finishedVersion)? = events.last else {
            return XCTFail("最后一个事件应为 finished，实际 \(String(describing: events.last))")
        }
        XCTAssertEqual(finishedVersion, "20260810")

        // 二次更新：图标已存在应全部跳过
        _ = try await updater.update(channel: 2)
        XCTAssertEqual(fetcher.fileDownloads.count, 2, "已存在的图标必须跳过下载")

        // 清除缓存：图标目录删除、战备表清空、版本回退 "0"
        try updater.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: iconFile.path))
        XCTAssertEqual(try database.stratagemStore.count(), 0)
        XCTAssertEqual(settings.dbVersion, "0")
    }

    /// SVG use/href 兼容性修补：SVG2 的 <use href> 改写为 xlink:href 并补命名空间；
    /// 已是 xlink 写法或不含 <use> 的文件必须原样返回
    func testPatchUseHref() {
        let svg2Style = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 126 126"><defs><path id="mgr" d="M1 1"/></defs><use href="#mgr"/><use href="#mgr" transform="translate(0 18)"/></svg>"#
        let patched = StratagemIconCache.patchUseHref(svg2Style)
        XCTAssertTrue(patched.contains(#"xlink:href="#mgr""#))
        XCTAssertTrue(patched.contains("xmlns:xlink=\"http://www.w3.org/1999/xlink\""))
        XCTAssertFalse(patched.contains(" href=\"#mgr\""), "全部 href 都应被改写")

        let xlinkStyle = #"<svg xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="#a"/></svg>"#
        XCTAssertEqual(StratagemIconCache.patchUseHref(xlinkStyle), xlinkStyle, "已是 xlink 写法应原样返回")

        let noUse = #"<svg><path d="M1 1" fill="#fff"/></svg>"#
        XCTAssertEqual(StratagemIconCache.patchUseHref(noUse), noUse, "不含 use 应原样返回")
    }

    /// 自定义频道地址为空必须明确报错
    func testUpdaterEmptyCustomURLThrows() async throws {
        let suiteName = "cfs.test.download.empty.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfs-dl-empty-\(UUID().uuidString)", isDirectory: true)
        let database = try AppDatabase(directory: directory)
        let updater = DatabaseUpdater(fetcher: FakeFetcher(), database: database, settings: settings)

        do {
            _ = try await updater.update(channel: 2)
            XCTFail("自定义地址为空应抛错")
        } catch {
            guard case DownloadError.invalidURL = error else {
                return XCTFail("应抛 invalidURL，实际 \(error)")
            }
        }
    }
}
