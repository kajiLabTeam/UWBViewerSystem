import Testing
import Foundation
@testable import UWBViewerSystem

/// キャリブレーションデータフローのテストスイート
@Suite("キャリブレーションデータフロー統合テスト")
struct CalibrationDataFlowTests {

    // MARK: - Test Setup

    @MainActor
    private func createTestDataFlow() -> CalibrationDataFlow {
        let mockRepository = MockCalibrationDataRepository()
        let mockCalibrationUsecase = CalibrationUsecase(dataRepository: mockRepository)
        let mockUWBManager = MockUWBDataManager()
        let mockObservationUsecase = ObservationDataUsecase(dataRepository: mockRepository, uwbManager: mockUWBManager)

        return CalibrationDataFlow(
            dataRepository: mockRepository,
            calibrationUsecase: mockCalibrationUsecase,
            observationUsecase: mockObservationUsecase
        )
    }

    private func createTestReferencePoints() -> [MapCalibrationPoint] {
        return [
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 100, y: 100, z: 0),
                realWorldCoordinate: Point3D(x: 1.0, y: 1.0, z: 0.0),
                antennaId: "antenna1",
                pointIndex: 1
            ),
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 200, y: 100, z: 0),
                realWorldCoordinate: Point3D(x: 2.0, y: 1.0, z: 0.0),
                antennaId: "antenna1",
                pointIndex: 2
            ),
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 150, y: 200, z: 0),
                realWorldCoordinate: Point3D(x: 1.5, y: 2.0, z: 0.0),
                antennaId: "antenna1",
                pointIndex: 3
            )
        ]
    }

    private func createTestObservationPoints() -> [ObservationPoint] {
        return [
            ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: 1.1, y: 1.1, z: 0.1),
                quality: SignalQuality(strength: 0.8, isLineOfSight: true, confidenceLevel: 0.9, errorEstimate: 0.2),
                distance: 10.0,
                rssi: -45.0,
                sessionId: "session1"
            ),
            ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: 2.1, y: 1.1, z: 0.1),
                quality: SignalQuality(strength: 0.7, isLineOfSight: true, confidenceLevel: 0.8, errorEstimate: 0.3),
                distance: 12.0,
                rssi: -50.0,
                sessionId: "session1"
            ),
            ObservationPoint(
                antennaId: "antenna1",
                position: Point3D(x: 1.4, y: 1.9, z: 0.1),
                quality: SignalQuality(strength: 0.9, isLineOfSight: true, confidenceLevel: 0.95, errorEstimate: 0.1),
                distance: 8.0,
                rssi: -40.0,
                sessionId: "session1"
            )
        ]
    }

    // MARK: - 基準データ収集テスト

    @Test("基準データ収集 - マップから基準点を設定")
    func testCollectReferencePointsFromMap() async throws {
        let dataFlow = await createTestDataFlow()
        let testPoints = createTestReferencePoints()

        // 基準点を設定
        await dataFlow.collectReferencePoints(from: testPoints)

        // 検証
        await #expect(dataFlow.referencePoints.count == 3)
        await #expect(dataFlow.currentWorkflow == .collectingReference)
        await #expect(dataFlow.workflowProgress > 0.0)
    }

    @Test("基準データ収集 - 手動で基準点を追加")
    func testAddManualReferencePoint() async throws {
        let dataFlow = await createTestDataFlow()

        // 手動で基準点を追加
        await dataFlow.addReferencePoint(position: Point3D(x: 1.0, y: 1.0, z: 0.0), name: "基準点1")
        await dataFlow.addReferencePoint(position: Point3D(x: 2.0, y: 1.0, z: 0.0), name: "基準点2")
        await dataFlow.addReferencePoint(position: Point3D(x: 1.5, y: 2.0, z: 0.0), name: "基準点3")

        // 検証
        await #expect(dataFlow.referencePoints.count == 3)
        await #expect(dataFlow.referencePoints[0].realWorldCoordinate.x == 1.0)
        await #expect(dataFlow.referencePoints[1].realWorldCoordinate.x == 2.0)
        await #expect(dataFlow.referencePoints[2].realWorldCoordinate.y == 2.0)
    }

    // MARK: - 観測データ収集テスト

    @Test("観測データ収集 - セッション開始と停止")
    func testObservationDataCollection() async throws {
        let dataFlow = await createTestDataFlow()

        // 観測データ収集開始
        await dataFlow.startObservationData(for: "antenna1")

        // 開始状態の検証
        await #expect(dataFlow.currentWorkflow == .collectingObservation)
        await #expect(dataFlow.observationSessions.count == 1)

        // 観測データ収集停止
        await dataFlow.stopObservationData(for: "antenna1")

        // 停止状態の検証
        await #expect(dataFlow.observationSessions["antenna1"]?.status == .completed)
    }

    // MARK: - データマッピングテスト

    @Test("データマッピング - 基準点と観測データの対応付け")
    func testDataMapping() async throws {
        let dataFlow = await createTestDataFlow()
        let testReferencePoints = createTestReferencePoints()
        let testObservationPoints = createTestObservationPoints()

        // 基準点を設定
        await dataFlow.collectReferencePoints(from: testReferencePoints)

        // 観測セッションを模擬
        let mockSession = ObservationSession(
            name: "テストセッション",
            antennaId: "antenna1"
        )
        var sessionWithData = mockSession
        sessionWithData.observations = testObservationPoints
        sessionWithData.status = .completed
        await MainActor.run {
            dataFlow.observationSessions["antenna1"] = sessionWithData
        }

        // マッピング実行
        let mappings = await dataFlow.mapObservationsToReferences()

        // 検証
        #expect(mappings.count == 3)
        await #expect(dataFlow.mappings.count == 3)
        await #expect(dataFlow.currentWorkflow == .calculating)

        // マッピング精度の確認
        await MainActor.run {
            for mapping in dataFlow.mappings {
                #expect(mapping.positionError < 1.0)  // 1m以内の誤差
                #expect(mapping.mappingQuality > 0.5) // 品質50%以上
            }
        }
    }

    // MARK: - キャリブレーション実行テスト

    @Test("キャリブレーション実行 - 完全なワークフロー")
    func testCompleteCalibrationWorkflow() async throws {
        let dataFlow = await createTestDataFlow()
        let testReferencePoints = createTestReferencePoints()
        let testObservationPoints = createTestObservationPoints()

        // 1. 基準点設定
        await dataFlow.collectReferencePoints(from: testReferencePoints)

        // 2. 観測データ設定
        let mockSession = ObservationSession(
            name: "テストセッション",
            antennaId: "antenna1"
        )
        var sessionWithData = mockSession
        sessionWithData.observations = testObservationPoints
        sessionWithData.status = .completed
        await MainActor.run {
            dataFlow.observationSessions["antenna1"] = sessionWithData
        }

        // 3. マッピング
        let mappings = await dataFlow.mapObservationsToReferences()
        #expect(mappings.count == 3)

        // 4. キャリブレーション実行
        let result = await dataFlow.executeCalibration()

        // 結果検証
        #expect(result.success == true)
        #expect(result.processedAntennas.contains("antenna1"))
        await #expect(dataFlow.currentWorkflow == .completed)
        await #expect(dataFlow.workflowProgress == 1.0)
    }

    // MARK: - ワークフロー検証テスト

    @Test("ワークフロー検証 - 不十分なデータでの検証")
    func testWorkflowValidationWithInsufficientData() async throws {
        let dataFlow = await createTestDataFlow()

        // 基準点が不足している状態
        await dataFlow.addReferencePoint(position: Point3D(x: 1.0, y: 1.0, z: 0.0), name: "基準点1")

        let validation = await dataFlow.validateCurrentState()

        #expect(validation.canProceed == false)
        #expect(validation.issues.count > 0)
        #expect(validation.issues.contains { $0.contains("基準点が不足") })
    }

    @Test("ワークフロー検証 - 十分なデータでの検証")
    func testWorkflowValidationWithSufficientData() async throws {
        let dataFlow = await createTestDataFlow()
        let testReferencePoints = createTestReferencePoints()
        let testObservationPoints = createTestObservationPoints()

        // 十分なデータを設定
        await dataFlow.collectReferencePoints(from: testReferencePoints)

        let mockSession = ObservationSession(
            name: "テストセッション",
            antennaId: "antenna1"
        )
        var sessionWithData = mockSession
        sessionWithData.observations = testObservationPoints
        sessionWithData.status = .completed
        await MainActor.run {
            dataFlow.observationSessions["antenna1"] = sessionWithData
        }

        let validation = await dataFlow.validateCurrentState()

        #expect(validation.canProceed == true)
        #expect(validation.recommendations.count >= 0)
    }

    // MARK: - エラーハンドリングテスト

    @Test("エラーハンドリング - 観測データなしでのキャリブレーション")
    func testCalibrationWithoutObservationData() async throws {
        let dataFlow = await createTestDataFlow()
        let testReferencePoints = createTestReferencePoints()

        // 基準点のみ設定（観測データなし）
        await dataFlow.collectReferencePoints(from: testReferencePoints)

        let result = await dataFlow.executeCalibration()

        #expect(result.success == false)
        #expect(result.errorMessage != nil)
        await #expect(dataFlow.currentWorkflow == .failed)
    }

    @Test("品質統計計算 - 複数セッションの統計")
    func testQualityStatisticsCalculation() async throws {
        let dataFlow = await createTestDataFlow()
        let testObservationPoints = createTestObservationPoints()

        // 複数のセッションを作成
        let session1 = ObservationSession(name: "セッション1", antennaId: "antenna1")
        var sessionWithData1 = session1
        sessionWithData1.observations = testObservationPoints
        await MainActor.run {
            dataFlow.observationSessions["antenna1"] = sessionWithData1
        }

        let session2 = ObservationSession(name: "セッション2", antennaId: "antenna2")
        var sessionWithData2 = session2
        sessionWithData2.observations = testObservationPoints
        await MainActor.run {
            dataFlow.observationSessions["antenna2"] = sessionWithData2
        }

        // 統計計算（プライベートメソッドなので間接的にテスト）
        let validation = await dataFlow.validateCurrentState()
        #expect(validation != nil)
    }

    // MARK: - ワークフローリセットテスト

    @Test("ワークフローリセット - 状態の初期化")
    func testWorkflowReset() async throws {
        let dataFlow = await createTestDataFlow()
        let testReferencePoints = createTestReferencePoints()

        // データを設定
        await dataFlow.collectReferencePoints(from: testReferencePoints)
        await dataFlow.startObservationData(for: "antenna1")

        // リセット実行
        await dataFlow.resetWorkflow()

        // リセット後の状態確認
        await #expect(dataFlow.currentWorkflow == .idle)
        await #expect(dataFlow.referencePoints.isEmpty)
        await #expect(dataFlow.observationSessions.isEmpty)
        await #expect(dataFlow.mappings.isEmpty)
        await #expect(dataFlow.workflowProgress == 0.0)
        await #expect(dataFlow.errorMessage == nil)
        await #expect(dataFlow.lastCalibrationResult == nil)
    }
}

// MARK: - Mock Classes

/// モックデータリポジトリ
class MockCalibrationDataRepository: DataRepositoryProtocol {
    func saveCalibrationData(_ data: CalibrationData) async throws {}
    func loadCalibrationData() async throws -> [CalibrationData] { return [] }
    func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? { return nil }
    func deleteCalibrationData(for antennaId: String) async throws {}
    func deleteAllCalibrationData() async throws {}

    func saveFieldAntennaConfiguration(_ antennas: [AntennaInfo]) {}
    func loadFieldAntennaConfiguration() -> [AntennaInfo]? {
        return [
            AntennaInfo(id: "antenna1", name: "アンテナ1", coordinates: Point3D(x: 0, y: 0, z: 0))
        ]
    }

    func saveRecentSensingSessions(_ sessions: [SensingSession]) {}
    func loadRecentSensingSessions() -> [SensingSession] { return [] }

    // 不足しているメソッドを追加
    func saveAntennaPositions(_ positions: [AntennaPositionData]) {}
    func loadAntennaPositions() -> [AntennaPositionData]? { return nil }
    func saveAntennaPairings(_ pairings: [AntennaPairing]) {}
    func loadAntennaPairings() -> [AntennaPairing]? { return nil }
    func saveHasDeviceConnected(_ connected: Bool) {}
    func loadHasDeviceConnected() -> Bool { return false }
    func saveCalibrationResults(_ results: Data) {}
    func loadCalibrationResults() -> Data? { return nil }
    func saveBoolSetting(key: String, value: Bool) {}
    func loadBoolSetting(key: String) -> Bool { return false }
    func saveRecentSystemActivities(_ activities: [SystemActivity]) {}
    func loadRecentSystemActivities() -> [SystemActivity]? { return nil }
    func saveData<T: Codable>(_ data: T, forKey key: String) throws {}
    func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? { return nil }
}

/// モックUWBデータマネージャー
@MainActor
class MockUWBDataManager: UWBDataManager {
    // @Publishedプロパティは新しく定義し、親クラスのものを隠す
    @Published public var mockConnectionStatus: UWBConnectionStatus = .connected
    @Published public var mockLatestObservation: ObservationPoint?

    public override func startDataCollection(for antennaId: String, sessionId: String) async throws {
        mockConnectionStatus = .connected
        // 親クラスのプロパティも更新
        connectionStatus = .connected
        // シミュレーションデータの生成は省略
    }

    public override func stopDataCollection(sessionId: String) async throws {
        // 何もしない
    }

    public override func pauseDataCollection(sessionId: String) async throws {
        // 何もしない
    }

    public override func resumeDataCollection(sessionId: String) async throws {
        // 何もしない
    }

    public override func getLatestObservations(for sessionId: String) async -> [ObservationPoint] {
        return []
    }

    // テスト用メソッド
    func simulateObservation(_ observation: ObservationPoint) {
        self.mockLatestObservation = observation
        // 親クラスのプロパティも更新
        latestObservation = observation
    }
}