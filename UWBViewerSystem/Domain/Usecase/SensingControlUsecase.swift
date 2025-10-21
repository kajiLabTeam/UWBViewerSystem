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
        logger.info("センシング開始処理開始 - ファイル名: \(fileName)")

        guard !fileName.isEmpty else {
            sensingStatus = "ファイル名を入力してください"
            logger.error("ファイル名が空です")
            return
        }

        let hasConnected = connectionUsecase.hasConnectedDevices()
        let connectedCount = connectionUsecase.getConnectedDeviceCount()

        logger.debug("接続状態チェック - hasConnectedDevices: \(hasConnected), connectedCount: \(connectedCount)")

        guard hasConnected else {
            sensingStatus = "接続された端末がありません（\(connectedCount)台接続中）"
            logger.error("接続された端末がありません")
            return
        }

        Task {
            do {
                // 新しいセンシングセッションを作成してSwiftDataに保存
                let session = SensingSession(name: fileName, startTime: Date(), isActive: true)
                try await swiftDataRepository.saveSensingSession(session)
                currentSessionId = session.id

                // システム活動ログも記録
                let activity = SystemActivity(
                    activityType: "sensing",
                    activityDescription: "センシングセッション開始: \(fileName)"
                )
                try await swiftDataRepository.saveSystemActivity(activity)

                logger.info("センシングセッション作成完了: \(session.id)")
            } catch {
                logger.error("センシングセッション作成エラー: \(error)")
                sensingStatus = "セッション作成に失敗しました"
                return
            }
        }

        let command = "SENSING_START:\(fileName)"
        logger.info("送信するコマンド: \(command), 送信対象端末数: \(connectedCount)")

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
            self.logger.debug("フォローアップテストメッセージ送信")
            self.connectionUsecase.sendMessage("SENSING_TEST_FOLLOW_UP")
        }

        logger.info("センシング開始処理完了")
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
            Task {
                await saveCurrentSession()
            }
        }

        sensingStartTime = nil
        currentSensingFileName = ""
        currentSessionId = nil
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

                logger.info("センシングセッション更新完了: \(sessionId)")
            }
        } catch {
            logger.error("センシングセッション更新エラー: \(error)")
        }
    }

    // MARK: - Data Management

    public func saveRealtimeData(_ data: RealtimeData) async {
        guard let sessionId = currentSessionId else { return }

        do {
            try await swiftDataRepository.saveRealtimeData(data, sessionId: sessionId)

            // データポイント数を更新
            Task { @MainActor in
                self.dataPointCount += 1
            }
        } catch {
            logger.error("リアルタイムデータ保存エラー: \(error)")
        }
    }

    public func loadSensingHistory() async throws -> [SensingSession] {
        try await swiftDataRepository.loadAllSensingSessions()
    }

    // MARK: - Configuration

    public func updateDataPointCount(_ count: Int) {
        dataPointCount = count
    }

    public func canStartSensing(connectedDeviceCount: Int) -> Bool {
        !sensingFileName.isEmpty && connectedDeviceCount >= 3
    }

    public var hasDataToView: Bool {
        dataPointCount > 0
    }
}
