import SwiftUI

/// "My week": the day's chosen meals, each swappable for any of the plan's options.
struct WeekMenuSection: View {
    @Environment(ProfileStore.self) private var store
    @Environment(WeekMenuStore.self) private var menus
    let plan: PersonalPlan
    @State private var weekday = TrainingProgram.mondayBasedWeekday(of: .now)
    @State private var picking: Meal.Course?

    private var nutrition: NutritionPlan { plan.nutrition }
    private var lang: ContentLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: store.t("Моята седмица", "My week"),
                              subtitle: store.t("Смени всяко хранене с друг вариант от режима", "Swap any meal for another option from the plan"))
                if menus.isCustomized(plan) {
                    Button(store.t("Примерна", "Sample")) { menus.resetWeek(for: plan) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(plan.accentColor)
                        .accessibilityLabel(store.t("Върни примерната седмица", "Reset to the sample week"))
                }
            }
            WeekdayPicker(selection: $weekday, tint: plan.accentColor)

            if let day = menus.menu(for: plan, weekday: weekday) {
                ForEach([Meal.Course.breakfast, .lunch, .dinner]) { course in
                    if let number = day.number(for: course), let meal = nutrition.meal(course, number) {
                        slot(meal: meal) { picking = course }
                    }
                }
                ForEach(day.snacks, id: \.self) { number in
                    if let meal = nutrition.meal(.snack, number) {
                        slot(meal: meal, removable: true) { menus.toggleSnack(number, weekday: weekday, plan: plan) }
                    }
                }
                Button { picking = .snack } label: {
                    Label(store.t("Добави междинно", "Add a snack"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.sage)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.Palette.sage.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
                .buttonStyle(.plain)

                let totals = day.totals(in: nutrition)
                HStack {
                    Text(store.t("Общо", "Total")).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("≈ \(totals.kcal.text) kcal · \(totals.protein.text) \(store.t("г протеин", "g protein"))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, Theme.Spacing.xs)
                targetHint(totals.kcal)
            }
        }
        .sheet(item: $picking) { course in
            MealPickerSheet(plan: plan, course: course, weekday: weekday)
        }
    }

    private func slot(meal: Meal, removable: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            NavigationLink(value: meal) { MealRow(meal: meal) }
                .buttonStyle(.plain)
            Button(action: action) {
                Image(systemName: removable ? "minus.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(removable ? Theme.Palette.inkSecondary : plan.accentColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removable ? store.t("Махни", "Remove") : store.t("Смени", "Swap"))
        }
    }

    /// Nudges toward the plan's daily range without blocking any choice.
    @ViewBuilder
    private func targetHint(_ kcal: ApproxRange) -> some View {
        let target = nutrition.kcal
        let mid = (kcal.lower + kcal.upper) / 2
        if mid < target.lower - 150 {
            Text(store.t("Под дневната цел от \(target.text) kcal – добави междинно хранене.",
                         "Below the \(target.text) kcal daily target – add a snack."))
                .font(.footnote).foregroundStyle(Theme.Palette.apricot)
        } else if mid > target.upper + 150 {
            Text(store.t("Над дневната цел от \(target.text) kcal.", "Above the \(target.text) kcal daily target."))
                .font(.footnote).foregroundStyle(Theme.Palette.apricot)
        }
    }
}

struct MealPickerSheet: View {
    @Environment(ProfileStore.self) private var store
    @Environment(WeekMenuStore.self) private var menus
    @Environment(\.dismiss) private var dismiss
    let plan: PersonalPlan
    let course: Meal.Course
    let weekday: Int

    private var lang: ContentLanguage { store.language }

    var body: some View {
        let day = menus.menu(for: plan, weekday: weekday)
        NavigationStack {
            List(plan.nutrition.meals(for: course)) { meal in
                let isChosen = course == .snack ? day?.snacks.contains(meal.number) == true : day?.number(for: course) == meal.number
                Button {
                    if course == .snack {
                        menus.toggleSnack(meal.number, weekday: weekday, plan: plan)
                    } else {
                        menus.choose(course, number: meal.number, weekday: weekday, plan: plan)
                    }
                    dismiss()
                } label: {
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        Text("№\(meal.number)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(plan.accentColor)
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meal.name[lang]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                            Text("≈ \(meal.kcal.text) kcal · \(meal.protein.text) \(store.t("г протеин", "g protein"))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.inkSecondary)
                            Text(meal.ingredients.map { $0[lang] }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isChosen ? plan.accentColor : Theme.Palette.hairline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(course.title[lang])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Затвори", "Close")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Weekly shopping list: everything needed for the chosen meals on the chosen days.
struct GroceryListView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(WeekMenuStore.self) private var menus

    private var lang: ContentLanguage { store.language }
    private var plans: [PersonalPlan] { PlanLibrary.shared.plans }

    private var includedPlanIDs: Set<String> {
        menus.groceryPlanIDs ?? Set([store.activePlan?.id].compactMap { $0 })
    }

    private var list: GroceryList {
        let weeks = plans.filter { includedPlanIDs.contains($0.id) }.map { plan in
            (plan.nutrition, menus.week(for: plan).filter { menus.groceryDays.contains($0.weekday) })
        }
        return GroceryCalculator.list(for: weeks, catalog: .shared)
    }

    var body: some View {
        let list = list
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                settings
                summary(list)
                ForEach(GroceryItem.Aisle.allCases, id: \.self) { aisle in
                    let lines = list.lines(in: aisle)
                    if !lines.isEmpty { aisleSection(aisle, lines: lines) }
                }
                if !list.toTaste.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: store.t("По вкус", "To taste"), subtitle: store.t("Без точно количество в режима", "No set amount in the plan"))
                        Card {
                            Text(list.toTaste.map { $0[lang] }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(store.t("Количествата са сурово тегло (ориз, паста, булгур и овес – сухи) и са закръглени нагоре.",
                             "Amounts are raw weight (rice, pasta, bulgur and oats dry) and rounded up."))
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Пазаруване", "Groceries"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: GroceryCalculator.text(list, language: lang, title: store.t("Пазаруване", "Groceries"))) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("За кого", "For whom"))
            HStack(spacing: Theme.Spacing.s) {
                ForEach(plans) { plan in
                    Chip(title: plan.name[lang], isSelected: includedPlanIDs.contains(plan.id), tint: plan.accentColor) {
                        var ids = includedPlanIDs
                        if ids.contains(plan.id) { ids.remove(plan.id) } else { ids.insert(plan.id) }
                        menus.groceryPlanIDs = ids
                    }
                }
            }
            SectionHeader(title: store.t("За кои дни", "For which days"))
            DayToggleRow(selection: Binding(get: { menus.groceryDays }, set: { menus.groceryDays = $0 }),
                         tint: store.activePlan?.accentColor ?? Theme.Palette.berry)
        }
    }

    private func summary(_ list: GroceryList) -> some View {
        let done = list.lines.filter { menus.checked.contains($0.id) }.count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(list.lines.count) \(store.t("продукта", "items"))")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(store.t("\(list.mealCount) хранения · \(done) отметнати", "\(list.mealCount) meals · \(done) ticked"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer()
            if done > 0 {
                Button(store.t("Изчисти", "Clear")) { menus.clearChecked() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func aisleSection(_ aisle: GroceryItem.Aisle, lines: [GroceryLine]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label(aisle.title[lang], systemImage: aisle.systemImage)
                .font(.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
            Card(padding: Theme.Spacing.m) {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                        let isChecked = menus.checked.contains(line.id)
                        Button { menus.toggleChecked(line.id) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isChecked ? Theme.Palette.sage : Theme.Palette.hairline)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.item.name[lang])
                                        .font(.body)
                                        .strikethrough(isChecked)
                                        .foregroundStyle(isChecked ? Theme.Palette.inkSecondary : Theme.Palette.ink)
                                    Text(store.t("в \(line.mealCount) хранения", "in \(line.mealCount) meals"))
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.inkSecondary)
                                }
                                Spacer()
                                Text(line.amount(lang))
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(isChecked ? Theme.Palette.inkSecondary : Theme.Palette.ink)
                            }
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Mon–Sun multi-select, used to pick which days the shopping list covers.
struct DayToggleRow: View {
    @Environment(ProfileStore.self) private var store
    @Binding var selection: Set<Int>
    var tint: Color

    private static let bg = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]
    private static let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text((store.language == .bg ? Self.bg : Self.en)[day - 1])
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isOn ? Theme.Palette.onAccent : Theme.Palette.ink)
                        .background(isOn ? tint : Theme.Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Entry card on the Nutrition tab.
struct GroceriesCard: View {
    @Environment(ProfileStore.self) private var store
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "cart.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Пазаруване за седмицата", "Weekly groceries")).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                Text(store.t("Колко да купиш за избраните хранения", "How much to buy for your chosen meals"))
                    .font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
    }
}
