import ComposableArchitecture
import LatergramCore
import SwiftUI

struct ComposeView: View {
    @Bindable var store: StoreOf<ComposeFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("訊息") {
                    TextEditor(text: $store.body)
                        .frame(minHeight: 120)
                    Text("\(store.body.count)/1000")
                        .font(.caption)
                        .foregroundStyle(store.body.count > 1000 ? .red : .secondary)
                }

                Section("倒數時間") {
                    DatePicker(
                        "解鎖時間",
                        selection: $store.unlockAt,
                        in: store.minUnlockAt...store.maxUnlockAt
                    )
                }

                Section("樣式") {
                    Picker("Style", selection: $store.style) {
                        ForEach(MessageStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.icon).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let error = store.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("建立倒數訊息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { store.send(.cancelTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSending {
                        ProgressView()
                    } else {
                        Button("送出") { store.send(.submitTapped) }
                            .disabled(store.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
