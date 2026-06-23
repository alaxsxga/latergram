#if os(iOS)
import ComposableArchitecture
import SwiftUI

struct FeedbackView: View {
    @Bindable var store: StoreOf<FeedbackFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(LS("feedback.section_category")) {
                    Picker(LS("feedback.section_category"), selection: $store.category) {
                        ForEach(FeedbackFeature.Category.allCases, id: \.self) { category in
                            Text(label(for: category)).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if store.content.isEmpty {
                            Text(LS("feedback.content_placeholder"))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $store.content)
                            .frame(minHeight: 140)
                    }
                } header: {
                    Text(LS("feedback.section_content"))
                } footer: {
                    Text("\(store.trimmedContent.count) / \(FeedbackFeature.State.maxContentLength)")
                        .foregroundStyle(
                            store.trimmedContent.count > FeedbackFeature.State.maxContentLength
                                ? Color.red : Color.secondary
                        )
                }

                Section(LS("feedback.section_email")) {
                    TextField(LS("feedback.email_placeholder"), text: $store.contactEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle(LS("feedback.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LS("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSubmitting {
                        ProgressView()
                    } else {
                        Button(LS("feedback.submit")) {
                            store.send(.submitTapped)
                        }
                        .disabled(!store.canSubmit)
                    }
                }
            }
            .onAppear { store.send(.onAppear) }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    private func label(for category: FeedbackFeature.Category) -> String {
        switch category {
        case .bug:   LS("feedback.category_bug")
        case .idea:  LS("feedback.category_idea")
        case .other: LS("feedback.category_other")
        }
    }
}
#endif
