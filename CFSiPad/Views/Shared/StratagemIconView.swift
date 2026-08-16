//
// StratagemIconView.swift
// 战备图标渲染（M3）：SwiftDraw 光栅化本地 SVG + 内存缓存
// 图标文件由 DatabaseUpdater 下载到 icons/<dbName>/<icon>.svg
// 作者: ZJ
//

import SwiftUI
import SwiftDraw

/// 战备图标内存缓存：首次访问时从本地 SVG 文件光栅化，NSCache 自动响应内存压力回收。
/// 图标为几 KB 的小文件，同步光栅化耗时可忽略（安卓版同样在列表绑定时同步渲染）
final class StratagemIconCache {
    static let shared = StratagemIconCache()

    private let cache = NSCache<NSString, UIImage>()

    /// 取图标位图；本地文件缺失或解析失败返回 nil，由视图层显示占位符
    func image(icon: String, dbName: String) -> UIImage? {
        let key = "\(dbName)/\(icon)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let fileURL = AppDatabase.shared
            .iconsDirectory(dbName: dbName)
            .appendingPathComponent(icon + ".svg")
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let svg = SVG(fileURL: fileURL) else {
            return nil
        }
        let image = svg.rasterize()
        cache.setObject(image, forKey: key)
        return image
    }

    /// 清空缓存（清除数据库缓存或更新完成后调用，强制重新读盘）
    func clear() {
        cache.removeAllObjects()
    }
}

/// 战备图标视图：图标缺失时显示虚线问号占位（对应安卓版 Unknown 占位逻辑）
struct StratagemIconView: View {
    /// 图标文件名（不含 .svg 后缀），来自战备表 icon 列
    let icon: String
    /// 图标所属战备库标识（icons 子目录名）
    let dbName: String

    var body: some View {
        if let image = StratagemIconCache.shared.image(icon: icon, dbName: dbName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}
