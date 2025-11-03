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

@MainActor
class SettingsViewModel: BaseViewModel {
    @Published var selectedSettingDetail: SettingsDetailType?

    let appVersion = "1.0.0"

    func selectSettingDetail(_ detail: SettingsDetailType) {
        self.selectedSettingDetail = detail
    }

    func showHelp() {
        print("ヘルプ画面を表示")
    }

    func showTerms() {
        print("利用規約を表示")
    }
}
