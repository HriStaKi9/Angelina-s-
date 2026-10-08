import SwiftUI

enum NutritionRoute: Hashable {
    case groceries
    case library(Meal.Course)
    case about
    case rules
}

struct NutritionView: View {
    @Environment(ProfileStore.self) private var store
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let plan = store.activePlan {
                    PlanNutritionContent(plan: plan)
                } else {
                    GenericNutritionContent()
                }
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle(store.activePlan == nil ? "Nutrition" : store.t("Хранене", "Nutrition"))
            .toolbar {
                if store.activePlan != nil {
                    ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
                }
            }
            .navigationDestination(for: Meal.self) { MealDetailView(meal: $0) }
            #if DEBUG
            // `-openGroceries YES` opens the shopping list directly, for simulator screenshots.
            .onAppear {
                if path.isEmpty, store.activePlan != nil, UserDefaults.standard.bool(forKey: "openGroceries") {
                    path.append(NutritionRoute.groceries)
                }
            }
            #endif
            .navigationDestination(for: NutritionRoute.self) { route in
                if let plan = store.activePlan { destination(route, plan: plan.nutrition) }
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: NutritionRoute, plan: NutritionPlan) -> some View {
        switch route {
        case .groceries:
            GroceryListView()
        case .library(let course):
            MealLibraryView(plan: plan, initialCourse: course)
        case .about:
            PlanGuideView(title: plan.aboutTitle, intro: plan.about + (plan.dayFlow ?? []), sections: [])
        case .rules:
            PlanGuideView(title: Localized(bg: "Правила и бележки", en: "Rules & notes"),
                          sections: plan.sections, adjustments: plan.adjustments, footnote: plan.important)
        }
    }
}

// MARK: - Personal plan

private struct PlanNutritionContent: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan

    private var nutrition: NutritionPlan { plan.nutrition }
    private var lang: ContentLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                NavigationLink(value: NutritionRoute.groceries) { GroceriesCard(tint: plan.accentColor) }
                    .buttonStyle(.plain)
                WeekMenuSection(plan: plan)
                library
                guide
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private var header: some View {
        Card(padding: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.m) {
                    PlanAvatar(plan: plan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name[lang]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                        Text(nutrition.title[lang]).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
                Text(nutrition.goal[lang])
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top) {
                    PlanMetric(value: nutrition.kcal.text, caption: store.t("kcal на ден", "kcal per day"), tint: plan.accentColor)
                    PlanMetric(value: "\(nutrition.protein.text) \(store.t("г", "g"))", caption: store.t("протеин", "protein"), tint: Theme.Palette.sage)
                }
                Divider().overlay(Theme.Palette.hairline)
                VStack(alignment: .leading, spacing: 6) {
                    Label(nutrition.mealsPerDay[lang], systemImage: "fork.knife")
                    Label(nutrition.pace[lang], systemImage: "chart.line.downtrend.xyaxis")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Всички рецепти", "All recipes"),
                          subtitle: store.t("Избери по 1 от всяка група за деня", "Pick one from each group per day"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())], spacing: Theme.Spacing.m) {
                ForEach(Meal.Course.allCases) { course in
                    NavigationLink(value: NutritionRoute.library(course)) {
                        CourseTile(course: course, count: nutrition.meals(for: course).count, tint: plan.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Ръководство", "Guide"))
            NavigationLink(value: NutritionRoute.about) {
                GuideLinkRow(title: nutrition.aboutTitle[lang], systemImage: "function")
            }
            NavigationLink(value: NutritionRoute.rules) {
                GuideLinkRow(title: store.t("Правила и бележки", "Rules & notes"), systemImage: "list.bullet.rectangle")
            }
        }
        .buttonStyle(.plain)
    }
}

struct WeekdayPicker: View {
    @Environment(ProfileStore.self) private var store
    @Binding var selection: Int
    var tint: Color = Theme.Palette.berry

    private static let bg = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]
    private static let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let today = TrainingProgram.mondayBasedWeekday(of: .now)
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = day == selection
                Button { selection = day } label: {
                    VStack(spacing: 4) {
                        Text((store.language == .bg ? Self.bg : Self.en)[day - 1])
                            .font(.caption.weight(.semibold))
                        Circle()
                            .fill(day == today ? (isSelected ? Theme.Palette.onAccent : tint) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.ink)
                    .background(isSelected ? tint : Theme.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

struct MealRow: View {
    @Environment(ProfileStore.self) private var store
    let meal: Meal

    private var tint: Color {
        switch meal.course {
        case .breakfast: Theme.Palette.apricot
        case .lunch: Theme.Palette.berry
        case .dinner: Theme.Palette.lavender
        case .snack: Theme.Palette.sage
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: meal.course.systemImage)
                .font(.title3)
                .frame(width: 48, height: 48)
                .foregroundStyle(tint)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(meal.course.title[store.language]) · №\(meal.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                Text(meal.name[store.language])
                    .font(.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("≈ \(meal.kcal.text) kcal · \(meal.protein.text) \(store.t("г протеин", "g protein"))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
    }
}

private struct CourseTile: View {
    @Environment(ProfileStore.self) private var store
    let course: Meal.Course
    let count: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: course.systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(course.pluralTitle[store.language])
                .font(.cardTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text(store.t("\(count) варианта", "\(count) options"))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.Palette.hairline))
    }
}

// MARK: - No personal plan

private struct GenericNutritionContent: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                MacroSplitCard(goal: store.profile.goal)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: "Personal plans", subtitle: "Pick a coach-written eating and training plan")
                    ForEach(PlanLibrary.shared.plans) { plan in
                        PlanChoiceCard(plan: plan, isSelected: false) { store.selectPlan(plan.id) }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
    }
}

private struct MacroSplitCard: View {
    let goal: FitnessGoal

    private var split: (protein: Double, carbs: Double, fat: Double) {
        switch goal {
        case .loseFat: (0.35, 0.35, 0.30)
        case .tone: (0.30, 0.40, 0.30)
        case .buildMuscle: (0.30, 0.45, 0.25)
        case .maintain: (0.25, 0.45, 0.30)
        }
    }

    var body: some View {
        Card(padding: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your plate").font(.subheadline.weight(.medium)).foregroundStyle(Theme.Palette.inkSecondary)
                    Text(goal.title).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Theme.Palette.ink)
                }
                GeometryReader { proxy in
                    HStack(spacing: 4) {
                        Capsule().fill(Theme.Palette.berry).frame(width: proxy.size.width * split.protein - 4)
                        Capsule().fill(Theme.Palette.apricot).frame(width: proxy.size.width * split.carbs - 4)
                        Capsule().fill(Theme.Palette.sage)
                    }
                }
                .frame(height: 14)
                HStack {
                    legend("Protein", split.protein, Theme.Palette.berry)
                    Spacer()
                    legend("Carbs", split.carbs, Theme.Palette.apricot)
                    Spacer()
                    legend("Fat", split.fat, Theme.Palette.sage)
                }
            }
        }
    }

    private func legend(_ name: String, _ share: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Text(share, format: .percent).font(.metric).foregroundStyle(Theme.Palette.ink)
        }
    }
}
