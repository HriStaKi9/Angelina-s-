import SwiftUI
import VisionKit

struct AddFoodView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case plan, search, scan, quick
        var id: String { rawValue }
    }

    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let course: Meal.Course
    let date: Date
    @State private var mode: Mode

    init(course: Meal.Course, date: Date) {
        self.course = course
        self.date = date
        _mode = State(initialValue: .search)
    }

    private var hasPlan: Bool { store.activePlan != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    if hasPlan { Text(store.t("План", "Plan")).tag(Mode.plan) }
                    Text(store.t("Търси", "Search")).tag(Mode.search)
                    Text(store.t("Скенер", "Scan")).tag(Mode.scan)
                    Text(store.t("Бързо", "Quick")).tag(Mode.quick)
                }
                .pickerStyle(.segmented)
                .padding(Theme.Spacing.l)

                switch mode {
                case .plan: PlanMealsList(course: course, date: date)
                case .search: FoodSearchList(course: course, date: date)
                case .scan: BarcodeTab(course: course, date: date)
                case .quick: QuickAddForm(course: course, date: date)
                }
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle(course.title[store.language])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Готово", "Done")) { dismiss() } } }
            .navigationDestination(for: FoodItem.self) { FoodAmountView(food: $0, course: course, date: date) }
        }
        .onAppear { if hasPlan { mode = .plan } }
    }
}

/// The plan's options for this course; the day's chosen one first. One tap logs a portion.
private struct PlanMealsList: View {
    @Environment(ProfileStore.self) private var store
    @Environment(FoodDiaryStore.self) private var diary
    @Environment(WeekMenuStore.self) private var menus
    let course: Meal.Course
    let date: Date
    @State private var portion = 1.0

    var body: some View {
        if let plan = store.activePlan {
            let chosen = menus.menu(for: plan, weekday: TrainingProgram.mondayBasedWeekday(of: date))
            let chosenNumbers: [Int] = course == .snack ? (chosen?.snacks ?? []) : [chosen?.number(for: course)].compactMap { $0 }
            let meals = plan.nutrition.meals(for: course).sorted { a, b in
                (chosenNumbers.contains(a.number) ? 0 : 1, a.number) < (chosenNumbers.contains(b.number) ? 0 : 1, b.number)
            }
            List {
                Section {
                    Stepper(store.t("Порция: × \(portion.formatted())", "Portion: × \(portion.formatted())"), value: $portion, in: 0.5...3, step: 0.5)
                }
                Section(store.t("Варианти от режима", "Options from the plan")) {
                    ForEach(meals) { meal in
                        let logged = diary.isLogged(meal, on: date)
                        Button { diary.logPlanMeal(meal, portion: portion, on: date) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("№\(meal.number) \(meal.name[store.language])").font(.subheadline.weight(.semibold))
                                        if chosenNumbers.contains(meal.number) { Tag(text: store.t("по меню", "on menu"), tint: plan.accentColor) }
                                    }
                                    Text("≈ \(meal.kcal.text) kcal · \(meal.protein.text) \(store.t("г протеин", "g protein"))")
                                        .font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: logged ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(logged ? Theme.Palette.sage : plan.accentColor)
                            }
                            .foregroundStyle(Theme.Palette.ink)
                        }
                        .sensoryFeedback(.success, trigger: logged)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// Recents and built-in basics instantly; Open Food Facts on submit.
private struct FoodSearchList: View {
    @Environment(ProfileStore.self) private var store
    @Environment(FoodDiaryStore.self) private var diary
    let course: Meal.Course
    let date: Date
    @State private var query = ""
    @State private var online: [FoodItem] = []
    @State private var isSearching = false
    @State private var onlineError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.inkSecondary)
                    TextField(store.t("Храна или марка", "Food or brand"), text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await searchOnline() } }
                        .autocorrectionDisabled()
                }
                if !query.isEmpty {
                    Button { Task { await searchOnline() } } label: {
                        Label(store.t("Търси в Open Food Facts", "Search Open Food Facts"), systemImage: "globe")
                    }
                }
            }
            if query.isEmpty, !diary.recents.isEmpty {
                Section(store.t("Последни", "Recent")) { ForEach(diary.recents) { foodRow($0) } }
            }
            let basics = BasicFoods.search(query)
            if !basics.isEmpty {
                Section(store.t("Основни храни (≈ на 100 г)", "Basic foods (≈ per 100 g)")) { ForEach(basics) { foodRow($0) } }
            }
            if isSearching {
                Section { HStack { ProgressView(); Text(store.t("Търсене…", "Searching…")) } }
            } else if let onlineError {
                Section { Text(onlineError).foregroundStyle(Theme.Palette.apricot) }
            } else if !online.isEmpty {
                Section("Open Food Facts") { ForEach(online) { foodRow($0) } }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func foodRow(_ food: FoodItem) -> some View {
        NavigationLink(value: food) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name[store.language]).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Palette.ink)
                Text([food.brand, "\(Int(food.per100.kcal.rounded())) kcal · P \(food.per100.protein.trimmed) \(store.t("г", "g")) / 100 \(store.t("г", "g"))"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    private func searchOnline() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        onlineError = nil
        defer { isSearching = false }
        do {
            online = try await OpenFoodFacts.search(term)
            if online.isEmpty { onlineError = store.t("Няма резултати.", "No results.") }
        } catch {
            onlineError = store.t("Търсенето не успя – провери интернета.", "Search failed – check your connection.")
        }
    }
}

/// Camera barcode scanner (VisionKit) with a manual barcode field as fallback.
private struct BarcodeTab: View {
    @Environment(ProfileStore.self) private var store
    let course: Meal.Course
    let date: Date
    @State private var code = ""
    @State private var found: FoodItem?
    @State private var status: String?
    @State private var isLoading = false

    private var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if scannerAvailable {
                BarcodeScanner { scanned in
                    guard !isLoading, found == nil else { return }
                    code = scanned
                    Task { await lookup() }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .frame(maxHeight: 320)
            } else {
                Label(store.t("Камерата не е достъпна тук – въведи баркода ръчно.", "Camera scanning isn't available here – type the barcode."),
                      systemImage: "barcode.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            HStack {
                TextField(store.t("Баркод", "Barcode"), text: $code)
                    .keyboardType(.numberPad)
                    .padding(Theme.Spacing.m)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                Button(store.t("Търси", "Look up")) { Task { await lookup() } }
                    .disabled(code.count < 8 || isLoading)
            }
            if isLoading { ProgressView() }
            if let status { Text(status).font(.subheadline).foregroundStyle(Theme.Palette.apricot) }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .navigationDestination(item: $found) { FoodAmountView(food: $0, course: course, date: date) }
    }

    private func lookup() async {
        isLoading = true
        status = nil
        defer { isLoading = false }
        do {
            if let item = try await OpenFoodFacts.product(barcode: code) {
                found = item
            } else {
                status = store.t("Продуктът не е намерен в Open Food Facts.", "Product not found in Open Food Facts.")
            }
        } catch {
            status = store.t("Проверката не успя – провери интернета.", "Lookup failed – check your connection.")
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let value = barcode.payloadStringValue {
                    onScan(value)
                    return
                }
            }
        }
    }
}

/// Manual entry: name plus calories (macros optional).
private struct QuickAddForm: View {
    @Environment(ProfileStore.self) private var store
    @Environment(FoodDiaryStore.self) private var diary
    let course: Meal.Course
    let date: Date
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var saved = 0

    var body: some View {
        Form {
            TextField(store.t("Име (по желание)", "Name (optional)"), text: $name)
            numberRow(store.t("Калории", "Calories"), "kcal", $kcal)
            numberRow(store.t("Протеин", "Protein"), store.t("г", "g"), $protein)
            numberRow(store.t("Въглехидрати", "Carbs"), store.t("г", "g"), $carbs)
            numberRow(store.t("Мазнини", "Fat"), store.t("г", "g"), $fat)
            Button(store.t("Добави", "Add")) {
                diary.add(DiaryEntry(day: FoodDiaryStore.dayKey(date), course: course,
                                     name: name.isEmpty ? Localized(bg: "Бързо добавяне", en: "Quick add") : Localized(bg: name, en: name),
                                     detail: nil, nutrients: Nutrients(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs, fat: fat)))
                name = ""; kcal = nil; protein = nil; carbs = nil; fat = nil
                saved += 1
            }
            .disabled((kcal ?? 0) <= 0)
        }
        .scrollContentBackground(.hidden)
        .sensoryFeedback(.success, trigger: saved)
    }

    private func numberRow(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(Theme.Palette.inkSecondary)
        }
    }
}

/// Pick the amount in grams (or portions) and see the nutrition before adding.
struct FoodAmountView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(FoodDiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss
    let food: FoodItem
    let course: Meal.Course
    let date: Date
    @State private var grams: Double?

    private var amount: Double { grams ?? food.portion ?? 100 }

    var body: some View {
        let n = food.nutrients(grams: amount)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name[store.language]).font(.cardTitle)
                    if let brand = food.brand { Text(brand).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary) }
                }
            }
            Section(store.t("Количество", "Amount")) {
                HStack {
                    TextField("100", value: $grams, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    Text(store.t("г", "g")).foregroundStyle(Theme.Palette.inkSecondary)
                }
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(quickAmounts, id: \.self) { value in
                        Button("\(value.trimmed)") { grams = value }
                            .buttonStyle(.bordered)
                    }
                }
            }
            Section(store.t("Хранителни стойности", "Nutrition")) {
                row("kcal", n.kcal, "")
                row(store.t("Протеин", "Protein"), n.protein, store.t("г", "g"))
                if let c = n.carbs { row(store.t("Въглехидрати", "Carbs"), c, store.t("г", "g")) }
                if let f = n.fat { row(store.t("Мазнини", "Fat"), f, store.t("г", "g")) }
            }
            Button(store.t("Добави в дневника", "Add to diary")) {
                diary.add(DiaryEntry(day: FoodDiaryStore.dayKey(date), course: course, name: food.name,
                                     detail: "\(amount.trimmed) \(store.t("г", "g"))" + (food.brand.map { " · \($0)" } ?? ""),
                                     nutrients: n, food: food, grams: amount))
                dismiss()
            }
            .disabled(amount <= 0)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var quickAmounts: [Double] {
        var values: [Double] = [50, 100, 150, 200]
        if let portion = food.portion, !values.contains(portion) { values.insert(portion, at: 0) }
        return Array(values.prefix(4))
    }

    private func row(_ title: String, _ value: Double, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)").monospacedDigit()
        }
    }
}
