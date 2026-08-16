//
// PlayView.swift
// 游玩面板（M5），对应安卓版 PlayFragment（已按决策去掉语音与震动）
// 作者: ZJ
//

import SwiftUI

struct PlayView: View {
    let group: StratagemGroup

    private let settings = AppSettings.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var status = ConnectionStatusModel()
    @State private var stratagems: [Stratagem] = []
    @State private var selected: Stratagem?
    @State private var stepProgress = 0
    @State private var isFreeInput = false
    @State private var isSimplified = false
    @State private var highlightedDirection: Int?
    @State private var lastActivatedName: String?
    @State private var sound: PlaySoundPlayer?
    @State private var directionFlashTask: Task<Void, Never>?
    @State private var activatedFlashTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ConnectionStatusBar(model: status, activatedName: lastActivatedName)
            if isSimplified {
                simplifiedContent
            } else {
                normalContent
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    setFreeInput(!isFreeInput)
                } label: {
                    Label("自由输入", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
                .tint(isFreeInput ? .yellow : Color.accentColor)
            }
        }
        // 游玩期间隐藏 Home 指示条、屏幕常亮（对应安卓版沉浸全屏 + keepScreenOn）
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: setup)
        .onDisappear(perform: tearDown)
        .onChange(of: scenePhase) { _, phase in
            // 退后台 TCP 会被系统挂起，回前台整体重启连接（start 会丢弃旧连接）
            if phase == .active {
                status.start()
            }
        }
        .errorAlert($errorMessage)
    }

    // MARK: - 普通模式：左侧手势区 + 右侧战备列表

    private var normalContent: some View {
        HStack(spacing: 0) {
            gestureArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            stratagemList
                .frame(width: 300)
        }
    }

    /// 战备列表：点击选中（再点取消），左右滑动条目立即呼叫（宏）
    private var stratagemList: some View {
        List {
            ForEach(stratagems) { stratagem in
                Button {
                    select(stratagem)
                } label: {
                    HStack(spacing: 12) {
                        StratagemIconView(icon: stratagem.icon, dbName: settings.dbName)
                            .frame(width: 40, height: 40)
                        Text(stratagem.displayName(lang: settings.ctrlLang))
                            .foregroundStyle(.primary)
                    }
                }
                .listRowBackground(
                    selected?.id == stratagem.id ? Color.accentColor.opacity(0.18) : nil
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    macroSwipeButton(stratagem)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    macroSwipeButton(stratagem)
                }
            }
        }
        .listStyle(.plain)
    }

    private func macroSwipeButton(_ stratagem: Stratagem) -> some View {
        Button {
            activateMacro(stratagem)
        } label: {
            Label("呼叫", systemImage: "dot.radiowaves.left.and.right")
        }
        .tint(.orange)
    }

    /// 手势区：深色底（战备图标为白色主体）；普通模式展示选中战备与步骤进度，
    /// 自由输入模式展示十字方向指示
    private var gestureArea: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.13)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 24) {
                if isFreeInput {
                    freeInputIndicator
                    Text("自由输入模式：滑动发送单步方向")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                } else if let selected {
                    StratagemIconView(icon: selected.icon, dbName: settings.dbName)
                        .frame(width: 96, height: 96)
                    Text(selected.displayName(lang: settings.ctrlLang))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    StepArrowsView(steps: selected.steps, completed: stepProgress)
                        .font(.system(size: 34, weight: .bold))
                    Text("在此区域按步骤滑动输入")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("点击右侧列表选择战备后滑动输入\n或左右滑动列表条目直接呼叫")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding()
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    /// 十字方向指示，触发方向高亮 200ms（对应安卓版自由输入指示）
    private var freeInputIndicator: some View {
        VStack(spacing: 20) {
            directionArrow(1, "arrow.up")
            HStack(spacing: 72) {
                directionArrow(3, "arrow.left")
                directionArrow(4, "arrow.right")
            }
            directionArrow(2, "arrow.down")
        }
    }

    private func directionArrow(_ direction: Int, _ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(highlightedDirection == direction ? Color.yellow : Color.white.opacity(0.85))
    }

    // MARK: - 简化模式：网格点击即呼叫

    private var simplifiedContent: some View {
        Group {
            if isFreeInput {
                gestureArea
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: CGFloat(settings.ctrlStratagemSize)), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(stratagems) { stratagem in
                            Button {
                                activateMacro(stratagem)
                            } label: {
                                StratagemIconView(icon: stratagem.icon, dbName: settings.dbName)
                                    .frame(height: CGFloat(settings.ctrlStratagemSize))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - 手势判定（对照安卓版 onFling：距离与速度双阈值，|dx| 与 |dy| 较大者定轴）

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                handleSwipe(translation: value.translation, velocity: value.velocity)
            }
    }

    private func handleSwipe(translation: CGSize, velocity: CGSize) {
        let dx = translation.width
        let dy = translation.height
        let distanceThreshold = Double(settings.ctrlSwipeDistanceThreshold)
        let velocityThreshold = Double(settings.ctrlSwipeVelocityThreshold)
        let direction: Int
        if abs(dx) > abs(dy) {
            guard abs(dx) > distanceThreshold, abs(velocity.width) > velocityThreshold else { return }
            direction = dx >= 0 ? 4 : 3
        } else {
            guard abs(dy) > distanceThreshold, abs(velocity.height) > velocityThreshold else { return }
            direction = dy >= 0 ? 2 : 1
        }
        onInput(direction)
    }

    /// 输入处理（对照安卓版 onInputting）：
    /// 自由输入模式发单步；普通模式比对当前步骤——正确推进（步骤音效），
    /// 错误播失败音效不重置进度，全部完成发宏并取消选中
    private func onInput(_ direction: Int) {
        if isFreeInput {
            sendStep(step: direction, type: 0)
            flashDirection(direction)
            return
        }
        guard let current = selected else { return }
        let steps = current.steps
        guard stepProgress < steps.count else { return }
        if direction == steps[stepProgress] {
            stepProgress += 1
            sound?.playStep()
            if stepProgress >= steps.count {
                activateMacro(current)
                // 与安卓一致：完成后取消选中、进度清零
                selected = nil
                stepProgress = 0
            }
        } else {
            sound?.playFail()
        }
    }

    // MARK: - 选择与指令发送

    /// 点击列表条目：选中并清零进度；点击已选中条目则取消选中（与安卓一致）
    private func select(_ stratagem: Stratagem) {
        guard !isFreeInput else { return }
        stepProgress = 0
        if selected?.id == stratagem.id {
            selected = nil
        } else {
            selected = stratagem
        }
    }

    /// 发送战备宏（opt=1）：宏名按语言取显示名，与安卓一致
    private func activateMacro(_ stratagem: Stratagem) {
        sound?.playActivation()
        let name = stratagem.displayName(lang: settings.ctrlLang)
        let steps = stratagem.steps
        Task {
            await AppClient.shared.activateMacro(StratagemMacroData(name: name, steps: steps))
        }
        showActivatedFlash(name)
    }

    /// 发送单步输入（opt=2）。安卓版 activateStep 每次都播步骤音效（含进入/退出自由输入），保持一致
    private func sendStep(step: Int, type: Int) {
        sound?.playStep()
        Task {
            await AppClient.shared.sendInput(StratagemInputData(step: step, type: type))
        }
    }

    /// 切换自由输入：进入发 {step:0,type:3}（服务器按住"打开战备列表"键），退出发 {step:0,type:4}
    private func setFreeInput(_ flag: Bool) {
        guard flag != isFreeInput else { return }
        isFreeInput = flag
        if flag {
            selected = nil
            stepProgress = 0
            sendStep(step: 0, type: 3)
        } else {
            sendStep(step: 0, type: 4)
        }
    }

    // MARK: - 瞬时反馈

    private func flashDirection(_ direction: Int) {
        directionFlashTask?.cancel()
        highlightedDirection = direction
        directionFlashTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled {
                highlightedDirection = nil
            }
        }
    }

    private func showActivatedFlash(_ name: String) {
        activatedFlashTask?.cancel()
        lastActivatedName = name
        activatedFlashTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled {
                lastActivatedName = nil
            }
        }
    }

    // MARK: - 生命周期

    private func setup() {
        isSimplified = settings.ctrlSimplified
        sound = PlaySoundPlayer(enabled: settings.ctrlSfx)
        loadStratagems()
        UIApplication.shared.isIdleTimerDisabled = true
        status.start()
    }

    private func tearDown() {
        UIApplication.shared.isIdleTimerDisabled = false
        if isFreeInput {
            // 退出前必须释放服务器端按住的"打开战备列表"键
            Task {
                await AppClient.shared.sendInput(StratagemInputData(step: 0, type: 4))
                await AppClient.shared.stop()
            }
        } else {
            status.stop()
        }
    }

    /// 按编组顺序加载战备，过滤当前库中不存在的 id（对应安卓版 isIdValid 过滤）
    private func loadStratagems() {
        do {
            let dict = try AppDatabase.shared.stratagemStore.fetchDictionary(ids: group.list)
            stratagems = group.list.compactMap { dict[$0] }
        } catch {
            errorMessage = "读取编组战备失败：\(error.localizedDescription)"
        }
    }
}
