import SwiftUI

@main
struct AngelinasNutritionApp: App {
    @State private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profileStore)
                .tint(Theme.Palette.berry)
        }
    }
}

struct RootView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.hasCompletedOnboarding)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max.fill") { TodayView() }
            Tab("Workouts", systemImage: "figure.strengthtraining.functional") { ExerciseListView() }
            Tab("Nutrition", systemImage: "leaf.fill") { NutritionView() }
            Tab("Profile", systemImage: "person.crop.circle.fill") { ProfileView() }
        }
    }
}
