import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: self.$selectedTab) {
            FloorMapView()
                .tabItem {
                    Label("フロアマップ", systemImage: "map")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(1)
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
