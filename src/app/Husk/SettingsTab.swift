// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Settings, as a hierarchy rather than one long form.
///
/// Everything used to live on a single scrolling page, so choices that change
/// the machine sat next to choices that change a colour, and the ones with
/// consequences were easy to reach by accident. The grouping here is the
/// concept's: what belongs to the app, what belongs to the emulator, and what
/// the thing actually is.
struct SettingsTab: View {
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var host = AndroidHost.shared
    @State private var searching = false

    var body: some View {
        HuskNavStack {
            ZStack {
                Theme.backdrop
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HuskHeader(mark: true, title: "设置")

                        group("通用") {
                            link(LibrarySettings(), "square.grid.2x2", "应用库",
                                 "你的应用与它们的图标")
                            RowDivider()
                            link(PerformanceSettings(), "speedometer", "性能",
                                 "渲染器、声音")
                            RowDivider()
                            link(AppearanceSettings(), "paintbrush", "外观",
                                 "浅色或深色、应用图标")
                        }

                        group("模拟器") {
                            link(JITSettings(), "bolt.circle", "JIT 与侧载",
                                 "可执行内存、启动")
                            RowDivider()
                            link(InputSettings(), "hand.tap", "输入",
                                 "屏幕、触控、键盘")
                            RowDivider()
                            link(NetworkSettings(), "globe", "网络",
                                 "互联网与保存的会话")
                            RowDivider()
                            link(SavedMachineSettings(), "externaldrive",
                                 "保存的机器", "快照与自动保存")
                        }

                        group("实验性") {
                            link(TranslationLayerSettings(), "testtube.2",
                                 "Android 翻译层",
                                 "无需启动 Android 的应用")
                        }

                        group("关于") {
                            NavigationLink { AboutSettings() } label: {
                                HStack(spacing: 14) {
                                    HuskMark(size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Husk")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                        Text("版本 \(Bundle.main.version) "
                                           + " · \(Bundle.main.commit)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.textDim)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textDim.opacity(0.7))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
            .huskToolbarHiddenTabBar()
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String,
                                      @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .padding(.leading, 4)
            RowGroup { rows() }
        }
    }

    private func link<D: View>(_ destination: D, _ icon: String,
                               _ title: String, _ subtitle: String) -> some View {
        NavigationLink { destination } label: {
            HuskRow(systemImage: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

/// A Form, on Husk's page rather than the system's.
private struct HuskForm: ViewModifier {
    func body(content: Content) -> some View {
        content
            .huskScrollBackgroundHidden()
            .background(Theme.backdrop)
            .tint(Theme.accent)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func huskForm() -> some View { modifier(HuskForm()) }
}

// MARK: - Library

struct LibrarySettings: View {
    @ObservedObject private var host = AndroidHost.shared
    @State private var working = false

    var body: some View {
        Form {
            Section {
                DetailRow(label: "应用", value: "\(host.packages.count)", mono: false)
                DetailRow(label: "带图标",
                          value: "\(host.packages.filter { $0.iconPath != nil }.count)",
                          mono: false)
            } footer: {
                Text("列表会写入磁盘，所以在 Android "
                   + "完成启动之前就能显示。")
            }

            Section {
                Button {
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label(working ? "正在刷新…" : "从 Android 刷新",
                          systemImage: "arrow.clockwise")
                }
                .disabled(working || !host.isReady)

                Button {
                    AndroidHost.forgetIcons()
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label("重新获取图标", systemImage: "photo.on.rectangle")
                }
                .disabled(working || !host.isReady)
            } footer: {
                Text("名称和图标来自 Android 自己的桌面，它保留自己绘制的版本。重新获取会"
                   + "丢弃 Husk 的副本并重新询问。"
                   + "")
            }
        }
        .huskForm()
        .navigationTitle("应用库")
    }
}

// MARK: - Performance

struct PerformanceSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var gpuMode =
        UserDefaults.standard.object(forKey: "husk.gpuMode") as? Bool ?? true
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var soundDevice =
        UserDefaults.standard.object(forKey: "husk.soundDevice") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Picker("渲染器", selection: $gpuMode) {
                    Text("GPU").tag(true)
                    Text("CPU").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: gpuMode) { v in
                    UserDefaults.standard.set(v, forKey: "husk.gpuMode")
                    HuskLog.log("ui", v ? "GPU renderer selected" : "CPU renderer selected")
                }
            } header: {
                Text("渲染器")
            } footer: {
                Text(gpuMode
                     ? "Android 通过 Metal 在真实 GPU 上绘制——帧率大约四倍。"
                     + "这是默认值。"
                     : "每个像素都由模拟的 CPU 绘制。慢得多，只有在 GPU 出问题时才"
                     + "值得选它。")
            }

            Section {
                DetailRow(label: "帧率",
                          value: runner.fps > 0
                                 ? String(format: "%.0f fps", runner.fps) : "—")
                DetailRow(label: "客户机屏幕",
                          value: "\(QemuRunner.lastGuestRes.w)×\(QemuRunner.lastGuestRes.h)")
            } header: {
                Text("当前")
            }

            Section {
                Toggle("声音", isOn: $sound)
                    .onChange(of: sound) { v in
                        UserDefaults.standard.set(v, forKey: "husk.sound")
                        HuskLog.log("ui", v ? "sound on" : "sound off")
                    }
                if sound {
                    Toggle("附加声音设备", isOn: $soundDevice)
                        .onChange(of: soundDevice) { v in
                            UserDefaults.standard.set(v, forKey: "husk.soundDevice")
                        }
                }
            } header: {
                Text("声音")
            } footer: {
                Text("会添加一个声音设备。它附加时 Android 无法保存——QEMU"
                   + "拒绝保存带有声音设备的机器——所以每次启动都是冷启动。"
                   + "打开或关闭都需要一次冷启动。"
                   + "")
            }
        }
        .huskForm()
        .navigationTitle("性能")
    }
}

// MARK: - Input

struct InputSettings: View {
    @State private var landscapeGuest =
        UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var customRes = UserDefaults.standard.bool(forKey: "husk.customRes")
    @State private var widthText = InputSettings.stored("husk.resWidth", 720)
    @State private var heightText = InputSettings.stored("husk.resHeight", 1280)

    /// Sizes worth offering without typing. Deliberately short: these are the
    /// shapes a phone guest is actually run at, not a catalogue of every panel
    /// ever made.
    private static let presets: [(name: String, w: Int, h: Int)] = [
        ("小屏 — 360 × 800", 360, 800),
        ("高清 — 720 × 1280", 720, 1280),
        ("全高清 — 1080 × 1920", 1080, 1920),
        ("横屏高清 — 1280 × 720", 1280, 720),
        ("平板 — 1280 × 800", 1280, 800),
    ]

    private static func stored(_ key: String, _ fallback: Int) -> String {
        let v = UserDefaults.standard.integer(forKey: key)
        return String(v > 0 ? v : fallback)
    }

    /// What the typed numbers actually come to, or nothing if they are not a
    /// size the guest can be given.
    private var effective: (w: Int, h: Int)? {
        QemuRunner.validResolution(w: Int(widthText) ?? 0, h: Int(heightText) ?? 0)
    }

    var body: some View {
        Form {
            Section {
                Picker("屏幕", selection: $landscapeGuest) {
                    Text("竖屏").tag(false)
                    Text("横屏").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(customRes)
                .onChange(of: landscapeGuest) { v in
                    UserDefaults.standard.set(v, forKey: "husk.landscapeGuest")
                    HuskLog.log("ui", v ? "guest panel will be landscape"
                                        : "guest panel will be portrait")
                }
            } header: {
                Text("屏幕")
            } footer: {
                Text(customRes
                     ? "自定义分辨率会自行决定形状，所以它开启时"
                     + "这里不起作用。输入宽的尺寸即可横屏。"
                     : "Android 运行后无法改变屏幕形状，所以竖屏上的"
                     + "横屏游戏会被信箱式压进一条带里，看起来很小。以横屏创建是"
                     + "它填满屏幕的唯一方式——竖屏应用则反过来被信箱化。需要"
                     + "一次冷启动。"
                     + "")
            }

            Section {
                Toggle("自定义分辨率", isOn: $customRes)
                    .onChange(of: customRes) { v in
                        UserDefaults.standard.set(v, forKey: "husk.customRes")
                        store()
                        HuskLog.log("ui", v ? "custom resolution on: "
                                            + "\(widthText)x\(heightText)"
                                            : "custom resolution off")
                    }

                if customRes {
                    Picker("预设", selection: Binding(
                        get: { presetIndex },
                        set: { i in
                            guard i >= 0, i < Self.presets.count else { return }
                            widthText = String(Self.presets[i].w)
                            heightText = String(Self.presets[i].h)
                            store()
                        })) {
                        ForEach(0..<Self.presets.count, id: \.self) { i in
                            Text(Self.presets[i].name).tag(i)
                        }
                        Text("自定义").tag(-1)
                    }

                    HStack {
                        Text("宽度")
                        Spacer()
                        TextField("720", text: $widthText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: widthText) { _ in store() }
                    }
                    HStack {
                        Text("高度")
                        Spacer()
                        TextField("1280", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: heightText) { _ in store() }
                    }

                    if let size = effective {
                        DetailRow(label: "Android 将获得",
                                  value: "\(size.w) × \(size.h)")
                    } else {
                        Text("两边都必须在 240 到 2560 之间。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                DetailRow(label: "当前运行", value: running)
            } header: {
                Text("分辨率")
            } footer: {
                Text("面板在机器启动时建立，所以更改需要"
                   + "一次冷启动，且下一次保存会替换旧尺寸保存的机器——改回来"
                   + "又要一次。尺寸会取 8 的倍数。越大越慢：每个像素都由"
                   + "模拟的手机绘制。Android 的密度不随面板变化，所以"
                   + "更大的面板显示更多内容而不是更大的内容。"
                   + "")
            }

            Section {
                Text("触控始终开启。键盘和旋转控制在客户机屏幕底部的胶囊里；"
                   + "手柄和鼠标还没有接入。"
                   + "")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("控制")
            }
        }
        .huskForm()
        .navigationTitle("输入")
    }

    /// The panel the guest actually has, which only means anything while there
    /// is a guest: the stored value is last launch's until one starts.
    private var running: String {
        guard QemuRunner.shared.isRunning else { return "未启动" }
        return "\(QemuRunner.lastGuestRes.w) × \(QemuRunner.lastGuestRes.h)"
    }

    /// Which preset the typed numbers are, if any.
    private var presetIndex: Int {
        guard let size = effective else { return -1 }
        return Self.presets.firstIndex { $0.w == size.w && $0.h == size.h } ?? -1
    }

    private func store() {
        UserDefaults.standard.set(Int(widthText) ?? 0, forKey: "husk.resWidth")
        UserDefaults.standard.set(Int(heightText) ?? 0, forKey: "husk.resHeight")
    }
}

// MARK: - Network

struct NetworkSettings: View {
    @State private var keepNetwork =
        UserDefaults.standard.object(forKey: "husk.keepNetwork") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Toggle("保存时保留网络", isOn: $keepNetwork)
                    .onChange(of: keepNetwork) { v in
                        UserDefaults.standard.set(v, forKey: "husk.keepNetwork")
                    }
            } footer: {
                Text(keepNetwork
                     ? "保存会关闭应用但让 Android 的框架继续运行，所以"
                     + "恢复之后网络仍然可用。"
                     : "保存也会停止框架。这会清掉所有 GPU 资源，更稳定——"
                     + "但网络可能要到冷启动才恢复。"
                     + "")
            }

            Section {
                Text("Android 通过 QEMU 自己网络上的虚拟网卡访问互联网。"
                   + "你手机网络上的任何东西都看不到客户机，"
                   + "客户机也看不到它们。"
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("连接方式")
            }
        }
        .huskForm()
        .navigationTitle("网络")
    }
}

// MARK: - JIT and sideloading

struct JITSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var autoStart = Onboarding.autoStart
    @State private var keepAttached = JITBootstrap.keepDebuggerAttached

    private var pairingLabel: String {
        switch jit.pairingSource {
        case .onDevice: return "已在此设备配对"
        case .imported: return "文件已导入"
        case nil: return "未设置"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("方法", selection: $jit.method) {
                    ForEach(JITMethod.allCases) { Text($0.title).tag($0) }
                }
                DetailRow(label: "StikDebug",
                          value: JITBootstrap.isStikDebugInstalled ? "已安装" : "未找到", mono: false)
                DetailRow(label: "TrollStore",
                          value: JITBootstrap.isTrollStoreInstalled ? "已安装" : "未找到", mono: false)
                DetailRow(label: "内置配对", value: pairingLabel, mono: false)
                Button {
                    jit.showSetup = true
                } label: {
                    Label("设置 JIT", systemImage: "wand.and.stars")
                }
            } header: {
                Text("方法")
            } footer: {
                Text(jit.method == .automatic
                     ? jit.automaticDescription + "内置 StikJIT 需要 iOS 26、LocalDevVPN 和一个"
                       + "配对文件，Husk 在 iOS 27 上可以自己制作。"
                     : HuskBuiltInJIT.unavailableReason ?? "内置 StikJIT 需要 LocalDevVPN 和一个配对"
                       + "文件，Husk 在 iOS 27 上可以自己制作。")
            }

            Section {
                DetailRow(label: "调试器",
                          value: JITBootstrap.isDebuggerAttached ? "已附加" : "未附加",
                          mono: false)
                DetailRow(label: "可执行内存",
                          value: JITBootstrap.isLive ? "已授予" : "未申请", mono: false)
                // The two routes, named separately. Either one is enough, and
                // when someone reports "JIT does not work" these two rows are
                // the whole diagnosis.
                DetailRow(label: "陷阱服务",
                          value: JITBootstrap.prewarmed ? "响应中" : "未响应",
                          mono: false)
                // Cached answer only: running the probe from a view body
                // could freeze the app (see JITBootstrap.mapJITWorks).
                DetailRow(label: "MAP_JIT",
                          value: JITBootstrap.deviceEnforcesTXM ? "未使用（TXM）"
                               : JITBootstrap.mapJITResult.map { $0 ? "可执行" : "被拒绝" }
                                 ?? "未测试",
                          mono: false)
                DetailRow(label: "设置后的调试器",
                          value: JITBootstrap.detached ? "已分离" : "已附加",
                          mono: false)
                if let why = JITBootstrap.lastFailure {
                    Text(why).font(.caption).foregroundStyle(.orange)
                }
                if !JITBootstrap.isDebuggerAttached {
                    Button {
                        jit.enable()
                    } label: {
                        Label("用 \(jit.resolvedMethod.title) 启用 JIT", systemImage: "bolt.fill")
                    }
                    .disabled(jit.busy)
                    Button {
                        _ = JITBootstrap.requestTrollStoreAttach()
                    } label: {
                        Label("用 TrollStore 启用 JIT", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("JIT")
            } footer: {
                Text("Husk 需要可写且可执行的内存，在 iOS 上"
                   + "需要附加的调试器。两条路：一个服务陷阱请求的调试器，"
                   + "或一个 MAP_JIT 映射——内核允许任何被调试的进程使用它。"
                   + "两条路任选其一即可——哪条可用取决于设备和 iOS 版本，"
                   + "所以 Husk 两条都测，而不是假设。"
                   + "")
            }

            Section {
                Toggle("启动时自动开启 Android", isOn: $autoStart)
                    .onChange(of: autoStart) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoStart")
                    }
            } footer: {
                Text("JIT 可用时，Husk 一打开就启动客户机。")
            }

            Section {
                Toggle("保持调试器附加", isOn: $keepAttached)
                    .onChange(of: keepAttached) { v in JITBootstrap.keepDebuggerAttached = v }
            } footer: {
                Text("默认关闭。Husk 拿到 JIT 区域后立刻与 StikDebug 分离，"
                   + "因为被 iOS 挂起的调试器下次需要时会拖垮整个应用。"
                   + "打开这个选项只是为了收集 StikDebug 自己的日志。"
                   + "")
            }

            Section {
                Text("APK 从应用库的 + 按钮或文件页安装。"
                   + "Split 集合（基础 APK 加上它的配置分卷）必须一起选；"
                   + "只装基础包会因缺少原生库而失败。"
                   + "")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("侧载")
            }
        }
        .huskForm()
        .navigationTitle("JIT 与侧载")
    }
}

// MARK: - Saved machine

struct SavedMachineSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var autoSave =
        UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @State private var useSnapshot =
        UserDefaults.standard.object(forKey: "husk.downloadSnapshot") as? Bool ?? true
    @State private var askWhichToDelete = false
    @State private var deleteResult: String?

    var body: some View {
        Form {
            Section {
                Toggle("自动保存", isOn: $autoSave)
                    .onChange(of: autoSave) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoSave")
                        HuskLog.log("ui", v ? "automatic saving on" : "automatic saving off")
                    }
                Button {
                    QemuRunner.shared.saveState(reason: "asked from settings")
                } label: {
                    Label(runner.isSavingState ? "正在保存…" : "立即保存",
                          systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(runner.isSavingState)
            } footer: {
                Text("Husk 恢复保存的机器而不是重新启动它，这只需要几秒"
                   + "而不是几分钟。保存时画面会冻结。"
                   + "关掉它之后什么都不会自动保存——包括安装之后。"
                   + "")
            }

            Section {
                Button(role: .destructive) { askWhichToDelete = true } label: {
                    Label("删除保存的机器", systemImage: "trash")
                }
                .disabled(!QemuRunner.shared.hasSnapshot)
                if let deleteResult {
                    Text(deleteResult).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(QemuRunner.shared.hasSnapshot
                     ? "当前保存："
                     + ((QemuRunner.shared.snapshotDisplay ?? "sw").contains("gl")
                        ? "GPU" : "软件渲染") + "。"
                     : "没有保存的机器，Android 将冷启动。")
            }

            Section {
                Toggle("下载预启动快照", isOn: $useSnapshot)
                    .onChange(of: useSnapshot) { v in
                        UserDefaults.standard.set(v, forKey: "husk.downloadSnapshot")
                    }
            } footer: {
                Text("首次下载会多约 2 GB。它是在软件渲染器上捕获的，"
                   + "所以 GPU 模式不会使用它——GPU 会冷启动一次，"
                   + "然后保存自己的快照。")
            }
        }
        .huskForm()
        .navigationTitle("保存的机器")
        .confirmationDialog("删除哪个保存的机器？", isPresented: $askWhichToDelete,
                            titleVisibility: .visible) {
            Button("GPU 机器", role: .destructive) { forget("gl", "GPU") }
            Button("软件渲染机器", role: .destructive) { forget("sw", "软件渲染") }
            Button("取消", role: .cancel) { }
        } message: {
            Text("Android 会冷启动一次，然后保存新的机器。")
        }
    }

    private func forget(_ mode: String, _ name: String) {
        if QemuRunner.shared.forgetSnapshot(mode: mode) {
            deleteResult = "已删除\(name)机器。下次启动将从冷启动开始。"
        } else {
            deleteResult = "没有保存\(name)机器，因此没有删除任何内容。"
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @State private var appIcon = HuskAppIcon.current
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.dark
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        ZStack {
            Theme.backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("外观", selection: $appearance) {
                        ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { v in
                        HuskLog.log("ui", "appearance: \(v.rawValue)")
                    }
                    Text("跟随系统会跟从手机。客户机自己的屏幕"
                       + "无论如何都是暗色——那是另一台手机的画面。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 12)

                SectionHeader(title: "应用图标")
                    .padding(.horizontal, 22).padding(.top, 14)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(HuskAppIcon.allCases) { icon in
                        Button {
                            appIcon = icon
                            HuskAppIcon.apply(icon)
                        } label: {
                            VStack(spacing: 8) {
                                if let art = icon.preview(dark: scheme == .dark) {
                                    Image(uiImage: art)
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14,
                                                                    style: .continuous))
                                }
                                Text(icon.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            // The selected icon is ringed in the accent rather
                            // than filled with it: the artwork is the subject
                            // here, and a tinted panel behind it changes how
                            // the thing you are choosing looks.
                            .background(Theme.surface,
                                        in: RoundedRectangle(cornerRadius: Theme.cardCorner,
                                                             style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner,
                                                      style: .continuous)
                                        .stroke(appIcon == icon ? Theme.accent
                                                                : Theme.hairline,
                                                lineWidth: appIcon == icon ? 2 : 0.5))
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8)

                Text("自动跟随系统外观——浅色、深色与着色。"
                   + "其他选项固定一种外观。iOS 会在更改后显示自己的确认提示，"
                   + "那个提示无法关闭。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28).padding(.vertical, 18)
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var showLogs = false
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false

    var body: some View {
        ZStack {
            Theme.backdrop
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        HuskMark(size: 76)
                        Text("Husk")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("版本 \(Bundle.main.version)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textDim)
                    }
                    .padding(.top, 10)

                    RowGroup {
                        VStack(spacing: 12) {
                            DetailRow(label: "构建", value: Bundle.main.commit)
                            DetailRow(label: "客户机镜像", value: GuestImage.imageVersion)
                            DetailRow(label: "Renderer",
                                      value: runner.displayKind == .gl ? "GPU"
                                           : runner.displayKind == .software ? "CPU"
                                           : "未启动")
                        }
                        .padding(14)
                    }

                    RowGroup {
                        Toggle(isOn: $devInfo) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("开发者信息")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Text("Android 翻译层界面的技术细节："
                                   + "库报告、设备检查和运行日志。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        .padding(14)
                    }

                    Button { showLogs = true } label: {
                        Label("打开控制台", systemImage: "terminal")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Text("Husk 在你 iPhone 上的真实 Android 系统中运行未修改的"
                       + "Android APK。控制台显示 Husk 的实时日志、客户机的串行输出"
                       + "和 QEMU 自己的输出——这里是排查任何问题的"
                       + "三个文件。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) { LogView() }
    }
}

extension Bundle {
    var version: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    var commit: String {
        (infoDictionary?["HuskBuildCommit"] as? String) ?? "?"
    }
}
