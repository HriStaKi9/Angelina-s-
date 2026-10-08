import SwiftUI

@main
struct AngelinasNutritionApp: App {
    @State private var profileStore = ProfileStore()
    @State private var trainingLog = TrainingLog()
    @State private var weekMenus = WeekMenuStore()
    @State private var assistant = AssistantStore()
    @State private var foodDiary = FoodDiaryStore()
    @State private var account = AccountStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profileStore)
                .environment(trainingLog)
                .environment(weekMenus)
                .environment(assistant)
                .environment(foodDiary)
                .environment(account)
                .onChange(of: scenePhase) { _, phase in
                    // Back up when the app goes to the background, if signed in.
                    guard phase == .background, account.isSignedIn else { return }
                    Task {
                        try? await AccountSync.backUp(account: account, profile: profileStore, log: trainingLog,
                                                      menus: weekMenus, diary: foodDiary)
                    }
                }
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
        #if DEBUG
        // `-debugSheet account|import` opens those screens at launch, for simulator screenshots.
        .sheet(isPresented: .constant(UserDefaults.standard.string(forKey: "debugSheet") != nil)) {
            if UserDefaults.standard.string(forKey: "debugSheet") == "account" { AccountView() } else { ImportPlanView() }
        }
        #endif
    }
}

struct MainTabView: View {
    enum TabID: String { case today, diary, workouts, nutrition, progress }

    @State private var selection: TabID = Self.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) { TodayView() }
            Tab("Diary", systemImage: "fork.knife.circle.fill", value: .diary) { DiaryView() }
            Tab("Workouts", systemImage: "figure.strengthtraining.functional", value: .workouts) { WorkoutsView() }
            Tab("Nutrition", systemImage: "leaf.fill", value: .nutrition) { NutritionView() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) { ProgressTabView() }
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
