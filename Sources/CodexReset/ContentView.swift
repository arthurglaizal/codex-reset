import SwiftUI

/// 强调橙：浅色主题下的主色（按钮/恢复时间高亮），保证白字按钮对比与文字可读
private let highlightOrange = Color(red: 0.72, green: 0.33, blue: 0.10)
/// 暂停仍是最后一轮（确实卡住）
private let stuckSymbol = "pause.circle.fill"
/// 失败之后对话已被继续过
private let resumedSymbol = "checkmark.circle"

/// 主面板：单屏展示用量、倒计时、暂停对话与操作（浅色轻拟物主题）
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    /// 右上角「设置」回调（由 MenuBarController 注入：打开独立设置窗口）
    private let onOpenSettings: (() -> Void)?
    /// 概览左栏同一时刻最多展开一个模块，默认「暂停的对话」；nil = 全部收起
    private enum OverviewSection { case paused, continued, all }
    @State private var openSection: OverviewSection? = .paused
    /// 「暂停的对话」列表的搜索词（对话标题 + 项目路径）
    @State private var searchText = ""
    /// 自定义指令输入区展开状态（默认收起）
    @State private var commandExpanded = false
    /// 当前 Tab：0=概览 1=用量历史 2=日志
    @State private var selectedTab = 0
    /// 是否在概览中显示「全部对话」模块
    @AppStorage("showAllThreads") private var showAllThreads = true
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
        .frame(width: 760, height: 800, alignment: .top)
        // 浅色主题：全不透明浅色背景
        .background(Color(red: 0.95, green: 0.945, blue: 0.93))
        .preferredColorScheme(.light)
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
            .frame(width: 260)
        }
    }

    /// 用量分析卡片：大号倒计时 + 原顶部的用量条
    private var analyticsCard: some View {
        softCard {
            Text(L("用量分析", "Analytics"))
                .font(.subheadline)
                .fontWeight(.semibold)
            resetCountdown
            Divider()
                .overlay(Color.black.opacity(0.05))
            usageSection
        }
    }

    /// 距离 5 小时窗口重置的大号倒计时。
    /// 用 TimelineView 每 30 秒自刷新，不依赖用量轮询的节奏。
    private var resetCountdown: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 0) {
                Text(model.countdownText() ?? "…")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(highlightOrange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(L("距离 5 小时窗口重置", "until the 5h window resets"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            if model.accessibilityAuthorized {
                Label(L("辅助功能已授权", "Accessibility granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(L("辅助功能未授权", "Accessibility not granted"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
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

    // MARK: - 状态头

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
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

    private var statusColor: Color {
        guard let primary = model.rateLimits?.rateLimits.primary else { return .gray }
        return primary.usedPercent >= 100 ? .red : (primary.usedPercent >= 80 ? .orange : .green)
    }

    private var statusText: String {
        guard let rl = model.rateLimits else {
            return model.lastError ?? L("连接中…", "Connecting…")
        }
        let used = rl.rateLimits.primary?.usedPercent ?? 0
        if used >= 100 {
            if let cd = model.countdownText() {
                return L("已到用量上限 · \(cd)后恢复", "Usage limit reached · resets in \(cd)")
            }
            return L("已到用量上限", "Usage limit reached")
        }
        return L("用量正常", "Usage OK")
    }

    // MARK: - 用量（固定显示在顶部）

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rl = model.rateLimits {
                windowBar(title: L("5小时用量", "5h usage"), window: rl.rateLimits.primary, color: .orange)
                windowBar(title: L("1周用量", "1 week"), window: rl.rateLimits.secondary, color: .blue)
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

    private func windowBar(title: String, window: RateLimitWindow?, color: Color) -> some View {
        let percent = window?.usedPercent ?? 0
        return HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 64, alignment: .leading)
            ProgressView(value: Double(percent), total: 100)
                .tint(percent >= 100 ? .red : color)
            Text("\(percent)%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
            Text(resetText(window))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
        }
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

    /// 确实卡住的对话（列表只展示这些）
    private var stuckThreads: [PausedThread] {
        model.pausedThreads.filter(\.isStillPaused)
    }

    /// 暂停之后已被继续过的对话（折叠在底部，仅供核对）
    private var continuedThreads: [PausedThread] {
        model.pausedThreads.filter { !$0.isStillPaused }
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

    /// 搜索框：取代原先的状态图例（列表已只剩卡住的对话，图例无意义）
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
                .fill(Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    /// 「全选」主复选框：空 / 半选 / 全选，与下方每行的复选框同列
    @ViewBuilder
    private var selectAllCheckbox: some View {
        let ids = Set(stuckThreads.map { $0.threadId })
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
                  : L("全选卡住的对话（\(selected.count)/\(ids.count) 已选）",
                      "Select all stuck chats (\(selected.count)/\(ids.count) selected)"))
            .accessibilityLabel(L("全选卡住的对话", "Select all stuck chats"))
        }
    }

    /// 手风琴标题行：点击展开该模块，再次点击收起（同一时刻最多展开一个）
    private func accordionHeader(title: String, section: OverviewSection, isOpen: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                openSection = isOpen ? nil : section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOpen ? Color.primary : Color.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? L("收起", "Collapse") : L("展开", "Expand"))
    }

    private var pausedSection: some View {
        let isOpen = openSection == .paused
        let threads = matchingSearch(stuckThreads)
        return VStack(alignment: .leading, spacing: 8) {
            accordionHeader(title: L("暂停的对话（\(stuckThreads.count)）",
                                     "Paused chats (\(stuckThreads.count))"),
                            section: .paused, isOpen: isOpen)
            if isOpen {
                HStack(spacing: 8) {
                    selectAllCheckbox
                    searchField
                }
                if stuckThreads.isEmpty {
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
                Text(L("这些对话在触发用量上限后又被继续过，无需再次继续",
                       "These chats were continued after hitting the limit. They don't need resuming."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if continuedThreads.isEmpty {
                    Text(L("暂无", "None"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    threadList(continuedThreads, showRecovery: true)
                }
            }
        }
        .frame(maxHeight: isOpen ? .infinity : nil, alignment: .top)
    }

    /// 按项目分组的滚动列表（暂停 / 已继续 / 全部对话共用）
    private func threadList(_ threads: [PausedThread], showRecovery: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(groupByProject(threads).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(group.threads, id: \.threadId) { thread in
                            threadRow(thread, showRecovery: showRecovery)
                        }
                    }
                }
            }
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
                threadList(model.allThreads, showRecovery: false)
            }
        }
        .frame(maxHeight: isOpen ? .infinity : nil, alignment: .top)
    }

    /// 模式 `.all` 下勾选没有意义，直接去掉复选框只留内容
    @ViewBuilder
    private func threadRow(_ paused: PausedThread, showRecovery: Bool) -> some View {
        if model.autoMode == .all {
            threadRowLabel(paused, showRecovery: showRecovery)
                .padding(.leading, 3)
        } else {
            Toggle(isOn: Binding(
                get: { model.selectedThreadIds.contains(paused.threadId) },
                set: { on in
                    if on {
                        model.selectedThreadIds.insert(paused.threadId)
                    } else {
                        model.selectedThreadIds.remove(paused.threadId)
                    }
                }
            )) {
                threadRowLabel(paused, showRecovery: showRecovery)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func threadRowLabel(_ paused: PausedThread, showRecovery: Bool) -> some View {
        HStack(spacing: 6) {
            if showRecovery {
                let label = paused.isStillPaused
                    ? L("暂停仍是最后一轮，对话确实卡住",
                        "The pause is the last message, so this chat is really stuck")
                    : L("失败之后对话已被继续过，无需再次继续",
                        "The chat was continued after the pause, so it needs nothing")
                Image(systemName: paused.isStillPaused ? stuckSymbol : resumedSymbol)
                    .font(.caption)
                    .foregroundStyle(paused.isStillPaused ? highlightOrange : Color.secondary)
                    .help(label)
                    .accessibilityLabel(label)
            } else {
                Text("–")
                    .foregroundStyle(.secondary)
            }
            Text(paused.title)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer(minLength: 4)
            if showRecovery {
                // 右列与指示图标同色：卡住显示恢复时间，已继续显示「已继续」
                if paused.isStillPaused, let hint = paused.recoveryHint {
                    Text(cleanHint(hint))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(highlightOrange)
                } else if !paused.isStillPaused {
                    Text(L("已继续", "Resumed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // 已继续过的整行淡化，与卡住的拉开对比
        .opacity(showRecovery && !paused.isStillPaused ? 0.55 : 1)
        .contentShape(Rectangle())
        // 双击在 Codex 中打开该对话
        .onTapGesture(count: 2) {
            model.openInCodex(threadId: paused.threadId)
        }
        .help(L("双击在 Codex 中打开该对话", "Double-click to open in Codex"))
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
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white, Color.black.opacity(0.06)],
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

    /// 作用范围：勾上=全部卡住的对话，不勾=只继续已勾选的
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
            return L("用量窗口重置后，自动继续所有卡住的对话，无需勾选",
                     "When the usage window resets, every stuck chat is continued. No ticking needed.")
        }
    }

    private var controlsSection: some View {
        softCard {
            // 总开关 + 作用范围复选框（三种模式互斥，但拆成「开关」与「范围」更易读）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Label(L("用量恢复后自动继续", "Auto-continue after usage resets"),
                          systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Toggle("", isOn: autoEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Toggle(isOn: autoScopeBinding) {
                    Text(L("包含全部卡住的对话，无需勾选",
                           "Every stuck chat, no ticking needed"))
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
                .overlay(Color.black.opacity(0.05))

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
                            .tint(.white)
                        Text(L("继续中…", "Continuing…"))
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text(L("立即继续", "Continue Now"))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.86, green: 0.45, blue: 0.15), highlightOrange],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
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
                .background(Color.black.opacity(0.03))
                .cornerRadius(6)
            }
        }
    }
}
