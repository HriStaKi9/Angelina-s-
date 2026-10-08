import SwiftUI

struct TodayView: View {
    @Environment(ProfileStore.self) private var store

    private var profile: UserProfile { store.profile }
    private var workout: Workout { WorkoutPlanner(library: .shared).workout(for: profile) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    WorkoutHeroCard(workout: workout, location: profile.location)
                    PlanLinkCard(goal: profile.goal)
                    exerciseSection(title: "Warm-up", subtitle: "Loosen up the muscles you'll train", exercises: workout.warmUp, numbered: false)
                    exerciseSection(title: "Workout", subtitle: workout.prescription.style, exercises: workout.main, numbered: true)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .textCase(.uppercase)
            Text(greeting)
                .font(.displayTitle)
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return profile.firstName.isEmpty ? part : "\(part),\n\(profile.firstName)"
    }

    @ViewBuilder
    private func exerciseSection(title: String, subtitle: String, exercises: [Exercise], numbered: Bool) -> some View {
        if !exercises.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: title, subtitle: subtitle)
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    NavigationLink(value: exercise) {
                        PlannedExerciseRow(
                            exercise: exercise,
                            index: numbered ? index + 1 : nil,
                            detail: numbered ? "\(workout.prescription.sets) × \(workout.prescription.reps) · rest \(workout.prescription.restSeconds)s" : "Hold 20–30s each side"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct WorkoutHeroCard: View {
    let workout: Workout
    let location: TrainingLocation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Label(location.title, systemImage: location.systemImage)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: Capsule())
                Spacer()
                Image(systemName: "figure.strengthtraining.functional")
                    .font(.title2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's session").font(.subheadline.weight(.medium)).opacity(0.85)
                Text(workout.title).font(.system(.title, design: .rounded).weight(.bold))
            }
            HStack(spacing: Theme.Spacing.xl) {
                stat(value: "\(workout.estimatedMinutes)", unit: "min")
                stat(value: "\(workout.main.count)", unit: "exercises")
                stat(value: "\(workout.prescription.sets)×\(workout.prescription.reps)", unit: "sets × reps")
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Gradients.hero, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: Theme.Palette.berry.opacity(0.3), radius: 16, y: 8)
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(unit).font(.caption).opacity(0.85)
        }
    }
}

/// Explains how today's eating plan shapes the workout. Becomes live data once Nutrition ships.
private struct PlanLinkCard: View {
    let goal: FitnessGoal

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: goal.systemImage)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Theme.Palette.sage)
                    .background(Theme.Palette.sage.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan: \(goal.title)").font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    Text(goal.subtitle).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
    }
}

struct PlannedExerciseRow: View {
    let exercise: Exercise
    var index: Int?
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ExerciseImage(url: exercise.thumbnailURL, cornerRadius: Theme.Radius.small)
                .frame(width: 64, height: 64)
                .overlay(alignment: .topLeading) {
                    if let index {
                        Text("\(index)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.Palette.berry, in: Circle())
                            .offset(x: -6, y: -6)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                Text(detail).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
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
