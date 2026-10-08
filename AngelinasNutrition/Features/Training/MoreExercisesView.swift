import SwiftUI

enum MuscleArea: String, CaseIterable, Identifiable, Hashable {
    case legs, back, chest, arms, core

    var id: String { rawValue }

    var title: Localized {
        switch self {
        case .legs: Localized(bg: "Седалище и крака", en: "Glutes & legs")
        case .back: Localized(bg: "Гръб", en: "Back")
        case .chest: Localized(bg: "Гърди и рамене", en: "Chest & shoulders")
        case .arms: Localized(bg: "Ръце", en: "Arms")
        case .core: Localized(bg: "Корем", en: "Core")
        }
    }

    var systemImage: String {
        switch self {
        case .legs: "figure.strengthtraining.functional"
        case .back: "figure.rower"
        case .chest: "figure.arms.open"
        case .arms: "dumbbell.fill"
        case .core: "figure.core.training"
        }
    }

    func contains(_ muscle: Exercise.Muscle) -> Bool {
        switch self {
        case .legs: [.quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors].contains(muscle)
        case .back: [.lats, .middleBack, .lowerBack, .traps].contains(muscle)
        case .chest: [.chest, .shoulders].contains(muscle)
        case .arms: [.biceps, .triceps, .forearms].contains(muscle)
        case .core: muscle == .abdominals || muscle == .neck
        }
    }
}

/// Exercises beyond the program that fit the user's equipment, with a power-rack collection up top.
struct MoreExercisesView: View {
    @Environment(ProfileStore.self) private var store
    @State private var query = ""

    private var lang: ContentLanguage { store.language }
    private var plan: PersonalPlan? { store.activePlan }
    private var tint: Color { plan?.accentColor ?? Theme.Palette.berry }

    /// Training exercises (no stretches, strongman or Olympic lifts) doable with the chosen gear.
    private var available: [Exercise] {
        let gear = store.gear
        let avoid = Set(plan?.training.extraExercises?.avoidCategories ?? [])
        let allowed: Set<Exercise.Category> = [.strength, .powerlifting, .plyometrics]
        return ExerciseLibrary.shared.exercises.filter {
            allowed.contains($0.category) && !avoid.contains($0.category) && $0.isDoable(with: gear)
        }
    }

    var body: some View {
        let available = available
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                gearPicker
                if let note = plan?.training.extraExercises?.note {
                    Callout(title: store.t("Преди да добавиш", "Before you add one"), items: [note[lang]], isWarning: true)
                }
                if query.isEmpty {
                    if store.gear.contains(.powerRack) || store.gear.contains(.gym) { powerRack(available) }
                    ForEach(MuscleArea.allCases) { area in
                        let list = available.filter { $0.primaryMuscles.contains(where: area.contains) }
                        if !list.isEmpty { areaSection(area, list) }
                    }
                } else {
                    let results = available.filter { $0.name.localizedCaseInsensitiveContains(query) }
                    SectionHeader(title: store.t("\(results.count) резултата", "\(results.count) results"))
                    ForEach(results) { exercise in row(exercise) }
                }
                Text(store.t("Имената на упражненията са от базата данни (на английски).",
                             "Exercise names come from the exercise database."))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .searchable(text: $query, prompt: store.t("Търси упражнение", "Search exercises"))
        .navigationTitle(store.t("Още упражнения", "More exercises"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if plan != nil { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } } }
    }

    private var gearPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: store.t("Моето оборудване", "My equipment"),
                          subtitle: store.t("Показваме само каквото можеш да направиш", "Only shows what you can actually do"))
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(HomeGear.allCases) { item in
                    Chip(title: item.title[lang], systemImage: item.systemImage, isSelected: store.gear.contains(item), tint: tint) {
                        var gear = store.gear
                        if gear.contains(item) { gear.remove(item) } else { gear.insert(item) }
                        store.gear = gear
                    }
                }
            }
        }
    }

    private func powerRack(_ available: [Exercise]) -> some View {
        let doable = Set(available.map(\.id))
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("С рака", "Power rack"),
                          subtitle: store.t("Най-доброто, което можеш да правиш с рак и щанга", "The best of what a rack and barbell can do"))
            ForEach(PowerRackCollection.groups) { group in
                let exercises = group.exerciseIDs.filter(doable.contains).compactMap(ExerciseLibrary.shared.exercise(id:))
                if !exercises.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(group.title[lang]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.m) {
                                ForEach(exercises) { exercise in
                                    NavigationLink(value: exercise) { card(exercise) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func areaSection(_ area: MuscleArea, _ list: [Exercise]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label(area.title[lang], systemImage: area.systemImage)
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                NavigationLink(value: WorkoutRoute.muscleArea(area)) {
                    Text(store.t("Всички (\(list.count))", "All (\(list.count))"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
            // Beginner-friendly, compound moves first.
            ForEach(Self.featured(list).prefix(4)) { exercise in row(exercise) }
        }
    }

    static func featured(_ list: [Exercise]) -> [Exercise] {
        list.sorted {
            ($0.level, $0.isCompound ? 0 : 1, $0.name) < ($1.level, $1.isCompound ? 0 : 1, $1.name)
        }
    }

    private func card(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ExerciseImage(url: exercise.thumbnailURL, cornerRadius: Theme.Radius.medium)
                .frame(width: 150, height: 110)
            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(2, reservesSpace: true)
            Tag(text: exercise.level.title, tint: Theme.Palette.sage)
        }
        .frame(width: 150, alignment: .leading)
    }

    private func row(_ exercise: Exercise) -> some View {
        NavigationLink(value: exercise) {
            HStack(spacing: Theme.Spacing.m) {
                ExerciseImage(url: exercise.thumbnailURL, cornerRadius: Theme.Radius.small)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name).font(.cardTitle).foregroundStyle(Theme.Palette.ink).lineLimit(2)
                    Text("\(exercise.primaryMuscles.map(\.title).joined(separator: ", ")) · \(exercise.resolvedEquipment.title) · \(exercise.level.title)")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary)
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
        }
        .buttonStyle(.plain)
    }
}

/// Every doable exercise for one muscle area.
struct MuscleAreaListView: View {
    @Environment(ProfileStore.self) private var store
    let area: MuscleArea

    var body: some View {
        let avoid = Set(store.activePlan?.training.extraExercises?.avoidCategories ?? [])
        let list = MoreExercisesView.featured(ExerciseLibrary.shared.exercises.filter {
            [.strength, .powerlifting, .plyometrics].contains($0.category) && !avoid.contains($0.category)
                && $0.isDoable(with: store.gear) && $0.primaryMuscles.contains(where: area.contains)
        })
        List(list) { exercise in
            NavigationLink(value: exercise) { ExerciseRow(exercise: exercise) }
                .listRowBackground(Theme.Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(area.title[store.language])
        .navigationBarTitleDisplayMode(.inline)
    }
}
