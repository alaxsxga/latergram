import SwiftUI

// MARK: - Colors

extension Color {
    static let brand = Color(red: 0.00, green: 0.80, blue: 0.64)
    static let brandDark  = Color(red: 0.016, green: 0.173, blue: 0.122) // brand 按鈕上的深色文字

    static let pageBg = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let cardBg = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let cardBase   = Color(red: 0.078, green: 0.082, blue: 0.102) // 訊息卡片底色
    static let surfaceMid = Color(red: 0.165, green: 0.173, blue: 0.204) // 輕提升面板／大頭貼底色

    static let fgMuted    = Color(red: 0.373, green: 0.384, blue: 0.427) // 次要文字
    static let accentMint = Color(red: 0.373, green: 0.890, blue: 0.690) // Inbox 強調色
    static let errorRed   = Color.red                                     // 表單錯誤
    static let badgeNew   = Color(red: 0.6,   green: 0.85,  blue: 0.6)   // NEW badge

    // Avatar palette — index by abs(name.hashValue) % count
    static let avatarPalette: [Color] = [
        .brand,
        Color(red: 0.49, green: 0.36, blue: 0.75), // purple
        Color(red: 0.91, green: 0.44, blue: 0.35), // coral
        Color(red: 0.20, green: 0.60, blue: 0.86), // blue
        Color(red: 0.91, green: 0.60, blue: 0.20), // amber
    ]
}

// MARK: - View modifiers

extension View {
    /// Full-page background. Apply to the outermost container of each screen.
    func pageBackground() -> some View {
        background(Color.pageBg.ignoresSafeArea())
    }

    /// Floating card: dark fill + rounded corners + drop shadow.
    func cardStyle(radius: CGFloat = 16) -> some View {
        self
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 1)
    }

    /// Inline surface (inside sheets/cards): dark fill + rounded corners, no shadow.
    func cardBackground(radius: CGFloat = 12) -> some View {
        self
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
