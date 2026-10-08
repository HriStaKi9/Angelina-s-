import SwiftUI

@main
struct AngelinasNutritionApp: App {
    @State private var profileStore = ProfileStore()
    @State private var trainingLog = TrainingLog()
    @State private var weekMenus = WeekMenuStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profileStore)
                .environment(trainingLog)
                .environment(weekMenus)
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
    enum TabID: String { case today, workouts, nutrition, progress, profile }

    @State private var selection: TabID = Self.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) { TodayView() }
            Tab("Workouts", systemImage: "figure.strengthtraining.functional", value: .workouts) { WorkoutsView() }
            Tab("Nutrition", systemImage: "leaf.fill", value: .nutrition) { NutritionView() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) { ProgressTabView() }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: .profile) { ProfileView() }
        }
    }

    /// Debug builds accept `-tab <id>` so simulator screenshots can open any tab.
    private static var initialTab: TabID {
        #if DEBUG
        UserDefaults.standard.string(forKey: "tab").flatMap(TabID.init(rawValue:)) ?? .today
        #else
        .today
        #endif
    }
}
