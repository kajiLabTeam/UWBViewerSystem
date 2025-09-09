//
//  UWBViewerSystemTests.swift
//  UWBViewerSystemTests
//
//  Created by はるちろ on R 7/07/08.
//

import Foundation
import SwiftData
import Testing
@testable import UWBViewerSystem

struct UWBViewerSystemTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
}

// MARK: - SwiftDataRepository Tests

struct SwiftDataRepositoryTests {

    @MainActor
    private func createInMemoryRepository() throws -> SwiftDataRepository {
        let schema = Schema([
            PersistentSensingSession.self,
            PersistentAntennaPosition.self,
            PersistentAntennaPairing.self,
            PersistentRealtimeData.self,
            PersistentSystemActivity.self,
            PersistentFloorMap.self,
            PersistentProjectProgress.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let modelContext = ModelContext(modelContainer)

        return SwiftDataRepository(modelContext: modelContext)
    }

    @Test("センシングセッション保存・読み込みテスト")
    @MainActor
    func testSensingSessionSaveAndLoad() async throws {
        let repository = try createInMemoryRepository()

        // テストデータを作成
        let testSession = SensingSession(
            id: "test_session_1",
            name: "Test Session",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isActive: false
        )

        // 保存
        try await repository.saveSensingSession(testSession)

        // 読み込み
        let loadedSession = try await repository.loadSensingSession(by: testSession.id)
        #expect(loadedSession != nil)
        #expect(loadedSession?.id == testSession.id)
        #expect(loadedSession?.name == testSession.name)
        #expect(loadedSession?.isActive == testSession.isActive)

        // 全てのセッションを読み込み
        let allSessions = try await repository.loadAllSensingSessions()
        #expect(allSessions.count == 1)
        #expect(allSessions.first?.id == testSession.id)

        // 削除
        try await repository.deleteSensingSession(by: testSession.id)
        let deletedSession = try await repository.loadSensingSession(by: testSession.id)
        #expect(deletedSession == nil)
    }

    @Test("アンテナペアリング保存・読み込みテスト")
    @MainActor
    func testAntennaPairingSaveAndLoad() async throws {
        let repository = try createInMemoryRepository()

        // テストデータを作成
        let antenna = AntennaInfo(
            id: "antenna_1",
            name: "Test Antenna",
            coordinates: Point3D(x: 1.0, y: 2.0, z: 3.0)
        )

        let device = AndroidDevice(
            id: "device_1",
            name: "Test Device",
            isConnected: true,
            isNearbyDevice: true
        )

        let testPairing = AntennaPairing(antenna: antenna, device: device)

        // 保存
        try await repository.saveAntennaPairing(testPairing)

        // 読み込み
        let loadedPairings = try await repository.loadAntennaPairings()
        #expect(loadedPairings.count == 1)
        let loadedPairing = loadedPairings.first!
        #expect(loadedPairing.id == testPairing.id)
        #expect(loadedPairing.antenna.id == antenna.id)
        #expect(loadedPairing.device.id == device.id)

        // 削除
        try await repository.deleteAntennaPairing(by: testPairing.id)
        let emptyPairings = try await repository.loadAntennaPairings()
        #expect(emptyPairings.isEmpty)
    }

    @Test("アンテナ位置データ保存・読み込みテスト")
    @MainActor
    func testAntennaPositionSaveAndLoad() async throws {
        let repository = try createInMemoryRepository()

        // テストデータを作成
        let testPosition = AntennaPositionData(
            id: "pos_1",
            antennaId: "antenna_1",
            antennaName: "Test Antenna Position",
            position: Point3D(x: 10.0, y: 20.0, z: 30.0),
            rotation: 45.0,
            floorMapId: "test_floor_1"
        )

        // 保存
        try await repository.saveAntennaPosition(testPosition)

        // 読み込み
        let loadedPositions = try await repository.loadAntennaPositions()
        #expect(loadedPositions.count == 1)
        let loadedPosition = loadedPositions.first!
        #expect(loadedPosition.id == testPosition.id)
        #expect(loadedPosition.antennaId == testPosition.antennaId)
        #expect(loadedPosition.antennaName == testPosition.antennaName)
        #expect(loadedPosition.position.x == testPosition.position.x)
        #expect(loadedPosition.rotation == testPosition.rotation)

        // 削除
        try await repository.deleteAntennaPosition(by: testPosition.id)
        let emptyPositions = try await repository.loadAntennaPositions()
        #expect(emptyPositions.isEmpty)
    }

    @Test("プロジェクト進行状況保存・読み込みテスト")
    @MainActor
    func testProjectProgressSaveAndLoad() async throws {
        let repository = try createInMemoryRepository()

        // テストデータを作成
        let testProgress = ProjectProgress(
            id: "test_progress_1",
            floorMapId: "test_floor_1",
            currentStep: .antennaConfiguration,
            completedSteps: [.floorMapSetting, .antennaConfiguration]
        )

        // 保存
        try await repository.saveProjectProgress(testProgress)

        // ID指定で読み込み
        let loadedProgress = try await repository.loadProjectProgress(by: testProgress.id)
        #expect(loadedProgress != nil)
        #expect(loadedProgress?.id == testProgress.id)
        #expect(loadedProgress?.floorMapId == testProgress.floorMapId)
        #expect(loadedProgress?.currentStep == testProgress.currentStep)
        #expect(loadedProgress?.completedSteps == testProgress.completedSteps)

        // フロアマップID指定で読み込み
        let progressByFloorMap = try await repository.loadProjectProgress(for: testProgress.floorMapId)
        #expect(progressByFloorMap?.id == testProgress.id)

        // 全件取得
        let allProgress = try await repository.loadAllProjectProgress()
        #expect(allProgress.count == 1)
        #expect(allProgress.first?.id == testProgress.id)

        // 更新テスト
        var updatedProgress = testProgress
        updatedProgress.currentStep = .devicePairing
        updatedProgress.completedSteps.insert(.devicePairing)
        updatedProgress.updatedAt = Date()

        try await repository.updateProjectProgress(updatedProgress)

        let updatedLoadedProgress = try await repository.loadProjectProgress(by: testProgress.id)
        #expect(updatedLoadedProgress?.currentStep == .devicePairing)
        #expect(updatedLoadedProgress?.completedSteps.contains(.devicePairing) == true)

        // 削除
        try await repository.deleteProjectProgress(by: testProgress.id)
        let deletedProgress = try await repository.loadProjectProgress(by: testProgress.id)
        #expect(deletedProgress == nil)
    }
}

// MARK: - ViewModel Tests with Mock Repository

class MockSwiftDataRepository: SwiftDataRepositoryProtocol {
    private var sessions: [SensingSession] = []
    private var pairings: [AntennaPairing] = []
    private var positions: [AntennaPositionData] = []
    private var floorMaps: [FloorMapInfo] = []
    private var projectProgresses: [ProjectProgress] = []

    func saveSensingSession(_ session: SensingSession) async throws {
        sessions.append(session)
    }

    func loadSensingSession(by id: String) async throws -> SensingSession? {
        sessions.first { $0.id == id }
    }

    func loadAllSensingSessions() async throws -> [SensingSession] {
        sessions.sorted { $0.startTime > $1.startTime }
    }

    func deleteSensingSession(by id: String) async throws {
        sessions.removeAll { $0.id == id }
    }

    func updateSensingSession(_ session: SensingSession) async throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    func saveAntennaPairing(_ pairing: AntennaPairing) async throws {
        pairings.append(pairing)
    }

    func loadAntennaPairings() async throws -> [AntennaPairing] {
        pairings.sorted { $0.pairedAt > $1.pairedAt }
    }

    func deleteAntennaPairing(by id: String) async throws {
        pairings.removeAll { $0.id == id }
    }

    func updateAntennaPairing(_ pairing: AntennaPairing) async throws {
        if let index = pairings.firstIndex(where: { $0.id == pairing.id }) {
            pairings[index] = pairing
        }
    }

    func saveAntennaPosition(_ position: AntennaPositionData) async throws {
        positions.append(position)
    }

    func loadAntennaPositions() async throws -> [AntennaPositionData] {
        positions.sorted { $0.antennaName < $1.antennaName }
    }

    func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData] {
        positions.filter { $0.floorMapId == floorMapId }.sorted { $0.antennaName < $1.antennaName }
    }

    func deleteAntennaPosition(by id: String) async throws {
        positions.removeAll { $0.id == id }
    }

    func updateAntennaPosition(_ position: AntennaPositionData) async throws {
        if let index = positions.firstIndex(where: { $0.id == position.id }) {
            positions[index] = position
        }
    }

    // 他の実装はダミー
    func saveRealtimeData(_ data: RealtimeData, sessionId: String) async throws {}
    func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData] { [] }
    func deleteRealtimeData(by id: UUID) async throws {}
    func saveSystemActivity(_ activity: SystemActivity) async throws {}
    func loadRecentSystemActivities(limit: Int) async throws -> [SystemActivity] { [] }
    func deleteOldSystemActivities(olderThan date: Date) async throws {}

    // 受信ファイル関連ダミー実装
    func saveReceivedFile(_ file: ReceivedFile) async throws {}
    func loadReceivedFiles() async throws -> [ReceivedFile] { [] }
    func deleteReceivedFile(by id: UUID) async throws {}
    func deleteAllReceivedFiles() async throws {}

    // フロアマップ関連実装
    func saveFloorMap(_ floorMap: FloorMapInfo) async throws {
        floorMaps.append(floorMap)
    }

    func loadAllFloorMaps() async throws -> [FloorMapInfo] {
        floorMaps.sorted { $0.createdAt > $1.createdAt }
    }

    func loadFloorMap(by id: String) async throws -> FloorMapInfo? {
        floorMaps.first { $0.id == id }
    }

    func deleteFloorMap(by id: String) async throws {
        floorMaps.removeAll { $0.id == id }
    }

    func setActiveFloorMap(id: String) async throws {
        // テスト用なので実装省略
    }

    func saveProjectProgress(_ progress: ProjectProgress) async throws {
        projectProgresses.append(progress)
    }

    func loadProjectProgress(by id: String) async throws -> ProjectProgress? {
        projectProgresses.first { $0.id == id }
    }

    func loadProjectProgress(for floorMapId: String) async throws -> ProjectProgress? {
        projectProgresses.first { $0.floorMapId == floorMapId }
    }

    func loadAllProjectProgress() async throws -> [ProjectProgress] {
        projectProgresses.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteProjectProgress(by id: String) async throws {
        projectProgresses.removeAll { $0.id == id }
    }

    func updateProjectProgress(_ progress: ProjectProgress) async throws {
        if let index = projectProgresses.firstIndex(where: { $0.id == progress.id }) {
            projectProgresses[index] = progress
        } else {
            projectProgresses.append(progress)
        }
    }
}

struct PairingSettingViewModelTests {

    @Test("PairingSettingViewModel データ保存・読み込みテスト")
    @MainActor
    func testPairingDataSaveAndLoad() async throws {
        let mockRepository = MockSwiftDataRepository()
        let viewModel = PairingSettingViewModel(swiftDataRepository: mockRepository)

        // テストデータ準備
        let antenna = AntennaInfo(
            id: "test_antenna",
            name: "Test Antenna",
            coordinates: Point3D(x: 1.0, y: 2.0, z: 3.0)
        )

        let device = AndroidDevice(
            id: "test_device",
            name: "Test Device",
            isConnected: true,
            isNearbyDevice: true
        )

        // アンテナとデバイスを設定
        viewModel.selectedAntennas.append(antenna)
        viewModel.availableDevices.append(device)

        // ペアリングを実行
        viewModel.pairAntennaWithDevice(antenna: antenna, device: device)

        // 少し待機（非同期処理のため）
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // ペアリングが成功したかチェック
        #expect(viewModel.antennaPairings.count == 1)
        #expect(viewModel.antennaPairings.first?.antenna.id == antenna.id)
        #expect(viewModel.antennaPairings.first?.device.id == device.id)
        #expect(viewModel.isConnected == true)
    }
}

struct DataDisplayViewModelTests {

    @Test("DataDisplayViewModel 履歴データ読み込みテスト")
    @MainActor
    func testHistoryDataLoading() async throws {
        let mockRepository = MockSwiftDataRepository()
        let viewModel = DataDisplayViewModel(swiftDataRepository: mockRepository)

        // テストセッションを追加
        let testSession = SensingSession(
            id: "test_session",
            name: "Test History Session",
            startTime: Date().addingTimeInterval(-3600),
            endTime: Date(),
            isActive: false
        )

        try await mockRepository.saveSensingSession(testSession)

        // データを再読み込み
        viewModel.refreshHistoryData()

        // 少し待機（非同期処理のため）
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // 履歴データが読み込まれたかチェック
        #expect(viewModel.historyData.count == 1)
        #expect(viewModel.historyData.first?.id == testSession.id)
    }
}
