import Combine
import Foundation
import SwiftUI

// MARK: - Data Models

struct DashboardActivity: Identifiable {
    let id = UUID()
    let description: String
    let timestamp: Date
    let type: ActivityType

    enum ActivityType {
        case sensingStart, sensingStop, deviceConnect, deviceDisconnect,
             antennaAdded, antennaRemoved, pairingAdded, pairingRemoved, error

        var color: Color {
            switch self {
            case .sensingStart, .deviceConnect, .antennaAdded, .pairingAdded:
                return .green
            case .sensingStop, .deviceDisconnect, .antennaRemoved, .pairingRemoved:
                return .orange
            case .error:
                return .red
            }
        }
    }

    var icon: String {
        switch type {
        case .sensingStart: return "play.circle.fill"
        case .sensingStop: return "stop.circle.fill"
        case .deviceConnect: return "iphone.and.arrow.forward"
        case .deviceDisconnect: return "iphone.slash"
        case .antennaAdded: return "plus.circle.fill"
        case .antennaRemoved: return "minus.circle.fill"
        case .pairingAdded: return "link.circle.fill"
        case .pairingRemoved: return "link.circle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }
}

// MARK: - ViewModel

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var antennaCount = 0
    @Published var pairedDeviceCount = 0
    @Published var connectedDeviceCount = 0
    @Published var isSensingActive = false
    @Published var sensingStatus = "停止中"
    @Published var recentActivities: [DashboardActivity] = []

    // DI対応: 必要なUseCaseを直接注入
    private let sensingControlUsecase: SensingControlUsecase
    private let connectionUsecase: ConnectionManagementUsecase
    private var cancellables = Set<AnyCancellable>()

    var connectionStatus: StatusRow.SystemStatus {
        if pairedDeviceCount == 0 {
            return .warning
        } else if connectedDeviceCount == pairedDeviceCount {
            return .success
        } else if connectedDeviceCount > 0 {
            return .warning
        } else {
            return .error
        }
    }

    init(
        sensingControlUsecase: SensingControlUsecase? = nil,
        connectionUsecase: ConnectionManagementUsecase? = nil
    ) {
        let nearbyRepository = NearbyRepository()
        let defaultConnectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase(nearbyRepository: nearbyRepository)

        self.connectionUsecase = defaultConnectionUsecase
        self.sensingControlUsecase =
            sensingControlUsecase ?? SensingControlUsecase(connectionUsecase: defaultConnectionUsecase)

        setupObservers()
        refreshStatus()
        loadRecentActivities()
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        sensingControlUsecase.$isSensingControlActive
            .assign(to: &$isSensingActive)

        sensingControlUsecase.$sensingStatus
            .assign(to: &$sensingStatus)

        connectionUsecase.$connectedEndpoints
            .map { $0.count }
            .assign(to: &$connectedDeviceCount)
    }

    // MARK: - Status Management

    func refreshStatus() {
        loadAntennaCount()
        loadPairedDeviceCount()
        updateConnectionStatus()
    }

    private func loadAntennaCount() {
        if let data = UserDefaults.standard.data(forKey: "FieldAntennaConfiguration") {
            let decoder = JSONDecoder()
            if let antennas = try? decoder.decode([AntennaInfo].self, from: data) {
                antennaCount = antennas.count
            }
        }
    }

    private func loadPairedDeviceCount() {
        if let data = UserDefaults.standard.data(forKey: "AntennaPairings") {
            let decoder = JSONDecoder()
            if let pairings = try? decoder.decode([AntennaPairing].self, from: data) {
                pairedDeviceCount = pairings.count
            }
        }
    }

    private func updateConnectionStatus() {
        // ConnectionUsecaseから最新の接続状態を取得
        connectedDeviceCount = connectionUsecase.connectedEndpoints.count
    }

    // MARK: - Activity Management

    func addActivity(_ description: String, type: DashboardActivity.ActivityType) {
        let activity = DashboardActivity(
            description: description,
            timestamp: Date(),
            type: type
        )

        recentActivities.insert(activity, at: 0)

        // 最大20件まで保持
        if recentActivities.count > 20 {
            recentActivities.removeLast()
        }

        saveRecentActivities()
    }

    func clearActivity() {
        recentActivities.removeAll()
        saveRecentActivities()
    }

    private func saveRecentActivities() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(recentActivities) {
            UserDefaults.standard.set(encoded, forKey: "RecentSystemActivities")
        }
    }

    private func loadRecentActivities() {
        if let data = UserDefaults.standard.data(forKey: "RecentSystemActivities") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([DashboardActivity].self, from: data) {
                recentActivities = decoded
            }
        }

        // デモ用の初期データ
        if recentActivities.isEmpty {
            addDemoActivities()
        }
    }

    private func addDemoActivities() {
        addActivity("システムが初期化されました", type: .sensingStart)
        addActivity("アンテナ設定が読み込まれました", type: .antennaAdded)
        addActivity("端末ペアリング設定が確認されました", type: .pairingAdded)
    }

    // MARK: - System Statistics

    func getSystemStatistics() -> SystemStatistics {
        SystemStatistics(
            totalAntennas: antennaCount,
            pairedDevices: pairedDeviceCount,
            connectedDevices: connectedDeviceCount,
            isSensingActive: isSensingActive,
            uptime: getSystemUptime(),
            totalActivities: recentActivities.count
        )
    }

    private func getSystemUptime() -> TimeInterval {
        // アプリの起動時間を取得（簡易実装）
        Date().timeIntervalSince(Date().addingTimeInterval(-3600))  // 仮の1時間
    }
}

// MARK: - Statistics Model

struct SystemStatistics {
    let totalAntennas: Int
    let pairedDevices: Int
    let connectedDevices: Int
    let isSensingActive: Bool
    let uptime: TimeInterval
    let totalActivities: Int

    var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = Int(uptime.truncatingRemainder(dividingBy: 3600)) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    var connectionRate: Double {
        guard pairedDevices > 0 else { return 0 }
        return Double(connectedDevices) / Double(pairedDevices)
    }
}

// MARK: - Activity Extensions

extension DashboardActivity: Codable {
    enum CodingKeys: String, CodingKey {
        case description, timestamp, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decode(String.self, forKey: .description)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        let typeString = try container.decode(String.self, forKey: .type)
        type = ActivityType.from(string: typeString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(type.rawValue, forKey: .type)
    }
}

extension DashboardActivity.ActivityType {
    var rawValue: String {
        switch self {
        case .sensingStart: return "sensingStart"
        case .sensingStop: return "sensingStop"
        case .deviceConnect: return "deviceConnect"
        case .deviceDisconnect: return "deviceDisconnect"
        case .antennaAdded: return "antennaAdded"
        case .antennaRemoved: return "antennaRemoved"
        case .pairingAdded: return "pairingAdded"
        case .pairingRemoved: return "pairingRemoved"
        case .error: return "error"
        }
    }

    static func from(string: String) -> DashboardActivity.ActivityType {
        switch string {
        case "sensingStart": return .sensingStart
        case "sensingStop": return .sensingStop
        case "deviceConnect": return .deviceConnect
        case "deviceDisconnect": return .deviceDisconnect
        case "antennaAdded": return .antennaAdded
        case "antennaRemoved": return .antennaRemoved
        case "pairingAdded": return .pairingAdded
        case "pairingRemoved": return .pairingRemoved
        case "error": return .error
        default: return .error
        }
    }
}
