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
        return formatter.string(from: connectionTime)
    }

    var formattedLastMessage: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: lastMessageTime)
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
        return formatter.string(from: timestamp)
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
    private let homeViewModel = HomeViewModel.shared
    private var connectionUsecase: ConnectionManagementUsecase {
        homeViewModel.connectionUsecase
    }

    var formattedDataTransferred: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: dataTransferred)
    }

    init() {
        setupObservers()
    }

    deinit {
        uptimeTimer?.invalidate()
    }

    private func setupObservers() {
        // HomeViewModelからの状態を監視
        connectionUsecase.$isAdvertising
            .assign(to: &$isAdvertising)

        connectionUsecase.$connectedEndpoints
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
            .assign(to: &$connectedDevices)

        connectionUsecase.$connectedEndpoints
            .map { $0.count }
            .assign(to: &$activeConnections)
    }

    // MARK: - Connection Control

    func initializeConnection() {
        startUptimeTimer()
        loadStatistics()
    }

    func toggleAdvertising() {
        if isAdvertising {
            homeViewModel.stopAdvertising()
        } else {
            homeViewModel.startAdvertising()
            startTime = Date()
        }
    }

    func startDiscovery() {
        isDiscovering = true
        homeViewModel.startDiscovery()

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
        homeViewModel.disconnectEndpoint(device.id)

        // メッセージ履歴に切断ログを追加
        let disconnectMessage = ConnectionMessage(
            content: "\(device.name) が切断されました",
            deviceName: "System",
            isOutgoing: false
        )
        messageHistory.append(disconnectMessage)
        totalMessages += 1
    }

    func disconnectAll() {
        for device in connectedDevices {
            homeViewModel.disconnectEndpoint(device.id)
        }

        let disconnectAllMessage = ConnectionMessage(
            content: "全ての端末が切断されました",
            deviceName: "System",
            isOutgoing: false
        )
        messageHistory.append(disconnectAllMessage)
        totalMessages += 1
    }

    // MARK: - Messaging

    func sendMessage(_ content: String) {
        guard !content.isEmpty && !connectedDevices.isEmpty else { return }

        // 全ての接続端末にメッセージを送信
        for device in connectedDevices {
            homeViewModel.sendMessage(content, to: device.id)
        }

        // メッセージ履歴に追加
        let outgoingMessage = ConnectionMessage(
            content: content,
            deviceName: "Mac",
            isOutgoing: true
        )
        messageHistory.append(outgoingMessage)
        totalMessages += 1

        saveStatistics()
    }

    func clearMessages() {
        messageHistory.removeAll()
    }

    // MARK: - Statistics

    private func startUptimeTimer() {
        startTime = Date()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUptime()
            }
        }
    }

    private func updateUptime() {
        guard let startTime = startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(elapsed) % 60
        uptime = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func saveStatistics() {
        let statistics = [
            "totalConnections": totalConnections,
            "totalMessages": totalMessages,
            "dataTransferred": Int(dataTransferred),
        ]

        UserDefaults.standard.set(statistics, forKey: "ConnectionStatistics")
    }

    private func loadStatistics() {
        if let statistics = UserDefaults.standard.dictionary(forKey: "ConnectionStatistics") {
            totalConnections = statistics["totalConnections"] as? Int ?? 0
            totalMessages = statistics["totalMessages"] as? Int ?? 0
            dataTransferred = Int64(statistics["dataTransferred"] as? Int ?? 0)
        }
    }

    // MARK: - Device Management

    func getDeviceStatistics() -> DeviceStatistics {
        DeviceStatistics(
            totalDevices: connectedDevices.count,
            activeDevices: connectedDevices.filter { $0.isConnected }.count,
            averageConnectionTime: calculateAverageConnectionTime(),
            messagesSent: messageHistory.filter { $0.isOutgoing }.count,
            messagesReceived: messageHistory.filter { !$0.isOutgoing }.count
        )
    }

    private func calculateAverageConnectionTime() -> TimeInterval {
        guard !connectedDevices.isEmpty else { return 0 }

        let totalTime = connectedDevices.reduce(0.0) { result, device in
            return result + Date().timeIntervalSince(device.connectionTime)
        }

        return totalTime / Double(connectedDevices.count)
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
