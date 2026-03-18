import Foundation

public enum CountdownFormatter {
    public static func dHms(from interval: TimeInterval) -> String {
        let clamped = max(0, Int(interval.rounded(.down)))
        let days = clamped / 86_400
        let hours = (clamped % 86_400) / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        return "\(days)天 \(String(format: "%02d", hours)):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
}
