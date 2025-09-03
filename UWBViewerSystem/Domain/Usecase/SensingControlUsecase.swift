import Foundation
import Combine

// MARK: - センシング制御 Usecase

@MainActor
public class SensingControlUsecase: ObservableObject {
    @Published var sensingStatus: String = "停止中"
    @Published var isSensingControlActive = false
    @Published var sensingFileName: String = ""
    @Published var currentSensingFileName: String = ""
    @Published var sensingDuration = "00:00:00"
    @Published var dataPointCount = 0
    @Published var isPaused = false
    @Published var sampleRate = 10
    @Published var autoSave = true
    
    private let connectionUsecase: ConnectionManagementUsecase
    private let dataRepository: DataRepositoryProtocol
    private var sensingStartTime: Date?
    private var durationTimer: Timer?
    
    public init(connectionUsecase: ConnectionManagementUsecase, dataRepository: DataRepositoryProtocol = DataRepository()) {
        self.connectionUsecase = connectionUsecase
        self.dataRepository = dataRepository
    }
    
    // MARK: - Sensing Control
    
    public func startRemoteSensing(fileName: String) {
        print("=== センシング開始処理開始 ===")
        print("ファイル名: \(fileName)")
        
        guard !fileName.isEmpty else {
            sensingStatus = "ファイル名を入力してください"
            print("エラー: ファイル名が空です")
            return
        }
        
        let hasConnected = connectionUsecase.hasConnectedDevices()
        let connectedCount = connectionUsecase.getConnectedDeviceCount()
        
        print("接続状態チェック:")
        print("- hasConnectedDevices: \(hasConnected)")
        print("- connectedCount: \(connectedCount)")
        
        guard hasConnected else {
            sensingStatus = "接続された端末がありません（\(connectedCount)台接続中）"
            print("エラー: 接続された端末がありません")
            return
        }
        
        let command = "SENSING_START:\(fileName)"
        print("送信するコマンド: \(command)")
        print("送信対象端末数: \(connectedCount)")
        
        connectionUsecase.sendMessage(command)
        sensingStatus = "センシング開始コマンド送信: \(fileName)"
        isSensingControlActive = true
        sensingFileName = fileName
        currentSensingFileName = fileName
        sensingStartTime = Date()
        
        // 継続時間タイマーを開始
        startDurationTimer()
        
        // 送信確認のため、少し遅らせてテストメッセージも送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("=== フォローアップテストメッセージ送信 ===")
            self.connectionUsecase.sendMessage("SENSING_TEST_FOLLOW_UP")
        }
        
        print("=== センシング開始処理完了 ===")
    }
    
    public func stopRemoteSensing() {
        guard connectionUsecase.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_STOP"
        connectionUsecase.sendMessage(command)
        sensingStatus = "センシング終了コマンド送信"
        isSensingControlActive = false
        sensingFileName = ""
        isPaused = false
        
        stopDurationTimer()
        
        if autoSave {
            saveCurrentSession()
        }
        
        sensingStartTime = nil
        currentSensingFileName = ""
    }
    
    public func pauseRemoteSensing() {
        guard connectionUsecase.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_PAUSE"
        connectionUsecase.sendMessage(command)
        sensingStatus = "センシング一時停止中"
        isPaused = true
        stopDurationTimer()
    }
    
    public func resumeRemoteSensing() {
        guard connectionUsecase.hasConnectedDevices() else {
            sensingStatus = "接続された端末がありません"
            return
        }
        
        let command = "SENSING_RESUME"
        connectionUsecase.sendMessage(command)
        sensingStatus = "センシング実行中"
        isSensingControlActive = true
        isPaused = false
        startDurationTimer()
    }
    
    // MARK: - Timer Management
    
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
    
    // MARK: - Session Management
    
    public func generateDefaultFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        sensingFileName = "sensing_\(formatter.string(from: Date()))"
    }
    
    private func saveCurrentSession() {
        guard let startTime = sensingStartTime else { return }
        
        let session = SensingSession(
            fileName: currentSensingFileName,
            startTime: startTime,
            dataPoints: dataPointCount
        )
        
        // 最近のセッションに追加
        var recentSessions = dataRepository.loadRecentSensingSessions()
        
        recentSessions.insert(session, at: 0)
        if recentSessions.count > 10 {
            recentSessions.removeLast()
        }
        
        dataRepository.saveRecentSensingSessions(recentSessions)
    }
    
    // MARK: - Configuration
    
    public func updateDataPointCount(_ count: Int) {
        dataPointCount = count
    }
    
    public func canStartSensing(connectedDeviceCount: Int) -> Bool {
        return !sensingFileName.isEmpty && connectedDeviceCount >= 3
    }
    
    public var hasDataToView: Bool {
        dataPointCount > 0
    }
}