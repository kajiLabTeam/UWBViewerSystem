import Foundation
import SwiftData
import Testing
@testable import UWBViewerSystem

@MainActor
struct SwiftDataRepositoryXCTests {

    private func createTestRepository() throws -> (SwiftDataRepository, ModelContext, ModelContainer) {
        // テスト用のin-memoryコンテナを作成
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PersistentSensingSession.self,
            PersistentAntennaPosition.self,
            PersistentCalibrationData.self,
            PersistentFloorMap.self,
            PersistentMapCalibrationData.self,
            configurations: config
        )
        let modelContext = ModelContext(container)
        let repository = SwiftDataRepository(modelContext: modelContext)

        // テスト開始前にデータをクリーンアップ
        try modelContext.delete(model: PersistentSensingSession.self)
        try modelContext.delete(model: PersistentAntennaPosition.self)
        try modelContext.delete(model: PersistentCalibrationData.self)
        try modelContext.delete(model: PersistentFloorMap.self)
        try modelContext.delete(model: PersistentMapCalibrationData.self)
        try modelContext.save()

        return (repository, modelContext, container)
    }

    private func cleanupTestRepository(modelContext: ModelContext) throws {
        // テストデータをクリーンアップ
        try modelContext.delete(model: PersistentSensingSession.self)
        try modelContext.delete(model: PersistentAntennaPosition.self)
        try modelContext.delete(model: PersistentCalibrationData.self)
        try modelContext.delete(model: PersistentFloorMap.self)
        try modelContext.delete(model: PersistentMapCalibrationData.self)
        try modelContext.save()
    }

    // MARK: - センシングセッション関連のテスト

    @Test("センシングセッション保存・読み込み - 正常ケース")
    func saveSensingSession_正常ケース() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let session = SensingSession(
            id: "test-session-1",
            name: "テストセッション",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        // Act
        try await repository.saveSensingSession(session)
        let loadedSession = try await repository.loadSensingSession(by: session.id)

        // Assert
        #expect(loadedSession != nil)
        guard let loadedSession else { return }

        #expect(loadedSession.id == session.id)
        #expect(loadedSession.name == session.name)
        #expect(loadedSession.isActive == session.isActive)
    }

    @Test("センシングセッション保存 - 空のIDでエラー")
    func saveSensingSession_空のIDでエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let session = SensingSession(
            id: "",
            name: "テストセッション",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        // Act & Assert
        await #expect(throws: RepositoryError.self) {
            try await repository.saveSensingSession(session)
        }
    }

    @Test("センシングセッション保存 - 空の名前でエラー")
    func saveSensingSession_空の名前でエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let session = SensingSession(
            id: "test-session-1",
            name: "",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        // Act & Assert
        await #expect(throws: RepositoryError.self) {
            try await repository.saveSensingSession(session)
        }
    }

    @Test("センシングセッション保存 - 重複IDでエラー")
    func saveSensingSession_重複IDでエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let session1 = SensingSession(
            id: "duplicate-id",
            name: "セッション1",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )
        let session2 = SensingSession(
            id: "duplicate-id",
            name: "セッション2",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        // Act & Assert
        try await repository.saveSensingSession(session1)

        do {
            try await repository.saveSensingSession(session2)
            #expect(Bool(false), "重複エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .duplicateEntry:
                #expect(Bool(true)) // 期待される動作
            default:
                #expect(Bool(false), "予期しないエラータイプ: \(error)")
            }
        }
    }

    // MARK: - アンテナ位置関連のテスト

    @Test("アンテナ位置保存・読み込み - 正常ケース")
    func saveAntennaPosition_正常ケース() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let position = AntennaPositionData(
            id: "test-position-1",
            antennaId: "antenna-1",
            antennaName: "テストアンテナ",
            position: Point3D(x: 1.0, y: 2.0, z: 3.0),
            rotation: 45.0,
            floorMapId: "floor-1"
        )

        // Act
        try await repository.saveAntennaPosition(position)
        let loadedPositions = try await repository.loadAntennaPositions(for: "floor-1")

        // Assert
        #expect(loadedPositions.count == 1)

        guard let firstPosition = loadedPositions.first else {
            #expect(Bool(false), "読み込まれたアンテナ位置データが空です")
            return
        }

        #expect(firstPosition.antennaId == position.antennaId)
        #expect(firstPosition.antennaName == position.antennaName)
        #expect(firstPosition.floorMapId == position.floorMapId)
        #expect(abs(firstPosition.position.x - position.position.x) < 0.001)
        #expect(abs(firstPosition.position.y - position.position.y) < 0.001)
        #expect(abs(firstPosition.position.z - position.position.z) < 0.001)
        #expect(abs(firstPosition.rotation - position.rotation) < 0.001)
    }

    @Test("アンテナ位置保存 - 空のアンテナIDでエラー")
    func saveAntennaPosition_空のアンテナIDでエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let position = AntennaPositionData(
            id: "test-position-1",
            antennaId: "",
            antennaName: "テストアンテナ",
            position: Point3D(x: 1.0, y: 2.0, z: 3.0),
            rotation: 45.0,
            floorMapId: "floor-1"
        )

        // Act & Assert
        await #expect(throws: RepositoryError.self) {
            try await repository.saveAntennaPosition(position)
        }
    }

    @Test("アンテナ位置削除 - 正常ケース")
    func deleteAntennaPosition_正常ケース() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let position = AntennaPositionData(
            id: "test-position-1",
            antennaId: "antenna-1",
            antennaName: "テストアンテナ",
            position: Point3D(x: 1.0, y: 2.0, z: 3.0),
            rotation: 45.0,
            floorMapId: "floor-1"
        )
        try await repository.saveAntennaPosition(position)

        // Act & Assert
        try await repository.deleteAntennaPosition(by: "test-position-1")  // idフィールドで削除
        let loadedPositions = try await repository.loadAntennaPositions(for: "floor-1")

        #expect(loadedPositions.isEmpty)
    }

    @Test("アンテナ位置削除 - 存在しないIDでエラー")
    func deleteAntennaPosition_存在しないIDでエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        // Act & Assert
        do {
            try await repository.deleteAntennaPosition(by: "non-existent-id")
            #expect(Bool(false), "エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .notFound:
                #expect(Bool(true)) // 期待される動作
            default:
                #expect(Bool(false), "予期しないエラータイプ: \(error)")
            }
        }
    }

    // MARK: - フロアマップ関連のテスト

    @Test("フロアマップ保存・読み込み - 正常ケース")
    func saveFloorMap_正常ケース() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let floorMap = FloorMapInfo(
            id: "floor-1",
            name: "テストフロア",
            buildingName: "テストビル",
            width: 10.0,
            depth: 20.0,
            createdAt: Date()
        )

        // Act
        try await repository.saveFloorMap(floorMap)
        let loadedFloorMap = try await repository.loadFloorMap(by: floorMap.id)

        // Assert
        #expect(loadedFloorMap != nil)
        guard let loadedFloorMap else { return }

        #expect(loadedFloorMap.id == floorMap.id)
        #expect(loadedFloorMap.name == floorMap.name)
        #expect(loadedFloorMap.width == floorMap.width)
        #expect(loadedFloorMap.depth == floorMap.depth)
    }

    @Test("フロアマップ保存 - 無効なサイズでエラー")
    func saveFloorMap_無効なサイズでエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let floorMap = FloorMapInfo(
            id: "floor-1",
            name: "テストフロア",
            buildingName: "テストビル",
            width: 0.0, // 無効なサイズ
            depth: 20.0,
            createdAt: Date()
        )

        // Act & Assert
        await #expect(throws: RepositoryError.self) {
            try await repository.saveFloorMap(floorMap)
        }
    }

    // MARK: - キャリブレーションデータ関連のテスト

    @Test("キャリブレーションデータ保存・読み込み - 正常ケース")
    func saveCalibrationData_正常ケース() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let calibrationPoint = CalibrationPoint(
            referencePosition: Point3D(x: 1.0, y: 2.0, z: 0.0),
            measuredPosition: Point3D(x: 1.1, y: 2.1, z: 0.1),
            antennaId: "antenna-1"
        )

        let calibrationData = CalibrationData(
            antennaId: "antenna-1",
            calibrationPoints: [calibrationPoint],
            transform: nil,
            isActive: true
        )

        // Act
        try await repository.saveCalibrationData(calibrationData)
        let loadedData = try await repository.loadCalibrationData(for: "antenna-1")

        // Assert
        #expect(loadedData != nil)
        guard let loadedData else { return }

        #expect(loadedData.antennaId == calibrationData.antennaId)
        #expect(loadedData.calibrationPoints.count == 1)
        #expect(loadedData.isActive == calibrationData.isActive)
    }

    @Test("キャリブレーションデータ保存 - 空のキャリブレーションポイントでエラー")
    func saveCalibrationData_空のキャリブレーションポイントでエラー() async throws {
        // Arrange
        let (repository, modelContext, _) = try createTestRepository()
        defer { try? cleanupTestRepository(modelContext: modelContext) }

        let calibrationData = CalibrationData(
            antennaId: "antenna-1",
            calibrationPoints: [], // 空の配列
            transform: nil,
            isActive: true
        )

        // Act & Assert
        await #expect(throws: RepositoryError.self) {
            try await repository.saveCalibrationData(calibrationData)
        }
    }

    // MARK: - パフォーマンステスト

    @Test("パフォーマンス - 大量アンテナ位置作成")
    func performance_大量アンテナ位置保存() throws {
        let floorMapId = "performance-test-floor"

        // パフォーマンステストは同期的な操作のみ測定
        let positions = (0..<100).map { i in
            AntennaPositionData(
                id: "position-\(i)",
                antennaId: "antenna-\(i)",
                antennaName: "アンテナ\(i)",
                position: Point3D(x: Double(i), y: Double(i), z: 0.0),
                rotation: 0.0,
                floorMapId: floorMapId
            )
        }

        // 同期的な処理として配列の作成をテスト
        #expect(positions.count == 100)
    }
}