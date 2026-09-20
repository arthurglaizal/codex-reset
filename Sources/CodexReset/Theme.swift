import SwiftUI

/// 外观设置：深色 / 浅色（面板右上角切换，存 UserDefaults，默认深色）
enum AppearanceSetting: String {
    case dark
    case light

    static var current: AppearanceSetting {
        AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "dark") ?? .dark
    }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// 调色板：界面配色全部写死在代码里，两套值放一起才好对照着调。
/// 不从 `@Environment(\.colorScheme)` 读，因为面板自己用 `.preferredColorScheme`
/// 设定外观，环境里拿到的还是改之前的值。
struct Palette {
    let isDark: Bool

    init(_ setting: AppearanceSetting) {
        self.isDark = setting == .dark
    }

    /// 主色。深色沿用 Claude 深色界面的珊瑚橙，比纯橙柔和，配暖色底更耐看。
    var accent: Color {
        isDark ? Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
               : Color(red: 0.72, green: 0.33, blue: 0.10)
    }
    /// 实心按钮的底色。亮橙配白字对比不足，所以深色下按钮文字改用深色。
    var buttonFill: Color {
        isDark ? Color(red: 0.851, green: 0.467, blue: 0.341)
               : Color(red: 0.72, green: 0.33, blue: 0.10)
    }
    var buttonText: Color {
        isDark ? Color(red: 0.067, green: 0.067, blue: 0.067) : .white
    }
    /// 面板底色。深色取自 Claude Code 桌面端：接近纯黑的中性灰，不带色偏。
    var windowBackground: Color {
        isDark ? Color(red: 0.067, green: 0.067, blue: 0.067)   // #111111
               : Color(red: 0.95, green: 0.945, blue: 0.93)
    }
    /// 卡片底色（自动继续 / 用量分析）
    var cardBackground: Color {
        isDark ? Color(red: 0.102, green: 0.102, blue: 0.102)   // #1A1A1A
               : .white
    }
    /// 列表里每条对话的底色
    var rowFill: Color {
        isDark ? Color(red: 0.129, green: 0.129, blue: 0.129)   // #212121
               : Color.white.opacity(0.55)
    }
    /// 分隔线、卡片描边
    var hairline: Color {
        isDark ? Color(red: 0.165, green: 0.165, blue: 0.165)   // #2A2A2A
               : Color.black.opacity(0.05)
    }
    /// 可点控件的描边，比 hairline 明显一点
    var controlBorder: Color {
        isDark ? Color(red: 0.200, green: 0.200, blue: 0.200)   // #333333
               : Color.black.opacity(0.16)
    }
    /// 搜索框底色
    var fieldFill: Color {
        isDark ? Color(red: 0.129, green: 0.129, blue: 0.129)   // #212121
               : Color.white.opacity(0.75)
    }
    /// 量表的空槽
    var gaugeTrack: Color {
        isDark ? Color(red: 0.149, green: 0.149, blue: 0.149)   // #262626
               : Color.black.opacity(0.06)
    }
    /// 悬停卡片底色
    var hoverBackground: Color {
        isDark ? Color(red: 0.118, green: 0.118, blue: 0.118)   // #1E1E1E
               : Color(red: 0.99, green: 0.985, blue: 0.975)
    }
    /// 日志区底色
    var wellBackground: Color {
        isDark ? Color(red: 0.039, green: 0.039, blue: 0.039)   // #0A0A0A
               : Color.black.opacity(0.03)
    }

    // MARK: - 额度状态色（深色下整体提亮）

    var ok: Color {
        isDark ? Color(red: 0.42, green: 0.78, blue: 0.56)
               : Color(red: 0.10, green: 0.68, blue: 0.42)
    }
    var warn: Color {
        isDark ? Color(red: 0.90, green: 0.64, blue: 0.30)
               : Color(red: 0.86, green: 0.50, blue: 0.10)
    }
    var danger: Color {
        isDark ? Color(red: 0.90, green: 0.42, blue: 0.38)
               : Color(red: 0.80, green: 0.18, blue: 0.16)
    }
    /// 「已继续」胶囊的文字
    var resumed: Color {
        isDark ? Color(red: 0.48, green: 0.80, blue: 0.60)
               : Color(red: 0.08, green: 0.48, blue: 0.30)
    }
}
