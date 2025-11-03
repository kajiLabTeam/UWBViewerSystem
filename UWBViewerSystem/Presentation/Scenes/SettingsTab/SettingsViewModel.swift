import Foundation

class SettingsViewModel: ObservableObject {
    let appVersion = "1.0.0"

    func showHelp() {
        print("ヘルプ画面を表示")
    }

    func showTerms() {
        print("利用規約を表示")
    }
}
