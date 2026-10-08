import SwiftUI

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var store
    @State private var draft = UserProfile()
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable { case welcome, plan, goal, location, level }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                progressBar
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.m)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    switch step {
                    case .welcome: welcome
                    case .plan: planStep
                    case .goal: goalStep
                    case .location: locationStep
                    case .level: levelStep
                    }
                }
                .padding(Theme.Spacing.xl)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(Theme.Spacing.xl)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ZStack {
                Circle().fill(Theme.Gradients.hero).frame(width: 96, height: 96)
                Image(systemName: "leaf.fill").font(.system(size: 40)).foregroundStyle(.white)
            }
            .padding(.top, Theme.Spacing.xxl)

            Text("Angelina's\nNutrition")
                .font(.displayTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text("Eat well, train smart. Your eating plan shapes every workout, at the gym or at home.")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("What should we call you?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                TextField("Your name", text: $draft.name)
                    .textContentType(.givenName)
                    .padding(Theme.Spacing.l)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
            }
            .padding(.top, Theme.Spacing.l)
        }
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            stepHeader("Do you have a plan?", "Pick your coach-written eating and training plan, or let the app build one from your goal.")
            ForEach(PlanLibrary.shared.plans) { plan in
                PlanChoiceCard(plan: plan, isSelected: draft.planID == plan.id) { draft.planID = plan.id }
            }
            ChoiceCard(title: "No plan yet", subtitle: "Answer a few questions and get a generated plan",
                       systemImage: "wand.and.stars", isSelected: draft.planID == nil, tint: Theme.Palette.lavender) {
                draft.planID = nil
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            stepHeader("What's your goal?", "This sets your eating plan and how you train.")
            ForEach(FitnessGoal.allCases) { goal in
                ChoiceCard(title: goal.title, subtitle: goal.subtitle, systemImage: goal.systemImage,
                           isSelected: draft.goal == goal) { draft.goal = goal }
            }
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            stepHeader("Where do you train?", "We'll only suggest exercises you can actually do.")
            ForEach(TrainingLocation.allCases) { location in
                ChoiceCard(title: location.title,
                           subtitle: location == .gym ? "Full access to machines, cables and free weights" : "Bodyweight plus whatever you have at home",
                           systemImage: location.systemImage,
                           isSelected: draft.location == location) { draft.location = location }
            }
            if draft.location == .home {
                Text("What do you have at home?")
                    .font(.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, Theme.Spacing.m)
                HomeEquipmentPicker(selection: $draft.homeEquipment)
            }
        }
        .animation(.snappy, value: draft.location)
    }

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            stepHeader("Your experience", "We'll match exercise difficulty to you.")
            ForEach(Exercise.Level.allCases, id: \.self) { level in
                ChoiceCard(title: level.title, subtitle: Self.levelSubtitle(level),
                           systemImage: Self.levelIcon(level), isSelected: draft.level == level,
                           tint: Theme.Palette.sage) { draft.level = level }
            }
            Text("Workouts per week")
                .font(.cardTitle)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, Theme.Spacing.m)
            SessionsPicker(value: $draft.sessionsPerWeek)
        }
    }

    // MARK: Chrome

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1..<Step.allCases.count, id: \.self) { index in
                Capsule()
                    .fill(index <= step.rawValue ? Theme.Palette.berry : Theme.Palette.surfaceMuted)
                    .frame(height: 6)
            }
        }
        .animation(.snappy, value: step)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.m) {
            if step != .welcome {
                Button { go(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 54, height: 54)
                        .foregroundStyle(Theme.Palette.ink)
                        .background(Theme.Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
                .accessibilityLabel("Back")
            }
            Button(isLastStep ? "Start my plan" : "Continue") {
                if isLastStep {
                    if draft.planID != nil { draft.programStart = TrainingProgram.mondayOfWeek(containing: .now) }
                    store.profile = draft
                    store.hasCompletedOnboarding = true
                } else {
                    go(1)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// With a personal plan, the goal/location/level questions don't apply.
    private var isLastStep: Bool { step == .level || (step == .plan && draft.planID != nil) }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.snappy) { step = next }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.displayTitle).foregroundStyle(Theme.Palette.ink)
            Text(subtitle).font(.body).foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    static func levelSubtitle(_ level: Exercise.Level) -> String {
        switch level {
        case .beginner: "New to training or coming back after a break"
        case .intermediate: "Training regularly for 6+ months"
        case .expert: "Confident with complex lifts"
        }
    }

    static func levelIcon(_ level: Exercise.Level) -> String {
        switch level {
        case .beginner: "leaf"
        case .intermediate: "bolt"
        case .expert: "trophy"
        }
    }
}

struct HomeEquipmentPicker: View {
    @Binding var selection: Set<Exercise.Equipment>

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            ForEach(Exercise.Equipment.homeOptions) { item in
                Chip(title: item.title, systemImage: item.systemImage, isSelected: selection.contains(item)) {
                    if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                }
            }
        }
    }
}

struct SessionsPicker: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(2...6, id: \.self) { count in
                Button { value = count } label: {
                    Text("\(count)")
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(value == count ? Theme.Palette.onAccent : Theme.Palette.ink)
                        .background(value == count ? Theme.Palette.sage : Theme.Palette.surfaceMuted,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) workouts per week")
            }
        }
        .animation(.snappy(duration: 0.2), value: value)
    }
}
