import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var store
    @Environment(AssistantStore.self) private var assistant
    @Environment(AccountStore.self) private var account
    @Environment(HealthService.self) private var health
    @State private var healthError: String?
    @State private var confirmReset = false
    @State private var showAccount = false
    @State private var showImport = false
    @State private var showRecommended = false
    @State private var showProviders = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    Button { showAccount = true } label: {
                        HStack {
                            Label(account.session?.email ?? "Sign in or create an account",
                                  systemImage: account.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(account.isSignedIn ? "Backed up \(account.lastSynced?.formatted(.relative(presentation: .named)) ?? "not yet")." : "Back up your data and restore it on a new phone.")
                }
                Section {
                    TextField("Name", text: $store.profile.name)
                }
                Section {
                    Picker("App look", selection: Binding(get: { store.profile.theme }, set: { store.profile.theme = $0 })) {
                        Text("Automatic").tag(ThemeVariant?.none)
                        Text("Rose").tag(Optional(ThemeVariant.rose))
                        Text("Steel").tag(Optional(ThemeVariant.steel))
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(ThemeVariant.allCases) { variant in
                            ThemeSwatch(variant: variant, isActive: store.theme == variant)
                        }
                    }
                } header: {
                    Text("App look")
                } footer: {
                    Text("Automatic uses Steel for a man's plan (Hristomir) and Rose otherwise. The app icon changes with it.")
                }
                Section {
                    Picker("Active plan", selection: Binding(get: { store.profile.planID }, set: { store.selectPlan($0) })) {
                        Text("None – generic plan").tag(String?.none)
                        ForEach(PlanLibrary.shared.plans) { plan in
                            Text(plan.name[store.language]).tag(Optional(plan.id))
                        }
                    }
                    Button("Import plan from PDF…", systemImage: "doc.badge.plus") { showImport = true }
                    if let plan = store.activePlan, PlanLibrary.shared.isImported(plan.id) {
                        Button(PlanLibrary.shared.isBundled(plan.id) ? "Restore the coach's original plan" : "Delete this imported plan",
                               role: .destructive) {
                            let bundled = PlanLibrary.shared.isBundled(plan.id)
                            PlanLibrary.shared.removeImported(id: plan.id)
                            if !bundled { store.selectPlan(nil) }
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
                Section {
                    Picker("Goal", selection: $store.profile.goal) {
                        ForEach(FitnessGoal.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Button("See the recommended training program", systemImage: "wand.and.stars") { showRecommended = true }
                } header: {
                    Text("Goal")
                } footer: {
                    if let running = store.profile.recommendedProgram {
                        Text(running.goal == store.profile.goal
                             ? "Training with: \(running.program.title.en)."
                             : "Your goal changed – the active program is still \(running.program.title.en). Open the recommendation to switch.")
                    } else {
                        Text("Each goal gets its own program, built for your equipment and level.")
                    }
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
                Section {
                    if !health.isAvailable {
                        Text("Apple Health isn't available on this device.").foregroundStyle(Theme.Palette.inkSecondary)
                    } else if !health.isConnected {
                        Button("Connect Apple Health", systemImage: "heart.fill") {
                            Task {
                                do { try await health.connect() } catch { healthError = error.localizedDescription }
                            }
                        }
                    } else {
                        Label("Connected", systemImage: "heart.fill").foregroundStyle(Theme.Palette.berry)
                        Toggle("Save measurements to Health", isOn: Binding(get: { health.writeMeasurements }, set: { health.writeMeasurements = $0 }))
                        Toggle("Save food diary to Health", isOn: Binding(get: { health.writeDiary }, set: { health.writeDiary = $0 }))
                        Toggle("Save workouts to Health", isOn: Binding(get: { health.writeWorkouts }, set: { health.writeWorkouts = $0 }))
                        Button("Stop using Apple Health", role: .destructive) { health.disconnect() }
                    }
                    if let healthError { Text(healthError).font(.caption).foregroundStyle(Theme.Palette.berry) }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Reads steps, active energy, distance, weight, body fat and waist; saves what you choose. Change exactly what's shared any time in Settings → Health → Data Access & Devices.")
                }
                Section {
                    FlowLayout(spacing: Theme.Spacing.s) {
                        ForEach(HomeGear.allCases) { item in
                            Chip(title: item.title[store.language], systemImage: item.systemImage, isSelected: store.gear.contains(item)) {
                                var gear = store.gear
                                if gear.contains(item) { gear.remove(item) } else { gear.insert(item) }
                                store.gear = gear
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                } header: {
                    Text("My equipment")
                } footer: {
                    Text("Used by Workouts → More exercises.")
                }
                Section {
                    Button { showProviders = true } label: {
                        HStack {
                            Label(assistant.provider.map { "\($0.title) · \(assistant.model(for: $0))" } ?? "Choose Claude, ChatGPT or Gemini",
                                  systemImage: assistant.provider?.systemImage ?? "sparkles")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }
                } header: {
                    Text("AI assistant")
                } footer: {
                    Text("Connect your Claude, ChatGPT or Gemini account with an API key; chats are billed to that account. Importing plans from PDF uses Claude.")
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
            .sheet(isPresented: $showAccount) { AccountView() }
            .sheet(isPresented: $showImport) { ImportPlanView() }
            .sheet(isPresented: $showProviders) {
                NavigationStack {
                    ProviderPickerView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showProviders = false } } }
                }
            }
            .sheet(isPresented: $showRecommended) {
                NavigationStack {
                    RecommendedProgramsView(goal: store.profile.goal, sessions: store.profile.sessionsPerWeek)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRecommended = false } } }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Reset your profile and go back to onboarding?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.reset() }
            }
        }
    }
}

/// Small preview of a theme's colors and icon.
private struct ThemeSwatch: View {
    let variant: ThemeVariant
    let isActive: Bool

    private var colors: [Color] {
        variant == .steel
            ? [Color(red: 0.12, green: 0.31, blue: 0.53), Color(red: 0.18, green: 0.42, blue: 0.69), Color(red: 0.14, green: 0.52, blue: 0.44)]
            : [Color(red: 0.85, green: 0.34, blue: 0.43), Color(red: 0.91, green: 0.57, blue: 0.35), Color(red: 0.37, green: 0.58, blue: 0.47)]
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { Circle().fill(colors[$0]).frame(width: 18, height: 18) }
            }
            Text(variant == .steel ? "Steel" : "Rose").font(.caption.weight(isActive ? .bold : .regular))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
        .background(isActive ? Theme.Palette.surfaceMuted : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}
