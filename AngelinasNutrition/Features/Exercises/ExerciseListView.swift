import SwiftUI

struct ExerciseListView: View {
    @Environment(ProfileStore.self) private var store
    @State private var query = ""
    @State private var group: Exercise.MuscleGroup?
    @State private var category: Exercise.Category?
    @State private var onlyMyEquipment = true

    private let library = ExerciseLibrary.shared

    private var results: [Exercise] {
        let base = onlyMyEquipment ? library.available(for: store.profile) : library.exercises
        return base.filter { exercise in
            (group == nil || exercise.primaryMuscles.contains { $0.group == group })
                && (category == nil || exercise.category == category)
                && (query.isEmpty || exercise.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filters
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(results) { exercise in
                        NavigationLink(value: exercise) { ExerciseRow(exercise: exercise) }
                            .listRowBackground(Theme.Palette.surface)
                    }
                } header: {
                    Text("\(results.count) exercises")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Workouts")
            .searchable(text: $query, prompt: "Search exercises")
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Picker("Equipment", selection: $onlyMyEquipment) {
                Text(store.profile.location == .home ? "My home setup" : "My gym").tag(true)
                Text("All exercises").tag(false)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    Chip(title: "All muscles", isSelected: group == nil) { group = nil }
                    ForEach(Exercise.MuscleGroup.allCases) { item in
                        Chip(title: item.title, isSelected: group == item) { group = group == item ? nil : item }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([Exercise.Category.strength, .cardio, .plyometrics, .stretching], id: \.self) { item in
                        Chip(title: item.title, isSelected: category == item, tint: Theme.Palette.sage) {
                            category = category == item ? nil : item
                        }
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ExerciseImage(url: exercise.thumbnailURL, cornerRadius: Theme.Radius.small)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(exercise.primaryMuscles.map(\.title).joined(separator: ", "))
                    Text("·")
                    Text(exercise.resolvedEquipment.title)
                }
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
