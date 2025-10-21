import Combine
import Foundation
import os.log

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
    private let swiftDataRepository: SwiftDataRepositoryProtocol
    private var sensingStartTime: Date?
    private var durationTimer: Timer?
    private var currentSessionId: String?
    private let logger = Logger(subsystem: "com.uwbviewer.system", category: "sensing-control")

    public init(
        connectionUsecase: ConnectionManagementUsecase,
        swiftDataRepository: SwiftDataRepositoryProtocol = DummySwiftDataRepository()
    ) {
        self.connectionUsecase = connectionUsecase
        self.swiftDataRepository = swiftDataRepository
    }

    // MARK: - Sensing Control

    public func startRemoteSensing(fileName: String) {
        self.logger.info("センシング開始処理開始 - ファイル名: \(fileName)")

        guard !fileName.isEmpty else {
            self.sensingStatus = "ファイル名を入力してください"
            self.logger.error("ファイル名が空です")
            return
        }

        let hasConnected = self.connectionUsecase.hasConnectedDevices()
        let connectedCount = self.connectionUsecase.getConnectedDeviceCount()

        self.logger.debug("接続状態チェック - hasConnectedDevices: \(hasConnected), connectedCount: \(connectedCount)")

        guard hasConnected else {
            self.sensingStatus = "接続された端末がありません（\(connectedCount)台接続中）"
            self.logger.error("接続された端末がありません")
            return
        }

        Task {
            do {
                // 新しいセンシングセッションを作成してSwiftDataに保存
                let session = SensingSession(name: fileName, startTime: Date(), isActive: true)
                try await swiftDataRepository.saveSensingSession(session)
                self.currentSessionId = session.id

                // システム活動ログも記録
                let activity = SystemActivity(
                    activityType: "sensing",
                    activityDescription: "センシングセッション開始: \(fileName)"
                )
                try await swiftDataRepository.saveSystemActivity(activity)

                self.logger.info("センシングセッション作成完了: \(session.id)")
            } catch {
                self.logger.error("センシングセッション作成エラー: \(error)")
                self.sensingStatus = "セッション作成に失敗しました"
                return
            }
        }

        let command = "SENSING_START:\(fileName)"
        self.logger.info("送信するコマンド: \(command), 送信対象端末数: \(connectedCount)")

        self.connectionUsecase.sendMessage(command)
        self.sensingStatus = "センシング開始コマンド送信: \(fileName)"
        self.isSensingControlActive = true
        self.sensingFileName = fileName
        self.currentSensingFileName = fileName
        self.sensingStartTime = Date()

        // 継続時間タイマーを開始
        self.startDurationTimer()

        // 送信確認のため、少し遅らせてテストメッセージも送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.logger.debug("フォローアップテストメッセージ送信")
            self.connectionUsecase.sendMessage("SENSING_TEST_FOLLOW_UP")
        }

        self.logger.info("センシング開始処理完了")
    }

    public func stopRemoteSensing() {
        guard self.connectionUsecase.hasConnectedDevices() else {
            self.sensingStatus = "接続された端末がありません"
            return
        }

        let command = "SENSING_STOP"
        self.connectionUsecase.sendMessage(command)
        self.sensingStatus = "センシング終了コマンド送信"
        self.isSensingControlActive = false
        self.sensingFileName = ""
        self.isPaused = false

        self.stopDurationTimer()

        if self.autoSave {
            Task {
                await self.saveCurrentSession()
            }
        }

        self.sensingStartTime = nil
        self.currentSensingFileName = ""
        self.currentSessionId = nil
    }

    public func pauseRemoteSensing() {
        guard self.connectionUsecase.hasConnectedDevices() else {
            self.sensingStatus = "接続された端末がありません"
            return
        }

        let command = "SENSING_PAUSE"
        self.connectionUsecase.sendMessage(command)
        self.sensingStatus = "センシング一時停止中"
        self.isPaused = true
        self.stopDurationTimer()
    }

    public func resumeRemoteSensing() {
        guard self.connectionUsecase.hasConnectedDevices() else {
            self.sensingStatus = "接続された端末がありません"
            return
        }

        let command = "SENSING_RESUME"
        self.connectionUsecase.sendMessage(command)
        self.sensingStatus = "センシング実行中"
        self.isSensingControlActive = true
        self.isPaused = false
        self.startDurationTimer()
    }

    // MARK: - Timer Management

    private func startDurationTimer() {
        self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSensingDuration()
            }
        }
    }

    private func stopDurationTimer() {
        self.durationTimer?.invalidate()
        self.durationTimer = nil
    }

    private func updateSensingDuration() {
        guard let startTime = sensingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)

        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) / 60 % 60
        let seconds = Int(elapsed) % 60

        self.sensingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Session Management

    public func generateDefaultFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        self.sensingFileName = "sensing_\(formatter.string(from: Date()))"
    }

    private func saveCurrentSession() async {
        guard let startTime = sensingStartTime, let sessionId = currentSessionId else { return }

        do {
            // 既存のセッションを更新（終了時間とデータポイント数を設定）
            if let _ = try await swiftDataRepository.loadSensingSession(by: sessionId) {
                let updatedSession = SensingSession(
                    id: sessionId,
                    name: currentSensingFileName,
                    startTime: startTime,
                    endTime: Date(),
                    isActive: false,
                    dataPoints: dataPointCount
                )

                try await swiftDataRepository.updateSensingSession(updatedSession)

                // システム活動ログも記録
                let activity = SystemActivity(
                    activityType: "sensing",
                    activityDescription: "センシングセッション終了: \(currentSensingFileName) (\(dataPointCount)データポイント)"
                )
                try await swiftDataRepository.saveSystemActivity(activity)

                self.logger.info("センシングセッション更新完了: \(sessionId)")
            }
        } catch {
            self.logger.error("センシングセッション更新エラー: \(error)")
        }
    }

    // MARK: - Data Management

    public func saveRealtimeData(_ data: RealtimeData) async {
        guard let sessionId = currentSessionId else { return }

        do {
            try await self.swiftDataRepository.saveRealtimeData(data, sessionId: sessionId)

            // データポイント数を更新
            Task { @MainActor in
                self.dataPointCount += 1
            }
        } catch {
            self.logger.error("リアルタイムデータ保存エラー: \(error)")
        }
    }

    public func loadSensingHistory() async throws -> [SensingSession] {
        try await self.swiftDataRepository.loadAllSensingSessions()
    }

    // MARK: - Configuration

    public func updateDataPointCount(_ count: Int) {
        self.dataPointCount = count
    }

    public func canStartSensing(connectedDeviceCount: Int) -> Bool {
        !self.sensingFileName.isEmpty && connectedDeviceCount >= 3
    }

    public var hasDataToView: Bool {
        self.dataPointCount > 0
    }
}
