import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("マーケット", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(0)

            NavigationStack {
                SimulationView()
            }
            .tabItem {
                Label("シミュレーション", systemImage: "function")
            }
            .tag(1)

            NavigationStack {
                CalendarView()
            }
            .tabItem {
                Label("カレンダー", systemImage: "calendar")
            }
            .tag(2)

            NavigationStack {
                LoanManagementView()
            }
            .tabItem {
                Label("管理", systemImage: "tray.full.fill")
            }
            .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
            .tag(4)
        }
        .tint(Theme.accent)
    }
}
