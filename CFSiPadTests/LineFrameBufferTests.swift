//
// LineFrameBufferTests.swift
// M1 分帧器测试：换行分帧的粘包/半包，以及 opt=3 响应无换行的 JSON 完整性回落
// 作者: ZJ
//

import XCTest
@testable import CFSiPad

final class LineFrameBufferTests: XCTestCase {

    /// 粘包：一次到达两条完整报文，应拆成两条
    func testStickyPacketsSplitIntoTwoMessages() {
        var buffer = LineFrameBuffer()
        buffer.append(Data("{\"status\":0,\"api\":6}\n{\"auth\":true,\"token\":\"x\"}\n".utf8))
        let messages = buffer.drainMessages()
        XCTAssertEqual(messages, ["{\"status\":0,\"api\":6}", "{\"auth\":true,\"token\":\"x\"}"])
    }

    /// 半包：报文跨两个 TCP 分片到达，第一片不产出，第二片补齐后产出完整一条
    func testPartialPacketAcrossChunks() {
        var buffer = LineFrameBuffer()
        buffer.append(Data("{\"status\":0,\"ap".utf8))
        XCTAssertEqual(buffer.drainMessages(), [], "半包不应产出报文")
        buffer.append(Data("i\":6}\n".utf8))
        XCTAssertEqual(buffer.drainMessages(), ["{\"status\":0,\"api\":6}"])
    }

    /// opt=3 场景：服务器配置响应末尾没有 \n，JSON 完整即应产出
    func testJSONWithoutTrailingNewline() {
        var buffer = LineFrameBuffer()
        let configJSON = "{\"server\":{\"port\":23333,\"ip\":\"\"},\"debug\":false,\"records\":[]}"
        buffer.append(Data(configJSON.utf8))
        XCTAssertEqual(buffer.drainMessages(), [configJSON])
    }

    /// 嵌套对象 + 字符串内含右花括号和转义引号：未收完时不得提前产出，收完后完整产出
    func testNestedBracesAndEscapesNotPrematurelyEmitted() {
        var buffer = LineFrameBuffer()
        let head = #"{"config":{"open":"ctrl_left","note":"a}b\"c""#
        buffer.append(Data(head.utf8))
        XCTAssertEqual(buffer.drainMessages(), [], "字符串内的 } 不应被计入配对")
        buffer.append(Data("}}".utf8))
        XCTAssertEqual(buffer.drainMessages(), [head + "}}"])
    }

    /// JSON 回落产出后又收到孤立换行：不得产出空报文或重复报文
    func testLateNewlineAfterJSONFallbackProducesNoEmptyMessage() {
        var buffer = LineFrameBuffer()
        buffer.append(Data("{\"status\":0,\"api\":6}".utf8))
        XCTAssertEqual(buffer.drainMessages().count, 1)
        buffer.append(Data("\n".utf8))
        XCTAssertEqual(buffer.drainMessages(), [], "孤立换行只应被丢弃")
    }

    /// 行尾 \r\n 应被清理干净
    func testCRLFTrimmed() {
        var buffer = LineFrameBuffer()
        buffer.append(Data("{\"status\":0,\"api\":6}\r\n".utf8))
        XCTAssertEqual(buffer.drainMessages(), ["{\"status\":0,\"api\":6}"])
    }

    /// JSON 完整性判定的边界用例
    func testIsCompleteJSONObjectEdgeCases() {
        XCTAssertTrue(LineFrameBuffer.isCompleteJSONObject(Data("{\"a\":1}".utf8)))
        XCTAssertTrue(LineFrameBuffer.isCompleteJSONObject(Data("  {\"a\":{\"b\":2}} ".utf8)), "前后空白应被容忍")
        XCTAssertFalse(LineFrameBuffer.isCompleteJSONObject(Data("{\"a\":1".utf8)), "未闭合不算完整")
        XCTAssertFalse(LineFrameBuffer.isCompleteJSONObject(Data("{\"a\":1}x".utf8)), "闭合后有多余内容不算恰好一个对象")
        XCTAssertFalse(LineFrameBuffer.isCompleteJSONObject(Data("[1,2]".utf8)), "顶层数组不属于本协议报文")
        XCTAssertFalse(LineFrameBuffer.isCompleteJSONObject(Data(#"{"s":"un\"closed}"#.utf8)), "字符串未闭合不算完整")
    }
}
