import Charts
import SwiftUI
import UserNotifications

/// Weekly body measurements: latest values, change since last time and since the start, a chart per
/// measurement, and an optional weekly reminder.
struct MeasurementsView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @Environment(HealthService.self) private var health
    @State private var selected: CheckInField = .waist
    @State private var isMeasuring = false
    @State private var importMessage: String?

    private var plan: PersonalPlan? { store.trainingPlan ?? store.activePlan }
    private var logID: String { plan?.id ?? "personal" }
    private var tint: Color { plan?.accentColor ?? Theme.Palette.berry }
    private var lang: ContentLanguage { store.language }
    /// Oldest first.
    private var checkIns: [CheckIn] { log.checkIns(planID: logID).reversed() }

    var body: some View {
        let measured = CheckInField.bodyMeasurements.filter { field in checkIns.contains { $0.value(field) != nil } }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Button { isMeasuring = true } label: {
                    Label(store.t("Измери се", "Take measurements"), systemImage: "ruler")
                }
                .buttonStyle(PrimaryButtonStyle(tint: tint))
                .padding(.top, Theme.Spacing.s)

                if health.isConnected {
                    Button { Task { await importFromHealth() } } label: {
                        Label(store.t("Вземи от Apple Health", "Import from Apple Health"), systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(tint)
                            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if let importMessage {
                        Text(importMessage).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }

                if measured.isEmpty {
                    Card {
                        Text(store.t("Още няма измервания. Веднъж седмично: тегло, талия, ханш, гърди, врат, ръка, бедро, прасец и % мазнини – по желание.",
                                     "No measurements yet. Once a week: weight, waist, hips, chest, neck, arm, thigh, calf and body fat % – whichever you like."))
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                } else {
                    chart(measured)
                    table(measured)
                }

                WeeklyReminderCard(tint: tint)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Измервания", "Measurements"))
        .sheet(isPresented: $isMeasuring) {
            CheckInSheet(logID: logID, fields: [], flags: [], tint: tint, expandMeasurements: true)
        }
        .onAppear { if let first = measured.first, !measured.contains(selected) { selected = first } }
    }

    /// Weight, body fat and waist from a smart scale or other apps (last 90 days), one check-in per day.
    private func importFromHealth() async {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        let samples = await health.bodySamples(since: since)
        let result = HealthImport.checkIns(from: samples, alreadyImported: HealthImport.importedIDs, logID: logID)
        for checkIn in result.checkIns { log.add(checkIn) }
        HealthImport.importedIDs.formUnion(result.importedIDs)
        importMessage = result.checkIns.isEmpty
            ? store.t("Няма нови измервания в Apple Health.", "No new measurements in Apple Health.")
            : store.t("Добавени \(result.checkIns.count) дни с измервания.", "Added \(result.checkIns.count) days of measurements.")
    }

    private func points(_ field: CheckInField) -> [(date: Date, value: Double)] {
        checkIns.compactMap { c in c.value(field).map { (c.date, $0) } }
    }

    private func chart(_ measured: [CheckInField]) -> some View {
        let data = points(selected)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(measured) { field in
                        Chip(title: field.title[lang], isSelected: selected == field, tint: tint) { selected = field }
                    }
                }
            }
            Card {
                if data.count >= 2 {
                    Chart(data, id: \.date) { point in
                        LineMark(x: .value("Date", point.date, unit: .day), y: .value(selected.unit.en, point.value))
                            .foregroundStyle(tint)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        PointMark(x: .value("Date", point.date, unit: .day), y: .value(selected.unit.en, point.value))
                            .foregroundStyle(tint)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                } else {
                    Text(store.t("Графиката се появява след второто измерване.", "The chart appears after the second measurement."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
    }

    private func table(_ measured: [CheckInField]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Последни стойности", "Latest"),
                          subtitle: store.t("Промяна спрямо миналия път · от началото", "Change since last time · since the start"))
            Card(padding: Theme.Spacing.m) {
                VStack(spacing: 0) {
                    ForEach(Array(measured.enumerated()), id: \.element) { index, field in
                        if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                        let data = points(field)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.title[lang]).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Palette.ink)
                                if let last = data.last {
                                    Text(last.date.formatted(.dateTime.day().month(.abbreviated)))
                                        .font(.caption2).foregroundStyle(Theme.Palette.inkSecondary)
                                }
                            }
                            Spacer()
                            if let last = data.last {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(format(last.value, field)) \(field.unit[lang])")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(Theme.Palette.ink)
                                    Text([delta(data.dropLast().last?.value, last.value), delta(data.count > 1 ? data.first?.value : nil, last.value)]
                                        .map { $0 ?? "–" }.joined(separator: " · "))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.Palette.inkSecondary)
                                }
                            }
                        }
                        .padding(.vertical, Theme.Spacing.s)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = field }
                    }
                }
            }
        }
    }

    private func format(_ value: Double, _ field: CheckInField) -> String {
        field == .weight || field == .bodyFat
            ? value.formatted(.number.precision(.fractionLength(1)))
            : value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func delta(_ from: Double?, _ to: Double) -> String? {
        guard let from else { return nil }
        let change = to - from
        return (change > 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(1)))
    }
}

/// Summary card on the Progress tab: latest weight and waist with the change since the start.
struct MeasurementsCard: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    let logID: String
    let tint: Color

    var body: some View {
        let items = Array(log.checkIns(planID: logID).reversed())
        let lastDate = items.last { c in CheckInField.bodyMeasurements.contains { c.value($0) != nil } }?.date
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "ruler.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Измервания", "Measurements")).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                Text(summary(items) ?? store.t("Тегло, талия, ханш и още – веднъж седмично", "Weight, waist, hips and more – weekly"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSecondary)
                if let lastDate {
                    let days = Calendar.current.dateComponents([.day], from: lastDate, to: .now).day ?? 0
                    Text(days >= 7 ? store.t("Време е за ново измерване", "Time to measure again")
                                   : store.t("Последно преди \(days) дни", "Last measured \(days) days ago"))
                        .font(.caption.weight(days >= 7 ? .semibold : .regular))
                        .foregroundStyle(days >= 7 ? tint : Theme.Palette.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
    }

    private func summary(_ items: [CheckIn]) -> String? {
        let parts: [String] = [CheckInField.weight, .waist].compactMap { field in
            let values = items.compactMap { $0.value(field) }
            guard let last = values.last else { return nil }
            var text = "\(field.title[store.language].components(separatedBy: " ").first ?? "") \(last.formatted(.number.precision(.fractionLength(0...1)))) \(field.unit[store.language])"
            if values.count > 1, let first = values.first {
                let change = last - first
                text += " (\(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))))"
            }
            return text
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Weekly local notification: "time to take your measurements".
struct WeeklyReminderCard: View {
    @Environment(ProfileStore.self) private var store
    let tint: Color
    @AppStorage("measureReminder.on") private var isOn = false
    @AppStorage("measureReminder.weekday") private var weekday = 1
    @AppStorage("measureReminder.hour") private var hour = 8
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Напомняне", "Reminder"))
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Toggle(store.t("Напомняй ми всяка седмица", "Remind me every week"), isOn: $isOn).tint(tint)
                    if isOn {
                        Picker(store.t("Ден", "Day"), selection: $weekday) {
                            ForEach(1...7, id: \.self) { Text(PlanSummary.weekdayName($0, store.language)).tag($0) }
                        }
                        Stepper(store.t("Час: \(hour):00", "Time: \(hour):00"), value: $hour, in: 5...22)
                    }
                    if denied {
                        Text(store.t("Известията са изключени – включи ги от Настройки.", "Notifications are off – turn them on in Settings."))
                            .font(.caption).foregroundStyle(Theme.Palette.berry)
                    }
                }
            }
        }
        .onChange(of: isOn) { reschedule() }
        .onChange(of: weekday) { reschedule() }
        .onChange(of: hour) { reschedule() }
    }

    private func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-measurements"])
        guard isOn else { return }
        let (title, body) = (store.t("Седмично измерване", "Weekly measurements"),
                             store.t("Тегло, талия, ханш и още – отнема 2 минути.", "Weight, waist, hips and more – takes 2 minutes."))
        let weekday = self.weekday, hour = self.hour
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run { denied = !granted }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // Calendar weekday: 1 = Sunday … 7 = Saturday; ours: 1 = Monday … 7 = Sunday.
            var date = DateComponents()
            date.weekday = weekday % 7 + 1
            date.hour = hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "weekly-measurements", content: content, trigger: trigger))
        }
    }
}
