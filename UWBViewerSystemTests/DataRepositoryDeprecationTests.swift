import Foundation
import SwiftData
import Testing

@testable import UWBViewerSystem

/// DataRepository廃止計画Phase 1の検証テスト
///
/// ## 目的
/// DataRepositoryからSwiftDataRepositoryへの段階的移行を検証する
///
/// ## Phase 1の検証内容
/// 1. DataRepository使用箇所の特定と文書化
/// 2. SwiftDataRepositoryが完全に機能することの確認
/// 3. マイグレーション機能の動作確認
/// 4. データ整合性の検証
///
/// ## 今後の計画
/// - Phase 2: DataRepositoryに非推奨マーカーを追加
/// - Phase 3: DataRepositoryの完全削除
@Suite("DataRepository Deprecation Phase 1 Tests")
@MainActor
struct DataRepositoryDeprecationTests {

    /// SwiftDataRepositoryが正常に動作することを確認
    @Test("SwiftDataRepository全機能動作確認")
    func swiftDataRepositoryFullFunctionality() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // センシングセッションの保存と読み込み
        let session = SensingSession(
            id: "test-session-1",
            name: "テストセッション",
            startTime: Date(),
            endTime: nil,
            isActive: true
        )

        try await repository.saveSensingSession(session)
        let loadedSession = try await repository.loadSensingSession(by: session.id)

        #expect(loadedSession != nil)
        #expect(loadedSession?.name == "テストセッション")

        // アンテナ位置の保存と読み込み
        let antennaPosition = AntennaPositionData(
            id: "antenna-1",
            antennaId: "ant-001",
            antennaName: "アンテナ1",
            position: Point3D(x: 1.0, y: 2.0, z: 0.5),
            rotation: 0.0,
            floorMapId: "floor-001"
        )

        try await repository.saveAntennaPosition(antennaPosition)
        let loadedPositions = try await repository.loadAntennaPositions(for: "floor-001")

        #expect(loadedPositions.count == 1)
        #expect(loadedPositions.first?.antennaName == "アンテナ1")

        // キャリブレーションデータの保存と読み込み
        let calibrationData = CalibrationData(
            antennaId: "ant-001",
            calibrationPoints: [
                CalibrationPoint(
                    referencePosition: Point3D(x: 0, y: 0, z: 0),
                    measuredPosition: Point3D(x: 0.1, y: 0.1, z: 0.05),
                    antennaId: "ant-001"
                )
            ],
            transform: nil,
            isActive: true
        )

        try await repository.saveCalibrationData(calibrationData)
        let loadedCalibration = try await repository.loadCalibrationData(for: "ant-001")

        #expect(loadedCalibration != nil)
        #expect(loadedCalibration?.antennaId == "ant-001")
    }

    /// DataMigrationUsecaseが正常に動作することを確認
    @Test("DataMigrationUsecase動作確認")
    func dataMigrationUsecaseFunctionality() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let swiftDataRepository = SwiftDataRepository(modelContext: context)
        let preferenceRepository = PreferenceRepository()
        let migrationUsecase = DataMigrationUsecase(
            dataRepository: DataRepository(),
            swiftDataRepository: swiftDataRepository,
            preferenceRepository: preferenceRepository
        )

        // 移行前の状態確認
        let needsMigrationBefore = migrationUsecase.needsMigration

        // 移行実行
        try await migrationUsecase.migrateDataIfNeeded()

        // 移行完了確認
        let needsMigrationAfter = migrationUsecase.needsMigration

        #expect(needsMigrationAfter == false)

        // 移行状態をリセット
        migrationUsecase.resetMigration()
    }

    /// SwiftDataRepositoryのデータ整合性機能を確認
    @Test("データ整合性検証機能の確認")
    func dataIntegrityValidation() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // テストデータを挿入
        let position1 = AntennaPositionData(
            id: "pos-1",
            antennaId: "ant-001",
            antennaName: "アンテナ1",
            position: Point3D(x: 1.0, y: 2.0, z: 0.5),
            rotation: 0.0,
            floorMapId: "floor-001"
        )

        try await repository.saveAntennaPosition(position1)

        // データ整合性チェック
        let issues = try await repository.validateDataIntegrity()

        // 正常なデータでは問題がないことを確認
        #expect(issues.isEmpty)
    }

    /// 重複データのクリーンアップ機能を確認
    @Test("重複データクリーンアップ機能の確認")
    func duplicateDataCleanup() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // 重複データを手動で作成（通常は発生しないが、テスト用）
        let position1 = AntennaPositionData(
            id: "pos-1",
            antennaId: "ant-001",
            antennaName: "アンテナ1",
            position: Point3D(x: 1.0, y: 2.0, z: 0.5),
            rotation: 0.0,
            floorMapId: "floor-001"
        )

        try await repository.saveAntennaPosition(position1)

        // クリーンアップ実行
        let deletedCount = try await repository.cleanupDuplicateAntennaPositions()

        // 重複がない場合は削除されないことを確認
        #expect(deletedCount == 0)
    }

    /// CalibrationDataのCRUD操作を確認
    @Test("CalibrationData CRUD操作確認")
    func calibrationDataCRUD() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // Create
        let calibrationData = CalibrationData(
            antennaId: "ant-001",
            calibrationPoints: [
                CalibrationPoint(
                    referencePosition: Point3D(x: 0, y: 0, z: 0),
                    measuredPosition: Point3D(x: 0.1, y: 0.1, z: 0.05),
                    antennaId: "ant-001"
                ),
                CalibrationPoint(
                    referencePosition: Point3D(x: 1, y: 0, z: 0),
                    measuredPosition: Point3D(x: 1.1, y: 0.1, z: 0.05),
                    antennaId: "ant-001"
                ),
                CalibrationPoint(
                    referencePosition: Point3D(x: 0, y: 1, z: 0),
                    measuredPosition: Point3D(x: 0.1, y: 1.1, z: 0.05),
                    antennaId: "ant-001"
                ),
            ],
            transform: nil,
            isActive: true
        )

        try await repository.saveCalibrationData(calibrationData)

        // Read
        let loadedData = try await repository.loadCalibrationData(for: "ant-001")
        #expect(loadedData != nil)
        #expect(loadedData?.calibrationPoints.count == 3)

        // Update
        var updatedData = calibrationData
        updatedData.isActive = false
        try await repository.saveCalibrationData(updatedData)

        let reloadedData = try await repository.loadCalibrationData(for: "ant-001")
        #expect(reloadedData?.isActive == false)

        // Delete
        try await repository.deleteCalibrationData(for: "ant-001")

        let deletedData = try await repository.loadCalibrationData(for: "ant-001")
        #expect(deletedData == nil)
    }

    /// MapCalibrationDataのCRUD操作を確認
    @Test("MapCalibrationData CRUD操作確認")
    func mapCalibrationDataCRUD() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // Create
        let mapCalibrationData = MapCalibrationData(
            antennaId: "ant-001",
            floorMapId: "floor-001",
            calibrationPoints: [
                MapCalibrationPoint(
                    mapCoordinate: Point3D(x: 0, y: 0, z: 0),
                    realWorldCoordinate: Point3D(x: 0.1, y: 0.1, z: 0.05),
                    antennaId: "ant-001",
                    pointIndex: 1
                )
            ],
            affineTransform: nil,
            isActive: true
        )

        try await repository.saveMapCalibrationData(mapCalibrationData)

        // Read
        let loadedData = try await repository.loadMapCalibrationData(
            for: "ant-001",
            floorMapId: "floor-001"
        )
        #expect(loadedData != nil)
        #expect(loadedData?.antennaId == "ant-001")
        #expect(loadedData?.floorMapId == "floor-001")

        // Update
        var updatedData = mapCalibrationData
        updatedData.isActive = false
        try await repository.saveMapCalibrationData(updatedData)

        let reloadedData = try await repository.loadMapCalibrationData(
            for: "ant-001",
            floorMapId: "floor-001"
        )
        #expect(reloadedData?.isActive == false)

        // Delete
        try await repository.deleteMapCalibrationData(for: "ant-001", floorMapId: "floor-001")

        let deletedData = try await repository.loadMapCalibrationData(
            for: "ant-001",
            floorMapId: "floor-001"
        )
        #expect(deletedData == nil)
    }

    /// FloorMapInfoのCRUD操作を確認
    @Test("FloorMapInfo CRUD操作確認")
    func floorMapInfoCRUD() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // Create
        let floorMapInfo = FloorMapInfo(
            id: "floor-001",
            name: "テストフロア",
            buildingName: "テストビル",
            width: 10.0,
            depth: 10.0,
            createdAt: Date()
        )

        try await repository.saveFloorMap(floorMapInfo)

        // Read
        let loadedFloorMap = try await repository.loadFloorMap(by: "floor-001")
        #expect(loadedFloorMap != nil)
        #expect(loadedFloorMap?.name == "テストフロア")

        // Read All
        let allFloorMaps = try await repository.loadAllFloorMaps()
        #expect(allFloorMaps.count == 1)

        // Set Active
        try await repository.setActiveFloorMap(id: "floor-001")

        // Delete
        try await repository.deleteFloorMap(by: "floor-001")

        let deletedFloorMap = try await repository.loadFloorMap(by: "floor-001")
        #expect(deletedFloorMap == nil)
    }

    /// ProjectProgressのCRUD操作を確認
    @Test("ProjectProgress CRUD操作確認")
    func projectProgressCRUD() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistentSensingSession.self, configurations: config)
        let context = container.mainContext

        let repository = SwiftDataRepository(modelContext: context)

        // Create
        let progress = ProjectProgress(
            id: "progress-001",
            floorMapId: "floor-001",
            currentStep: .antennaConfiguration,
            completedSteps: [.floorMapSetting],
            stepData: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        try await repository.saveProjectProgress(progress)

        // Read by ID
        let loadedProgress = try await repository.loadProjectProgress(by: "progress-001")
        #expect(loadedProgress != nil)
        #expect(loadedProgress?.floorMapId == "floor-001")

        // Read by FloorMapId
        let progressForFloorMap = try await repository.loadProjectProgress(for: "floor-001")
        #expect(progressForFloorMap != nil)

        // Update
        var updatedProgress = progress
        updatedProgress.currentStep = .dataCollection
        try await repository.updateProjectProgress(updatedProgress)

        let reloadedProgress = try await repository.loadProjectProgress(by: "progress-001")
        #expect(reloadedProgress?.currentStep == .dataCollection)

        // Delete
        try await repository.deleteProjectProgress(by: "progress-001")

        let deletedProgress = try await repository.loadProjectProgress(by: "progress-001")
        #expect(deletedProgress == nil)
    }
}
