//
// DataPacketTests.swift
// M1 协议报文测试：字段名与 opt 编号必须与服务器 JSON 完全一致（PLAN.md 3.1 节）
// 作者: ZJ
//

import XCTest
@testable import CFSiPad

final class DataPacketTests: XCTestCase {

    /// 编码为 JSON 对象字典，便于逐字段断言字段名
    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            XCTFail("编码结果不是 JSON 对象")
            return [:]
        }
        return dict
    }

    /// 五种请求报文的 opt 编号与字段名核对（opt=4 单独测）
    func testRequestPacketsFieldNamesAndOpt() throws {
        let status = try jsonObject(RequestStatusPacket(api: 6))
        XCTAssertEqual(status["opt"] as? Int, 0)
        XCTAssertEqual(status["api"] as? Int, 6)

        let macro = try jsonObject(
            RequestMacroPacket(macro: StratagemMacroData(name: "轨道炮攻击", steps: [1, 4, 4]), token: "tk")
        )
        XCTAssertEqual(macro["opt"] as? Int, 1)
        XCTAssertEqual(macro["token"] as? String, "tk")
        let macroBody = macro["macro"] as? [String: Any]
        XCTAssertEqual(macroBody?["name"] as? String, "轨道炮攻击")
        XCTAssertEqual(macroBody?["steps"] as? [Int], [1, 4, 4])

        let input = try jsonObject(
            RequestInputPacket(input: StratagemInputData(step: 2, type: 0), token: "tk")
        )
        XCTAssertEqual(input["opt"] as? Int, 2)
        let inputBody = input["input"] as? [String: Any]
        XCTAssertEqual(inputBody?["step"] as? Int, 2)
        XCTAssertEqual(inputBody?["type"] as? Int, 0)

        let config = try jsonObject(RequestConfigPacket(token: "tk"))
        XCTAssertEqual(config["opt"] as? Int, 3)
        XCTAssertEqual(config["token"] as? String, "tk")

        let auth = try jsonObject(RequestAuthPacket(sid: "abcd1234ABCD5678"))
        XCTAssertEqual(auth["opt"] as? Int, 5)
        XCTAssertEqual(auth["sid"] as? String, "abcd1234ABCD5678")
    }

    /// opt=4 配置包：默认值与安卓版 Constants 一致，且必须编码出完整配置对象（服务器整包替换）
    func testSyncPacketEncodesFullDefaultConfig() throws {
        let packet = try jsonObject(RequestSyncPacket(config: SyncConfigData(), token: "tk"))
        XCTAssertEqual(packet["opt"] as? Int, 4)

        let config = packet["config"] as? [String: Any]
        let server = config?["server"] as? [String: Any]
        XCTAssertEqual(server?["port"] as? Int, 23333)
        XCTAssertEqual(server?["ip"] as? String, "")

        let inputConfig = config?["input"] as? [String: Any]
        XCTAssertEqual(inputConfig?["delay"] as? Int, 25)
        XCTAssertEqual(inputConfig?["open"] as? String, "ctrl_left")
        XCTAssertEqual(inputConfig?["keytype"] as? String, "hold")
        XCTAssertEqual(inputConfig?["up"] as? String, "w")
        XCTAssertEqual(inputConfig?["down"] as? String, "s")
        XCTAssertEqual(inputConfig?["left"] as? String, "a")
        XCTAssertEqual(inputConfig?["right"] as? String, "d")

        let authConfig = config?["auth"] as? [String: Any]
        XCTAssertEqual(authConfig?["enabled"] as? Bool, true)
        XCTAssertEqual(authConfig?["timeout"] as? Int, 3)

        XCTAssertEqual(config?["debug"] as? Bool, false)
        XCTAssertEqual(config?["records"] as? [Int], [])
    }

    /// 服务器响应与扫码内容解码（注意扫码字段名是 add）
    func testDecodeServerResponses() throws {
        let decoder = JSONDecoder()

        let status = try decoder.decode(
            ReceiveStatusData.self, from: Data(#"{"status":2,"api":6}"#.utf8)
        )
        XCTAssertEqual(status.status, 2)
        XCTAssertEqual(status.api, 6)

        let authOk = try decoder.decode(
            ReceiveAuthData.self, from: Data(#"{"auth":true,"token":"AbCd1234"}"#.utf8)
        )
        XCTAssertTrue(authOk.auth)
        XCTAssertEqual(authOk.token, "AbCd1234")

        let address = try decoder.decode(
            AddressData.self, from: Data(#"{"add":"192.168.1.5","port":23333}"#.utf8)
        )
        XCTAssertEqual(address.add, "192.168.1.5")
        XCTAssertEqual(address.port, 23333)
    }

    /// sid：16 位字母数字，生成后持久化、二次读取不变（服务器按 sid 记忆认证记录）
    func testSidGenerationAndPersistence() throws {
        let suiteName = "cfs.test.sid"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let sid = AppClient.loadOrCreateSid(defaults: defaults)
        XCTAssertEqual(sid.count, 16)
        XCTAssertTrue(sid.allSatisfy { $0.isLetter || $0.isNumber }, "sid 只应包含字母与数字")
        XCTAssertEqual(AppClient.loadOrCreateSid(defaults: defaults), sid, "sid 必须持久化且稳定")

        defaults.removePersistentDomain(forName: suiteName)
    }
}
