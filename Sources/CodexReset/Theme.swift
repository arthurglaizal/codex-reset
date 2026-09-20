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
        isDark ? Color(red: 0.122, green: 0.118, blue: 0.114) : .white
    }
    /// 面板底色。深色取暖灰而非中性灰，纯灰在暖色强调色旁边会发蓝。
    var windowBackground: Color {
        isDark ? Color(red: 0.122, green: 0.118, blue: 0.114)   // #1F1E1D
               : Color(red: 0.95, green: 0.945, blue: 0.93)
    }
    /// 卡片底色（自动继续 / 用量分析）
    var cardBackground: Color {
        isDark ? Color(red: 0.149, green: 0.149, blue: 0.141)   // #262624
               : .white
    }
    /// 列表里每条对话的底色
    var rowFill: Color {
        isDark ? Color(red: 0.173, green: 0.173, blue: 0.165)
               : Color.white.opacity(0.55)
    }
    /// 分隔线、卡片描边
    var hairline: Color {
        isDark ? Color(red: 0.227, green: 0.227, blue: 0.216)   // #3A3A37
               : Color.black.opacity(0.05)
    }
    /// 可点控件的描边，比 hairline 明显一点
    var controlBorder: Color {
        isDark ? Color(red: 0.310, green: 0.306, blue: 0.290)
               : Color.black.opacity(0.16)
    }
    /// 搜索框底色
    var fieldFill: Color {
        isDark ? Color(red: 0.188, green: 0.188, blue: 0.180)   // #30302E
               : Color.white.opacity(0.75)
    }
    /// 量表的空槽
    var gaugeTrack: Color {
        isDark ? Color(red: 0.188, green: 0.188, blue: 0.180)
               : Color.black.opacity(0.06)
    }
    /// 悬停卡片底色
    var hoverBackground: Color {
        isDark ? Color(red: 0.165, green: 0.165, blue: 0.157)
               : Color(red: 0.99, green: 0.985, blue: 0.975)
    }
    /// 日志区底色
    var wellBackground: Color {
        isDark ? Color(red: 0.102, green: 0.102, blue: 0.098)
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
