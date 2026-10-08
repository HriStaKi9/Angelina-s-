import SwiftUI

/// Daily calorie needs (Mifflin-St Jeor), pre-filled from the plan's body stats.
struct CalorieCalculatorView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(FoodDiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var body_: BodyStats

    private static let changes: [(Double, Localized)] = [
        (-0.75, Localized(bg: "Отслабване −0.75 кг/седм.", en: "Lose 0.75 kg/week")),
        (-0.5, Localized(bg: "Отслабване −0.5 кг/седм.", en: "Lose 0.5 kg/week")),
        (-0.25, Localized(bg: "Леко −0.25 кг/седм.", en: "Lose 0.25 kg/week")),
        (0, Localized(bg: "Поддържане", en: "Maintain")),
        (0.25, Localized(bg: "Качване +0.25 кг/седм.", en: "Gain 0.25 kg/week")),
    ]

    init() {
        _body_ = State(initialValue: BodyStats(sex: .female, weight: 65, height: 168, age: 30, activity: 1.375, weeklyChange: 0, breastfeeding: false))
    }

    private var plan: PersonalPlan? { store.activePlan }
    private var lang: ContentLanguage { store.language }

    var body: some View {
        let result = CalorieCalculator.calculate(body_)
        // A plan's protein range wins over the generic 2 g/kg.
        let protein = plan.map { ($0.nutrition.protein.lower + $0.nutrition.protein.upper) / 2 } ?? result.protein
        let fat = result.fat
        let carbs = max(0, Int((result.target - Double(protein) * 4 - Double(fat) * 9) / 4))
        NavigationStack {
            Form {
                Section(store.t("Данни", "About you")) {
                    Picker(store.t("Пол", "Sex"), selection: $body_.sex) {
                        Text(store.t("Жена", "Female")).tag(BodyStats.Sex.female)
                        Text(store.t("Мъж", "Male")).tag(BodyStats.Sex.male)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Stepper(store.t("Възраст: \(body_.age)", "Age: \(body_.age)"), value: $body_.age, in: 16...90)
                    numberRow(store.t("Ръст", "Height"), store.t("см", "cm"), $body_.height)
                    numberRow(store.t("Тегло", "Weight"), store.t("кг", "kg"), $body_.weight)
                    if body_.sex == .female {
                        Toggle(store.t("Кърмя", "Breastfeeding"), isOn: $body_.breastfeeding)
                    }
                }
                Section(store.t("Активност и цел", "Activity & goal")) {
                    Picker(store.t("Активност", "Activity"), selection: $body_.activity) {
                        ForEach(CalorieCalculator.activityLevels, id: \.value) { Text($0.title[lang]).tag($0.value) }
                    }
                    .pickerStyle(.navigationLink)
                    Picker(store.t("Цел", "Goal"), selection: $body_.weeklyChange) {
                        ForEach(Self.changes, id: \.0) { Text($0.1[lang]).tag($0.0) }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section(store.t("Резултат", "Result")) {
                    row(store.t("Разход в покой (BMR)", "Resting (BMR)"), "\(Int(result.bmr)) kcal")
                    row(store.t("Поддръжка", "Maintenance"), "\(Int(result.maintenance)) kcal")
                    HStack {
                        Text(store.t("Дневна цел", "Daily target")).font(.headline)
                        Spacer()
                        Text("\(Int(result.target.rounded())) kcal")
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(plan?.accentColor ?? Theme.Palette.berry)
                    }
                    row(store.t("Протеин", "Protein"), "\(protein) \(store.t("г", "g"))")
                    row(store.t("Мазнини (30%)", "Fat (30%)"), "\(fat) \(store.t("г", "g"))")
                    row(store.t("Въглехидрати", "Carbs"), "\(carbs) \(store.t("г", "g"))")
                    if result.hitFloor {
                        Text(body_.breastfeeding
                             ? store.t("Вдигнато до 1800 kcal – по време на кърмене не се слиза под това.", "Raised to 1800 kcal – the plan never goes below this while breastfeeding.")
                             : store.t("Вдигнато до безопасния минимум.", "Raised to a safe minimum."))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.apricot)
                    }
                }
                Section {
                    Button(store.t("Използвай като дневна цел", "Use as my daily goal")) {
                        diary.setGoal(CalorieGoal(kcal: Int(result.target.rounded()), protein: protein, carbs: carbs, fat: fat), for: plan)
                        dismiss()
                    }
                    if diary.hasCustomGoal(for: plan), let plan {
                        Button(store.t("Върни целта от режима (\(plan.nutrition.kcal.text) kcal)", "Back to the plan's target (\(plan.nutrition.kcal.text) kcal)")) {
                            diary.setGoal(nil, for: plan)
                            dismiss()
                        }
                    }
                } footer: {
                    Text(plan != nil
                         ? store.t("Целта от режима е сметната от треньора и има предимство. Калкулаторът е ориентир – напр. когато теглото се промени или спре кърменето.",
                                   "The coach's target takes priority. Use the calculator as a guide, e.g. when weight changes or breastfeeding stops.")
                         : store.t("Формула Mifflin-St Jeor. Ориентир, не медицински съвет.", "Mifflin-St Jeor formula. A guide, not medical advice."))
                }
            }
            .navigationTitle(store.t("Калориен калкулатор", "Calorie calculator"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Затвори", "Close")) { dismiss() } } }
        }
        .onAppear { if let stats = plan?.body { body_ = stats } }
    }

    private func numberRow(_ title: String, _ unit: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(Theme.Palette.inkSecondary)
        }
    }
}
