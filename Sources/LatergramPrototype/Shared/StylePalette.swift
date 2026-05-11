import SwiftUI
import LatergramCore

extension MessageStyle {
    var localizedName: String {
        switch self {
        case .classic: "簡約"
        case .warm:    "溫暖"
        case .cool:    "冷靜"
        case .heart:   "心意"
        }
    }

    var background: Color {
        switch self {
        case .classic: Color.gray.opacity(0.15)
        case .warm: Color.orange.opacity(0.2)
        case .cool: Color.blue.opacity(0.2)
        case .heart: Color.pink.opacity(0.22)
        }
    }

    var accent: Color {
        switch self {
        case .classic: .gray
        case .warm: .orange
        case .cool: .blue
        case .heart: .pink
        }
    }

    var icon: String {
        switch self {
        case .classic: "square.grid.2x2"
        case .warm: "sun.max"
        case .cool: "snow"
        case .heart: "heart.fill"
        }
    }

    var styleColor: Color {
        switch self {
        case .classic: Color(red: 0.722, green: 0.737, blue: 0.776)  // 184,188,198
        case .warm:    Color(red: 1.000, green: 0.580, blue: 0.337)  // 255,148,86
        case .cool:    Color(red: 0.353, green: 0.722, blue: 1.000)  // 90,184,255
        case .heart:   Color(red: 1.000, green: 0.361, blue: 0.541)  // 255,92,138
        }
    }

    var styleTextColor: Color {
        switch self {
        case .classic: Color(red: 0.831, green: 0.839, blue: 0.867)  // #D4D6DD
        case .warm:    Color(red: 1.000, green: 0.702, blue: 0.478)  // #FFB37A
        case .cool:    Color(red: 0.561, green: 0.816, blue: 1.000)  // #8FD0FF
        case .heart:   Color(red: 1.000, green: 0.561, blue: 0.682)  // #FF8FAE
        }
    }
}

// MARK: - GlowTier

enum GlowTier {
    case ready, countingDown, opened

    var alpha1: Double {
        switch self { case .ready: 0.5; case .countingDown: 0.4; case .opened: 0.3 }
    }
    var borderAlpha: Double {
        switch self { case .ready: 0.7; case .countingDown: 0.6; case .opened: 0.5 }
    }
    var bgTintAlpha: Double {
        switch self { case .ready: 0.1; case .countingDown: 0.06; case .opened: 0.05 }
    }
    var radius: CGFloat {
        switch self { case .ready: 10; case .countingDown: 6; case .opened: 4 }
    }
}

// MARK: - MessageCardModifier

private let _cardBase   = Color(red: 0.078, green: 0.082, blue: 0.102)  // #14151A
private let _cardRadius: CGFloat = 22

struct MessageCardModifier: ViewModifier {
    let style: MessageStyle
    let tier: GlowTier
    @State private var breathe = false

    private var a1: Double     { tier == .ready && breathe ? min(tier.alpha1 * 1.35, 0.80) : tier.alpha1 }
    private var border: Double { tier == .ready && breathe ? min(tier.borderAlpha * 1.35, 0.80) : tier.borderAlpha }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: _cardRadius).fill(_cardBase)
                    RoundedRectangle(cornerRadius: _cardRadius).fill(
                        LinearGradient(
                            stops: [
                                .init(color: style.styleColor.opacity(tier.bgTintAlpha), location: 0),
                                .init(color: .clear, location: 0.55)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: _cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: _cardRadius)
                    .stroke(style.styleColor.opacity(border), lineWidth: 0.8)
            )
            .shadow(color: style.styleColor.opacity(a1), radius: tier.radius, x: 0, y: 0)
            .onAppear {
                guard tier == .ready else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
    }
}

extension View {
    func messageCard(style: MessageStyle, tier: GlowTier) -> some View {
        modifier(MessageCardModifier(style: style, tier: tier))
    }
}
