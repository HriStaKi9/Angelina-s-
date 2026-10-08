import SwiftUI

/// Rearrange a program week: drag to move sessions between days, tap a day to swap what it holds,
/// for this week only or for every week.
struct ScheduleEditorView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var weekOffset = 0
    @State private var days: [ScheduleDay] = []
    @State private var everyWeek = false
    @State private var loadedWeek = 0

    private var lang: ContentLanguage { store.language }
    private var plan: PersonalPlan? { store.trainingPlan }
    private var program: TrainingProgram? { plan?.training }
    private var currentWeek: Int { store.programDay()?.week ?? 1 }
    private var week: Int { currentWeek + weekOffset }
    private var tint: Color { plan?.accentColor ?? Theme.Palette.berry }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(store.t("Седмица", "Week"), selection: $weekOffset) {
                        Text(store.t("Тази седмица", "This week")).tag(0)
                        Text(store.t("Следващата", "Next week")).tag(1)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(store.t("Влачи ≡, за да преместиш тренировка в друг ден. Докосни ден, за да смениш какво има в него.",
                                 "Drag ≡ to move a session to another day. Tap a day to change what's on it."))
                }

                Section(store.t("Седмица \(week)", "Week \(week)")) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        dayRow(index: index, day: day)
                    }
                    .onMove { from, to in
                        // Sessions move; the weekdays stay where they are.
                        days.move(fromOffsets: from, toOffset: to)
                    }
                }

                if let warning = restWarning {
                    Section { Label(warning, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Theme.Palette.apricot) }
                }

                Section {
                    Toggle(isOn: $everyWeek) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.t("Важи за всяка седмица", "Apply to every week"))
                            Text(everyWeek
                                 ? ((program?.schedule.count ?? 1) > 1
                                    ? store.t("Всяка седмица от същия тип (A-B-A / B-A-B се редуват).", "Every week of the same type (A-B-A / B-A-B alternate).")
                                    : store.t("Новият ред става постоянен.", "The new order becomes your regular week."))
                                 : store.t("Само за седмица \(week).", "Only for week \(week)."))
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }
                    .tint(tint)
                }

                if store.hasScheduleEdits {
                    Section {
                        Button(store.t("Върни графика от плана", "Reset to the plan's schedule"), role: .destructive) {
                            store.resetSchedule()
                            load()
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(store.t("Подреди седмицата", "Arrange the week"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Отказ", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Запази", "Save")) {
                        store.saveWeek(days, week: week, everyWeek: everyWeek)
                        dismiss()
                    }
                    .disabled(days.count != 7)
                }
            }
            .onAppear(perform: load)
            .onChange(of: weekOffset) { load() }
        }
    }

    private func load() {
        days = store.scheduledWeek(week) ?? []
        loadedWeek = week
    }

    private func dayRow(index: Int, day: ScheduleDay) -> some View {
        let workout = day.workout.flatMap { program?.workout(id: $0) }
        let isToday = weekOffset == 0 && index == TrainingProgram.mondayBasedWeekday(of: .now) - 1
        return Menu {
            ForEach(program?.workouts ?? []) { option in
                Button(option.title[lang], systemImage: "dumbbell.fill") { days[index] = ScheduleDay(kind: .workout, workout: option.id) }
            }
            Divider()
            ForEach([ScheduleDay.Kind.steps, .walk, .rest], id: \.self) { kind in
                let option = ScheduleDay(kind: kind, workout: nil)
                Button(option.kindTitle[lang], systemImage: option.systemImage) { days[index] = option }
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text(PlanSummary.weekdayName(index + 1, lang))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? tint : Theme.Palette.inkSecondary)
                    .frame(width: 96, alignment: .leading)
                if let workout {
                    Text(workout.short[lang])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .frame(width: 28, height: 28)
                        .background(tint, in: Circle())
                    Text(workout.title[lang]).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Palette.ink)
                } else {
                    Image(systemName: day.systemImage)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.Palette.surfaceMuted, in: Circle())
                    Text(day.kindTitle[lang]).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
    }

    /// The plans ask for a rest day between strength sessions.
    private var restWarning: String? {
        let workoutDays = days.enumerated().filter { $0.element.kind == .workout }.map(\.offset)
        let backToBack = zip(workoutDays, workoutDays.dropFirst()).contains { $1 - $0 == 1 }
        guard backToBack else { return nil }
        return store.t("Две силови тренировки са в поредни дни – програмата препоръчва поне ден почивка между тях.",
                       "Two strength sessions are on back-to-back days – the program recommends at least a day of rest between them.")
    }
}
