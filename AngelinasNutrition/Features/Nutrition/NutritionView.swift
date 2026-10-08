import SwiftUI

/// First pass of the nutrition tab: shows the macro split implied by the goal.
/// Food logging, calorie targets and meal plans arrive in the next milestone.
struct NutritionView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    MacroSplitCard(goal: store.profile.goal)

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: "Coming next", subtitle: "The nutrition toolkit we're building")
                        roadmapRow("Daily calorie & macro targets", "From your body stats and goal", "target")
                        roadmapRow("Food diary", "Search foods and scan barcodes", "barcode.viewfinder")
                        roadmapRow("Angelina's meal plans", "Recipes matched to your plan", "fork.knife")
                        roadmapRow("Water & habits", "Small daily wins", "drop.fill")
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Nutrition")
        }
    }

    private func roadmapRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.Palette.sage)
                .background(Theme.Palette.sage.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer()
        }
    }
}

private struct MacroSplitCard: View {
    let goal: FitnessGoal

    private var split: (protein: Double, carbs: Double, fat: Double) {
        switch goal {
        case .loseFat: (0.35, 0.35, 0.30)
        case .tone: (0.30, 0.40, 0.30)
        case .buildMuscle: (0.30, 0.45, 0.25)
        case .maintain: (0.25, 0.45, 0.30)
        }
    }

    var body: some View {
        Card(padding: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your plate").font(.subheadline.weight(.medium)).foregroundStyle(Theme.Palette.inkSecondary)
                    Text(goal.title).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Theme.Palette.ink)
                }
                GeometryReader { proxy in
                    HStack(spacing: 4) {
                        Capsule().fill(Theme.Palette.berry).frame(width: proxy.size.width * split.protein - 4)
                        Capsule().fill(Theme.Palette.apricot).frame(width: proxy.size.width * split.carbs - 4)
                        Capsule().fill(Theme.Palette.sage)
                    }
                }
                .frame(height: 14)
                HStack {
                    legend("Protein", split.protein, Theme.Palette.berry)
                    Spacer()
                    legend("Carbs", split.carbs, Theme.Palette.apricot)
                    Spacer()
                    legend("Fat", split.fat, Theme.Palette.sage)
                }
            }
        }
    }

    private func legend(_ name: String, _ share: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Text(share, format: .percent).font(.metric).foregroundStyle(Theme.Palette.ink)
        }
    }
}
