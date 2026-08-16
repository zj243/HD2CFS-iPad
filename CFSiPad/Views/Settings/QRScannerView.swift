//
// QRScannerView.swift
// 扫码连接（M6）：扫描服务器控制台打印的二维码，内容为 {"add":"IP","port":23333}
// 对应安卓版 QRCodeScanActivity（ZXingLite），iOS 侧用 AVFoundation 实现
// 作者: ZJ
//

import AVFoundation
import SwiftUI

/// 扫码弹窗：处理相机权限，扫到第一个二维码即回调原始文本并关闭
struct QRScannerSheet: View {
    /// 扫到二维码的回调（原始字符串，由调用方解析）
    var onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permission: Permission = .checking

    private enum Permission {
        case checking, granted, denied
    }

    var body: some View {
        NavigationStack {
            Group {
                switch permission {
                case .checking:
                    ProgressView("正在请求相机权限…")
                case .granted:
                    QRScannerRepresentable { code in
                        onResult(code)
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                case .denied:
                    ContentUnavailableView {
                        Label("无法使用相机", systemImage: "camera.fill")
                    } description: {
                        Text("请到 设置 - 隐私与安全性 - 相机 中允许本 App 使用相机，或手动输入服务器地址。")
                    }
                }
            }
            .navigationTitle("扫描连接二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .task(requestPermission)
    }

    @Sendable
    private func requestPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .granted : .denied
        default:
            permission = .denied
        }
    }
}

/// AVFoundation 扫码控制器封装
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// 只回调第一次识别结果，避免同一码连续触发
    private var hasDelivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showSetupFailure()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showSetupFailure()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // startRunning 为阻塞调用，须在后台队列执行
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDelivered,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let text = object.stringValue else {
            return
        }
        hasDelivered = true
        onCode?(text)
    }

    /// 相机初始化失败（如模拟器无摄像头）时给出可见提示，而非黑屏
    private func showSetupFailure() {
        let label = UILabel()
        label.text = "相机初始化失败"
        label.textColor = .white
        label.textAlignment = .center
        label.frame = view.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }
}
