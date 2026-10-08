import SwiftUI

/// Full-screen session: log weight × reps per set, rest timer between sets, then save to the log.
struct LiveWorkoutView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss

    let plan: PersonalPlan
    let workout: ProgramWorkout
    let week: Int

    @State private var entries: [LoggedExercise] = []
    @State private var suggestions: [String: SetSuggestion] = [:]
    @State private var isShort = false
    @State private var isDeload = false
    @State private var startedAt = Date.now
    @State private var restEnd: Date?
    @State private var restFinished = 0
    @State private var confirmCancel = false
    @State private var savedFeedback = 0

    private var lang: ContentLanguage { store.language }
    private var tint: Color { plan.accentColor }
    private var program: TrainingProgram { plan.training }

    private var visibleExercises: [ProgramExercise] {
        guard isShort, let short = program.shortVersion else { return workout.exercises }
        return Array(workout.exercises.prefix(short.exercises))
    }

    private var doneSets: Int { entries.reduce(0) { $0 + $1.doneSets.count } }
    private var totalSets: Int { entries.reduce(0) { $0 + $1.sets.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    options
                    ForEach(visibleExercises) { item in
                        if let index = entries.firstIndex(where: { $0.slot == item.label }) {
                            LiveExerciseCard(item: item, entry: $entries[index], suggestion: suggestions[item.label],
                                             tint: tint) { startRest(after: item) }
                        }
                    }
                    if let finisher = workout.finisher {
                        Callout(title: store.t("Финал", "Finisher"), items: [finisher[lang]], isWarning: false)
                    }
                    Button(store.t("Завърши и запази", "Finish & save")) { finish() }
                        .buttonStyle(PrimaryButtonStyle(tint: tint))
                        .disabled(doneSets == 0)
                        .opacity(doneSets == 0 ? 0.5 : 1)
                }
                .padding(Theme.Spacing.l)
                .padding(.bottom, restEnd == nil ? 0 : 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let restEnd {
                    RestTimerBar(end: restEnd, tint: tint,
                                 onAdd: { self.restEnd = restEnd.addingTimeInterval(15) },
                                 onSkip: { self.restEnd = nil })
                        .padding(.horizontal, Theme.Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: restEnd)
            .navigationTitle(workout.title[lang])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("Затвори", "Close")) {
                        if doneSets > 0 { confirmCancel = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Запази", "Save")) { finish() }.disabled(doneSets == 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Готово", "Done")) { hideKeyboard() }
                }
            }
            .confirmationDialog(store.t("Да се откаже ли тренировката? Въведеното няма да се запази.",
                                        "Discard this workout? What you've entered won't be saved."),
                                isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(store.t("Откажи тренировката", "Discard workout"), role: .destructive) { dismiss() }
                Button(store.t("Запази", "Save")) { finish() }
            }
            .sensoryFeedback(.success, trigger: restFinished)
            .sensoryFeedback(.success, trigger: savedFeedback)
            .task(id: restEnd) {
                guard let restEnd else { return }
                try? await Task.sleep(for: .seconds(max(0, restEnd.timeIntervalSinceNow)))
                guard !Task.isCancelled, self.restEnd == restEnd else { return }
                restFinished += 1
                self.restEnd = nil
            }
        }
        .onAppear {
            isDeload = log.shouldSuggestDeload(planID: plan.id, currentWeek: week, every: program.deloadEvery)
            rebuild()
        }
        .onChange(of: isShort) { rebuild() }
        .onChange(of: isDeload) { rebuild() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Седмица \(week)", "Week \(week)"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(Duration.seconds(context.date.timeIntervalSince(startedAt)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(doneSets)/\(totalSets)")
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.ink)
                Text(store.t("серии", "sets")).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let short = program.shortVersion {
                Toggle(isOn: $isShort) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("Лоша нощ – кратък вариант", "Bad night – short version")).font(.subheadline.weight(.semibold))
                        Text(short.note[lang]).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
            }
            Toggle(isOn: $isDeload) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("Разтоварваща седмица", "Deload week")).font(.subheadline.weight(.semibold))
                    Text(store.t("Половината серии със същите тежести – на всеки 6–8 седмици.",
                                 "Half the sets at the same weights – every 6–8 weeks."))
                        .font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
        .tint(tint)
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.Palette.hairline))
    }

    /// Recomputes suggestions and set rows, keeping anything already typed in.
    private func rebuild() {
        let shortSets = isShort ? program.shortVersion?.sets : nil
        var newEntries: [LoggedExercise] = []
        for item in visibleExercises {
            let optionIndex = log.option(planID: plan.id, workoutID: workout.id, slot: item.label)
            let option = item.option(optionIndex)
            let history = log.history(planID: plan.id, workoutID: workout.id, slot: item.label, option: optionIndex)
                .map { ($0.week, $0.exercise) }
            let suggestion = ProgressionCoach.suggest(for: item.tracking, week: week, history: history,
                                                      isDeload: isDeload, shortSets: shortSets)
            suggestions[item.label] = suggestion
            let existing = entries.first { $0.slot == item.label && $0.option == optionIndex }
            let sets = (0..<suggestion.sets).map { i in
                existing?.sets.indices.contains(i) == true
                    ? existing!.sets[i]
                    : LoggedSet(weight: suggestion.weight, reps: nil, seconds: suggestion.seconds)
            }
            newEntries.append(LoggedExercise(slot: item.label, option: optionIndex, name: option.name,
                                             sets: sets, feltEasy: existing?.feltEasy ?? false))
        }
        entries = newEntries
    }

    private func startRest(after item: ProgramExercise) {
        // In a superset ("5a" → "5b") you go straight to the partner exercise.
        guard item.tracking.restSeconds > 0 else { restEnd = nil; return }
        restEnd = .now.addingTimeInterval(TimeInterval(item.tracking.restSeconds))
    }

    private func finish() {
        let done = entries.filter { !$0.doneSets.isEmpty }
        guard !done.isEmpty else { dismiss(); return }
        log.add(WorkoutLog(planID: plan.id, workoutID: workout.id, date: startedAt, week: week,
                           isShort: isShort, isDeload: isDeload,
                           durationSeconds: Int(Date.now.timeIntervalSince(startedAt)), exercises: done))
        savedFeedback += 1
        let (start, title) = (startedAt, workout.title.en)
        Task { await health.saveWorkout(start: start, end: .now, title: title) }
        dismiss()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct LiveExerciseCard: View {
    @Environment(ProfileStore.self) private var store
    let item: ProgramExercise
    @Binding var entry: LoggedExercise
    let suggestion: SetSuggestion?
    let tint: Color
    let onSetDone: () -> Void

    private var lang: ContentLanguage { store.language }
    private var tracking: ExerciseTracking { item.tracking }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Text(item.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name[lang]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                        if let suggestion {
                            Text(suggestion.summary(store, load: tracking.load, perSide: tracking.perSide))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tint)
                            Text(suggestion.reason[lang])
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if entry.doneSets.count == entry.sets.count, !entry.sets.isEmpty {
                        Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Theme.Palette.sage)
                    }
                }

                columnHeaders
                ForEach(entry.sets.indices, id: \.self) { index in
                    setRow(index)
                }

                if !tracking.isTimed {
                    Toggle(isOn: $entry.feltEasy) {
                        Text(store.t("Лесно – 3+ повторения в запас", "Easy – 3+ reps in reserve"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                    .tint(tint)
                }
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(store.t("Серия", "Set")).frame(width: 40, alignment: .leading)
            if tracking.load.usesWeight {
                Text(tracking.load == .dumbbells ? store.t("кг (1 ръка)", "kg (each)") : store.t("кг", "kg"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(tracking.isTimed ? store.t("сек", "sec") : (tracking.perSide ? store.t("повт./страна", "reps/side") : store.t("повт.", "reps")))
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 44, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.Palette.inkSecondary)
    }

    private func setRow(_ index: Int) -> some View {
        let isDone = entry.sets[index].done
        return HStack(spacing: Theme.Spacing.s) {
            Text("\(index + 1)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(isDone ? Theme.Palette.sage : Theme.Palette.ink)
                .frame(width: 40, alignment: .leading)
            if tracking.load.usesWeight {
                numberField(value: $entry.sets[index].weight, prompt: "0", decimal: true)
            }
            if tracking.isTimed {
                numberField(value: Binding(get: { entry.sets[index].seconds.map(Double.init) },
                                           set: { entry.sets[index].seconds = $0.map { Int($0) } }),
                            prompt: suggestion?.seconds.map(String.init) ?? "", decimal: false)
            } else {
                numberField(value: Binding(get: { entry.sets[index].reps.map(Double.init) },
                                           set: { entry.sets[index].reps = $0.map { Int($0) } }),
                            prompt: suggestion?.reps.map { "\($0.lowerBound)–\($0.upperBound)" } ?? "", decimal: false)
            }
            Button {
                toggleDone(index)
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(isDone ? Theme.Palette.sage : Theme.Palette.hairline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("Серия \(index + 1) готова", "Set \(index + 1) done"))
        }
        .padding(.vertical, 2)
        .background(isDone ? Theme.Palette.sage.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        .sensoryFeedback(.impact(weight: .light), trigger: isDone)
    }

    private func numberField(value: Binding<Double?>, prompt: String, decimal: Bool) -> some View {
        TextField(prompt, value: value, format: .number)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .font(.headline.monospacedDigit())
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Theme.Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    private func toggleDone(_ index: Int) {
        if entry.sets[index].done {
            entry.sets[index].done = false
            return
        }
        // Untyped reps/seconds default to the bottom of the target, which the user can still edit.
        if tracking.isTimed {
            if entry.sets[index].seconds == nil { entry.sets[index].seconds = suggestion?.seconds }
        } else if entry.sets[index].reps == nil {
            entry.sets[index].reps = suggestion?.reps?.lowerBound
        }
        entry.sets[index].done = true
        onSetDone()
    }
}

private struct RestTimerBar: View {
    @Environment(ProfileStore.self) private var store
    let end: Date
    let tint: Color
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "timer").font(.title2)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("Почивка", "Rest")).font(.caption.weight(.semibold)).opacity(0.85)
                Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
            }
            Spacer()
            Button("+15", action: onAdd)
                .font(.headline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.22), in: Capsule())
            Button(store.t("Пропусни", "Skip"), action: onSkip)
                .font(.headline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.22), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(Theme.Spacing.l)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
    }
}
