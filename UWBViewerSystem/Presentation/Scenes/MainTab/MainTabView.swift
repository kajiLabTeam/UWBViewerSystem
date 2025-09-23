import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SensingView()
                .tabItem {
                    Label("センシング", systemImage: "waveform.path.ecg")
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
