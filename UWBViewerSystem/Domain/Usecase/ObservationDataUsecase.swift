import Combine
import Foundation

/// 観測データ収集を管理するUseCase
///
/// このUseCaseは、UWBデバイスからの観測データ収集プロセス全体を管理します。
/// セッション管理とリアルタイムデータ監視を提供します。
/// データ品質チェックはDataQualityUsecaseに委譲されています。

// MARK: - Observation Errors

/// 観測関連のエラー定義
///
/// UWBデバイスとの通信やデータ収集プロセスで発生する可能性のあるエラーを定義します。
/// 各エラーには適切なエラーメッセージと復旧提案が含まれています。
public enum ObservationError: LocalizedError {
    case deviceNotConnected
    case sessionNotFound(String)
    case invalidInput(String)
    case sessionStartFailed(String)
    case sessionStopFailed(String)
    case dataCollectionFailed(String)
    case qualityCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return "UWBデバイスが接続されていません"
        case .sessionNotFound(let sessionId):
            return "セッションが見つかりません: \(sessionId)"
        case .invalidInput(let message):
            return "無効な入力: \(message)"
        case .sessionStartFailed(let message):
            return "セッション開始に失敗しました: \(message)"
        case .sessionStopFailed(let message):
            return "セッション停止に失敗しました: \(message)"
        case .dataCollectionFailed(let message):
            return "データ収集に失敗しました: \(message)"
        case .qualityCheckFailed(let message):
            return "データ品質チェックに失敗しました: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotConnected:
            return "UWBデバイスの接続を確認してください。"
        case .sessionNotFound:
            return "有効なセッションを選択してください。"
        case .invalidInput:
            return "入力内容を確認してください。"
        case .sessionStartFailed, .sessionStopFailed:
            return "操作を再試行するか、デバイスの接続を確認してください。"
        case .dataCollectionFailed:
            return "デバイスの接続とセンサーの状態を確認してください。"
        case .qualityCheckFailed:
            return "測定環境や設定を見直してください。"
        }
    }
}

/// UWB観測データ収集のビジネスロジック実装
///
/// このクラスは、UWBデバイスからの観測データ収集を管理するメインのUseCaseです。
/// リアルタイムでの観測セッション管理、データ品質監視、エラーハンドリングを行います。
///
/// ## 主要機能
/// - **セッション管理**: 観測セッションの開始・停止・監視
/// - **リアルタイムデータ**: UWBデバイスからのリアルタイムデータ受信
/// - **データ品質監視**: 受信データの品質チェックと異常検出
/// - **エラーハンドリング**: デバイス接続エラーやデータ収集エラーの管理
/// - **永続化**: 観測データのSwiftDataへの保存
///
/// ## 使用例
/// ```swift
/// let usecase = ObservationDataUsecase(
///     dataRepository: swiftDataRepository,
///     uwbManager: uwbManager,
///     preferenceRepository: preferenceRepository
/// )
///
/// // 観測セッションの開始
/// try await usecase.startObservationSession(
///     sessionName: "測定セッション1",
///     locationInfo: locationInfo
/// )
///
/// // リアルタイムデータの監視
/// usecase.$realtimeObservations
///     .sink { observations in
///         // UIの更新処理
///     }
/// ```
@MainActor
public class ObservationDataUsecase: ObservableObject {

    // MARK: - Published Properties

    /// 現在アクティブな観測セッション（sessionId -> session）
    @Published public var currentSessions: [String: ObservationSession] = [:]
    /// データ収集中かどうかのフラグ
    @Published public var isCollecting: Bool = false
    /// リアルタイムで受信した観測ポイントの配列
    @Published public var realtimeObservations: [ObservationPoint] = []
    /// 発生したエラーメッセージ
    @Published public var errorMessage: String?
    /// UWBデバイスとの接続状態
    @Published public var connectionStatus: UWBConnectionStatus = .disconnected

    /// キャリブレーション用のプロパティ
    @Published public var calibrationProgress: Double = 0.0
    @Published public var calibrationTimeRemaining: TimeInterval = 0.0
    @Published public var isCalibrationCollecting: Bool = false
    @Published public var currentReferencePoint: String = ""

    // MARK: - Private Properties

    /// データ永続化を担当するリポジトリ
    private let dataRepository: DataRepositoryProtocol
    /// アプリケーション設定管理用リポジトリ
    private let preferenceRepository: PreferenceRepositoryProtocol
    /// UWBデバイスとの通信を管理するマネージャー
    private let uwbManager: UWBDataManager
    /// データ品質管理用のUsecase
    private let dataQualityUsecase: DataQualityUsecase
    /// データ収集用のタイマー
    private var dataCollectionTimer: Timer?
    /// Combineの購読を管理するセット
    private var cancellables = Set<AnyCancellable>()

    // キャリブレーション用のタイマー管理
    private var calibrationTimers: [String: Timer] = [:]
    private var calibrationDuration: TimeInterval = 15.0  // 15秒間のデータ収集

    // MARK: - Initialization

    /// ObservationDataUsecaseのイニシャライザ
    /// - Parameters:
    ///   - dataRepository: データ永続化用リポジトリ
    ///   - uwbManager: UWBデバイス通信管理用マネージャー
    ///   - preferenceRepository: アプリケーション設定管理用リポジトリ
    ///   - dataQualityUsecase: データ品質管理用Usecase
    public init(
        dataRepository: DataRepositoryProtocol,
        uwbManager: UWBDataManager,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository(),
        dataQualityUsecase: DataQualityUsecase = DataQualityUsecase()
    ) {
        self.dataRepository = dataRepository
        self.uwbManager = uwbManager
        self.preferenceRepository = preferenceRepository
        self.dataQualityUsecase = dataQualityUsecase
        self.setupObservers()
    }

    deinit {
        // デストラクタでは同期的な処理のみ行う
        dataCollectionTimer?.invalidate()
        dataCollectionTimer = nil
    }

    // MARK: - セッション管理

    /// 観測セッションを開始
    /// - Parameters:
    ///   - antennaId: 観測対象のアンテナID
    ///   - name: セッション名
    /// - Returns: 開始されたセッション
    /// 観測セッションを開始
    /// - Parameters:
    ///   - antennaId: 観測対象のアンテナID
    ///   - name: セッション名
    /// - Returns: 開始されたセッション
    public func startObservationSession(for antennaId: String, name: String) async throws -> ObservationSession {
        // 入力データの検証
        guard !antennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservationError.invalidInput("アンテナIDが空です")
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservationError.invalidInput("セッション名が空です")
        }

        // UWB接続状態を確認
        guard self.connectionStatus == .connected else {
            throw ObservationError.deviceNotConnected
        }

        do {
            // 既存セッションが実行中の場合は停止
            let activeSession = self.currentSessions.values.first { session in
                session.antennaId == antennaId && session.status == .recording
            }

            if let existingSession = activeSession {
                print("🔄 既存のアクティブセッションを停止します: \(existingSession.name)")
                _ = try await self.stopObservationSession(existingSession.id)
            }

            let session = ObservationSession(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                antennaId: antennaId.trimmingCharacters(in: .whitespacesAndNewlines),
                floorMapId: self.getCurrentFloorMapId()
            )

            self.currentSessions[session.id] = session
            self.isCollecting = true

            // UWBデータ収集を開始
            try await self.uwbManager.startDataCollection(for: antennaId, sessionId: session.id)

            // リアルタイムデータ更新タイマーを開始
            self.startDataCollectionTimer(for: session.id)

            print("🚀 観測セッション開始: \(name) (アンテナ: \(antennaId))")
            return session

        } catch let error as ObservationError {
            // 既に定義されたObservationErrorはそのまま再スロー
            throw error
        } catch {
            // その他のエラーをObservationErrorでラップ
            throw ObservationError.sessionStartFailed("セッション開始に失敗しました: \(error.localizedDescription)")
        }
    }

    /// 観測セッションを停止
    /// - Parameter sessionId: セッションID
    /// - Returns: 停止されたセッション
    /// 観測セッションを停止
    /// - Parameter sessionId: セッションID
    /// - Returns: 停止されたセッション
    public func stopObservationSession(_ sessionId: String) async throws -> ObservationSession {
        guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservationError.invalidInput("セッションIDが空です")
        }

        guard var session = currentSessions[sessionId] else {
            throw ObservationError.sessionNotFound(sessionId)
        }

        do {
            // UWBデータ収集を停止
            try await self.uwbManager.stopDataCollection(sessionId: sessionId)

            // セッション状態を更新
            session.endTime = Date()
            session.status = .completed
            self.currentSessions[sessionId] = session

            // データを永続化
            try await self.saveObservationSession(session)

            // 他にアクティブなセッションがない場合は収集フラグをオフ
            let hasActiveSessions = self.currentSessions.values.contains { $0.status == .recording }
            if !hasActiveSessions {
                self.isCollecting = false
                self.dataCollectionTimer?.invalidate()
                self.dataCollectionTimer = nil
            }

            print("⏹️ 観測セッション停止: \(session.name), データ点数: \(session.observations.count)")
            return session

        } catch let error as ObservationError {
            throw error
        } catch {
            throw ObservationError.sessionStopFailed("セッション停止処理でエラーが発生しました: \(error.localizedDescription)")
        }
    }

    /// 全ての観測セッションを停止
    public func stopAllSessions() {
        Task {
            for sessionId in self.currentSessions.keys {
                _ = try? await self.stopObservationSession(sessionId)
            }
        }
    }

    /// セッションを一時停止
    /// - Parameter sessionId: セッションID
    public func pauseObservationSession(_ sessionId: String) async throws {
        guard var session = currentSessions[sessionId] else {
            throw ObservationError.sessionNotFound(sessionId)
        }

        session.status = .paused
        self.currentSessions[sessionId] = session

        try await self.uwbManager.pauseDataCollection(sessionId: sessionId)
        print("⏸️ 観測セッション一時停止: \(session.name)")
    }

    /// セッションを再開
    /// - Parameter sessionId: セッションID
    public func resumeObservationSession(_ sessionId: String) async throws {
        guard var session = currentSessions[sessionId] else {
            throw ObservationError.sessionNotFound(sessionId)
        }

        session.status = .recording
        self.currentSessions[sessionId] = session

        try await self.uwbManager.resumeDataCollection(sessionId: sessionId)
        print("▶️ 観測セッション再開: \(session.name)")
    }

    /// キャリブレーション用の15秒間データ収集
    public func startCalibrationDataCollection(for antennaId: String, referencePoint: String) async throws
        -> ObservationSession
    {
        print("🎯 キャリブレーション用データ収集開始: アンテナ\(antennaId), 基準点\(referencePoint)")

        let sessionName = "キャリブレーション_\(referencePoint)_\(Date().timeIntervalSince1970)"
        let session = try await startObservationSession(for: antennaId, name: sessionName)

        // 15秒後に自動停止するタイマーを設定
        let timer = Timer.scheduledTimer(withTimeInterval: self.calibrationDuration, repeats: false) { [weak self] _ in
            Task { [weak self] in
                do {
                    _ = try await self?.stopObservationSession(session.id)
                    print("⏰ 15秒間のデータ収集完了: \(sessionName)")
                } catch {
                    print("❌ 自動停止中にエラー: \(error)")
                }
            }
        }

        self.calibrationTimers[session.id] = timer
        return session
    }

    /// キャリブレーション用データ収集の手動停止
    public func stopCalibrationDataCollection(_ sessionId: String) async throws -> ObservationSession {
        // タイマーをキャンセル
        self.calibrationTimers[sessionId]?.invalidate()
        self.calibrationTimers.removeValue(forKey: sessionId)

        return try await self.stopObservationSession(sessionId)
    }

    /// キャリブレーション用の進捗付きデータ収集（進捗表示機能付き）
    public func startCalibrationDataCollectionWithProgress(for antennaId: String, referencePoint: String) async throws
        -> ObservationSession
    {
        print("🎯 進捗付きキャリブレーション開始: アンテナ\(antennaId), 基準点\(referencePoint)")

        self.currentReferencePoint = referencePoint
        self.isCalibrationCollecting = true
        self.calibrationProgress = 0.0
        self.calibrationTimeRemaining = self.calibrationDuration

        let sessionName = "キャリブレーション_\(referencePoint)_\(Date().timeIntervalSince1970)"
        let session = try await startObservationSession(for: antennaId, name: sessionName)

        // 進捗更新タイマー（0.1秒間隔）
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            DispatchQueue.main.async {
                self.calibrationTimeRemaining = max(0, self.calibrationTimeRemaining - 0.1)
                self.calibrationProgress =
                    (self.calibrationDuration - self.calibrationTimeRemaining) / self.calibrationDuration

                if self.calibrationTimeRemaining <= 0 {
                    timer.invalidate()
                    Task {
                        do {
                            _ = try await self.stopObservationSession(session.id)
                            await MainActor.run {
                                self.isCalibrationCollecting = false
                                self.calibrationProgress = 1.0
                                self.calibrationTimeRemaining = 0.0
                            }
                            print("⏰ 15秒間のデータ収集完了: \(sessionName)")
                        } catch {
                            print("❌ 自動停止中にエラー: \(error)")
                            await MainActor.run {
                                self.isCalibrationCollecting = false
                            }
                        }
                    }
                }
            }
        }

        self.calibrationTimers[session.id] = progressTimer
        return session
    }

    // MARK: - データ品質管理

    /// リアルタイム品質チェック
    /// - Parameter observation: 観測データ点
    /// - Returns: 品質評価結果
    public func evaluateDataQuality(_ observation: ObservationPoint) -> DataQualityEvaluation {
        self.dataQualityUsecase.evaluateDataQuality(observation)
    }

    /// セッションの品質統計を取得
    /// - Parameter sessionId: セッションID
    /// - Returns: 品質統計
    public func getSessionQualityStatistics(_ sessionId: String) -> ObservationQualityStatistics? {
        guard let session = currentSessions[sessionId] else { return nil }
        return session.qualityStatistics
    }

    /// nLoS（見通し線なし）状態の検出
    /// - Parameter observations: 観測データ配列
    /// - Returns: nLoS検出結果
    public func detectNonLineOfSight(_ observations: [ObservationPoint]) -> NLoSDetectionResult {
        self.dataQualityUsecase.detectNonLineOfSight(observations)
    }

    // MARK: - データアクセス

    /// 保存された観測セッション一覧を取得
    public func loadSavedSessions() async throws -> [ObservationSession] {
        // TODO: DataRepositoryに観測セッション用のメソッドを追加する必要があります
        []
    }

    /// 観測データをフィルタリング
    /// - Parameters:
    ///   - sessionId: セッションID
    ///   - qualityThreshold: 品質閾値（0.0-1.0）
    ///   - timeRange: 時間範囲
    /// - Returns: フィルタリングされた観測データ
    public func filterObservations(
        sessionId: String,
        qualityThreshold: Double = 0.5,
        timeRange: DateInterval? = nil
    ) -> [ObservationPoint] {
        guard let session = currentSessions[sessionId] else { return [] }
        return self.dataQualityUsecase.filterObservations(
            session.observations,
            qualityThreshold: qualityThreshold,
            timeRange: timeRange
        )
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // UWB接続状態を監視
        self.uwbManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, on: self)
            .store(in: &self.cancellables)

        // リアルタイム観測データを監視
        self.uwbManager.$latestObservation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] observation in
                self?.handleNewObservation(observation)
            }
            .store(in: &self.cancellables)
    }

    private func startDataCollectionTimer(for sessionId: String) {
        self.dataCollectionTimer?.invalidate()
        self.dataCollectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateSessionData(sessionId)
            }
        }
    }

    private func updateSessionData(_ sessionId: String) async {
        guard var session = currentSessions[sessionId] else { return }

        // UWBマネージャーから最新データを取得
        let newObservations = await uwbManager.getLatestObservations(for: sessionId)
        session.observations.append(contentsOf: newObservations)

        // 品質チェック
        for observation in newObservations {
            let qualityEval = self.evaluateDataQuality(observation)
            if !qualityEval.isAcceptable {
                print("⚠️ 低品質データ検出: \(qualityEval.issues.joined(separator: ", "))")
            }
        }

        self.currentSessions[sessionId] = session

        // リアルタイム表示用データを更新
        self.realtimeObservations = Array(session.observations.suffix(100))  // 最新100点を表示
    }

    private func handleNewObservation(_ observation: ObservationPoint) {
        // 該当するセッションを見つけて追加
        for (sessionId, var session) in currentSessions {
            if session.antennaId == observation.antennaId && session.status == .recording {
                session.observations.append(observation)
                self.currentSessions[sessionId] = session
                break
            }
        }

        self.realtimeObservations.append(observation)
        if self.realtimeObservations.count > 100 {
            self.realtimeObservations.removeFirst()
        }
    }

    private func saveObservationSession(_ session: ObservationSession) async throws {
        // TODO: DataRepositoryに観測セッション保存機能を追加
        print("💾 観測セッション保存: \(session.name)")
    }

    private func getCurrentFloorMapId() -> String? {
        self.preferenceRepository.loadCurrentFloorMapInfo()?.id
    }
}
