import Charts
import SwiftUI

enum ProgressRoute: Hashable {
    case logbook
    case measurements
}

/// Weekly check-ins, the plan's advice for them, and the training log.
struct ProgressTabView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.activePlan {
                    PlanProgressContent(plan: plan)
                } else {
                    // Without a personal plan, Progress is the body measurements.
                    MeasurementsView()
                }
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle(store.activePlan == nil ? "Progress" : store.t("Прогрес", "Progress"))
            .toolbar {
                if store.activePlan != nil {
                    ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
                }
            }
            .askClaudeButton()
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .logbook: LogbookView()
                case .measurements: MeasurementsView()
                }
            }
        }
    }
}

private struct PlanProgressContent: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    let plan: PersonalPlan
    @State private var isAddingCheckIn = false

    private var lang: ContentLanguage { store.language }
    private var checkIns: [CheckIn] { log.checkIns(planID: plan.id) }
    private var currentWeek: Int { store.programDay()?.week ?? 1 }
    private var weeks: [WeekSummary] { PlanAdvisor.weeklySummaries(checkIns, programStart: store.programStart) }
    private var advice: PlanAdvice {
        PlanAdvisor.advice(table: plan.adviceTable, checkIns: checkIns, programStart: store.programStart, currentWeek: currentWeek)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                AdviceCard(plan: plan, advice: advice)

                Button { isAddingCheckIn = true } label: {
                    Label(store.t("Нов check-in", "New check-in"), systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(tint: plan.accentColor))

                NavigationLink(value: ProgressRoute.measurements) { MeasurementsCard(logID: plan.id, tint: plan.accentColor) }
                    .buttonStyle(.plain)

                if log.shouldSuggestDeload(planID: plan.id, currentWeek: currentWeek, every: store.trainingPlan?.training.deloadEvery) {
                    Callout(title: store.t("Време е за разтоварване", "Time for a deload"),
                            items: [store.t("Минаха 6+ седмици. Тази седмица: същите тежести, половината серии (включи го при старт на тренировката).",
                                            "6+ weeks have passed. This week: same weights, half the sets (switch it on when you start a workout).")],
                            isWarning: false)
                }

                if weeks.contains(where: { $0.weight != nil }) {
                    weightChart
                }
                if !weeks.isEmpty { weeklyTable }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: store.t("Тренировки", "Training"))
                    NavigationLink(value: ProgressRoute.logbook) {
                        GuideLinkRow(title: store.t("Дневник – тежест × повторения", "Logbook – weight × reps"),
                                     systemImage: "book.closed.fill", tint: plan.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                if !checkIns.isEmpty { recentCheckIns }

                Text(store.t("Кантар сутрин 3–4 пъти седмично – гледа се седмичната средна стойност. Талия и ханш – веднъж седмично. Корекции – на всеки 2–3 седмици.",
                             "Weigh in the morning 3–4 times a week – the weekly average is what counts. Waist and hips once a week. Adjust every 2–3 weeks."))
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .sheet(isPresented: $isAddingCheckIn) {
            CheckInSheet(logID: plan.id, fields: plan.checkIn.fields, flags: plan.checkIn.flags, tint: plan.accentColor)
        }
    }

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Тегло", "Weight"), subtitle: store.t("Точки: измервания · линия: седмична средна", "Dots: weigh-ins · line: weekly average"))
            Card {
                Chart {
                    ForEach(checkIns.filter { $0.weight != nil }) { item in
                        PointMark(x: .value("Date", item.date, unit: .day), y: .value("kg", item.weight!))
                            .foregroundStyle(plan.accentColor.opacity(0.35))
                            .symbolSize(30)
                    }
                    ForEach(weeks.filter { $0.weight != nil }) { week in
                        LineMark(x: .value("Date", weekMidpoint(week.week), unit: .day), y: .value("kg", week.weight!))
                            .foregroundStyle(plan.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", weekMidpoint(week.week), unit: .day), y: .value("kg", week.weight!))
                            .foregroundStyle(plan.accentColor)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
            }
        }
    }

    private var weeklyTable: some View {
        let fields = plan.checkIn.fields
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("По седмици", "By week"))
            Card {
                VStack(spacing: Theme.Spacing.s) {
                    HStack {
                        Text(store.t("Седм.", "Wk")).frame(width: 40, alignment: .leading)
                        ForEach(fields) { field in
                            Text(field.title[lang]).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Text("Δ").frame(width: 48, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    Divider().overlay(Theme.Palette.hairline)
                    ForEach(weeks.reversed()) { week in
                        weekRow(week, fields: fields)
                    }
                }
            }
        }
    }

    private var recentCheckIns: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Последни check-in-и", "Recent check-ins"),
                          subtitle: store.t("Задръж за изтриване", "Long-press to delete"))
            ForEach(checkIns.prefix(8)) { item in
                HStack {
                    Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text(summary(item))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(Theme.Spacing.m)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .contextMenu {
                    Button(store.t("Изтрий", "Delete"), systemImage: "trash", role: .destructive) { log.delete(item) }
                }
            }
        }
    }

    private func weekRow(_ week: WeekSummary, fields: [CheckInField]) -> some View {
        let previous = weeks.last { $0.week < week.week && $0.weight != nil }
        return HStack {
            Text("\(week.week)").frame(width: 40, alignment: .leading)
            ForEach(fields) { field in
                Text(format(week.value(field), field: field))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(delta(week.weight, previous?.weight))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(Theme.Palette.ink)
    }

    private func format(_ value: Double?, field: CheckInField) -> String {
        guard let value else { return "–" }
        switch field {
        case .steps: return Int(value).formatted()
        case .weight: return value.formatted(.number.precision(.fractionLength(1)))
        case .bodyFat: return value.formatted(.number.precision(.fractionLength(1)))
        default: return value.trimmed
        }
    }

    private func summary(_ item: CheckIn) -> String {
        var parts: [String] = plan.checkIn.fields.compactMap { field in
            item.value(field).map { field == .steps ? "\(Int($0).formatted()) \(field.unit[lang])" : "\($0.trimmed) \(field.unit[lang])" }
        }
        parts += item.flags.map { $0.title[lang] }
        return parts.joined(separator: " · ")
    }

    private func delta(_ current: Double?, _ previous: Double?) -> String {
        guard let current, let previous else { return "" }
        let change = current - previous
        return (change > 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(1)))
    }

    private func weekMidpoint(_ week: Int) -> Date {
        let monday = TrainingProgram.mondayOfWeek(containing: store.programStart)
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7 + 3, to: monday) ?? monday
    }
}

/// Shows which row of the plan's adjustment table applies right now.
struct AdviceCard: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan
    let advice: PlanAdvice

    private var lang: ContentLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Label(store.t("Съвет по плана", "Plan advice"), systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(plan.accentColor)
                Spacer()
                if let change = advice.weeklyChange {
                    Text((change > 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(1))) + store.t(" кг/седм.", " kg/wk"))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.Palette.surfaceMuted, in: Capsule())
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            switch advice.status {
            case .collecting(let weeksNeeded):
                Text(store.t("Събираме данни", "Collecting data"))
                    .font(.sectionTitle).foregroundStyle(Theme.Palette.ink)
                Text(store.t("Въведи тегло поне в \(weeksNeeded) седмица още, за да сравним седмичните средни.",
                             "Log your weight in at least \(weeksNeeded) more week to compare weekly averages."))
                    .font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            case .noRule:
                Text(store.t("Продължавай по плана", "Keep following the plan"))
                    .font(.sectionTitle).foregroundStyle(Theme.Palette.ink)
                Text(store.t("Данните не попадат точно в нито един ред от таблицата. Прегледай отново след 2–3 седмици.",
                             "The data doesn't match a specific row of the table. Review again in 2–3 weeks."))
                    .font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            case .matched(let row):
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.t("Какво се вижда", "What you see")).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    Text(row.when[lang]).font(.subheadline).foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.t("Какво се прави", "What to do")).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    Text(row.action[lang]).font(.sectionTitle).foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plan.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(plan.accentColor.opacity(0.35)))
        .padding(.top, Theme.Spacing.s)
    }
}

struct CheckInSheet: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @Environment(\.dismiss) private var dismiss
    /// Where the check-in is stored: the plan id, or "personal" without a plan.
    let logID: String
    /// The plan's own check-in fields, shown first; the other body measurements follow.
    let fields: [CheckInField]
    let flags: [CheckInFlag]
    let tint: Color
    var expandMeasurements = false

    @State private var date = Date.now
    @State private var values: [CheckInField: Double] = [:]
    @State private var chosenFlags: Set<CheckInFlag> = []
    @State private var showAll = false

    private var lang: ContentLanguage { store.language }
    private var extraFields: [CheckInField] { CheckInField.bodyMeasurements.filter { !fields.contains($0) } }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(store.t("Дата", "Date"), selection: $date, in: ...Date.now, displayedComponents: .date)
                if !fields.isEmpty {
                    Section {
                        ForEach(fields) { fieldRow($0) }
                    } footer: {
                        Text(store.t("Попълни само каквото си измерил днес.", "Only fill in what you measured today."))
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $showAll) {
                        ForEach(extraFields) { fieldRow($0) }
                    } label: {
                        Label(store.t("Още мерки (веднъж седмично)", "More measurements (weekly)"), systemImage: "ruler")
                    }
                } footer: {
                    Text(store.t("Мери сутрин, на едно и също място, със същия сантиметър.", "Measure in the morning, at the same spot, with the same tape."))
                }
                if !flags.isEmpty {
                    Section(store.t("Как се чувстваш", "How you feel")) {
                        ForEach(flags) { flag in
                            Toggle(flag.title[lang], isOn: Binding(
                                get: { chosenFlags.contains(flag) },
                                set: { if $0 { chosenFlags.insert(flag) } else { chosenFlags.remove(flag) } }
                            ))
                            .tint(tint)
                        }
                    }
                }
            }
            .navigationTitle(store.t("Измервания", "Measurements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Отказ", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Запази", "Save")) { save() }
                        .disabled(values.isEmpty && chosenFlags.isEmpty)
                }
            }
            .onAppear { showAll = expandMeasurements || fields.isEmpty }
        }
        .presentationDetents([.large])
    }

    private func fieldRow(_ field: CheckInField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(field.title[lang])
                Spacer()
                TextField("–", value: Binding(get: { values[field] }, set: { values[field] = $0 }), format: .number)
                    .keyboardType(field == .steps ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text(field.unit[lang]).foregroundStyle(Theme.Palette.inkSecondary).frame(width: 44, alignment: .leading)
            }
            if let howTo = field.howTo {
                Text(howTo[lang]).font(.caption2).foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    private func save() {
        var checkIn = CheckIn(planID: logID, date: date, flags: chosenFlags)
        for (field, value) in values { checkIn.set(field, value) }
        log.add(checkIn)
        dismiss()
    }
}
