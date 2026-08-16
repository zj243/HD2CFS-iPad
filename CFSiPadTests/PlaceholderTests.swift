//
// PlaceholderTests.swift
// M0 骨架自检
// 作者: ZJ
//

import XCTest

final class PlaceholderTests: XCTestCase {

    /// 校验测试宿主为主 App 且 Bundle 基本信息配置正确：
    /// 本用例通过即代表 "xcodegen 生成工程 → iPad 模拟器跑测试" 的 CI 链路可用，
    /// 后续模块（M1 起）的单元测试沿用同一链路。
    func testHostAppBundleConfigured() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier, "com.zj.cfsipad",
            "测试宿主不是主 App，project.yml 中 TEST_HOST 配置可能被改动"
        )
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertFalse((version ?? "").isEmpty, "MARKETING_VERSION 未写入 Info.plist")
    }
}
