import SwiftUI

/// 独立设置窗口内容（右上角齿轮打开，避免在面板内做遮罩）
struct SettingsPanelView: View {
    @EnvironmentObject var model: AppModel
    /// 是否在概览中显示「全部对话」模块
    @AppStorage("showAllThreads") private var showAllThreads = true
    /// 外观跟随主面板的选择
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.dark.rawValue

    private var appearance: AppearanceSetting {
        AppearanceSetting(rawValue: appearanceRaw) ?? .dark
    }
    private var theme: Palette { Palette(appearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                Text(L("设置", "Settings"))
                    .font(.headline)
            }
            settingsCard
            aboutLine
        }
        .padding(16)
        .frame(width: 340)
        .background(theme.windowBackground)
        // 外观由面板设置决定，不跟随系统，否则写死的配色会出现白字白底
        .preferredColorScheme(appearance.colorScheme)
    }

    /// 关于：注明这是谁的 fork，以及原作者是谁。
    /// 放设置窗口底部而不是主面板标题栏：署名归署名，别盖过产品名。
    private var aboutLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("CodexReset · boyso/codex-reset 的 fork",
                   "CodexReset · a fork of boyso/codex-reset"))
            Text(L("界面与功能改动：Arturo UX", "Interface and features by Arturo UX"))
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 语言选择绑定到 AppModel.language（切换后经 objectWillChange 刷新全界面）
    private var languageBinding: Binding<String> {
        Binding(
            get: { self.model.language },
            set: { self.model.language = $0 }
        )
    }

    /// 白色圆角卡片，装设置项
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 显示全部对话
            HStack(spacing: 10) {
                Text(L("显示全部对话", "Show all chats"))
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: $showAllThreads)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .help(L("在概览中显示全部对话，可勾选任意对话参与自动继续",
                    "Show all chats in Overview so any chat can be selected for auto-continue."))

            Divider()
                .overlay(theme.hairline)

            // 外观
            HStack(spacing: 10) {
                Text(L("外观", "Appearance"))
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $appearanceRaw) {
                    Label(L("浅色", "Light"), systemImage: "sun.max.fill")
                        .tag(AppearanceSetting.light.rawValue)
                    Label(L("深色", "Dark"), systemImage: "moon.fill")
                        .tag(AppearanceSetting.dark.rawValue)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .labelsHidden()
                .frame(width: 205)
            }
            .help(L("面板配色为固定的两套，不跟随系统",
                    "The panel ships two fixed palettes and does not follow the system"))

            Divider()
                .overlay(theme.hairline)

            // 语言
            HStack(spacing: 10) {
                Text(L("语言", "Language"))
                    .font(.subheadline)
                Spacer()
                Picker("", selection: languageBinding) {
                    Text(L("跟随系统", "System")).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .frame(width: 205)
            }

            Divider()
                .overlay(theme.hairline)

            // remote_control
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: Binding(
                    get: { model.remoteControlEnabled },
                    set: { model.setRemoteControl($0) }
                )) {
                    Text("remote_control")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text(L("通过 Codex 本地协议继续对话：重启 Codex 后生效，无需辅助功能授权",
                       "Continues chats via Codex's local protocol: takes effect after Codex restarts, no accessibility permission needed."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }
}
