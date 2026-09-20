import SwiftUI

/// 柱子本体的高度，刻度和分隔线都按它对齐
private let gaugeBarHeight: CGFloat = 128
/// 柱子上方（标题 + 百分比）占用的高度
private let gaugeHeaderHeight: CGFloat = 47
/// 暂停仍是最后一轮，对话仍处于暂停。
/// 胶囊里空间很紧，用不带外圈的图形，同样字号下符号本身更大。
private let pausedSymbol = "pause.fill"
/// 失败之后对话已被继续过
private let resumedSymbol = "checkmark"

/// 主面板：单屏展示用量、倒计时、暂停对话与操作（浅色轻拟物主题）
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    /// 右上角「设置」回调（由 MenuBarController 注入：打开独立设置窗口）
    private let onOpenSettings: (() -> Void)?
    /// 概览左栏同一时刻最多展开一个模块，默认「暂停的对话」；nil = 全部收起
    private enum OverviewSection { case paused, continued, ignored, all }
    @State private var openSection: OverviewSection? = .paused
    /// 「暂停的对话」列表的搜索词（对话标题 + 项目路径）
    @State private var searchText = ""
    /// 悬停提示当前显示的对话；hoverCandidate 用于延时，避免扫过列表时乱弹
    @State private var hoveredThreadId: String?
    @State private var hoverCandidate: String?
    /// 自定义指令输入区展开状态：默认展开，并记住用户的选择
    @AppStorage("commandExpanded") private var commandExpanded = true
    /// 当前 Tab：0=概览 1=用量历史 2=日志
    @State private var selectedTab = 0
    /// 是否在概览中显示「全部对话」模块
    @AppStorage("showAllThreads") private var showAllThreads = true
    /// 外观：深色 / 浅色，默认深色
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.dark.rawValue

    private var appearance: AppearanceSetting {
        AppearanceSetting(rawValue: appearanceRaw) ?? .dark
    }
    private var theme: Palette { Palette(appearance) }
    /// 自动继续的作用范围（关闭总开关后仍保留，重新打开时沿用）
    @AppStorage("autoScopeAll") private var autoScopeAll = false

    init(onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            // Tab 内容占满剩余高度：顶部对齐，概览内「立即继续」卡片置底
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 880, height: 800, alignment: .top)
        // 浅色主题：全不透明浅色背景
        .background(theme.windowBackground)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            model.refreshAllThreads()
            // 保存的模式是权威来源，启动时把范围开关对齐到它
            if model.autoMode == .all { autoScopeAll = true }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: overviewTab
        case 1: historyTab
        default: logTab
        }
    }

    /// 概览：左栏手风琴（暂停/全部对话），右栏自动继续 + 用量分析
    private var overviewTab: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                pausedSection
                Divider()
                ignoredSection
                Divider()
                continuedSection
                if showAllThreads {
                    Divider()
                    allSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                controlsSection
                analyticsCard
                Spacer(minLength: 0)
            }
            .frame(width: 290)
        }
    }

    /// 用量分析卡片：大号倒计时 + 原顶部的用量条
    private var analyticsCard: some View {
        softCard {
            Text(L("剩余额度", "Quota left"))
                .font(.subheadline)
                .fontWeight(.semibold)
            // 每 30 秒重绘，柱子下面的倒计时才会走
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                usageSection
            }
        }
    }

    /// 距离 5 小时窗口重置的大号倒计时。
    /// 用 TimelineView 每 30 秒自刷新，不依赖用量轮询的节奏。
    /// 倒计时有两种含义：额度用光时它是「还要等多久才能动」，
    /// 额度还有时它只是当前窗口的剩余时间，所以配色和文案都跟着变。
    private var resetCountdown: some View {
        let blocked = (model.rateLimits?.rateLimits.primary?.usedPercent ?? 0) >= 100
        let tint = blocked ? theme.accent : Color.secondary
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: blocked ? "hourglass" : "clock")
                .font(.system(size: 16))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.countdownText() ?? "…")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(blocked
                     ? L("之后对话才能继续", "until your chats can resume")
                     : L("当前 5 小时窗口剩余时间", "left in the current 5h window"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// 周额度见底时，5 小时窗口重置也解不了锁，必须说清楚
    @ViewBuilder
    private func weeklyBlockWarning(_ weekly: RateLimitWindow?) -> some View {
        let remaining = 100 - (weekly?.usedPercent ?? 0)
        if remaining < 10 {
            Label(L("周额度只剩 \(remaining)%，5 小时窗口重置也无法继续",
                    "Only \(remaining)% weekly quota left, so the 5h reset will not unblock anything."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(quotaColor(remaining))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 用量历史：5 小时窗口时间线
    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("5小时窗口时间线", "5-hour window timeline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L("共 \(model.resetHistory.count) 个窗口", "\(model.resetHistory.count) windows"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if model.resetHistory.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("暂无记录", "No records yet"))
                    Text(L("App 启动后每 30 秒采样一次，用量窗口重置时自动记录一个点",
                           "Sampled every 30s after launch; a point is recorded automatically when a usage window resets."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.resetHistory.enumerated()), id: \.element.id) { idx, evt in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(idx == 0 ? Color.blue : Color.gray.opacity(0.6))
                                        .frame(width: 8, height: 8)
                                    if idx < model.resetHistory.count - 1 {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.25))
                                            .frame(width: 2, height: 30)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(L("\(timeText(evt.windowStart)) 窗口开始", "\(timeText(evt.windowStart)) window start"))
                                            .font(.subheadline)
                                        if idx == 0 {
                                            Text(L("当前", "Now"))
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    Text(L("下次重置：\(timeText(evt.nextResetAt)) · 记录时用量 \(Int(evt.usedPercent))%",
                                           "Next reset: \(timeText(evt.nextResetAt)) · usage at record: \(Int(evt.usedPercent))%"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    /// 底部：辅助功能状态（左）+ 退出（右）
    private var footer: some View {
        HStack(spacing: 8) {
            Text(L("配置：", "Configuration:"))
                .foregroundStyle(.secondary)

            configItem(ok: model.rateLimits != nil && model.connectionMode != "none",
                       text: statusText,
                       help: L("与 Codex 的连接状态",
                               "Connection to Codex"))

            Text("·").foregroundStyle(.tertiary)

            configItem(ok: model.accessibilityAuthorized,
                       text: model.accessibilityAuthorized
                             ? L("辅助功能已授权", "Accessibility granted")
                             : L("辅助功能未授权（可选）", "Accessibility not granted (optional)"),
                       help: L("可选项：本地协议不可用时，用模拟输入在 Codex 里发送指令",
                               "Optional: types the command into Codex when the local protocol is unavailable"))

            if !model.accessibilityAuthorized {
                Button(L("授权", "Grant")) {
                    model.openAccessibilitySettings()
                }
                .font(.caption)
            }
            Spacer()
            Button(L("退出", "Quit")) {
                model.quit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
    }

    /// 「配置」行的一项：就绪=绿点，未就绪=灰叉。
    /// 两项都不是错误，辅助功能本来就是可选的，所以未就绪也不用警告色。
    private func configItem(ok: Bool, text: String, help: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "circle.fill" : "xmark")
                .font(.system(size: ok ? 7 : 9, weight: ok ? .regular : .semibold))
                .foregroundStyle(ok ? theme.ok : Color.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .help(help)
    }

    // MARK: - 状态头

    private var header: some View {
        HStack(spacing: 8) {
            Text("CodexReset")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            // Tab 切换移到标题栏，省下一整行高度给列表
            Picker("", selection: $selectedTab) {
                Text(L("概览", "Overview")).tag(0)
                Text(L("用量历史", "Usage History")).tag(1)
                Text(L("日志", "Log")).tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 330)

            Spacer()
                .frame(width: 4)
            // 右上角：设置（打开独立设置窗口）
            Button {
                onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("设置", "Settings"))
        }
    }

    private var statusText: String {
        if model.connectionMode == "none" {
            return model.lastError ?? L("未连接到 Codex", "Not connected to Codex")
        }
        guard let rl = model.rateLimits else {
            return L("正在连接 Codex…", "Connecting to Codex…")
        }
        if (rl.rateLimits.primary?.usedPercent ?? 0) >= 100 {
            if let cd = model.countdownText() {
                return L("已到用量上限，\(cd)后恢复", "Usage limit reached, resets in \(cd)")
            }
            return L("已到用量上限", "Usage limit reached")
        }
        return model.connectionMode == "desktop-control"
            ? L("已连接 Codex（官方协议）", "Connected to Codex (official protocol)")
            : L("已连接 Codex（独立 app-server）", "Connected to Codex (standalone app-server)")
    }

    // MARK: - 用量（固定显示在顶部）

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rl = model.rateLimits {
                HStack(alignment: .top, spacing: 10) {
                    gaugeScale
                    quotaGauge(title: L("5小时", "5h"),
                               window: rl.rateLimits.primary, primary: true)
                    Divider()
                        .frame(height: gaugeBarHeight)
                        .padding(.top, gaugeHeaderHeight)
                    quotaGauge(title: L("1周", "1 week"),
                               window: rl.rateLimits.secondary, primary: false)
                }
                weeklyBlockWarning(rl.rateLimits.secondary)
                HStack {
                    Text(L("计划：", "Plan: ") + (rl.rateLimits.planType ?? "?"))
                    Spacer()
                    if let balance = rl.rateLimits.credits?.balance {
                        Text(L("点数余额：", "Credit balance: ") + balance)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L("读取用量中…", "Reading usage…")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 竖向量表，显示**剩余**额度（与 Codex 侧边栏口径一致）：
    /// 柱子满=额度充足，见底=快用光。
    private func quotaGauge(title: String, window: RateLimitWindow?, primary: Bool) -> some View {
        let remaining = max(0, min(100, 100 - (window?.usedPercent ?? 0)))
        let tint = quotaColor(remaining)
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                if primary {
                    // 自动继续跟的是这个窗口
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text("\(remaining)%")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.gaugeTrack)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
                    .frame(height: max(4, gaugeBarHeight * CGFloat(remaining) / 100))
            }
            .frame(width: 54, height: gaugeBarHeight)
            Text(resetText(window))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Text(remainingText(window))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .help(L("剩余额度 \(remaining)%，\(resetText(window)) 重置",
                "\(remaining)% left, resets at \(resetText(window))"))
    }

    /// 柱子两端的刻度，只对齐柱子本身的高度
    private var gaugeScale: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("100%")
            Spacer(minLength: 0)
            Text("0%")
        }
        .font(.system(size: 9))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .frame(height: gaugeBarHeight)
        .padding(.top, gaugeHeaderHeight)
    }

    /// 剩余额度配色：充足=绿，低于 30%=橙，低于 10%=红
    private func quotaColor(_ remaining: Int) -> Color {
        if remaining < 10 { return theme.danger }
        if remaining < 30 { return theme.warn }
        return theme.ok
    }

    /// 距离该窗口重置还有多久；超过一天时带上天数（周窗口用得上）
    private func remainingText(_ window: RateLimitWindow?) -> String {
        guard let resetsAt = window?.resetsAt else { return "…" }
        let remain = Int(Double(resetsAt) - Date().timeIntervalSince1970)
        guard remain > 0 else { return L("已恢复", "resets now") }
        let days = remain / 86400
        let hours = (remain % 86400) / 3600
        let minutes = (remain % 3600) / 60
        if days > 0 { return L("\(days)天 \(hours)小时", "\(days)d \(hours)h") }
        if hours > 0 { return L("\(hours)小时 \(minutes)分", "\(hours)h \(minutes)m") }
        return L("\(minutes)分钟", "\(minutes)m")
    }

    private func resetText(_ window: RateLimitWindow?) -> String {
        guard let resetsAt = window?.resetsAt else { return "--" }
        let date = Date(timeIntervalSince1970: Double(resetsAt))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    // MARK: - 暂停对话（按项目分组）

    /// 按项目路径分组，保留「最新在前」的原始顺序
    private func groupByProject(_ threads: [PausedThread]) -> [(name: String, threads: [PausedThread])] {
        var order: [(name: String, threads: [PausedThread])] = []
        var seen = Set<String>()
        for paused in threads {
            let key = paused.cwd
            if !seen.contains(key) {
                seen.insert(key)
                let name = key.isEmpty ? L("未分类", "Uncategorized") : (key as NSString).lastPathComponent
                order.append((name, threads.filter { $0.cwd == key }))
            }
        }
        return order
    }

    /// 仍处于暂停的对话（列表只展示这些）
    private var pausedThreads: [PausedThread] {
        model.pausedThreads.filter { $0.isStillPaused && !isIgnored($0) }
    }

    /// 暂停之后已被继续过的对话（折叠在底部，仅供核对）
    private var continuedThreads: [PausedThread] {
        model.pausedThreads.filter { !$0.isStillPaused && !isIgnored($0) }
    }

    /// 被忽略的对话，可能来自任意一个列表，按 threadId 去重
    private var ignoredThreads: [PausedThread] {
        var seen = Set<String>()
        return (model.pausedThreads + model.allThreads)
            .filter { isIgnored($0) && seen.insert($0.threadId).inserted }
    }

    private func isIgnored(_ thread: PausedThread) -> Bool {
        model.ignoredThreadIds.contains(thread.threadId)
    }

    /// 按对话标题或项目路径过滤
    private func matchingSearch(_ threads: [PausedThread]) -> [PausedThread] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return threads }
        return threads.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.cwd.localizedCaseInsensitiveContains(query)
        }
    }

    /// 搜索框：取代原先的状态图例（列表已只剩暂停中的对话，图例无意义）
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(L("搜索对话或项目", "Search chats or projects"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("清空搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }

    /// 「全选」主复选框：空 / 半选 / 全选，与下方每行的复选框同列
    @ViewBuilder
    private func selectAllCheckbox(for threads: [PausedThread]) -> some View {
        let ids = Set(threads.map { $0.threadId })
        if !ids.isEmpty, model.autoMode != .all {
            let selected = ids.intersection(model.selectedThreadIds)
            let isAll = selected.count == ids.count
            Button {
                if isAll {
                    model.selectedThreadIds.subtract(ids)
                } else {
                    model.selectedThreadIds.formUnion(ids)
                }
            } label: {
                Image(systemName: isAll ? "checkmark.square.fill"
                                : (selected.isEmpty ? "square" : "minus.square.fill"))
                    .font(.system(size: 16))
                    .foregroundStyle(selected.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(isAll
                  ? L("取消全选", "Clear selection")
                  : L("全选（\(selected.count)/\(ids.count) 已选）",
                      "Select all (\(selected.count)/\(ids.count) selected)"))
            .accessibilityLabel(L("全选本组对话", "Select every chat in this group"))
        }
    }

    /// 手风琴标题行：点击展开该模块，再次点击收起（同一时刻最多展开一个）
    private func accordionHeader(title: String, section: OverviewSection, isOpen: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                openSection = isOpen ? nil : section
                // le filtre appartient a la section qu'on quitte
                searchText = ""
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOpen ? Color.primary : Color.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? L("收起", "Collapse") : L("展开", "Expand"))
    }

    /// Chaque module s'ouvre sur une phrase qui dit ce qu'il contient,
    /// suivie du rappel du double-clic (sinon personne ne le decouvre).
    private func sectionHint(_ text: String) -> some View {
        Text(text + " " + L("双击任意对话可在 Codex 中打开。",
                            "Double-click a chat to open it in Codex."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pausedSection: some View {
        let isOpen = openSection == .paused
        let threads = matchingSearch(pausedThreads)
        return VStack(alignment: .leading, spacing: 8) {
            accordionHeader(title: L("暂停的对话（\(pausedThreads.count)）",
                                     "Paused chats (\(pausedThreads.count))"),
                            section: .paused, isOpen: isOpen)
            if isOpen {
                sectionHint(L("这些对话在用量上限处停下，之后没有被继续过。",
                              "These chats stopped on a usage limit and were never continued since."))
                HStack(spacing: 8) {
                    selectAllCheckbox(for: pausedThreads)
                    searchField
                }
                if pausedThreads.isEmpty {
                    Text(L("未找到因用量暂停的对话", "No usage-paused chats found"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if threads.isEmpty {
                    Text(L("没有匹配的对话", "No chat matches your search"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    threadList(threads, showRecovery: true)
                }
            }
        }
        .frame(maxHeight: isOpen ? .infinity : nil, alignment: .top)
    }

    /// 暂停之后已被继续过的对话：默认折叠，仅用于核对检测是否准确
    private var continuedSection: some View {
        let isOpen = openSection == .continued
        return VStack(alignment: .leading, spacing: 8) {
            accordionHeader(title: L("已继续的对话（\(continuedThreads.count)）",
                                     "Already continued (\(continuedThreads.count))"),
                            section: .continued, isOpen: isOpen)
            if isOpen {
                sectionHint(L("这些对话在触发用量上限后又被继续过，无需再次继续。",
                              "These chats were continued after hitting the limit. They don't need resuming."))
                HStack(spacing: 8) {
                    selectAllCheckbox(for: continuedThreads)
                    searchField
                }
                let threads = matchingSearch(continuedThreads)
                if continuedThreads.isEmpty {
                    Text(L("暂无", "None"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if threads.isEmpty {
                    Text(L("没有匹配的对话", "No chat matches your search"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    threadList(threads, showRecovery: true)
                }
            }
        }
        .frame(maxHeight: isOpen ? .infinity : nil, alignment: .top)
    }

    /// 被忽略的对话：默认折叠，可随时恢复
    private var ignoredSection: some View {
        let isOpen = openSection == .ignored
        let threads = matchingSearch(ignoredThreads)
        return VStack(alignment: .leading, spacing: 8) {
            accordionHeader(title: L("已忽略的对话（\(ignoredThreads.count)）",
                                     "Ignored (\(ignoredThreads.count))"),
                            section: .ignored, isOpen: isOpen)
            if isOpen {
                sectionHint(L("这些对话不会出现在其他列表，也永远不会被自动继续。",
                              "These chats stay out of the other lists and are never continued automatically."))
                searchField
                if ignoredThreads.isEmpty {
                    Text(L("暂无", "None"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if threads.isEmpty {
                    Text(L("没有匹配的对话", "No chat matches your search"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    threadList(threads, showRecovery: true)
                }
            }
        }
        .frame(maxHeight: isOpen ? .infinity : nil, alignment: .top)
    }

    /// 按项目分组的滚动列表（暂停 / 已继续 / 忽略 / 全部对话共用）
    private func threadList(_ threads: [PausedThread], showRecovery: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(groupByProject(threads).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.threads, id: \.threadId) { thread in
                            threadRow(thread, showRecovery: showRecovery)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 全部对话（默认收起，可勾选任意对话参与自动继续）

    private var allSection: some View {
        let isOpen = openSection == .all
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                accordionHeader(title: L("全部对话（\(model.allThreads.count)）",
                                         "All chats (\(model.allThreads.count))"),
                                section: .all, isOpen: isOpen)
                if isOpen, !model.allThreads.isEmpty, model.autoMode != .all {
                    let allIds = Set(model.allThreads.map { $0.threadId })
                    Button(allIds.isSubset(of: model.selectedThreadIds)
                           ? L("取消全选", "Clear all")
                           : L("全选", "Select all")) {
                        if allIds.isSubset(of: model.selectedThreadIds) {
                            model.selectedThreadIds.subtract(allIds)
                        } else {
                            model.selectedThreadIds.formUnion(allIds)
                        }
                    }
                    .font(.caption)
                }
            }

            if isOpen {
                sectionHint(L("Codex 里的全部对话，勾选后同样会参与自动继续。",
                              "Every chat Codex knows about. Tick any of them to have it continued too."))
                searchField
                let threads = matchingSearch(model.allThreads.filter { !isIgnored($0) })
                if threads.isEmpty {
                    Text(L("没有匹配的对话", "No chat matches your search"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    threadList(threads, showRecovery: false)
                }
            }
        }
        .frame(maxHeight: isOpen ? .infinity : nil, alignment: .top)
    }

    /// 整行是一张卡片，复选框放在卡片内部，卡片才能和项目名左对齐。
    /// 模式 `.all` 下勾选没有意义，直接不画复选框。
    private func threadRow(_ paused: PausedThread, showRecovery: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if model.autoMode != .all {
                Toggle("", isOn: Binding(
                    get: { model.selectedThreadIds.contains(paused.threadId) },
                    set: { on in
                        if on {
                            model.selectedThreadIds.insert(paused.threadId)
                        } else {
                            model.selectedThreadIds.remove(paused.threadId)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            threadRowLabel(paused, showRecovery: showRecovery)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        // 双击在 Codex 中打开该对话
        .onTapGesture(count: 2) {
            model.openInCodex(threadId: paused.threadId)
        }
        .onHover { inside in
            let id = paused.threadId
            if inside {
                hoverCandidate = id
                // 停留半秒才弹，快速滑过列表时不会闪一片
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if hoverCandidate == id { hoveredThreadId = id }
                }
            } else {
                if hoverCandidate == id { hoverCandidate = nil }
                if hoveredThreadId == id { hoveredThreadId = nil }
            }
        }
        .popover(isPresented: Binding(
            get: { hoveredThreadId == paused.threadId },
            set: { shown in
                if !shown, hoveredThreadId == paused.threadId { hoveredThreadId = nil }
            }
        ), arrowEdge: .bottom) {
            hoverCard(paused)
        }
    }

    /// 悬停卡片：系统 tooltip 只能给一行灰字，这里要放操作提示 + 完整消息
    private func hoverCard(_ paused: PausedThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("双击在 Codex 中打开该对话", "Double-click to open in Codex"),
                  systemImage: "arrow.up.forward.app")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.accent)

            Divider()
                .overlay(theme.hairline)

            Text(L("对话标题", "Chat title"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Le titre est ellipse dans la liste : ici on le donne en entier
            ScrollView {
                Text(paused.title)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
        }
        .padding(14)
        .frame(width: 400)
        .background(theme.hoverBackground)
    }

    private func threadRowLabel(_ paused: PausedThread, showRecovery: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(paused.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            turnCountTag(paused.turnCount)
            if showRecovery, !isIgnored(paused) {
                statusChip(paused)
            }
            ignoreButton(paused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 忽略 / 恢复按钮。
    /// 刻意用不对称的一对：减号表示「从列表里拿走」，加号表示「放回去」，
    /// 对称的开关无法分辨图标描述的是现状还是动作。
    @ViewBuilder
    private func ignoreButton(_ paused: PausedThread) -> some View {
        if isIgnored(paused) {
            inlineButton(symbol: "plus.circle",
                         title: L("恢复", "Restore"),
                         help: L("把这条对话放回原来的列表", "Put this chat back in its list")) {
                model.setIgnored(false, threadId: paused.threadId)
            }
        } else {
            inlineButton(symbol: "minus.circle",
                         title: L("忽略", "Ignore"),
                         help: L("忽略这条对话：不再出现在列表，也不会被自动继续",
                                 "Ignore this chat: it leaves the lists and is never continued automatically")) {
                model.setIgnored(true, threadId: paused.threadId)
            }
        }
    }

    /// 行内小按钮：图标 + 文字的细边胶囊，和状态胶囊同一族，但留空心以示可点
    private func inlineButton(symbol: String, title: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(theme.controlBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }

    /// 状态胶囊：图标 + 文字同色，贴在行尾。
    /// 暂停的显示恢复时间，已继续的显示「已继续」，两种共用一个形状。
    @ViewBuilder
    private func statusChip(_ paused: PausedThread) -> some View {
        if paused.isStillPaused {
            chip(symbol: pausedSymbol,
                 text: paused.recoveryHint.map(cleanHint) ?? L("暂停中", "Paused"),
                 tint: theme.accent,
                 help: L("暂停仍是最后一轮，对话仍处于暂停",
                         "The pause is the last message, so this chat is still paused"))
        } else {
            chip(symbol: resumedSymbol,
                 text: L("已继续", "Resumed"),
                 tint: theme.resumed,
                 help: L("失败之后对话已被继续过，无需再次继续",
                         "The chat was continued after the pause, so it needs nothing"))
        }
    }

    private func chip(symbol: String, text: String, tint: Color, help: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        // 不带外圈的图形会顶到胶囊边上，靠内边距还回那几像素
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
        .help(help)
        .accessibilityLabel(help)
    }

    /// 轮次计数：气泡图标 + 数字，用来区分「聊了很久」和「刚起头就停了」
    @ViewBuilder
    private func turnCountTag(_ count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 9))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .help(L("该对话共 \(count) 轮", "\(count) turns in this chat"))
        }
    }

    /// 去掉恢复提示末尾的句点，如 "7:27 PM." -> "7:27 PM"
    private func cleanHint(_ hint: String) -> String {
        hint.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    // MARK: - 控制（自动继续模块，轻拟物主卡片：纯白、不使用阴影）

    /// 轻拟物卡片：纯白背景 + 细描边（无渐变、无阴影）
    private func softCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [theme.cardBackground, theme.hairline],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }

    /// 总开关：关闭时记住上次的作用范围，重新打开后恢复
    private var autoEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.autoMode != .off },
            set: { on in model.autoMode = on ? (autoScopeAll ? .all : .selected) : .off }
        )
    }

    /// 作用范围：勾上=全部暂停的对话，不勾=只继续已勾选的
    private var autoScopeBinding: Binding<Bool> {
        Binding(
            get: { autoScopeAll },
            set: { all in
                autoScopeAll = all
                if model.autoMode != .off {
                    model.autoMode = all ? .all : .selected
                }
            }
        )
    }

    /// 当前设置的一句话说明
    private var autoModeExplanation: String {
        switch model.autoMode {
        case .off:
            return L("用量恢复后不做任何事，只能手动点「立即继续」",
                     "Nothing happens when usage resets. Only the Continue Now button acts.")
        case .selected:
            return L("用量窗口重置后，自动把指令发送到已勾选的对话",
                     "When the usage window resets, the command is sent to the chats you ticked.")
        case .all:
            return L("用量窗口重置后，自动继续所有暂停的对话，无需勾选",
                     "When the usage window resets, every paused chat is continued. No ticking needed.")
        }
    }

    private var controlsSection: some View {
        softCard {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                resetCountdown
            }
            Divider()
                .overlay(theme.hairline)

            // 总开关 + 作用范围复选框（三种模式互斥，但拆成「开关」与「范围」更易读）
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    // Label tronque le texte dans un HStack contraint : on le compose a la main
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 19))
                    Text(L("用量恢复后自动继续（5 小时窗口）",
                           "Auto-continue after usage resets (5h reset)"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Toggle("", isOn: autoEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Toggle(isOn: autoScopeBinding) {
                    Text(L("包含全部暂停的对话，无需勾选",
                           "Every paused chat, no ticking needed"))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .disabled(model.autoMode == .off)
                Text(autoModeExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(theme.hairline)

            // 指令输入（默认收起，点标题展开）
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { commandExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: commandExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(L("指令", "Command"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !commandExpanded, !model.continueCommand.isEmpty {
                            Text(model.continueCommand)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .frame(maxWidth: 140, alignment: .trailing)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("展开自定义指令", "Show custom command"))

                if commandExpanded {
                    TextField(L("继续", "Continue"), text: $model.continueCommand)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            }

            // 立即继续（大按钮）
            Button {
                Task { await model.manualContinue() }
            } label: {
                HStack(spacing: 6) {
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.buttonText)
                        Text(L("继续中…", "Continuing…"))
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text(L("立即继续", "Continue Now"))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.buttonFill)
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
            .opacity(model.isWorking ? 0.75 : 1)
        }
    }

    // MARK: - 日志 Tab（文案按当前语言显示，切换语言后旧日志也会跟随切换）

    private var logTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("运行日志", "Activity log"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L("共 \(model.logLines.count) 条", "\(model.logLines.count) entries"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if model.logLines.isEmpty {
                Text(L("暂无日志", "No logs yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.logLines.enumerated().reversed()), id: \.offset) { _, entry in
                            Text("[\(entry.time)] \(entry.display)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 400)
                .frame(maxWidth: .infinity)
                .background(theme.wellBackground)
                .cornerRadius(6)
            }
        }
    }
}
