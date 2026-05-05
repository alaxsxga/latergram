import SwiftUI

// MARK: - Colors

extension Color {
    static let brand = Color(red: 0.00, green: 0.80, blue: 0.64)

    static let pageBg = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let cardBg = Color(red: 0.13, green: 0.13, blue: 0.13)

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
