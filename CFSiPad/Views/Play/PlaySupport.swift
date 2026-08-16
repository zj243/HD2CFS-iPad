//
// PlaySupport.swift
// Play 面板支撑件（M5）：音效播放器、连接状态模型与状态条
// 作者: ZJ
//

import AVFoundation
import Observation
import SwiftUI

/// 游玩音效（step/fail/activation，转自安卓版 res/raw 的 ogg）。
/// 总开关跟随 ctrl_sfx 设置；音频会话用 ambient 类别，与游戏/音乐混音不抢占
final class PlaySoundPlayer {
    private let isEnabled: Bool
    private var stepPlayer: AVAudioPlayer?
    private var failPlayer: AVAudioPlayer?
    private var activationPlayer: AVAudioPlayer?

    init(enabled: Bool) {
        isEnabled = enabled
        guard enabled else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音频会话配置失败不影响主功能，仅记录
            print("[PlaySoundPlayer] 音频会话配置失败：\(error)")
        }
        stepPlayer = Self.load("step")
        failPlayer = Self.load("fail")
        activationPlayer = Self.load("activation")
    }

    private static func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            print("[PlaySoundPlayer] 音效资源缺失：\(name).m4a")
            return nil
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    func playStep() { play(stepPlayer) }
    func playFail() { play(failPlayer) }
    func playActivation() { play(activationPlayer) }

    private func play(_ player: AVAudioPlayer?) {
        guard isEnabled, let player else { return }
        player.currentTime = 0
        player.play()
    }
}

/// 连接状态模型：接管 AppClient 事件并翻译为状态条文案/颜色。
/// start() 可重复调用（回前台重连、修改地址后重启都走它）。
/// 状态属性只在主线程写入：start/stop 由视图在主线程调用，事件回调内部切回主线程
@Observable
final class ConnectionStatusModel {
    enum Kind {
        case neutral, progress, ok, error
    }

    private(set) var text = "未连接"
    private(set) var kind: Kind = .neutral

    private var address = ""
    private var port = 0
    private var sid = ""

    /// 读取当前连接设置并启动客户端（旧连接被丢弃重建）
    func start() {
        let settings = AppSettings.shared
        address = settings.connAddress
        port = settings.connPort
        sid = AppClient.loadOrCreateSid()
        guard let portValue = UInt16(exactly: port) else {
            text = "端口号无效：\(port)，请到设置中修正"
            kind = .error
            return
        }
        text = "连接中… \(address):\(port)"
        kind = .progress

        let host = address
        let retry = settings.connRetry
        let deviceSid = sid
        Task {
            await AppClient.shared.setEventListener { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.apply(event)
                }
            }
            await AppClient.shared.start(address: host, port: portValue, sid: deviceSid, retry: retry)
        }
    }

    /// 关闭连接（离开 Play 页时调用，对应安卓版 onDestroy 的 closeClient）
    func stop() {
        Task {
            await AppClient.shared.stop()
        }
    }

    private func apply(_ event: AppClientEvent) {
        let suffix = " \(address):\(port)"
        switch event {
        case .connecting:
            text = "连接中…" + suffix
            kind = .progress
        case .retrying(let attempt, let limit):
            text = "等待重试 \(attempt)/\(limit)" + suffix
            kind = .progress
        case .authing:
            text = "等待认证：请在电脑服务器端按 Y 确认（\(sid)）"
            kind = .progress
        case .connected:
            text = "已连接" + suffix
            kind = .ok
        case .failed:
            text = "连接失败" + suffix
            kind = .error
        case .disconnected:
            text = "已断开"
            kind = .neutral
        case .authFailed:
            text = "认证被拒绝，请在电脑端重新确认"
            kind = .error
        case .apiMismatch:
            text = "服务器协议版本不匹配，请更新服务器"
            kind = .error
        case .serverError:
            text = "服务器状态异常"
            kind = .error
        case .sent:
            break
        }
    }
}

/// 顶部连接状态条：状态图标 + 文案 + 呼叫提示
struct ConnectionStatusBar: View {
    let model: ConnectionStatusModel
    let activatedName: String?

    var body: some View {
        HStack(spacing: 8) {
            switch model.kind {
            case .progress:
                ProgressView()
                    .controlSize(.small)
            case .ok:
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            case .neutral:
                Circle()
                    .fill(.gray)
                    .frame(width: 10, height: 10)
            }
            Text(model.text)
                .font(.footnote)
                .lineLimit(1)
            Spacer()
            if let activatedName {
                Text("已呼叫：\(activatedName)")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
