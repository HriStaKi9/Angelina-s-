import SwiftUI

struct MealLibraryView: View {
    @Environment(ProfileStore.self) private var store
    let plan: NutritionPlan
    @State private var course: Meal.Course

    init(plan: NutritionPlan, initialCourse: Meal.Course) {
        self.plan = plan
        _course = State(initialValue: initialCourse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Picker(store.t("Група", "Course"), selection: $course) {
                    ForEach(Meal.Course.allCases) { Text($0.pluralTitle[store.language]).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, Theme.Spacing.s)

                ForEach(plan.meals(for: course)) { meal in
                    NavigationLink(value: meal) { MealRow(meal: meal) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.l)
            .animation(.snappy, value: course)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Рецепти", "Recipes"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
    }
}

struct MealDetailView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(WeekMenuStore.self) private var menus
    let meal: Meal
    /// Ingredients ticked off while cooking or shopping; resets when leaving the screen.
    @State private var checked: Set<Int> = []

    private var lang: ContentLanguage { store.language }
    private var accent: Color { store.activePlan?.accentColor ?? Theme.Palette.berry }

    /// Weekdays in the user's week that use this meal.
    private var scheduledDays: [Int] {
        guard let plan = store.activePlan else { return [] }
        return menus.week(for: plan).filter { day in
            switch meal.course {
            case .breakfast: day.breakfast == meal.number
            case .lunch: day.lunch == meal.number
            case .dinner: day.dinner == meal.number
            case .snack: day.snacks.contains(meal.number)
            }
        }
        .map(\.weekday)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                ingredients
                if let steps = meal.steps {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: store.t("Приготвяне", "Preparation"))
                        Card {
                            Text(steps[lang])
                                .font(.body)
                                .foregroundStyle(Theme.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Label("\(meal.course.title[lang]) · №\(meal.number)", systemImage: meal.course.systemImage)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: Capsule())
                Spacer()
            }
            Text(meal.name[lang])
                .font(.system(.title2, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.xl) {
                stat(meal.kcal.text, "kcal")
                stat("\(meal.protein.text) \(store.t("г", "g"))", store.t("протеин", "protein"))
            }
            if !scheduledDays.isEmpty {
                Text(store.t("В моята седмица: ", "In my week: ") + scheduledDays.map(dayName).joined(separator: ", "))
                    .font(.caption)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        )
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Продукти", "Ingredients"),
                          subtitle: store.t("Докосни, за да отметнеш", "Tap to tick off"))
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { index, item in
                        Button {
                            if checked.contains(index) { checked.remove(index) } else { checked.insert(index) }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(index) ? Theme.Palette.sage : Theme.Palette.hairline)
                                    .font(.title3)
                                Text(item[lang])
                                    .font(.body)
                                    .foregroundStyle(checked.contains(index) ? Theme.Palette.inkSecondary : Theme.Palette.ink)
                                    .strikethrough(checked.contains(index))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("≈ \(value)").font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(caption).font(.caption).opacity(0.85)
        }
    }

    private func dayName(_ weekday: Int) -> String {
        let bg = ["пн", "вт", "ср", "чт", "пт", "сб", "нд"]
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (lang == .bg ? bg : en)[weekday - 1]
    }
}
