# CFS iPad 移植开发计划

把 [WisteFinch/Helldivers2CallForStratagemsOnPhone](https://github.com/WisteFinch/Helldivers2CallForStratagemsOnPhone)（安卓端《绝地潜兵2》战备呼叫工具，MIT 许可）移植为 iPadOS 原生 App。
安卓源码与 Rust 服务器均在本地：`C:\game\hl2\Helldivers2CallForStratagemsOnPhone`。
完整可行性评估报告：https://claude.ai/code/artifact/6db8948c-adcb-4dff-8b8a-b4a542049a0b

> **本文件是唯一的交接入口。** 任何人（或任何 agent）继续开发时：先读本文件，再按"第 6 节 执行约定"操作。每完成一个模块，更新第 1 节看板和第 7 节变更记录。

---

## 0. 已定决策（已确认，勿重新讨论）

| 决策项 | 结论 |
|---|---|
| 技术路线 | SwiftUI 原生重写（不用 Flutter / KMP / PWA） |
| 语音识别 | **完全砍掉**，不做 ASR、不做关键词库 UI、不引入任何语音依赖 |
| 目标设备 | 仅 iPad（`TARGETED_DEVICE_FAMILY = 2`），iPadOS 26.6，部署目标 iOS 17.0 |
| 装机方式 | 免费 Apple ID + Sideloadly（Windows 上签名安装，7 天续签） |
| 编译方式 | 无 Mac。GitHub Actions 免费 macOS runner 云编译未签名 IPA |
| 工程生成 | XcodeGen（`project.yml` 提交入库，CI 里生成 .xcodeproj，本地 Windows 不需要 Xcode） |
| 数据库 | GRDB（SPM 引入），直接复用安卓工程的 `stratagem_db.db` 种子文件 |
| SVG 图标 | SwiftDraw（SPM 引入）渲染运行时下载的 .svg |
| 扫码 | AVFoundation `AVCaptureMetadataOutput`（兼容性最稳，不用 VisionKit） |
| 网络 | Network.framework `NWConnection`，明文 TCP（不受 ATS 限制） |
| 服务器 | **零改动**，对接现有 Rust 服务器（API 6） |
| Bundle ID | `com.zj.cfsipad`（Sideloadly 签名时可能自动加前缀，无影响） |

## 1. 进度看板

- [x] 评估与技术选型（完成于 2026-08-16，见评估报告）
- [ ] M0 工程骨架 + CI 出包流水线 —— **代码已完成，待验收**（等用户建 GitHub 仓库推送后看 Actions 绿灯 + Sideloadly 装机）
- [ ] M1 网络协议层（TCP + 认证 + 心跳重连）
- [ ] M2 数据层（GRDB + 设置存储）
- [ ] M3 资源下载（战备库 + SVG 图标）
- [ ] M4 编组 UI（列表 / 浏览 / 编辑 / 战备总表）
- [ ] M5 Play 面板（手势输入 / 宏 / 自由输入 / 简化模式）
- [ ] M6 设置页 + 扫码 + 配置同步 + 备份
- [ ] M7 真机联调验收 + 安装手册

**当前状态**：M0 全部文件已写好（project.yml、App 入口与占位视图、测试、CI workflow、README/LICENSE/.gitignore），本地未初始化 git。CI 与真机安装尚未验证。
**下一步**：用户建公开 GitHub 仓库并推送 → 确认 Actions 绿灯、下载 IPA、Sideloadly 装机能启动 → 在看板给 M0 打勾 → 开始 M1。若 CI 报错，优先检查 project.yml 的 XcodeGen 语法与模拟器选择步骤的输出日志。

## 2. 目录结构规划

```
cfs-ipad/
├── PLAN.md                  # 本文件
├── project.yml              # XcodeGen 工程定义（唯一工程配置来源）
├── .github/workflows/
│   └── build-ipa.yml        # CI：xcodegen → xcodebuild → 打包未签名 ipa
├── CFSiPad/
│   ├── App/                 # App 入口、根导航、全局状态
│   ├── Network/             # M1：AppClient、LineFramedConnection、DataPacket
│   ├── Data/                # M2：GRDB 存储、Settings、备份模型
│   ├── Download/            # M3：数据库/图标下载器
│   ├── Views/
│   │   ├── Root/            # M4：编组列表
│   │   ├── Group/           # M4：浏览/编辑编组、战备总表
│   │   ├── Play/            # M5：游玩面板
│   │   └── Settings/        # M6：设置、扫码
│   ├── Resources/           # 种子库、音效(m4a)、App 图标、本地化
│   └── Support/             # Info.plist 片段、工具类
└── CFSiPadTests/            # M1/M2 单元测试（CI 模拟器跑）
```

## 3. 关键技术事实速查（已核实，直接采信）

### 3.1 协议（API 6，裸 TCP + 换行分隔 JSON，默认端口 23333）

| opt | 方向 | 报文 | 说明 |
|---|---|---|---|
| 0 | C→S | `{"opt":0,"api":6}` → 回 `{"status":0/2,"api":6}` | 状态/心跳；status 2=未认证 |
| 1 | C→S | `{"opt":1,"token":"..","macro":{"name":"..","steps":[1,4,4]}}` | 激活战备宏；1上2下3左4右；**无回包** |
| 2 | C→S | `{"opt":2,"token":"..","input":{"type":t,"step":s}}` | type: 0点击/1按下/2释放/3自由输入开始/4结束；step: 0开列表/1上/2下/3左/4右；**无回包** |
| 3 | C→S | `{"opt":3,"token":".."}` → 回完整配置 JSON | **响应末尾没有 `\n`**，解析要兼容 |
| 4 | C→S | `{"opt":4,"token":"..","config":{...}}` | 下发完整配置；**需 PC 控制台人工按 y**，用长超时；无回包 |
| 5 | C→S | `{"opt":5,"sid":".."}` → 回 `{"auth":true,"token":".."}` 或 `{"auth":false}` | sid 换 token |

**必守规则**：
1. 每条请求必须以 `\n` 结尾，否则服务器直接断开连接。
2. 一问一答，勿管线化：服务器单次读缓冲 4096 字节，一次 read 中第一个 `\n` 之后的内容被丢弃。
3. token 仅当前 TCP 连接有效，断线重连必须重新走 opt5。
4. 认证流程：connect → opt0 → status==2 → opt5(sid)；新 sid 需 PC 控制台人工 y/n 确认，**等待期间必须关闭读超时**（安卓版 `toggleTimeout(false)` 的等价物）。sid 是客户端首次启动生成的 16 位随机字母数字串，持久保存。
5. 心跳：每 10 秒发一次 opt0；失败触发自动重连（默认重试 5 次、间隔 2 秒，可配置）。
6. 扫码二维码内容：`{"add":"192.168.x.x","port":23333}`，**字段名是 `add`**。
7. 服务器不做版本拒绝（api 字段只用于分流和告警），直接报 `"api":6`。

### 3.2 资源下载源（全部保留自定义 URL 通道）

- 战备库 HD2：`https://cfsdb-hd2.wistefinch.site/index.json`；HD1：`https://cfsdb-hd.wistefinch.site/index.json`
- 流程：`index.json`（含 name/nameEn/nameZh/date/db_path/icons_path）→ 下载 db JSON（sqlite dump 的 `objects[0].rows` 结构）重建战备表 → 逐个下载 `<icon>.svg` 到本地图标目录，已存在则跳过。
- 语音模型下载源已随 ASR 一并砍掉。GitHub 版本检查功能也砍掉（自用侧载无意义）。

### 3.3 iOS 平台注意项

- Info.plist：`NSLocalNetworkUsageDescription`（必须，首次连接弹本地网络授权）、`NSCameraUsageDescription`（扫码）。不用 Bonjour，无需 `NSBonjourServices`。
- ATS 不约束 Network.framework 裸 socket，明文 TCP 无需任何豁免配置。
- Play 页进入时 `UIApplication.shared.isIdleTimerDisabled = true`，退出恢复。
- 退后台 TCP 会被挂起：监听 `scenePhase`，回前台自动重连（复用重连逻辑即可）。
- 多数 iPad 无震动马达：不做震动功能，只保留音效开关。
- 方向锁定不移植：iPad 上做自适应布局（横竖屏皆可用），比锁方向更符合 iPadOS。
- 音效：安卓的 3 个 ogg（step/fail/activation）iOS 不支持 ogg，需转成 .m4a 后放入 Resources（用 ffmpeg 转一次提交，或在 CI 用 afconvert 转）。

### 3.4 安卓源码参考对照（按需精读，不要全量重读）

| 移植内容 | 参考文件（相对 `Helldivers2CallForStratagemsOnPhone/`） |
|---|---|
| 协议数据结构 | `call-for-stratagems/app/src/main/java/.../network/DataPacket.kt` |
| 连接/认证/心跳/重连状态机 | 同目录 `AppClient.kt`（341 行）、`AppSocket.kt` |
| 协议权威文档 | `server_api_6.md`（根目录） |
| 服务器行为核实 | `server/src/modules/net.rs`、`auth.rs` |
| 常量（URL/键名/默认值） | `.../callforstratagems/Constants.kt` |
| 手势判定与 Play 逻辑 | `.../fragments/play/PlayFragment.kt`（990 行） |
| 数据库结构 | `.../data/` 三个 Database + `models/`；种子库 `app/src/main/assets/database/stratagem_db.db` |
| 下载流程 | `.../fragments/settings/SettingsFragment.kt` 的数据库更新部分、`utils/` 里的 DownloadService |
| 备份格式 | `.../data/BackupFileData.kt`（cfs_backup.json, ver=1） |
| 设置项与默认值 | SettingsFragment.kt + Constants.kt（SharedPreferences 键位表） |

---

## 4. 模块详情

> 每个模块设计为一次独立 agent 会话可完成的体量。完成定义：交付物齐全 + 验收标准满足 + 看板打勾 + 变更记录追加一行 + 输出建议 commit message。

### M0 工程骨架 + CI 出包流水线

**前置条件（需用户操作）**：在 GitHub 创建一个**公开**仓库（公开仓库 Actions 免费额度不限量；MIT 衍生项目公开无问题），把 `cfs-ipad/` 推上去。
**任务**：
1. `project.yml`（XcodeGen）：target CFSiPad，iOS 17.0，仅 iPad，SPM 依赖 GRDB + SwiftDraw，Info.plist 内嵌两条权限描述。
2. SwiftUI 入口 + 占位根视图（显示"CFS iPad"即可）。
3. `.github/workflows/build-ipa.yml`：macos-latest → `brew install xcodegen` → `xcodegen` → `xcodebuild -scheme CFSiPad -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build` → 产物打成 `Payload/CFSiPad.app` 结构 zip 为 `.ipa` → 上传 artifact。同时跑 `xcodebuild test`（模拟器）供后续模块使用。
4. 写 `README.md`：一段话项目说明 + 指向 PLAN.md + MIT 声明（注明衍生自 WisteFinch 原项目）。
**验收**：Actions 绿灯并能下载到 ipa；用户用 Sideloadly 装上 iPad 能打开占位界面。
**预估**：配置为主，约 300 行。

### M1 网络协议层（依赖 M0）

**任务**：
1. `DataPacket.swift`：3.1 节全部报文的 Codable 定义（字段名与 JSON 完全一致，含 `add`）。
2. `LineFramedConnection.swift`：NWConnection 封装——连接超时、按 `\n` 分帧收发、兼容 opt3 无换行响应（按"读到完整 JSON 即返回"兜底解析）、可切换读超时开关。
3. `AppClient.swift`（actor 或 @Observable 单例）：对照安卓 `AppClient.kt` 复刻状态机——connect → opt0 → 需要认证则 opt5（等待人工确认期间关超时）→ 拿 token；10s 心跳；断线自动重连（次数/间隔可配）；对 UI 暴露事件流（CONNECTING / RETRYING / AUTHING / CONNECTED / FAILED / AUTH_FAILED / API_MISMATCH / SERVER_ERR）。
4. sid 生成（16 位随机字母数字）与 UserDefaults 持久化。
5. 单元测试：报文编解码往返、分帧器（含粘包/半包/opt3 无换行三个用例）。
**验收**：CI 单元测试全绿。（真机对服务器联调放 M7；如需提前验证，可在 CI 起本仓库 Rust 服务器 `--disable-auth` 做 macOS 端集成测试，可选。）
**预估**：约 600 行 Swift + 200 行测试。

### M2 数据层（依赖 M0，与 M1 无依赖关系）

**任务**：
1. 从安卓工程复制 `stratagem_db.db` 入 Resources；首启拷贝到 Application Support，GRDB 打开。表结构照搬：`stratagem_table(id, name, nameZh, icon, steps, idx)`（steps 存 JSON 文本，读取时解码为 `[Int]`）。
2. `GroupStore`：编组表 `(id, title, list, dbName, idx)` 增删改查 + 排序持久化（GRDB 建表，不需要迁移历史包袱）。
3. `AppSettings`：UserDefaults 类型化封装。仅保留非 ASR 键：连接（addr/port/retry）、同步配置各项（端口/延迟/开列表键/按键类型/上下左右键/认证开关/有效期/debug）、控制（简化模式/图标尺寸/fastboot/音效/滑动距离阈值/滑动速度阈值/名称语言）、数据库（channel/custom/version/name 等）。默认值抄 `Constants.kt`。
4. 备份模型：`cfs_backup.json`（ver=1）的 Codable 定义，**读取时忽略 asr 相关字段**（保持能导入安卓端导出的备份），导出时省略 asr 字段。
**验收**：CI 单元测试：种子库能打开并读出战备；编组 CRUD；备份 JSON 与安卓样例互相解析成功（可从安卓 `BackupFileData.kt` 手工构造一个样例入测试资源）。
**预估**：约 500 行 + 150 行测试。

### M3 资源下载（依赖 M2）

**任务**：
1. `DownloadManager`：URLSession 下载字符串与文件（临时文件后缀 `.download` 完成后改名；已存在跳过；进度回调；可取消）。
2. 数据库更新流程：channel（HD2/HD1/自定义 URL）→ index.json → db JSON → 清空重建战备表 → 逐个下载 SVG 到 `icons/<dbName>/`。双进度（文件数 + 当前文件）。
3. `StratagemIcon` 视图：SwiftDraw 渲染本地 svg 文件，带内存缓存与占位图。
**验收**：CI 单测覆盖 index/db JSON 解析（用测试资源里的样例 JSON，不依赖外网）；下载流程留待真机验收。
**预估**：约 500 行。

### M4 编组 UI（依赖 M2、M3）

**任务**：对照安卓四个界面重写（交互细节见 PlayFragment 之外的各 Fragment，逐界面功能清单见评估报告）：
1. `RootView`：编组列表（标题 + 图标缩略行 + "+N" 溢出计数）、拖拽排序（onMove 写回 idx）、空态占位、新建入口、fastboot 模式（点击直接进 Play）。
2. `GroupView`：网格浏览组内战备（自适应列数）、点击弹战备详情（图标 + 名称 + 步骤箭头序列）、编辑/删除、进入 Play。dbName 与当前库不一致时告警条。
3. `EditGroupView`：组名 + 全量战备勾选网格 + 已选拖拽排序 + 保存（新建默认勾选 id 1/2/3）。
4. `StratagemListView`：当前库全部战备网格 + 详情弹窗（**去掉关键词编辑部分**）。
**验收**：CI 构建绿灯；模拟器截图（CI 可跑 `xcrun simctl` 截图作为产物）确认四个界面可走通主流程。
**预估**：约 800 行。

### M5 Play 面板（依赖 M1、M4）

**任务**：对照 `PlayFragment.kt` 重写，砍掉 ASR 与震动：
1. 普通模式：右侧战备列表（点击选中）+ 中央步骤箭头序列；DragGesture 方向判定（|dx| vs |dy|，距离阈值默认 100、速度阈值默认 50，读设置）；输入正确步骤高亮推进 + step 音效，错误播 fail 音效不重置；全部完成 → 发 opt1 宏 + activation 音效。
2. 宏激活：列表条目左右滑立即发 opt1。
3. 自由输入模式：进入发 opt2 `{step:0,type:3}`，每次滑动发 `{step:方向,type:0}`，退出发 `{step:0,type:4}`；十字方向指示高亮 200ms。
4. 简化模式：网格图标点击即宏 + 浮动按钮切自由输入；图标尺寸读设置。
5. 连接状态条：连接中/重试 N/M/等待认证（提示去 PC 按 y）/已连接/失败，显示地址端口。
6. 屏幕常亮（isIdleTimerDisabled）、隐藏 Home indicator、音效开关；scenePhase 回前台自动重连。
7. 三个 ogg 音效转 m4a 入 Resources（若 M0-M4 期间尚未转）。
**验收**：CI 构建绿灯 + 模拟器可进入面板并完成一次模拟输入流（无服务器时状态条显示失败但 UI 不崩）。
**预估**：约 900 行，是最大的单模块。

### M6 设置页 + 扫码 + 配置同步 + 备份（依赖 M1、M2、M3）

**任务**：
1. 连接设置：地址/端口/重试次数；测试连接（走完整连接+认证流程，弹结果）。
2. 扫码：AVFoundation 扫 QR → 解析 `{"add","port"}` → 回填连接设置；相机权限处理。
3. 同步配置：服务器端口/监听 IP/按键延迟/打开列表键 + 按键类型（hold/press/long_press/tap/double_tap）/上下左右键位选择（键值表抄 server_api_6.md 附录）/认证开关/有效期/debug；"应用配置"→ opt4 完整下发（长超时 + "去 PC 端确认"提示）。
4. 控制设置：简化模式/图标尺寸/fastboot/音效/两个滑动阈值/名称语言（auto/en/zh-CN）。
5. 信息区：数据库更新（调 M3 流程，双进度对话框）、清缓存、关于（原项目链接 + MIT 声明）。
6. 备份导入/导出：fileImporter/fileExporter 读写 `cfs_backup.json`。
**验收**：CI 绿灯；模拟器走通设置读写与备份导出导入回环。
**预估**：约 1000 行（安卓版 1660 行，砍掉 ASR 后缩水）。

### M7 真机联调验收 + 安装手册（依赖全部）

**任务**：
1. 真机全链路：PC 起 Rust 服务器（`cd server && cargo run`）→ iPad 扫码 → 认证（PC 按 y）→ 本地网络权限弹窗 → 宏/自由输入在记事本或游戏内验证按键注入 → 断线重连 → opt4 配置下发。
2. 修复联调发现的问题（预留会话空间）。
3. App 图标 + 显示名。
4. `INSTALL.md`：Sideloadly 安装步骤（Windows 装 iTunes/iCloud 官网版 → USB 连 iPad → 免费 Apple ID 签名 → iPad 开开发者模式 + 信任证书）、7 天续签说明（Sideloadly 自动续签需 PC 开机 + 同网/USB）、常见问题（本地网络权限误拒后去设置开启）。
5. 打 tag `v0.1.0`。
**验收**：用户在 iPad 上实际呼出一次战备。

---

## 5. 构建与安装（速查）

- **出包**：push 到 GitHub → Actions 自动出未签名 ipa（在 run 的 Artifacts 里下载）。
- **装机**：Windows 上 Sideloadly（v0.60+，sideloadly.io）+ 免费 Apple ID 签名安装；7 天有效，Sideloadly 可在 PC 开机且设备可达时自动续签；免费账号同时最多 3 个侧载 App。
- **首次装机**：iPad 需开"开发者模式"（设置→隐私与安全性），并在"通用→VPN 与设备管理"信任证书。

## 6. 执行约定（给后续 agent / 开发者）

1. **会话开始**：只读本文件 + 当前模块"参考对照"里列出的安卓文件，**不要**重新做可行性调研或通读安卓全部源码（评估已完成，结论在第 0/3 节）。
2. **会话结束**：更新第 1 节看板与"当前状态/下一步"，在第 7 节追加一行变更记录，输出建议 commit message（Conventional Commits，如 `feat: 完成 M1 网络协议层`）。
3. **一次会话一个模块**；模块过大做不完时，在"当前状态"写清断点（做到哪个文件哪一步）。
4. **编码规范**：遵守用户全局 CLAUDE.md（中文业务注释、作者标记 ZJ、单文件 ≤1000 行、不碎片化拆分、错误必须处理）。协议层报文字段名必须与 3.1 节 JSON 完全一致，不得"顺手规范化"。
5. **不引入新依赖**：SPM 依赖锁定为 GRDB + SwiftDraw 两个；新增依赖需用户点头。
6. **不改服务器、不改安卓端**：`C:\game\hl2\Helldivers2CallForStratagemsOnPhone` 只读。
7. Git 操作遵守用户全局规范：不主动 commit/push，完成后给建议 commit message。

## 7. 变更记录

| 日期 | 内容 |
|---|---|
| 2026-08-16 | 完成可行性评估与技术选型；制定本计划（M0-M7）。决策：SwiftUI 原生、无语音、免费 Apple ID + Sideloadly、GitHub Actions 云编译。 |
| 2026-08-16 | M0 代码完成：XcodeGen 工程定义（GRDB+SwiftDraw 依赖、iPad-only、双权限描述、TEST_HOST 宿主测试）、App 入口 + 占位根视图、骨架自检测试、CI workflow（动态选 iPad 模拟器跑测试 + 无签名真机包 + IPA 产物上传）、README/LICENSE/.gitignore。待用户建仓库后验收。 |
