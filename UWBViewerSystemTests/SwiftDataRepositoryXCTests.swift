import XCTest
import SwiftData
@testable import UWBViewerSystem

@MainActor
final class SwiftDataRepositoryXCTests: XCTestCase {

    var repository: SwiftDataRepository!
    var modelContext: ModelContext!
    var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // テスト用のin-memoryコンテナを作成
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistentSensingSession.self,
                 PersistentAntennaPosition.self,
                 PersistentCalibrationData.self,
                 PersistentFloorMap.self,
                 PersistentMapCalibrationData.self,
            configurations: config
        )
        modelContext = ModelContext(container)
        repository = SwiftDataRepository(modelContext: modelContext)

        // テスト開始前にデータをクリーンアップ
        try modelContext.delete(model: PersistentSensingSession.self)
        try modelContext.delete(model: PersistentAntennaPosition.self)
        try modelContext.delete(model: PersistentCalibrationData.self)
        try modelContext.delete(model: PersistentFloorMap.self)
        try modelContext.delete(model: PersistentMapCalibrationData.self)
        try modelContext.save()
    }

    override func tearDownWithError() throws {
        // テストデータをクリーンアップ
        if let modelContext = modelContext {
            // 全てのデータを削除
            try modelContext.delete(model: PersistentSensingSession.self)
            try modelContext.delete(model: PersistentAntennaPosition.self)
            try modelContext.delete(model: PersistentCalibrationData.self)
            try modelContext.delete(model: PersistentFloorMap.self)
            try modelContext.delete(model: PersistentMapCalibrationData.self)
            try modelContext.save()
        }

        repository = nil
        modelContext = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - センシングセッション関連のテスト

    func testSaveSensingSession_正常ケース() async throws {
        // Arrange
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
        guard let loadedSession = loadedSession else {
            XCTFail("保存したセンシングセッションが読み込まれていません")
            return
        }

        XCTAssertEqual(loadedSession.id, session.id)
        XCTAssertEqual(loadedSession.name, session.name)
        XCTAssertEqual(loadedSession.isActive, session.isActive)
    }

    func testSaveSensingSession_空のIDでエラー() async throws {
        // Arrange
        let session = SensingSession(
            id: "",
            name: "テストセッション",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        // Act & Assert
        do {
            try await repository.saveSensingSession(session)
            XCTFail("エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .invalidData(let message):
                XCTAssertTrue(message.contains("ID"))
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    func testSaveSensingSession_空の名前でエラー() async throws {
        // Arrange
        let session = SensingSession(
            id: "test-session-1",
            name: "",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        // Act & Assert
        do {
            try await repository.saveSensingSession(session)
            XCTFail("エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .invalidData(let message):
                XCTAssertTrue(message.contains("センシングセッション名が空です"))
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    func testSaveSensingSession_重複IDでエラー() async throws {
        // Arrange
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
            XCTFail("重複エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .duplicateEntry:
                break // 期待される動作
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    // MARK: - アンテナ位置関連のテスト

    func testSaveAntennaPosition_正常ケース() async throws {
        // Arrange
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
        XCTAssertEqual(loadedPositions.count, 1, "保存したアンテナ位置データが読み込まれていません")

        guard let firstPosition = loadedPositions.first else {
            XCTFail("読み込まれたアンテナ位置データが空です")
            return
        }

        XCTAssertEqual(firstPosition.antennaId, position.antennaId)
        XCTAssertEqual(firstPosition.antennaName, position.antennaName)
        XCTAssertEqual(firstPosition.floorMapId, position.floorMapId)
        XCTAssertEqual(firstPosition.position.x, position.position.x, accuracy: 0.001)
        XCTAssertEqual(firstPosition.position.y, position.position.y, accuracy: 0.001)
        XCTAssertEqual(firstPosition.position.z, position.position.z, accuracy: 0.001)
        XCTAssertEqual(firstPosition.rotation, position.rotation, accuracy: 0.001)
    }

    func testSaveAntennaPosition_空のアンテナIDでエラー() async throws {
        // Arrange
        let position = AntennaPositionData(
            id: "test-position-1",
            antennaId: "",
            antennaName: "テストアンテナ",
            position: Point3D(x: 1.0, y: 2.0, z: 3.0),
            rotation: 45.0,
            floorMapId: "floor-1"
        )

        // Act & Assert
        do {
            try await repository.saveAntennaPosition(position)
            XCTFail("エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .invalidData(let message):
                XCTAssertTrue(message.contains("アンテナID"))
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    func testDeleteAntennaPosition_正常ケース() async throws {
        // Arrange
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
        try await repository.deleteAntennaPosition(by: "antenna-1")
        let loadedPositions = try await repository.loadAntennaPositions(for: "floor-1")

        XCTAssertEqual(loadedPositions.count, 0)
    }

    func testDeleteAntennaPosition_存在しないIDでエラー() async throws {
        // Act & Assert
        do {
            try await repository.deleteAntennaPosition(by: "non-existent-id")
            XCTFail("エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .notFound:
                break // 期待される動作
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    // MARK: - フロアマップ関連のテスト

    func testSaveFloorMap_正常ケース() async throws {
        // Arrange
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
        guard let loadedFloorMap = loadedFloorMap else {
            XCTFail("保存したフロアマップが読み込まれていません")
            return
        }

        XCTAssertEqual(loadedFloorMap.id, floorMap.id)
        XCTAssertEqual(loadedFloorMap.name, floorMap.name)
        XCTAssertEqual(loadedFloorMap.width, floorMap.width)
        XCTAssertEqual(loadedFloorMap.depth, floorMap.depth)
    }

    func testSaveFloorMap_無効なサイズでエラー() async throws {
        // Arrange
        let floorMap = FloorMapInfo(
            id: "floor-1",
            name: "テストフロア",
            buildingName: "テストビル",
            width: 0.0, // 無効なサイズ
            depth: 20.0,
            createdAt: Date()
        )

        // Act & Assert
        do {
            try await repository.saveFloorMap(floorMap)
            XCTFail("エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .invalidData(let message):
                XCTAssertTrue(message.contains("サイズ"))
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    // MARK: - キャリブレーションデータ関連のテスト

    func testSaveCalibrationData_正常ケース() async throws {
        // Arrange
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
        guard let loadedData = loadedData else {
            XCTFail("保存したキャリブレーションデータが読み込まれていません")
            return
        }

        XCTAssertEqual(loadedData.antennaId, calibrationData.antennaId)
        XCTAssertEqual(loadedData.calibrationPoints.count, 1)
        XCTAssertEqual(loadedData.isActive, calibrationData.isActive)
    }

    func testSaveCalibrationData_空のキャリブレーションポイントでエラー() async throws {
        // Arrange
        let calibrationData = CalibrationData(
            antennaId: "antenna-1",
            calibrationPoints: [], // 空の配列
            transform: nil,
            isActive: true
        )

        // Act & Assert
        do {
            try await repository.saveCalibrationData(calibrationData)
            XCTFail("エラーが発生すべきです")
        } catch let error as RepositoryError {
            switch error {
            case .invalidData(let message):
                XCTAssertTrue(message.contains("キャリブレーションポイント"))
            default:
                XCTFail("予期しないエラータイプ: \(error)")
            }
        }
    }

    // MARK: - パフォーマンステスト

    func testPerformance_大量アンテナ位置保存() throws {
        let floorMapId = "performance-test-floor"

        measure {
            Task {
                for i in 0..<100 {
                    let position = AntennaPositionData(
                        id: "position-\(i)",
                        antennaId: "antenna-\(i)",
                        antennaName: "アンテナ\(i)",
                        position: Point3D(x: Double(i), y: Double(i), z: 0.0),
                        rotation: 0.0,
                        floorMapId: floorMapId
                    )
                    try? await repository.saveAntennaPosition(position)
                }
            }
        }
    }
}