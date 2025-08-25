import SwiftUI
import Foundation
import Combine

@MainActor
class SensingManagementViewModel: ObservableObject {
    @Published var antennaDevices: [AntennaDevice] = []
    @Published var realtimeData: [RealtimeDataPoint] = []
    @Published var isSensingActive = false
    @Published var isPaused = false
    @Published var sensingDuration = "00:00:00"
    @Published var dataPointCount = 0
    @Published var currentFileName = ""
    @Published var sensingFileName = ""
    @Published var sampleRate = 10
    @Published var autoSave = true
    
    private var homeViewModel = HomeViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    private var sensingStartTime: Date?
    private var durationTimer: Timer?
    
    var canStartSensing: Bool {
        !sensingFileName.isEmpty && 
        antennaDevices.filter { $0.connectionStatus == .connected }.count >= 3
    }
    
    var hasDataToView: Bool {
        dataPointCount > 0 || !realtimeData.isEmpty
    }
    
    func initialize() {
        loadAntennaDevices()
        setupObservers()
        generateDefaultFileName()
    }
    
    private func loadAntennaDevices() {
        // 保存されたアンテナ位置データから読み込み
        if let data = UserDefaults.standard.data(forKey: "AntennaPositions"),
           let positions = try? JSONDecoder().decode([AntennaPositionData].self, from: data) {
            
            antennaDevices = positions.map { position in
                AntennaDevice(
                    id: position.deviceId,
                    name: position.deviceName,
                    connectionStatus: .connected, // 実際の実装では実際のステータスを取得
                    rssi: Int.random(in: -60...(-40)),
                    batteryLevel: Int.random(in: 70...100),
                    dataRate: sampleRate,
                    position: position.realWorldPosition,
                    lastUpdate: Date()
                )
            }
        }
    }
    
    private func setupObservers() {
        // HomeViewModelからの状態を監視
        homeViewModel.$isSensingControlActive
            .assign(to: &$isSensingActive)
        
        // HomeViewModelからのリアルタイムデータを監視（モック実装）
        realtimeData = []
        
        // データポイント数を監視
        $realtimeData
            .map { $0.count }
            .assign(to: &$dataPointCount)
    }
    
    private func generateDefaultFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        sensingFileName = "sensing_\(formatter.string(from: Date()))"
    }
    
    func refreshAntennaStatus() {
        // 実際の実装ではデバイスから最新の状態を取得
        for index in antennaDevices.indices {
            antennaDevices[index].rssi = Int.random(in: -60...(-40))
            antennaDevices[index].batteryLevel = max(0, antennaDevices[index].batteryLevel - Int.random(in: 0...2))
            antennaDevices[index].lastUpdate = Date()
            
            // バッテリーレベルに基づいて接続状態を更新
            if antennaDevices[index].batteryLevel < 10 {
                antennaDevices[index].connectionStatus = .disconnected
            } else if antennaDevices[index].batteryLevel < 30 {
                antennaDevices[index].connectionStatus = .unstable
            } else {
                antennaDevices[index].connectionStatus = .connected
            }
        }
    }
    
    func startSensing() {
        guard canStartSensing else { return }
        
        currentFileName = sensingFileName
        sensingStartTime = Date()
        
        // HomeViewModelでセンシング開始
        homeViewModel.startRemoteSensing(fileName: currentFileName)
        
        // 継続時間タイマーを開始
        startDurationTimer()
        
        // データレートを更新
        for index in antennaDevices.indices {
            antennaDevices[index].dataRate = sampleRate
        }
        
        // 次回のファイル名を生成
        generateDefaultFileName()
    }
    
    func stopSensing() {
        homeViewModel.stopRemoteSensing()
        stopDurationTimer()
        
        // センシング完了時の処理
        if autoSave {
            saveCurrentSession()
        }
        
        sensingStartTime = nil
        currentFileName = ""
        isPaused = false
    }
    
    func pauseSensing() {
        isPaused = true
        homeViewModel.pauseRemoteSensing()
        stopDurationTimer()
    }
    
    func resumeSensing() {
        isPaused = false
        homeViewModel.resumeRemoteSensing()
        startDurationTimer()
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSensingDuration()
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    private func updateSensingDuration() {
        guard let startTime = sensingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) / 60 % 60
        let seconds = Int(elapsed) % 60
        
        sensingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func saveCurrentSession() {
        guard let startTime = sensingStartTime else { return }
        
        let session = SensingSession(
            fileName: currentFileName,
            startTime: startTime,
            dataPoints: dataPointCount
        )
        
        // 最近のセッションに追加
        var recentSessions: [SensingSession] = []
        if let data = UserDefaults.standard.data(forKey: "RecentSensingSessions"),
           let decoded = try? JSONDecoder().decode([SensingSession].self, from: data) {
            recentSessions = decoded
        }
        
        recentSessions.insert(session, at: 0)
        if recentSessions.count > 10 {
            recentSessions.removeLast()
        }
        
        if let encoded = try? JSONEncoder().encode(recentSessions) {
            UserDefaults.standard.set(encoded, forKey: "RecentSensingSessions")
        }
    }
}

// MARK: - Data Models
struct AntennaDevice: Identifiable {
    let id: String
    let name: String
    var connectionStatus: DeviceConnectionStatus
    var rssi: Int
    var batteryLevel: Int
    var dataRate: Int
    let position: RealWorldPosition
    var lastUpdate: Date?
    
    var rssiColor: Color {
        if rssi > -50 { return .green }
        if rssi > -70 { return .orange }
        return .red
    }
    
    var batteryColor: Color {
        if batteryLevel > 50 { return .green }
        if batteryLevel > 20 { return .orange }
        return .red
    }
}

enum DeviceConnectionStatus {
    case connected
    case disconnected
    case unstable
    
    var displayName: String {
        switch self {
        case .connected: return "接続済み"
        case .disconnected: return "未接続"
        case .unstable: return "不安定"
        }
    }
    
    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .red
        case .unstable: return .orange
        }
    }
}

struct RealtimeDataPoint: Identifiable {
    let id: String
    let deviceName: String
    let distance: Double
    let rssi: Int
    let timestamp: Date
}

