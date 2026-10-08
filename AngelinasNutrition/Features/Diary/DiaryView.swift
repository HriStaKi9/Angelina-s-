import SwiftUI

/// Food diary tab (MyFitnessPal-style): goal − food = remaining, per-meal entries, add food.
struct DiaryView: View {
    var body: some View {
        NavigationStack {
            DiaryContent()
        }
    }
}

struct DiaryContent: View {
    @Environment(ProfileStore.self) private var store
    @Environment(FoodDiaryStore.self) private var diary
    @Environment(WeekMenuStore.self) private var menus
    @State private var date = Date.now
    @State private var addingTo: Meal.Course?
    /// Debug builds accept `-openCalculator YES`, for simulator screenshots.
    @State private var showCalculator = UserDefaults.standard.bool(forKey: "openCalculator") && _isDebugAssertConfiguration()

    private var plan: PersonalPlan? { store.activePlan }
    private var tint: Color { plan?.accentColor ?? Theme.Palette.berry }
    private var lang: ContentLanguage { store.language }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var locale: Locale { Locale(identifier: plan != nil && lang == .bg ? "bg_BG" : "en_GB") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                dateSwitcher
                summary
                if plan != nil { logMenuButton }
                ForEach(Meal.Course.allCases) { course in mealSection(course) }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Дневник", "Diary"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCalculator = true } label: { Image(systemName: "function") }
                    .accessibilityLabel(store.t("Калориен калкулатор", "Calorie calculator"))
            }
        }
        .askClaudeButton()
        .sheet(item: $addingTo) { course in AddFoodView(course: course, date: date) }
        .sheet(isPresented: $showCalculator) { CalorieCalculatorView() }
    }

    private var dateSwitcher: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            Spacer()
            VStack(spacing: 0) {
                Text(isToday ? store.t("Днес", "Today") : date.formatted(.dateTime.weekday(.wide).locale(locale)))
                    .font(.cardTitle)
                Text(date.formatted(.dateTime.day().month(.wide).locale(locale)))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(isToday)
        }
        .font(.headline)
        .tint(tint)
        .padding(.top, Theme.Spacing.s)
    }

    private func shift(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    private var summary: some View {
        let goal = diary.goal(for: plan)
        let food = diary.totals(on: date)
        let remaining = Double(goal.kcal) - food.kcal
        let progress = min(1, food.kcal / Double(max(goal.kcal, 1)))
        return Card(padding: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.l) {
                HStack(alignment: .center, spacing: Theme.Spacing.l) {
                    ZStack {
                        Circle().stroke(Theme.Palette.surfaceMuted, lineWidth: 14)
                        Circle().trim(from: 0, to: progress)
                            .stroke(remaining < 0 ? Theme.Palette.apricot : tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.snappy, value: progress)
                        VStack(spacing: 0) {
                            Text("\(Int(abs(remaining).rounded()))")
                                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.Palette.ink)
                            Text(remaining >= 0 ? store.t("остават", "left") : store.t("над целта", "over"))
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        equationRow(store.t("Цел", "Goal"), "\(goal.kcal)")
                        equationRow(store.t("Храна", "Food"), "− \(Int(food.kcal.rounded()))")
                        Divider().overlay(Theme.Palette.hairline)
                        equationRow(store.t("Остават", "Remaining"), "\(Int(remaining.rounded()))", bold: true)
                    }
                }
                VStack(spacing: Theme.Spacing.s) {
                    macroBar(store.t("Протеин", "Protein"), food.protein, goal.protein, Theme.Palette.berry)
                    macroBar(store.t("Въглехидрати", "Carbs"), food.carbs ?? 0, goal.carbs, Theme.Palette.apricot)
                    macroBar(store.t("Мазнини", "Fat"), food.fat ?? 0, goal.fat, Theme.Palette.sage)
                }
                if diary.entries(on: date).contains(where: { $0.planMealID != nil }) {
                    Text(store.t("Храненията от плана имат само kcal и протеин.", "Plan meals only carry kcal and protein."))
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func equationRow(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(bold ? .headline.monospacedDigit() : .subheadline.monospacedDigit())
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    private func macroBar(_ title: String, _ value: Double, _ target: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(target.map { "\(Int(value.rounded())) / \($0) \(store.t("г", "g"))" } ?? "\(Int(value.rounded())) \(store.t("г", "g"))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            if let target {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.surfaceMuted)
                        Capsule().fill(color).frame(width: proxy.size.width * min(1, value / Double(max(target, 1))))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    /// One tap: log the day's chosen menu from the plan (skips meals already logged).
    private var logMenuButton: some View {
        let weekday = TrainingProgram.mondayBasedWeekday(of: date)
        let meals = plan.flatMap { p in menus.menu(for: p, weekday: weekday)?.meals(in: p.nutrition) } ?? []
        let missing = meals.filter { !diary.isLogged($0, on: date) }
        return Button {
            for meal in missing { diary.logPlanMeal(meal, on: date) }
        } label: {
            Label(missing.isEmpty ? store.t("Менюто за деня е въведено", "Day's menu logged")
                                  : store.t("Въведи менюто за деня (\(missing.count))", "Log the day's menu (\(missing.count))"),
                  systemImage: missing.isEmpty ? "checkmark.circle.fill" : "text.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(missing.isEmpty ? Theme.Palette.sage : tint)
                .background((missing.isEmpty ? Theme.Palette.sage : tint).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(missing.isEmpty)
    }

    private func mealSection(_ course: Meal.Course) -> some View {
        let entries = diary.entries(on: date, course: course)
        let total = diary.totals(on: date, course: course)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label(course.pluralTitle[lang], systemImage: course.systemImage)
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(Int(total.kcal.rounded())) kcal")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Card(padding: Theme.Spacing.m) {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                        Divider().overlay(Theme.Palette.hairline)
                    }
                    Button { addingTo = course } label: {
                        Label(store.t("Добави храна", "Add food"), systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name[lang]).font(.subheadline).foregroundStyle(Theme.Palette.ink).lineLimit(2)
                let macros = "P \(Int(entry.nutrients.protein.rounded()))" + (entry.nutrients.carbs.map { " · C \(Int($0.rounded()))" } ?? "") + (entry.nutrients.fat.map { " · F \(Int($0.rounded()))" } ?? "")
                Text([entry.detail, macros].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer()
            Text("\(Int(entry.nutrients.kcal.rounded()))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
        .contextMenu {
            Button(store.t("Изтрий", "Delete"), systemImage: "trash", role: .destructive) { diary.delete(entry) }
        }
    }
}
