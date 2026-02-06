import Foundation

class SettingsViewModel: ObservableObject {
    let appVersion = "1.0.0"

    // デバッグ設定
    @Published var skipCalibration: Bool {
        didSet {
            UserDefaults.standard.set(self.skipCalibration, forKey: "skipCalibration")
        }
    }

    init() {
        // UserDefaultsから設定を読み込み
        self.skipCalibration = UserDefaults.standard.bool(forKey: "skipCalibration")
    }

    func showHelp() {
        print("ヘルプ画面を表示")
    }

    func showTerms() {
        print("利用規約を表示")
    }
}
