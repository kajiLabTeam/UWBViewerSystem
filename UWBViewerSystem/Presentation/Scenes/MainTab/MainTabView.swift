import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var router: NavigationRouterModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: self.$selectedTab) {
            DataDisplayView()
                .tabItem {
                    Label("取得データ", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)

            FloorMapView()
                .tabItem {
                    Label("フロアマップ", systemImage: "map")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(2)
        }
        #if os(macOS)
        .tabViewStyle(.automatic)
        #endif
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        #if os(macOS)
        .frame(minWidth: 800)
        #endif
    }
}

#Preview {
    MainTabView()
        .environmentObject(NavigationRouterModel())
}
