import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @State private var frame = 0

    // The database ships a start and end photo per exercise; flipping between them reads as motion.
    private let timer = Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ExerciseImage(url: exercise.imageURLs.indices.contains(frame) ? exercise.imageURLs[frame] : exercise.thumbnailURL,
                              cornerRadius: Theme.Radius.large)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(exercise.name) demonstration")

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(exercise.name)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.Palette.ink)
                    FlowLayout(spacing: 6) {
                        Tag(text: exercise.level.title, tint: Theme.Palette.sage)
                        Tag(text: exercise.category.title, tint: Theme.Palette.lavender)
                        Tag(text: exercise.resolvedEquipment.title, tint: Theme.Palette.apricot)
                        if let mechanic = exercise.mechanic { Tag(text: mechanic.capitalized) }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        muscleRow("Primary", exercise.primaryMuscles, tint: Theme.Palette.berry)
                        if !exercise.secondaryMuscles.isEmpty {
                            Divider().overlay(Theme.Palette.hairline)
                            muscleRow("Secondary", exercise.secondaryMuscles, tint: Theme.Palette.inkSecondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: "How to do it")
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.Palette.berry)
                                .frame(width: 28, height: 28)
                                .background(Theme.Palette.berry.opacity(0.12), in: Circle())
                            Text(step)
                                .font(.body)
                                .foregroundStyle(Theme.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            guard exercise.imageURLs.count > 1 else { return }
            frame = (frame + 1) % exercise.imageURLs.count
        }
    }

    private func muscleRow(_ title: String, _ muscles: [Exercise.Muscle], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary).textCase(.uppercase)
            FlowLayout(spacing: 6) {
                ForEach(muscles) { Tag(text: $0.title, tint: tint) }
            }
        }
    }
}
