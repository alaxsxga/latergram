#if os(iOS)
import LatergramCore
import SwiftUI

struct LimitInfoSheet: View {
    let unlockAt: Date?
    let now: Date
    let isPremium: Bool
    let onDismiss: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            VStack(spacing: 6) {
                L("chat_detail.limit_title")
                    .font(.headline)
                if let unlockAt {
                    Text(CountdownFormatter.dHms(from: unlockAt.timeIntervalSince(now)))
                        .font(.title.monospacedDigit().bold())
                }
                L("chat_detail.limit_info")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                if !isPremium {
                    Button {
                        onUpgrade()
                    } label: {
                        Label(LS("chat_detail.unlock_more"), systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(LS("chat_detail.got_it"), action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
#endif
