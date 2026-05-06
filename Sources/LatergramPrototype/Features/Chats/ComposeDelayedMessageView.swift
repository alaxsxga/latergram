import ComposableArchitecture
import LatergramCore
import SwiftUI

struct ComposeView: View {
    @Bindable var store: StoreOf<ComposeFeature>

    @State private var countdownDays = 0
    @State private var countdownHours = 1
    @State private var countdownMinutes = 0

    @State private var selectedDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var unlockHour = 9
    @State private var unlockMinute = 0
    @State private var unlockIsAM = true

    private let minuteSteps = Array(0...59)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    composeLabel("收件人")
                    RecipientRow(friend: store.friend)
                        .padding(.bottom, 20)

                    composeLabel("訊息")
                    messageBox
                        .padding(.bottom, 20)

                    composeLabel("時間")
                    timingToggle
                        .padding(.bottom, 8)
                    if store.timingMode == .countdown {
                        CountdownCard(days: $countdownDays, hours: $countdownHours, minutes: $countdownMinutes)
                    } else {
                        UnlockDateCard(
                            selectedDate: $selectedDate,
                            hour: $unlockHour,
                            minute: $unlockMinute,
                            isAM: $unlockIsAM,
                            minuteSteps: minuteSteps
                        )
                    }
                    summaryPill
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    composeLabel("樣式")
                    stylePicker
                        .padding(.bottom, 16)

                    stylePreview
                        .padding(.bottom, 20)

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .navigationTitle("新訊息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { store.send(.cancelTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSending {
                        ProgressView()
                    } else {
                        Button("送出") { store.send(.submitTapped) }
                            .disabled(!canSend)
                    }
                }
            }
        }
        .onChange(of: countdownDays) { _ in updateUnlockAt() }
        .onChange(of: countdownHours) { _ in updateUnlockAt() }
        .onChange(of: countdownMinutes) { _ in updateUnlockAt() }
        .onChange(of: selectedDate) { _ in updateUnlockAt() }
        .onChange(of: unlockHour) { _ in updateUnlockAt() }
        .onChange(of: unlockMinute) { _ in updateUnlockAt() }
        .onChange(of: unlockIsAM) { _ in updateUnlockAt() }
        .onChange(of: store.timingMode) { _ in updateUnlockAt() }
        .onAppear { updateUnlockAt() }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !store.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.unlockAt > Date().addingTimeInterval(59)
    }

    private func updateUnlockAt() {
        let now = Date()
        switch store.timingMode {
        case .countdown:
            let secs = TimeInterval(countdownDays * 86400 + countdownHours * 3600 + countdownMinutes * 60)
            store.unlockAt = now.addingTimeInterval(secs)
        case .unlockDate:
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: selectedDate)
            let hour24: Int
            if unlockIsAM {
                hour24 = unlockHour == 12 ? 0 : unlockHour
            } else {
                hour24 = unlockHour == 12 ? 12 : unlockHour + 12
            }
            comps.hour = hour24
            comps.minute = unlockMinute
            comps.second = 0
            store.unlockAt = cal.date(from: comps) ?? now.addingTimeInterval(86400)
        }
    }

    private func composeLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
    }

    // MARK: - Subviews

    private var messageBox: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $store.body)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
            Text("\(store.body.count)/1000")
                .font(.caption)
                .foregroundStyle(store.body.count > 1000 ? .red : .secondary)
        }
        .padding(14)
        .cardBackground(radius: 16)
    }

    private var timingToggle: some View {
        HStack(spacing: 0) {
            timingOption("⏳ 倒數", mode: .countdown)
            timingOption("📅 指定日期", mode: .unlockDate)
        }
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func timingOption(_ label: String, mode: ComposeFeature.State.TimingMode) -> some View {
        let isActive = store.timingMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.timingMode = mode
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isActive ? Color.brand : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(4)
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        let cal = Calendar.current
        let now = Date()
        switch store.timingMode {
        case .countdown:
            var parts: [String] = []
            if countdownDays > 0 { parts.append("\(countdownDays) 天") }
            if countdownHours > 0 { parts.append("\(countdownHours) 小時") }
            if countdownMinutes > 0 { parts.append("\(countdownMinutes) 分鐘") }
            let duration = parts.isEmpty ? "0 分鐘" : parts.joined(separator: " ")
            return "⏳ \(duration) 後開啟 · \(store.unlockAt.formatted(date: .abbreviated, time: .shortened))"
        case .unlockDate:
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: selectedDate)).day ?? 0
            return "🔓 \(store.unlockAt.formatted(date: .abbreviated, time: .shortened)) 解鎖 · \(days) 天後"
        }
    }

    private var summaryPill: some View {
        Text(summaryText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brand.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brand.opacity(0.2), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Style Picker

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MessageStyle.allCases) { style in
                    StyleCard(style: style, isSelected: store.style == style)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.style = style
                            }
                        }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, -2)
    }

    // MARK: - Style Preview

    private var stylePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            composeLabel("預覽")
            VStack(alignment: .leading, spacing: 10) {
                Text("你的訊息，對方解鎖後就能看到。")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(store.style.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack {
                    Spacer()
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .cardBackground(radius: 16)
        }
    }
}

// MARK: - Style Card

private struct StyleCard: View {
    let style: MessageStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .frame(width: 44, height: 6)
                .foregroundStyle(style.accent.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(style.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 3) {
                Image(systemName: style.icon)
                    .font(.system(size: 9))
                Text(style.localizedName)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(style.accent)
        }
        .frame(width: 68, height: 60)
        .padding(8)
        .cardBackground(radius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.brand : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brand)
                    .background(Color.cardBg, in: Circle())
                    .padding(4)
            }
        }
    }
}

// MARK: - Recipient Row

private struct RecipientRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 10) {
            InitialsAvatar(name: friend.displayName, size: 32)
            Text(friend.displayName)
                .font(.body.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardBackground(radius: 14)
    }
}

// MARK: - Countdown Card

private struct CountdownCard: View {
    @Binding var days: Int
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("天數")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("最多 7 天")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    Button {
                        if days > 0 { days -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 38, height: 38)
                            .foregroundStyle(Color.brand)
                    }
                    Text("\(days)")
                        .font(.body.bold().monospacedDigit())
                        .frame(minWidth: 28)
                    Button {
                        if days < 7 { days += 1 }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 38, height: 38)
                            .foregroundStyle(Color.brand)
                    }
                }
                .background(Color(white: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            VStack(spacing: 4) {
                Text("時 · 分")
                    .font(.caption2.uppercaseSmallCaps())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)

                HStack(alignment: .center, spacing: 2) {
                    Picker("小時", selection: $hours) {
                        ForEach(0...23, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 140)
                    .clipped()

                    Text(":")
                        .font(.title.bold())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    Picker("分鐘", selection: $minutes) {
                        ForEach(0...59, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 140)
                    .clipped()
                }

                HStack {
                    Text("時").frame(width: 80)
                    Spacer().frame(width: 20)
                    Text("分").frame(width: 80)
                }
                .font(.caption2.uppercaseSmallCaps())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
            }
        }
        .cardStyle()
    }
}

// MARK: - Unlock Date Card

private struct UnlockDateCard: View {
    @Binding var selectedDate: Date
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var isAM: Bool
    let minuteSteps: [Int]

    private let dates: [Date] = {
        let cal = Calendar.current
        return (0...7).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(dates.indices, id: \.self) { i in
                        let date = dates[i]
                        if i > 0, monthChanged(from: dates[i - 1], to: date) {
                            monthDivider(for: date)
                        }
                        DatePill(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isToday: Calendar.current.isDateInToday(date)
                        ) {
                            selectedDate = date
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text("解鎖時間")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                HStack(alignment: .center, spacing: 2) {
                    Picker("時", selection: $hour) {
                        ForEach(1...12, id: \.self) { h in
                            Text("\(h)").tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 64, height: 120)
                    .clipped()

                    Text(":")
                        .font(.title.bold())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    Picker("分", selection: $minute) {
                        ForEach(minuteSteps, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 64, height: 120)
                    .clipped()

                    Picker("AM/PM", selection: $isAM) {
                        Text("AM").tag(true)
                        Text("PM").tag(false)
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 56, height: 120)
                    .clipped()
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
        }
        .cardStyle()
    }

    private func monthChanged(from: Date, to: Date) -> Bool {
        Calendar.current.component(.month, from: from) != Calendar.current.component(.month, from: to)
    }

    private func monthDivider(for date: Date) -> some View {
        Text(date.formatted(.dateTime.month(.abbreviated)))
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Date Pill

private struct DatePill: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    private var weekdayText: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var dayText: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Text(weekdayText)
                    .font(.caption2.bold())
                    .foregroundStyle(
                        isSelected ? Color.brand.opacity(0.9) :
                        isToday   ? Color.brand : Color(.tertiaryLabel)
                    )

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.brand : Color(white: 0.18))
                        .frame(width: 44, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isToday && !isSelected ? Color.brand.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )

                    VStack(spacing: 2) {
                        Text(dayText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isSelected ? .white : Color(.label))
                        if isToday {
                            Circle()
                                .fill(isSelected ? Color.white.opacity(0.7) : Color.brand)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 48)
    }
}
