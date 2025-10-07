import Foundation
import Testing

@testable import UWBViewerSystem

/// 観測データUseCaseのテストスイート
@Suite("観測データUseCase機能テスト")
struct ObservationDataUsecaseTests {

    // MARK: - Test Setup

    @MainActor
    private func createTestUsecase() async -> (ObservationDataUsecase, MockUWBDataManager) {
        let mockRepository = MockObservationDataRepository()
        let mockUWBManager = MockUWBDataManager()
        let usecase = ObservationDataUsecase(dataRepository: mockRepository, uwbManager: mockUWBManager)

        // 初期化待機
        try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05秒

        return (usecase, mockUWBManager)
    }

    private func createTestObservationPoints() -> [ObservationPoint] {
        [
            ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: 1.0, y: 1.0, z: 0.1),
                quality: SignalQuality(strength: 0.8, isLineOfSight: true, confidenceLevel: 0.9, errorEstimate: 0.2),
                distance: 10.0,
                rssi: -45.0,
                sessionId: "session1"
            ),
            ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: 1.1, y: 1.0, z: 0.1),
                quality: SignalQuality(strength: 0.3, isLineOfSight: false, confidenceLevel: 0.4, errorEstimate: 1.5),
                distance: 15.0,
                rssi: -75.0,
                sessionId: "session1"
            ),
            ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: 1.2, y: 1.0, z: 0.1),
                quality: SignalQuality(strength: 0.9, isLineOfSight: true, confidenceLevel: 0.95, errorEstimate: 0.1),
                distance: 8.0,
                rssi: -40.0,
                sessionId: "session1"
            ),
        ]
    }

    // MARK: - セッション管理テスト

    @Test("観測セッション開始")
    @MainActor
    func testStartObservationSession() async throws {
        let (usecase, _) = await createTestUsecase()

        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")

        #expect(session.antennaId == "antenna1")
        #expect(session.name == "テストセッション")
        #expect(session.status == ObservationStatus.recording)
        #expect(usecase.currentSessions[session.id] != nil)
        #expect(usecase.isCollecting == true)
    }

    @Test("観測セッション停止")
    @MainActor
    func testStopObservationSession() async throws {
        let (usecase, _) = await createTestUsecase()

        // セッション開始
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")

        // セッション停止
        let stoppedSession = try await usecase.stopObservationSession(session.id)

        #expect(stoppedSession.status == ObservationStatus.completed)
        #expect(stoppedSession.endTime != nil)
        #expect(usecase.isCollecting == false)
    }

    @Test("観測セッション一時停止と再開")
    @MainActor
    func pauseAndResumeObservationSession() async throws {
        let (usecase, _) = await createTestUsecase()

        // セッション開始
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")

        // 一時停止
        try await usecase.pauseObservationSession(session.id)
        let pausedSession = usecase.currentSessions[session.id]
        #expect(pausedSession?.status == .paused)

        // 再開
        try await usecase.resumeObservationSession(session.id)
        let resumedSession = usecase.currentSessions[session.id]
        #expect(resumedSession?.status == .recording)
    }

    @Test("複数セッションの管理")
    @MainActor
    func multipleSessionManagement() async throws {
        let (usecase, _) = await createTestUsecase()

        // 複数セッション開始
        let _ = try await usecase.startObservationSession(for: "antenna1", name: "セッション1")
        let _ = try await usecase.startObservationSession(for: "antenna2", name: "セッション2")

        #expect(usecase.currentSessions.count == 2)
        #expect(usecase.isCollecting == true)

        // 全停止
        usecase.stopAllSessions()

        // 少し待って状態確認（非同期処理のため）
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒

        // すべてのセッションが停止または停止処理中であることを確認
        let allStopped = usecase.currentSessions.values.allSatisfy {
            $0.status == ObservationStatus.completed || $0.status == ObservationStatus.paused
        }
        #expect(allStopped)
    }

    // MARK: - データ品質評価テスト

    @Test("データ品質評価 - 高品質データ")
    @MainActor
    func dataQualityEvaluationHighQuality() async throws {
        let (usecase, _) = await createTestUsecase()

        let highQualityObservation = ObservationPoint(
            antennaId: "antenna1",
            position: Point3D(x: 1.0, y: 1.0, z: 0.1),
            quality: SignalQuality(strength: 0.9, isLineOfSight: true, confidenceLevel: 0.95, errorEstimate: 0.1),
            distance: 8.0,
            rssi: -40.0,
            sessionId: "session1"
        )

        let evaluation = usecase.evaluateDataQuality(highQualityObservation)

        #expect(evaluation.isAcceptable == true)
        #expect(evaluation.qualityScore >= 0.9)
        #expect(evaluation.issues.isEmpty)
    }

    @Test("データ品質評価 - 低品質データ")
    @MainActor
    func dataQualityEvaluationLowQuality() async throws {
        let (usecase, _) = await createTestUsecase()

        let lowQualityObservation = ObservationPoint(
            antennaId: "antenna1",
            position: Point3D(x: 1.0, y: 1.0, z: 0.1),
            quality: SignalQuality(strength: 0.3, isLineOfSight: false, confidenceLevel: 0.4, errorEstimate: 2.5),
            distance: 25.0,
            rssi: -85.0,
            sessionId: "session1"
        )

        let evaluation = usecase.evaluateDataQuality(lowQualityObservation)

        #expect(evaluation.isAcceptable == false)
        #expect(evaluation.qualityScore < 0.5)
        #expect(!evaluation.issues.isEmpty)
        #expect(!evaluation.recommendations.isEmpty)
    }

    @Test("nLoS検出テスト")
    @MainActor
    func nLoSDetection() async throws {
        let (usecase, _) = await createTestUsecase()
        let testObservations = self.createTestObservationPoints()

        let nlosResult = usecase.detectNonLineOfSight(testObservations)

        #expect(nlosResult.lineOfSightPercentage < 100.0)  // 一部nLoSデータが含まれている
        #expect(nlosResult.averageSignalStrength > 0.0)
        #expect(nlosResult.recommendation.isEmpty == false)
    }

    // MARK: - データフィルタリングテスト

    @Test("観測データフィルタリング - 品質閾値")
    @MainActor
    func observationFiltering() async throws {
        let (usecase, _) = await createTestUsecase()
        let testObservations = self.createTestObservationPoints()

        // セッション作成とデータ追加（モック）
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")
        guard var sessionWithData = usecase.currentSessions[session.id] else {
            #expect(Bool(false), "セッションが見つかりません")
            return
        }
        sessionWithData.observations = testObservations
        usecase.currentSessions[session.id] = sessionWithData

        // 品質閾値0.5でフィルタリング
        let filteredObservations = usecase.filterObservations(sessionId: session.id, qualityThreshold: 0.5)

        #expect(filteredObservations.count == 2)  // 品質0.8と0.9の2つのみ
        #expect(filteredObservations.allSatisfy { $0.quality.strength >= 0.5 })
    }

    @Test("観測データフィルタリング - 時間範囲")
    @MainActor
    func observationFilteringByTimeRange() async throws {
        let (usecase, _) = await createTestUsecase()
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)

        // 異なる時刻のデータを作成
        let recentObservation = ObservationPoint(
            antennaId: "antenna1",
            position: Point3D(x: 1.0, y: 1.0, z: 0.1),
            timestamp: now,
            quality: SignalQuality(strength: 0.8, isLineOfSight: true, confidenceLevel: 0.9, errorEstimate: 0.2),
            distance: 10.0,
            rssi: -45.0,
            sessionId: "session1"
        )

        let oldObservation = ObservationPoint(
            antennaId: "antenna1",
            position: Point3D(x: 1.1, y: 1.0, z: 0.1),
            timestamp: oneHourAgo,
            quality: SignalQuality(strength: 0.9, isLineOfSight: true, confidenceLevel: 0.95, errorEstimate: 0.1),
            distance: 8.0,
            rssi: -40.0,
            sessionId: "session1"
        )

        // セッション作成とデータ追加
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")
        guard var sessionWithData = usecase.currentSessions[session.id] else {
            #expect(Bool(false), "セッションが見つかりません")
            return
        }
        sessionWithData.observations = [recentObservation, oldObservation]
        usecase.currentSessions[session.id] = sessionWithData

        // 過去30分のデータのみフィルタリング
        let timeRange = DateInterval(start: oneMinuteAgo.addingTimeInterval(-1800), end: now)
        let filteredObservations = usecase.filterObservations(
            sessionId: session.id,
            qualityThreshold: 0.0,
            timeRange: timeRange
        )

        #expect(filteredObservations.count == 1)  // 最近のデータのみ
        #expect(filteredObservations[0].timestamp >= oneMinuteAgo.addingTimeInterval(-1800))
    }

    // MARK: - セッション品質統計テスト

    @Test("セッション品質統計計算")
    @MainActor
    func sessionQualityStatistics() async throws {
        let (usecase, _) = await createTestUsecase()
        let testObservations = self.createTestObservationPoints()

        // セッション作成とデータ追加
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")
        guard var sessionWithData = usecase.currentSessions[session.id] else {
            #expect(Bool(false), "セッションが見つかりません")
            return
        }
        sessionWithData.observations = testObservations
        usecase.currentSessions[session.id] = sessionWithData

        let statistics = usecase.getSessionQualityStatistics(session.id)

        guard let statistics else {
            #expect(Bool(false), "統計情報が取得できませんでした")
            return
        }
        #expect(statistics.totalPoints == 3)
        #expect(statistics.validPoints == 2)  // 品質0.3を除く2つ
        #expect(statistics.averageQuality > 0.5)
        #expect(statistics.lineOfSightPercentage < 100.0)  // nLoSデータが含まれる
        #expect(statistics.qualityAssessment.isEmpty == false)
    }

    // MARK: - エラーハンドリングテスト

    @Test("未接続状態でのセッション開始エラー")
    @MainActor
    func startSessionWithoutConnection() async throws {
        let (usecase, _) = await createTestUsecase()

        // 接続状態を未接続に変更
        usecase.connectionStatus = UWBConnectionStatus.disconnected

        // セッション開始を試行
        await #expect(throws: ObservationError.self) {
            try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")
        }
    }

    @Test("存在しないセッションの停止エラー")
    @MainActor
    func stopNonexistentSession() async throws {
        let (usecase, _) = await createTestUsecase()

        // 存在しないセッションIDでの停止を試行
        await #expect(throws: ObservationError.self) {
            try await usecase.stopObservationSession("nonexistent-session")
        }
    }

    // MARK: - リアルタイムデータ更新テスト

    @Test("リアルタイムデータ更新")
    @MainActor
    func realtimeDataUpdate() async throws {
        let (usecase, mockUWBManager) = await createTestUsecase()

        // セッション開始
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")

        // リアルタイムデータが空であることを確認
        #expect(usecase.realtimeObservations.isEmpty)

        // 新しい観測データをシミュレート（handleNewObservationは内部メソッドなので間接的にテスト）
        let newObservation = ObservationPoint(
            antennaId: "antenna1",
            position: Point3D(x: 1.0, y: 1.0, z: 0.1),
            quality: SignalQuality(strength: 0.8, isLineOfSight: true, confidenceLevel: 0.9, errorEstimate: 0.2),
            distance: 10.0,
            rssi: -45.0,
            sessionId: session.id
        )

        // UWBマネージャーから観測データが届いたことをシミュレート
        mockUWBManager.simulateObservation(newObservation)

        // 少し待って更新を確認
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒

        // リアルタイムデータが更新されていることを確認
        #expect(!usecase.realtimeObservations.isEmpty)
    }

    @Test("リアルタイムデータ上限テスト")
    @MainActor
    func realtimeDataLimit() async throws {
        let (usecase, mockUWBManager) = await createTestUsecase()

        // セッション開始
        let session = try await usecase.startObservationSession(for: "antenna1", name: "テストセッション")

        // 150個の観測データを送信（上限100を超える）
        for i in 0..<150 {
            let observation = ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: Double(i), y: 1.0, z: 0.1),
                quality: SignalQuality(strength: 0.8, isLineOfSight: true, confidenceLevel: 0.9, errorEstimate: 0.2),
                distance: 10.0,
                rssi: -45.0,
                sessionId: session.id
            )
            mockUWBManager.simulateObservation(observation)

            // 少し待つ
            try await Task.sleep(nanoseconds: 1_000_000)  // 0.001秒
        }

        // リアルタイムデータが100個に制限されていることを確認
        #expect(usecase.realtimeObservations.count <= 100)
    }
}

// MARK: - Mock Classes

/// モック観測データリポジトリ
class MockObservationDataRepository: DataRepositoryProtocol {
    private var calibrationDataStorage: [String: Data] = [:]

    func saveCalibrationData(_ data: CalibrationData) async throws {
        // JSONエンコードして安全に保存
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(data)
        self.calibrationDataStorage[data.antennaId] = encodedData
    }

    func loadCalibrationData() async throws -> [CalibrationData] {
        let decoder = JSONDecoder()
        return self.calibrationDataStorage.values.compactMap { data in
            try? decoder.decode(CalibrationData.self, from: data)
        }
    }

    func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        guard let data = calibrationDataStorage[antennaId] else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CalibrationData.self, from: data)
    }

    func deleteCalibrationData(for antennaId: String) async throws {
        self.calibrationDataStorage.removeValue(forKey: antennaId)
    }

    func deleteAllCalibrationData() async throws {
        self.calibrationDataStorage.removeAll()
    }

    func saveFieldAntennaConfiguration(_ antennas: [AntennaInfo]) {}
    func loadFieldAntennaConfiguration() -> [AntennaInfo]? {
        [
            AntennaInfo(id: "antenna1", name: "アンテナ1", coordinates: Point3D(x: 0, y: 0, z: 0))
        ]
    }

    func saveRecentSensingSessions(_ sessions: [SensingSession]) {}
    func loadRecentSensingSessions() -> [SensingSession] { [] }

    // 不足しているメソッドを追加
    func saveAntennaPositions(_ positions: [AntennaPositionData]) {}
    func loadAntennaPositions() -> [AntennaPositionData]? { nil }
    func saveAntennaPairings(_ pairings: [AntennaPairing]) {}
    func loadAntennaPairings() -> [AntennaPairing]? { nil }
    func saveHasDeviceConnected(_ connected: Bool) {}
    func loadHasDeviceConnected() -> Bool { false }
    func saveCalibrationResults(_ results: Data) {}
    func loadCalibrationResults() -> Data? { nil }
    func saveBoolSetting(key: String, value: Bool) {}
    func loadBoolSetting(key: String) -> Bool { false }
    func saveRecentSystemActivities(_ activities: [SystemActivity]) {}
    func loadRecentSystemActivities() -> [SystemActivity]? { nil }
    func saveData(_ data: some Codable, forKey key: String) throws {}
    func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? { nil }

    // SwiftDataRepositoryProtocol メソッド
    func saveSensingSession(_ session: SensingSession) async throws {}
    func loadSensingSession(by id: String) async throws -> SensingSession? { nil }
    func loadAllSensingSessions() async throws -> [SensingSession] { [] }
    func deleteSensingSession(by id: String) async throws {}
    func saveAntennaPosition(_ position: AntennaPositionData) async throws {}
    func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData] { [] }
    func deleteAntennaPosition(by antennaId: String) async throws {}
    func saveFloorMap(_ floorMap: FloorMapInfo) async throws {}
    func loadFloorMap(by id: String) async throws -> FloorMapInfo? { nil }
    func loadAllFloorMaps() async throws -> [FloorMapInfo] { [] }
    func deleteFloorMap(by id: String) async throws {}
    func saveMapCalibrationData(_ data: MapCalibrationData) async throws {}
    func loadMapCalibrationData(for floorMapId: String) async throws -> MapCalibrationData? { nil }
    func deleteMapCalibrationData(for floorMapId: String) async throws {}
}

/// モックUWBデータマネージャー
@MainActor
class MockUWBDataManager: UWBDataManager {
    // @Publishedプロパティは新しく定義し、親クラスのものを隠す
    @Published var mockConnectionStatus: UWBConnectionStatus = .connected
    @Published var mockLatestObservation: ObservationPoint?

    override init() {
        super.init()
        // 初期状態でconnectedに設定
        connectionStatus = .connected
    }

    override func startDataCollection(for antennaId: String, sessionId: String) async throws {
        self.mockConnectionStatus = .connected
        // 親クラスのプロパティも更新
        connectionStatus = .connected
        // シミュレーションデータの生成は省略
    }

    override func stopDataCollection(sessionId: String) async throws {
        // 何もしない
    }

    override func pauseDataCollection(sessionId: String) async throws {
        // 何もしない
    }

    override func resumeDataCollection(sessionId: String) async throws {
        // 何もしない
    }

    override func getLatestObservations(for sessionId: String) async -> [ObservationPoint] {
        []
    }

    // テスト用メソッド
    func simulateObservation(_ observation: ObservationPoint) {
        self.mockLatestObservation = observation
        // 親クラスのプロパティも更新
        latestObservation = observation
    }
}
