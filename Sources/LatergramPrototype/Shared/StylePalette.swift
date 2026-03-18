import SwiftUI
import LatergramCore

extension MessageStyle {
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
}
