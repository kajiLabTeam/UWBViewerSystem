import Foundation
import Combine

/// 観測データ収集を管理するUseCase
@MainActor
public class ObservationDataUsecase: ObservableObject {

    // MARK: - Published Properties

    @Published public var currentSessions: [String: ObservationSession] = [:]  // sessionId -> session
    @Published public var isCollecting: Bool = false
    @Published public var realtimeObservations: [ObservationPoint] = []
    @Published public var errorMessage: String?
    @Published public var connectionStatus: UWBConnectionStatus = .disconnected

    // MARK: - Private Properties

    private let dataRepository: DataRepositoryProtocol
    private let uwbManager: UWBDataManager  // UWBデバイスとの通信を管理
    private var dataCollectionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // データ品質監視
    private var qualityMonitor = DataQualityMonitor()

    // MARK: - Initialization

    public init(dataRepository: DataRepositoryProtocol, uwbManager: UWBDataManager) {
        self.dataRepository = dataRepository
        self.uwbManager = uwbManager
        setupObservers()
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
    public func startObservationSession(for antennaId: String, name: String) async throws -> ObservationSession {
        // UWB接続状態を確認
        guard connectionStatus == .connected else {
            throw ObservationError.deviceNotConnected
        }

        // 既存セッションが実行中の場合は停止
        if let existingSession = currentSessions.values.first(where: { $0.antennaId == antennaId && $0.status == .recording }) {
            _ = try await stopObservationSession(existingSession.id)
        }

        let session = ObservationSession(
            name: name,
            antennaId: antennaId,
            floorMapId: getCurrentFloorMapId()
        )

        currentSessions[session.id] = session
        isCollecting = true

        // UWBデータ収集を開始
        try await uwbManager.startDataCollection(for: antennaId, sessionId: session.id)

        // リアルタイムデータ更新タイマーを開始
        startDataCollectionTimer(for: session.id)

        print("🚀 観測セッション開始: \(name) (アンテナ: \(antennaId))")
        return session
    }

    /// 観測セッションを停止
    /// - Parameter sessionId: セッションID
    /// - Returns: 停止されたセッション
    public func stopObservationSession(_ sessionId: String) async throws -> ObservationSession {
        guard var session = currentSessions[sessionId] else {
            throw ObservationError.sessionNotFound(sessionId)
        }

        // UWBデータ収集を停止
        try await uwbManager.stopDataCollection(sessionId: sessionId)

        // セッション状態を更新
        session.endTime = Date()
        session.status = .completed
        currentSessions[sessionId] = session

        // データを永続化
        try await saveObservationSession(session)

        // 他にアクティブなセッションがない場合は収集フラグをオフ
        let hasActiveSessions = currentSessions.values.contains { $0.status == .recording }
        if !hasActiveSessions {
            isCollecting = false
            dataCollectionTimer?.invalidate()
            dataCollectionTimer = nil
        }

        print("⏹️ 観測セッション停止: \(session.name), データ点数: \(session.observations.count)")
        return session
    }

    /// 全ての観測セッションを停止
    public func stopAllSessions() {
        Task {
            for sessionId in currentSessions.keys {
                try? await stopObservationSession(sessionId)
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
        currentSessions[sessionId] = session

        try await uwbManager.pauseDataCollection(sessionId: sessionId)
        print("⏸️ 観測セッション一時停止: \(session.name)")
    }

    /// セッションを再開
    /// - Parameter sessionId: セッションID
    public func resumeObservationSession(_ sessionId: String) async throws {
        guard var session = currentSessions[sessionId] else {
            throw ObservationError.sessionNotFound(sessionId)
        }

        session.status = .recording
        currentSessions[sessionId] = session

        try await uwbManager.resumeDataCollection(sessionId: sessionId)
        print("▶️ 観測セッション再開: \(session.name)")
    }

    // MARK: - データ品質管理

    /// リアルタイム品質チェック
    /// - Parameter observation: 観測データ点
    /// - Returns: 品質評価結果
    public func evaluateDataQuality(_ observation: ObservationPoint) -> DataQualityEvaluation {
        return qualityMonitor.evaluate(observation)
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
        return qualityMonitor.detectNLoS(observations)
    }

    // MARK: - データアクセス

    /// 保存された観測セッション一覧を取得
    public func loadSavedSessions() async throws -> [ObservationSession] {
        // TODO: DataRepositoryに観測セッション用のメソッドを追加する必要があります
        return []
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

        return session.observations.filter { observation in
            // 品質フィルタ
            if observation.quality.strength < qualityThreshold {
                return false
            }

            // 時間範囲フィルタ
            if let timeRange = timeRange {
                return timeRange.contains(observation.timestamp)
            }

            return true
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // UWB接続状態を監視
        uwbManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, on: self)
            .store(in: &cancellables)

        // リアルタイム観測データを監視
        uwbManager.$latestObservation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] observation in
                self?.handleNewObservation(observation)
            }
            .store(in: &cancellables)
    }

    private func startDataCollectionTimer(for sessionId: String) {
        dataCollectionTimer?.invalidate()
        dataCollectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
            let qualityEval = evaluateDataQuality(observation)
            if !qualityEval.isAcceptable {
                print("⚠️ 低品質データ検出: \(qualityEval.issues.joined(separator: ", "))")
            }
        }

        currentSessions[sessionId] = session

        // リアルタイム表示用データを更新
        realtimeObservations = Array(session.observations.suffix(100))  // 最新100点を表示
    }

    private func handleNewObservation(_ observation: ObservationPoint) {
        // 該当するセッションを見つけて追加
        for (sessionId, var session) in currentSessions {
            if session.antennaId == observation.antennaId && session.status == .recording {
                session.observations.append(observation)
                currentSessions[sessionId] = session
                break
            }
        }

        realtimeObservations.append(observation)
        if realtimeObservations.count > 100 {
            realtimeObservations.removeFirst()
        }
    }

    private func saveObservationSession(_ session: ObservationSession) async throws {
        // TODO: DataRepositoryに観測セッション保存機能を追加
        print("💾 観測セッション保存: \(session.name)")
    }

    private func getCurrentFloorMapId() -> String? {
        guard let data = UserDefaults.standard.data(forKey: "currentFloorMapInfo"),
              let floorMapInfo = try? JSONDecoder().decode(FloorMapInfo.self, from: data) else {
            return nil
        }
        return floorMapInfo.id
    }
}

// MARK: - Supporting Classes

/// UWBデータ管理（モックとして実装）
@MainActor
public class UWBDataManager: ObservableObject {
    @Published public var connectionStatus: UWBConnectionStatus = .disconnected
    @Published public var latestObservation: ObservationPoint?

    private var activeSessions: Set<String> = []
    private var simulationTimer: Timer?

    public init() {}

    public func startDataCollection(for antennaId: String, sessionId: String) async throws {
        activeSessions.insert(sessionId)
        connectionStatus = .connected

        // シミュレーション用タイマー開始
        startSimulation(for: antennaId, sessionId: sessionId)
        print("📡 UWBデータ収集開始: \(antennaId)")
    }

    public func stopDataCollection(sessionId: String) async throws {
        activeSessions.remove(sessionId)
        if activeSessions.isEmpty {
            simulationTimer?.invalidate()
            simulationTimer = nil
        }
        print("📡 UWBデータ収集停止: \(sessionId)")
    }

    public func pauseDataCollection(sessionId: String) async throws {
        // 実装は省略
    }

    public func resumeDataCollection(sessionId: String) async throws {
        // 実装は省略
    }

    public func getLatestObservations(for sessionId: String) async -> [ObservationPoint] {
        // 実際の実装では、UWBデバイスから最新データを取得
        return []
    }

    private func startSimulation(for antennaId: String, sessionId: String) {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateSimulatedObservation(antennaId: antennaId, sessionId: sessionId)
            }
        }
    }

    private func generateSimulatedObservation(antennaId: String, sessionId: String) {
        let observation = ObservationPoint(
            antennaId: antennaId,
            position: Point3D(
                x: Double.random(in: -10...10),
                y: Double.random(in: -10...10),
                z: Double.random(in: 0...3)
            ),
            quality: SignalQuality(
                strength: Double.random(in: 0.3...1.0),
                isLineOfSight: Bool.random(),
                confidenceLevel: Double.random(in: 0.5...1.0),
                errorEstimate: Double.random(in: 0.1...2.0)
            ),
            distance: Double.random(in: 1...20),
            rssi: Double.random(in: -80...(-30)),
            sessionId: sessionId
        )

        latestObservation = observation
    }
}

/// UWB接続状態
public enum UWBConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var displayText: String {
        switch self {
        case .disconnected:
            return "未接続"
        case .connecting:
            return "接続中"
        case .connected:
            return "接続済み"
        case .error(let message):
            return "エラー: \(message)"
        }
    }
}

/// データ品質監視
public class DataQualityMonitor {
    private let qualityThreshold: Double = 0.5
    private let stabilityWindow: Int = 10

    public func evaluate(_ observation: ObservationPoint) -> DataQualityEvaluation {
        var issues: [String] = []
        var isAcceptable = true

        // 信号強度チェック
        if observation.quality.strength < qualityThreshold {
            issues.append("信号強度が低い")
            isAcceptable = false
        }

        // RSSI チェック
        if observation.rssi < -75 {
            issues.append("RSSI値が低い")
        }

        // 信頼度チェック
        if observation.quality.confidenceLevel < 0.6 {
            issues.append("信頼度が低い")
            isAcceptable = false
        }

        // 誤差推定チェック
        if observation.quality.errorEstimate > 3.0 {
            issues.append("誤差推定値が大きい")
        }

        return DataQualityEvaluation(
            isAcceptable: isAcceptable,
            qualityScore: observation.quality.strength,
            issues: issues,
            recommendations: generateRecommendations(for: issues)
        )
    }

    public func detectNLoS(_ observations: [ObservationPoint]) -> NLoSDetectionResult {
        let losCount = observations.filter { $0.quality.isLineOfSight }.count
        let losPercentage = observations.isEmpty ? 0.0 : Double(losCount) / Double(observations.count) * 100.0

        let isNLoSCondition = losPercentage < 50.0  // 見通し線が50%未満の場合
        let averageSignalStrength = observations.isEmpty ? 0.0 : observations.map { $0.quality.strength }.reduce(0, +) / Double(observations.count)

        return NLoSDetectionResult(
            isNLoSDetected: isNLoSCondition,
            lineOfSightPercentage: losPercentage,
            averageSignalStrength: averageSignalStrength,
            recommendation: isNLoSCondition ? "障害物を除去するか、アンテナ位置を調整してください" : "良好な測定環境です"
        )
    }

    private func generateRecommendations(for issues: [String]) -> [String] {
        var recommendations: [String] = []

        if issues.contains("信号強度が低い") {
            recommendations.append("アンテナ間の距離を短くしてください")
            recommendations.append("障害物を除去してください")
        }

        if issues.contains("RSSI値が低い") {
            recommendations.append("アンテナの向きを調整してください")
        }

        if issues.contains("信頼度が低い") {
            recommendations.append("測定環境を安定化してください")
        }

        return recommendations
    }
}

// MARK: - Supporting Types

/// データ品質評価結果
public struct DataQualityEvaluation {
    public let isAcceptable: Bool
    public let qualityScore: Double
    public let issues: [String]
    public let recommendations: [String]

    public init(isAcceptable: Bool, qualityScore: Double, issues: [String], recommendations: [String]) {
        self.isAcceptable = isAcceptable
        self.qualityScore = qualityScore
        self.issues = issues
        self.recommendations = recommendations
    }
}

/// nLoS検出結果
public struct NLoSDetectionResult {
    public let isNLoSDetected: Bool
    public let lineOfSightPercentage: Double
    public let averageSignalStrength: Double
    public let recommendation: String

    public init(isNLoSDetected: Bool, lineOfSightPercentage: Double, averageSignalStrength: Double, recommendation: String) {
        self.isNLoSDetected = isNLoSDetected
        self.lineOfSightPercentage = lineOfSightPercentage
        self.averageSignalStrength = averageSignalStrength
        self.recommendation = recommendation
    }
}

/// 観測エラー
public enum ObservationError: Error, LocalizedError {
    case deviceNotConnected
    case sessionNotFound(String)
    case dataCollectionFailed(String)
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return "UWBデバイスが接続されていません"
        case .sessionNotFound(let sessionId):
            return "セッションが見つかりません: \(sessionId)"
        case .dataCollectionFailed(let reason):
            return "データ収集に失敗しました: \(reason)"
        case .invalidConfiguration:
            return "設定が無効です"
        }
    }
}