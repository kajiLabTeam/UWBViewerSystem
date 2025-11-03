import SwiftUI

// iOS用のenum値を列挙型で定義
enum NavigationBarTitleDisplayModeWrapper {
    case large
    case inline
    case automatic
}

extension View {
    /// iOS専用のnavigationBarTitleDisplayModeを条件付きで適用する
    /// macOSでは何もしない
    @ViewBuilder
    func navigationBarTitleDisplayModeIfAvailable(
        _ displayMode: NavigationBarTitleDisplayModeWrapper
    ) -> some View {
        #if os(iOS)
            switch displayMode {
            case .large:
                self.navigationBarTitleDisplayMode(.large)
            case .inline:
                self.navigationBarTitleDisplayMode(.inline)
            case .automatic:
                self.navigationBarTitleDisplayMode(.automatic)
            }
        #else
            self
        #endif
    }
}
