import Foundation
import SwiftUI

struct SensingData: Identifiable {
    let id = UUID()
    let name: String
    let dataPoints: Int
    let createdAt: Date

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: self.createdAt)
    }
}

struct ValidationResult {
    let isValid: Bool
    let message: String
}

class SensingViewModel: ObservableObject {
    @Published var savedSensingData: [SensingData] = []
    @Published var selectedSensingData: SensingData?
    @Published var hasFloorMap: Bool = false
    @Published var hasConnectedDevice: Bool = false

    private let preferenceRepository: PreferenceRepositoryProtocol

    init(preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()) {
        self.preferenceRepository = preferenceRepository
        self.loadSavedData()
        self.checkSystemStatus()
    }

    func loadSavedData() {
        self.savedSensingData = [
            SensingData(name: "測定データ 1", dataPoints: 1250, createdAt: Date().addingTimeInterval(-86400)),
            SensingData(name: "測定データ 2", dataPoints: 890, createdAt: Date().addingTimeInterval(-172800)),
            SensingData(name: "測定データ 3", dataPoints: 2100, createdAt: Date().addingTimeInterval(-259200)),
        ]
    }

    func checkSystemStatus() {
        self.hasFloorMap = self.preferenceRepository.getBool(forKey: "hasFloorMapConfigured")
        self.hasConnectedDevice = self.preferenceRepository.getBool(forKey: "hasDeviceConnected")
    }

    func validateSensingRequirements() -> ValidationResult {
        self.checkSystemStatus()

        if !self.hasFloorMap && !self.hasConnectedDevice {
            return ValidationResult(
                isValid: false,
                message: "センシングを開始するには、フロアマップの設定と端末の接続が必要です。どちらを先に設定しますか？"
            )
        } else if !self.hasFloorMap {
            return ValidationResult(
                isValid: false,
                message: "センシングを開始するには、フロアマップの設定が必要です。"
            )
        } else if !self.hasConnectedDevice {
            return ValidationResult(
                isValid: false,
                message: "センシングを開始するには、端末の接続が必要です。"
            )
        }

        return ValidationResult(isValid: true, message: "")
    }

    func selectSensingData(_ data: SensingData) {
        self.selectedSensingData = data
    }

    func deleteSensingData(_ data: SensingData) {
        self.savedSensingData.removeAll { $0.id == data.id }
        if self.selectedSensingData?.id == data.id {
            self.selectedSensingData = nil
        }
    }
}
