//
// RemoteDatabase.swift
// 远程战备库解析（M3）：URL 目录拆分、index.json、数据库 dump JSON
// 纯逻辑无网络依赖，供单元测试直接覆盖；格式对照安卓版 SettingsFragment 数据库更新流程
// 作者: ZJ
//

import Foundation

/// 下载与解析错误
enum DownloadError: Error, LocalizedError {
    case invalidURL(String)
    case httpStatus(Int)
    case emptyBody
    case malformedDatabase(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "无效的下载地址：\(url.isEmpty ? "（空）" : url)"
        case .httpStatus(let code): return "服务器返回错误状态码：\(code)"
        case .emptyBody: return "服务器返回内容为空"
        case .malformedDatabase(let reason): return "战备数据库格式不正确：\(reason)"
        }
    }
}

/// URL 拆分结果：directory 恒以 / 结尾，index.json 里的 db_path/icons_path 直接拼接其后
struct UrlParts: Equatable {
    var directory: String
    var fileName: String
}

/// index.json 结构：date 为版本号（全部下载完成后才写入 db_version），
/// db_path/icons_path 为相对 index.json 所在目录的路径
struct DatabaseIndex: Codable, Equatable {
    var name: String
    var nameEn: String
    var nameZh: String
    var date: String
    var dbPath: String
    var iconsPath: String

    enum CodingKeys: String, CodingKey {
        case name, nameEn, nameZh, date
        case dbPath = "db_path"
        case iconsPath = "icons_path"
    }
}

/// 数据库 dump 解析结果
struct RemoteDatabaseContent {
    var stratagems: [Stratagem]
    /// 图标文件名（不含 .svg 后缀），按行序排列，供逐个下载
    var icons: [String]
}

enum RemoteDatabase {

    /// 拆分 URL 为目录 + 文件名（对照安卓版 Utils.parseUrl）：
    /// 末段含 "." 且不以 / 结尾视为文件；否则整体视为目录、文件名用默认值
    static func parseUrl(_ raw: String, defaultFileName: String = "index.json") throws -> UrlParts {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme,
              let host = components.host else {
            throw DownloadError.invalidURL(raw)
        }
        // 用 URLComponents 取 path 以保留结尾斜杠（URL.path 会丢弃）
        let path = components.path
        let lastComponent = path.split(separator: "/").last.map(String.init) ?? ""
        let isFile = lastComponent.contains(".") && !path.hasSuffix("/")

        var fileName = isFile ? lastComponent : ""
        if fileName.isEmpty {
            fileName = defaultFileName
        }

        let directoryPath: String
        if path.hasSuffix("/") {
            directoryPath = path
        } else if isFile, let slashRange = path.range(of: "/", options: .backwards) {
            directoryPath = String(path[..<slashRange.upperBound])
        } else {
            directoryPath = path + "/"
        }

        let portPart = components.port.map { ":\($0)" } ?? ""
        return UrlParts(directory: "\(scheme)://\(host)\(portPart)\(directoryPath)", fileName: fileName)
    }

    /// 解析 index.json
    static func parseIndex(_ data: Data) throws -> DatabaseIndex {
        try JSONDecoder().decode(DatabaseIndex.self, from: data)
    }

    /// 解析数据库 dump（sqlite dump 的 JSON 形态）：
    /// {"objects":[{"rows":[[id, name, nameZh, icon, "steps JSON 文本", idx?], ...]}]}
    /// 行内第 5 元素是内嵌 JSON 数组文本；第 6 元素 idx 可缺省（旧格式），缺省取 0——与安卓版一致
    static func parseDatabaseDump(_ data: Data) throws -> RemoteDatabaseContent {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = root as? [String: Any],
              let objects = rootObject["objects"] as? [Any],
              let firstObject = objects.first as? [String: Any],
              let rows = firstObject["rows"] as? [[Any]] else {
            throw DownloadError.malformedDatabase("缺少 objects[0].rows 结构")
        }

        var stratagems: [Stratagem] = []
        var icons: [String] = []
        for (rowIndex, row) in rows.enumerated() {
            guard row.count >= 5,
                  let id = (row[0] as? NSNumber)?.intValue,
                  let name = row[1] as? String,
                  let nameZh = row[2] as? String,
                  let icon = row[3] as? String,
                  let stepsText = row[4] as? String else {
                throw DownloadError.malformedDatabase("第 \(rowIndex + 1) 行字段类型或数量不符")
            }
            let idx = row.count >= 6 ? ((row[5] as? NSNumber)?.intValue ?? 0) : 0
            stratagems.append(
                Stratagem(
                    id: id,
                    name: name,
                    nameZh: nameZh,
                    icon: icon,
                    steps: JSONIntList.decode(stepsText),
                    idx: idx
                )
            )
            icons.append(icon)
        }
        return RemoteDatabaseContent(stratagems: stratagems, icons: icons)
    }
}
