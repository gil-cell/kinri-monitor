import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("ダッシュボード", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(0)

            NavigationStack {
                LoanInputView()
            }
            .tabItem {
                Label("借入条件", systemImage: "pencil.and.list.clipboard")
            }
            .tag(1)

            NavigationStack {
                SimulationView()
            }
            .tabItem {
                Label("シミュレーション", systemImage: "chart.bar.xaxis.ascending")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
            .tag(3)
        }
        .tint(.blue)
    }
}
