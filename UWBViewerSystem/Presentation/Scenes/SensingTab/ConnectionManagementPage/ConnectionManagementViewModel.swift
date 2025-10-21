import Combine
import Foundation
import SwiftUI

// MARK: - Data Models

struct ConnectionDeviceInfo: Identifiable {
    let id: String
    let name: String
    let connectionTime: Date
    let lastMessageTime: Date
    let isConnected: Bool

    var formattedConnectionTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self.connectionTime)
    }

    var formattedLastMessage: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self.lastMessageTime)
    }
}

struct ConnectionMessage: Identifiable {
    let id: String
    let content: String
    let deviceName: String
    let timestamp: Date
    let isOutgoing: Bool

    init(content: String, deviceName: String, timestamp: Date = Date(), isOutgoing: Bool = false) {
        self.id = UUID().uuidString
        self.content = content
        self.deviceName = deviceName
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self.timestamp)
    }
}

// MARK: - ViewModel

@MainActor
class ConnectionManagementViewModel: ObservableObject {
    @Published var isAdvertising = false
    @Published var isDiscovering = false
    @Published var connectedDevices: [ConnectionDeviceInfo] = []
    @Published var messageHistory: [ConnectionMessage] = []
    @Published var uptime = "00:00:00"
    @Published var totalConnections = 0
    @Published var activeConnections = 0
    @Published var totalMessages = 0
    @Published var dataTransferred: Int64 = 0

    private var uptimeTimer: Timer?
    private var startTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // DI対応: 必要なUseCaseとRepositoryを直接注入
    private let connectionUsecase: ConnectionManagementUsecase
    private let preferenceRepository: PreferenceRepositoryProtocol

    var formattedDataTransferred: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: self.dataTransferred)
    }

    init(
        connectionUsecase: ConnectionManagementUsecase? = nil,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.connectionUsecase =
            connectionUsecase ?? ConnectionManagementUsecase.shared
        self.preferenceRepository = preferenceRepository
        self.setupObservers()
        self.loadStatistics()
    }

    deinit {
        uptimeTimer?.invalidate()
    }

    private func setupObservers() {
        // 直接注入されたUsecaseからの状態を監視
        self.connectionUsecase.$isAdvertising
            .assign(to: &self.$isAdvertising)

        self.connectionUsecase.$connectedEndpoints
            .map { endpoints in
                endpoints.map { endpointId in
                    ConnectionDeviceInfo(
                        id: endpointId,
                        name: "Android-\(endpointId.suffix(4))",
                        connectionTime: Date(),
                        lastMessageTime: Date(),
                        isConnected: true
                    )
                }
            }
            .assign(to: &self.$connectedDevices)

        self.connectionUsecase.$connectedEndpoints
            .map { $0.count }
            .assign(to: &self.$activeConnections)
    }

    // MARK: - Connection Control

    func initializeConnection() {
        self.startUptimeTimer()
        self.loadStatistics()
    }

    func toggleAdvertising() {
        if self.isAdvertising {
            self.connectionUsecase.stopAdvertising()
        } else {
            self.connectionUsecase.startAdvertising()
            self.startTime = Date()
        }
    }

    func startDiscovery() {
        self.isDiscovering = true
        self.connectionUsecase.startDiscovery()

        // 5秒後に自動停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.isDiscovering = false
        }
    }

    func refreshDevices() {
        // デバイス一覧を更新
        // HomeViewModelから最新の接続情報を取得
    }

    func disconnectDevice(_ device: ConnectionDeviceInfo) {
        self.connectionUsecase.disconnectFromDevice(endpointId: device.id)

        // メッセージ履歴に切断ログを追加
        let disconnectMessage = ConnectionMessage(
            content: "\(device.name) が切断されました",
            deviceName: "System",
            isOutgoing: false
        )
        self.messageHistory.append(disconnectMessage)
        self.totalMessages += 1
    }

    func disconnectAll() {
        self.connectionUsecase.disconnectAll()

        let disconnectAllMessage = ConnectionMessage(
            content: "全ての端末が切断されました",
            deviceName: "System",
            isOutgoing: false
        )
        self.messageHistory.append(disconnectAllMessage)
        self.totalMessages += 1
    }

    // MARK: - Messaging

    func sendMessage(_ content: String) {
        guard !content.isEmpty && !self.connectedDevices.isEmpty else { return }

        // 全ての接続端末にメッセージを送信
        for device in self.connectedDevices {
            self.connectionUsecase.sendMessageToDevice(content, to: device.id)
        }

        // メッセージ履歴に追加
        let outgoingMessage = ConnectionMessage(
            content: content,
            deviceName: "Mac",
            isOutgoing: true
        )
        self.messageHistory.append(outgoingMessage)
        self.totalMessages += 1

        self.saveStatistics()
    }

    func clearMessages() {
        self.messageHistory.removeAll()
    }

    // MARK: - Statistics

    private func startUptimeTimer() {
        self.startTime = Date()
        self.uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUptime()
            }
        }
    }

    private func updateUptime() {
        guard let startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(elapsed) % 60
        self.uptime = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func saveStatistics() {
        let statistics = [
            "totalConnections": totalConnections,
            "totalMessages": totalMessages,
            "dataTransferred": Int(dataTransferred),
        ]

        self.preferenceRepository.saveConnectionStatistics(statistics)
    }

    private func loadStatistics() {
        if let statistics = preferenceRepository.loadConnectionStatistics() {
            self.totalConnections = statistics["totalConnections"] as? Int ?? 0
            self.totalMessages = statistics["totalMessages"] as? Int ?? 0
            self.dataTransferred = Int64(statistics["dataTransferred"] as? Int ?? 0)
        }
    }

    // MARK: - Device Management

    func getDeviceStatistics() -> DeviceStatistics {
        DeviceStatistics(
            totalDevices: self.connectedDevices.count,
            activeDevices: self.connectedDevices.filter { $0.isConnected }.count,
            averageConnectionTime: self.calculateAverageConnectionTime(),
            messagesSent: self.messageHistory.filter { $0.isOutgoing }.count,
            messagesReceived: self.messageHistory.filter { !$0.isOutgoing }.count
        )
    }

    private func calculateAverageConnectionTime() -> TimeInterval {
        guard !self.connectedDevices.isEmpty else { return 0 }

        let totalTime = self.connectedDevices.reduce(0.0) { result, device in
            result + Date().timeIntervalSince(device.connectionTime)
        }

        return totalTime / Double(self.connectedDevices.count)
    }
}

// MARK: - Statistics Model

struct DeviceStatistics {
    let totalDevices: Int
    let activeDevices: Int
    let averageConnectionTime: TimeInterval
    let messagesSent: Int
    let messagesReceived: Int

    var formattedAverageConnectionTime: String {
        let minutes = Int(averageConnectionTime) / 60
        let seconds = Int(averageConnectionTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
