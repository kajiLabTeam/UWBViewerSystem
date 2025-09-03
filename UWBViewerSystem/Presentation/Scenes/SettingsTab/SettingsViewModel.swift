import Foundation
import SwiftUI

enum SettingsDetailType: String, CaseIterable {
    case antennaSettings = "アンテナ配置設定"
    case pairingSettings = "端末ペアリング"
    case connectionManagement = "接続管理"
    case dataExport = "データエクスポート"
    case cacheManagement = "キャッシュクリア"
    case advertiserSettings = "広告専用画面"
    case help = "ヘルプ"
    case terms = "利用規約"
}

class SettingsViewModel: ObservableObject {
    @Published var autoBackupEnabled: Bool = false
    @Published var highAccuracyMode: Bool = false
    @Published var notificationsEnabled: Bool = true
    @Published var selectedSettingDetail: SettingsDetailType?

    let appVersion = "1.0.0"

    init() {
        loadSettings()
    }

    private func loadSettings() {
        autoBackupEnabled = UserDefaults.standard.bool(forKey: "autoBackupEnabled")
        highAccuracyMode = UserDefaults.standard.bool(forKey: "highAccuracyMode")
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }

    func exportData() {
        print("データエクスポート機能を実行")
    }

    func clearCache() {
        print("キャッシュクリア機能を実行")
    }

    func showHelp() {
        print("ヘルプ画面を表示")
    }

    func showTerms() {
        print("利用規約を表示")
    }

    func selectSettingDetail(_ detail: SettingsDetailType) {
        selectedSettingDetail = detail
    }
}
