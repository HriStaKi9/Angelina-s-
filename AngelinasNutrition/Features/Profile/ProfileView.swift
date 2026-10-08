import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var store
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $store.profile.name)
                }
                Section {
                    Picker("Active plan", selection: Binding(get: { store.profile.planID }, set: { store.selectPlan($0) })) {
                        Text("None – generic plan").tag(String?.none)
                        ForEach(PlanLibrary.shared.plans) { plan in
                            Text(plan.name[store.language]).tag(Optional(plan.id))
                        }
                    }
                    if store.activePlan != nil {
                        DatePicker("Program started", selection: Binding(
                            get: { store.programStart },
                            set: { store.profile.programStart = TrainingProgram.mondayOfWeek(containing: $0) }
                        ), displayedComponents: .date)
                        Picker("Plan language", selection: $store.language) {
                            ForEach(ContentLanguage.allCases) { Text($0.title).tag($0) }
                        }
                    }
                } header: {
                    Text("Personal plan")
                } footer: {
                    if store.activePlan != nil {
                        Text("The start date sets the program week (\"Week N\") and which A/B rotation applies.")
                    }
                }
                Section("Goal") {
                    Picker("Goal", selection: $store.profile.goal) {
                        ForEach(FitnessGoal.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Training") {
                    Picker("Where", selection: $store.profile.location) {
                        ForEach(TrainingLocation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Level", selection: $store.profile.level) {
                        ForEach(Exercise.Level.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Stepper("Workouts per week: \(store.profile.sessionsPerWeek)",
                            value: $store.profile.sessionsPerWeek, in: 2...6)
                }
                if store.profile.location == .home {
                    Section("Home equipment") {
                        HomeEquipmentPicker(selection: $store.profile.homeEquipment)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                }
                Section {
                    Button("Start over", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Exercise data: free-exercise-db (public domain).")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .confirmationDialog("Reset your profile and go back to onboarding?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.reset() }
            }
        }
    }
}
