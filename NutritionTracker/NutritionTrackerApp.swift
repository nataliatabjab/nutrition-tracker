import SwiftUI
import SwiftData

@main
struct NutritionTrackerApp: App {
    @StateObject private var goals = GoalStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(goals)
        }
        .modelContainer(for: [Food.self, LogEntry.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
            FoodsView()
                .tabItem { Label("My Foods", systemImage: "fork.knife") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
