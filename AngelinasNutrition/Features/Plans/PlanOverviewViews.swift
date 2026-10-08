import SwiftUI

/// The whole eating plan on one scrollable page: targets, the week at a glance, every option, the rules.
struct NutritionOverviewView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(WeekMenuStore.self) private var menus
    let plan: PersonalPlan

    private var n: NutritionPlan { plan.nutrition }
    private var lang: ContentLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                OverviewHeader(plan: plan, title: n.title[lang], lines: [n.goal[lang], n.stats[lang]], metrics: [
                    (n.kcal.text, store.t("kcal / ден", "kcal / day")),
                    ("\(n.protein.text) \(store.t("г", "g"))", store.t("протеин", "protein")),
                ], footer: [n.mealsPerDay[lang], n.pace[lang]])

                weekGrid

                ForEach(Meal.Course.allCases) { course in
                    OverviewBlock(title: course.pluralTitle[lang], systemImage: course.systemImage) {
                        ForEach(Array(n.meals(for: course).enumerated()), id: \.element.id) { index, meal in
                            if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                            NavigationLink(value: meal) { mealLine(meal) }.buttonStyle(.plain)
                        }
                    }
                }

                OverviewBlock(title: n.aboutTitle[lang], systemImage: "function") {
                    ForEach(Array((n.about + (n.dayFlow ?? [])).enumerated()), id: \.offset) { _, item in
                        BulletText(text: item[lang])
                    }
                }
                ForEach(n.sections) { section in
                    OverviewBlock(title: section.title[lang], systemImage: section.style == .warning ? "exclamationmark.triangle.fill" : "list.bullet") {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in BulletText(text: item[lang]) }
                    }
                }
                if let table = n.adjustments { AdjustmentTableView(table: table) }
                if let important = n.important {
                    Callout(title: store.t("Важно", "Important"), items: [important[lang]], isWarning: false)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Режимът накратко", "Plan at a glance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: PlanSummary.nutrition(plan, week: menus.week(for: plan), language: lang)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
        }
    }

    /// Mon–Sun × breakfast / lunch / dinner / snacks, using the user's chosen week.
    private var weekGrid: some View {
        OverviewBlock(title: store.t("Моята седмица", "My week"), systemImage: "calendar") {
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.s) {
                GridRow {
                    Text("")
                    ForEach([Meal.Course.breakfast, .lunch, .dinner, .snack]) { course in
                        Image(systemName: course.systemImage).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                    Text("kcal").foregroundStyle(Theme.Palette.inkSecondary)
                }
                .font(.caption.weight(.semibold))
                ForEach(menus.week(for: plan).sorted { $0.weekday < $1.weekday }, id: \.weekday) { day in
                    GridRow {
                        Text(PlanSummary.shortWeekday(day.weekday, lang))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                        cell("№\(day.breakfast)")
                        cell("№\(day.lunch)")
                        cell("№\(day.dinner)")
                        cell(day.snacks.isEmpty ? "–" : day.snacks.map { "№\($0)" }.joined(separator: " "))
                        Text(day.totals(in: n).kcal.text)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
        }
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(plan.accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func mealLine(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("№\(meal.number)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(plan.accentColor)
                    .frame(width: 32, alignment: .leading)
                Text(meal.name[lang])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Spacing.s)
                Text("\(meal.kcal.text) · \(meal.protein.text)\(store.t("г", "g"))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Text(meal.ingredients.map { $0[lang] }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .padding(.leading, 32)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The whole training program on one page: schedule, warm-up, every workout as a table, the rules.
struct TrainingOverviewView: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan

    private var t: TrainingProgram { plan.training }
    private var lang: ContentLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                OverviewHeader(plan: plan, title: t.title[lang], lines: [t.subtitle[lang], t.stats[lang]], metrics: [], footer: [])

                OverviewBlock(title: store.t("Седмичен график", "Weekly schedule"), systemImage: "calendar") {
                    ForEach(Array(t.schedule.enumerated()), id: \.offset) { index, week in
                        VStack(alignment: .leading, spacing: 4) {
                            if t.schedule.count > 1 {
                                Text(store.t("Седмица \(index + 1)", "Week \(index + 1)"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.inkSecondary)
                            }
                            HStack(spacing: 4) {
                                ForEach(Array(week.enumerated()), id: \.offset) { offset, day in
                                    VStack(spacing: 2) {
                                        Text(PlanSummary.shortWeekday(offset + 1, lang))
                                            .font(.caption2)
                                            .foregroundStyle(Theme.Palette.inkSecondary)
                                        if let workout = day.workout.flatMap(t.workout(id:)) {
                                            Text(workout.short[lang])
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Theme.Palette.onAccent)
                                                .frame(width: 30, height: 30)
                                                .background(plan.accentColor, in: Circle())
                                        } else {
                                            Image(systemName: day.systemImage)
                                                .font(.caption)
                                                .foregroundStyle(Theme.Palette.inkSecondary)
                                                .frame(width: 30, height: 30)
                                                .background(Theme.Palette.surfaceMuted, in: Circle())
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    if let note = t.scheduleNote {
                        Text(note[lang]).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                OverviewBlock(title: store.t("Загрявка", "Warm-up"), systemImage: "flame.fill") {
                    ForEach(Array(t.warmUp.enumerated()), id: \.offset) { _, item in BulletText(text: item[lang]) }
                }

                ForEach(t.workouts) { workout in
                    OverviewBlock(title: workout.title[lang], systemImage: "dumbbell.fill",
                                  subtitle: [workout.duration[lang], workout.focus?[lang]].compactMap { $0 }.joined(separator: " · ")) {
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                            exerciseLine(item)
                        }
                        if let finisher = workout.finisher {
                            Text(finisher[lang]).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                ForEach(t.callouts) { InfoSectionView(section: $0) }
                if let short = t.shortVersion {
                    Callout(title: store.t("Лоша нощ", "Bad night"), items: [short.note[lang]], isWarning: false)
                }
                ForEach(t.sections) { section in
                    OverviewBlock(title: section.title[lang], systemImage: "list.bullet") {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in BulletText(text: item[lang]) }
                    }
                }
                if let table = t.adjustments { AdjustmentTableView(table: table) }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Програмата накратко", "Program at a glance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: PlanSummary.training(plan, language: lang)) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
        }
    }

    private func exerciseLine(_ item: ProgramExercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(item.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(plan.accentColor)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name[lang])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text([item.rest[lang], item.start.map { store.t("старт ", "start ") + $0[lang] }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            Text(item.prescription[lang])
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct OverviewHeader: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan
    let title: String
    let lines: [String]
    let metrics: [(String, String)]
    let footer: [String]

    var body: some View {
        Card(padding: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    PlanAvatar(plan: plan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name[store.language]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                        Text(title).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !metrics.isEmpty {
                    HStack(alignment: .top) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                            PlanMetric(value: metric.0, caption: metric.1, tint: index == 0 ? plan.accentColor : Theme.Palette.sage)
                        }
                    }
                }
                ForEach(footer, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
    }
}

private struct OverviewBlock<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label(title, systemImage: systemImage)
                .font(.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Card(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { content }
            }
        }
    }
}
