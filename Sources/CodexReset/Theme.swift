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

    /// 主色：浅色下用深橙保证对比，深色下提亮，否则在深背景上糊成一团
    var accent: Color {
        isDark ? Color(red: 0.98, green: 0.62, blue: 0.30)
               : Color(red: 0.72, green: 0.33, blue: 0.10)
    }
    /// 实心按钮的底色。深色下橙色必须够亮才有存在感，
    /// 亮橙配白字对比不足，所以那种情况下按钮文字改用深色。
    var buttonFill: Color {
        isDark ? Color(red: 0.97, green: 0.60, blue: 0.26)
               : Color(red: 0.72, green: 0.33, blue: 0.10)
    }
    var buttonText: Color {
        isDark ? Color(red: 0.13, green: 0.10, blue: 0.07) : .white
    }
    /// 面板底色
    var windowBackground: Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.12)
               : Color(red: 0.95, green: 0.945, blue: 0.93)
    }
    /// 卡片底色（自动继续 / 用量分析）
    var cardBackground: Color {
        isDark ? Color(red: 0.16, green: 0.16, blue: 0.18) : .white
    }
    /// 列表里每条对话的底色
    var rowFill: Color {
        isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.55)
    }
    /// 分隔线、卡片描边
    var hairline: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)
    }
    /// 可点控件的描边，比 hairline 明显一点
    var controlBorder: Color {
        isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)
    }
    /// 搜索框底色
    var fieldFill: Color {
        isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.75)
    }
    /// 量表的空槽
    var gaugeTrack: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    /// 悬停卡片底色
    var hoverBackground: Color {
        isDark ? Color(red: 0.18, green: 0.18, blue: 0.20)
               : Color(red: 0.99, green: 0.985, blue: 0.975)
    }
    /// 日志区底色
    var wellBackground: Color {
        isDark ? Color.black.opacity(0.25) : Color.black.opacity(0.03)
    }

    // MARK: - 额度状态色（深色下整体提亮）

    var ok: Color {
        isDark ? Color(red: 0.26, green: 0.82, blue: 0.54)
               : Color(red: 0.10, green: 0.68, blue: 0.42)
    }
    var warn: Color {
        isDark ? Color(red: 0.98, green: 0.68, blue: 0.26)
               : Color(red: 0.86, green: 0.50, blue: 0.10)
    }
    var danger: Color {
        isDark ? Color(red: 0.96, green: 0.40, blue: 0.37)
               : Color(red: 0.80, green: 0.18, blue: 0.16)
    }
    /// 「已继续」胶囊的文字
    var resumed: Color {
        isDark ? Color(red: 0.42, green: 0.86, blue: 0.62)
               : Color(red: 0.08, green: 0.48, blue: 0.30)
    }
}
