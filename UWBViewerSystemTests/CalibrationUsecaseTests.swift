import SwiftData
@testable import UWBViewerSystem
import XCTest

// Mock repository type alias for clarity
typealias TestMockDataRepository = MockDataRepository

@MainActor
final class CalibrationUsecaseTests: XCTestCase {

    var usecase: CalibrationUsecase!
    var mockRepository: TestMockDataRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockRepository = TestMockDataRepository()
        usecase = CalibrationUsecase(dataRepository: mockRepository)
    }

    override func tearDownWithError() throws {
        usecase = nil
        mockRepository = nil
        try super.tearDownWithError()
    }

    // MARK: - キャリブレーションポイント追加テスト

    func testAddCalibrationPoint_正常ケース() throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let referencePosition = Point3D(x: 1.0, y: 2.0, z: 0.0)
        let measuredPosition = Point3D(x: 1.1, y: 2.1, z: 0.1)

        // Act
        usecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: referencePosition,
            measuredPosition: measuredPosition
        )

        // Assert
        let calibrationData = usecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(calibrationData.calibrationPoints.count, 1)
        XCTAssertEqual(calibrationData.calibrationPoints.first?.referencePosition.x, 1.0)
        XCTAssertEqual(calibrationData.calibrationPoints.first?.measuredPosition.x, 1.1)
        XCTAssertEqual(usecase.calibrationStatus, .collecting)
    }

    func testAddCalibrationPoint_複数ポイント() throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let points = [
            (Point3D(x: 1.0, y: 1.0, z: 0.0), Point3D(x: 1.1, y: 1.1, z: 0.1)),
            (Point3D(x: 2.0, y: 2.0, z: 0.0), Point3D(x: 2.1, y: 2.1, z: 0.1)),
            (Point3D(x: 3.0, y: 3.0, z: 0.0), Point3D(x: 3.1, y: 3.1, z: 0.1))
        ]

        // Act
        for (reference, measured) in points {
            usecase.addCalibrationPoint(
                for: antennaId,
                referencePosition: reference,
                measuredPosition: measured
            )
        }

        // Assert
        let calibrationData = usecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(calibrationData.calibrationPoints.count, 3)
    }

    // MARK: - キャリブレーション実行テスト

    func testPerformCalibration_成功ケース() async throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let points = [
            (Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 0.1, y: 0.1, z: 0.0)),
            (Point3D(x: 5.0, y: 0.0, z: 0.0), Point3D(x: 5.1, y: 0.1, z: 0.0)),
            (Point3D(x: 0.0, y: 5.0, z: 0.0), Point3D(x: 0.1, y: 5.1, z: 0.0))
        ]

        for (reference, measured) in points {
            usecase.addCalibrationPoint(
                for: antennaId,
                referencePosition: reference,
                measuredPosition: measured
            )
        }

        // 非同期保存処理が完了するまで少し待機
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // キャリブレーションデータが正しく設定されているか確認
        let calibrationData = usecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(calibrationData.calibrationPoints.count, 3, "キャリブレーションポイントが3つ追加されている必要があります")

        // Act
        await usecase.performCalibration(for: antennaId)

        // Assert
        XCTAssertEqual(usecase.calibrationStatus, .completed, "キャリブレーション状態がcompletedになるべきです")
        XCTAssertNotNil(usecase.lastCalibrationResult, "キャリブレーション結果が存在すべきです")

        guard let result = usecase.lastCalibrationResult else {
            XCTFail("キャリブレーション結果が取得できませんでした")
            return
        }
        XCTAssertTrue(result.success, "キャリブレーションが成功すべきです")
        XCTAssertTrue(usecase.isCalibrationValid(for: antennaId), "キャリブレーションが有効になるべきです")
    }

    func testPerformCalibration_不十分なポイント数でエラー() async throws {
        // Arrange
        let antennaId = "test-antenna-1"
        usecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: Point3D(x: 1.0, y: 1.0, z: 0.0),
            measuredPosition: Point3D(x: 1.1, y: 1.1, z: 0.1)
        )

        // Act
        await usecase.performCalibration(for: antennaId)

        // Assert
        XCTAssertEqual(usecase.calibrationStatus, .failed)
        XCTAssertNotNil(usecase.lastCalibrationResult)
        XCTAssertFalse(usecase.lastCalibrationResult?.success == true)
        XCTAssertNotNil(usecase.errorMessage)
    }

    func testPerformCalibration_空のアンテナIDでエラー() async throws {
        // Act
        await usecase.performCalibration(for: "")

        // Assert
        XCTAssertEqual(usecase.calibrationStatus, .failed)
        XCTAssertNotNil(usecase.lastCalibrationResult)
        XCTAssertFalse(usecase.lastCalibrationResult?.success == true)
        XCTAssertTrue(usecase.errorMessage?.contains("アンテナID") == true)
    }

    func testPerformCalibration_無効な座標値でエラー() async throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let invalidPoints = [
            (Point3D(x: Double.nan, y: 1.0, z: 0.0), Point3D(x: 1.1, y: 1.1, z: 0.1)),
            (Point3D(x: 2.0, y: Double.infinity, z: 0.0), Point3D(x: 2.1, y: 2.1, z: 0.1)),
            (Point3D(x: 3.0, y: 3.0, z: 0.0), Point3D(x: 3.1, y: 3.1, z: 0.1))
        ]

        for (reference, measured) in invalidPoints {
            usecase.addCalibrationPoint(
                for: antennaId,
                referencePosition: reference,
                measuredPosition: measured
            )
        }

        // 非同期保存処理が完了するまで少し待機
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // Act
        await usecase.performCalibration(for: antennaId)

        // Assert
        XCTAssertEqual(usecase.calibrationStatus, .failed)
        XCTAssertNotNil(usecase.errorMessage)
        XCTAssertTrue(usecase.errorMessage?.contains("無効な座標値") == true)
    }

    func testPerformCalibration_重複する基準座標でエラー() async throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let duplicatePoints = [
            (Point3D(x: 1.0, y: 1.0, z: 0.0), Point3D(x: 1.1, y: 1.1, z: 0.1)),
            (Point3D(x: 1.0, y: 1.0, z: 0.0), Point3D(x: 1.2, y: 1.2, z: 0.1)), // 同じ基準座標
            (Point3D(x: 3.0, y: 3.0, z: 0.0), Point3D(x: 3.1, y: 3.1, z: 0.1))
        ]

        for (reference, measured) in duplicatePoints {
            usecase.addCalibrationPoint(
                for: antennaId,
                referencePosition: reference,
                measuredPosition: measured
            )
        }

        // 非同期保存処理が完了するまで少し待機
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // Act
        await usecase.performCalibration(for: antennaId)

        // Assert
        XCTAssertEqual(usecase.calibrationStatus, .failed)
        XCTAssertNotNil(usecase.errorMessage)
        XCTAssertTrue(usecase.errorMessage?.contains("重複") == true)
    }

    // MARK: - キャリブレーション適用テスト

    func testApplyCalibratedTransform_キャリブレーション済み() async throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let points = [
            (Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 0.1, y: 0.1, z: 0.0)),
            (Point3D(x: 1.0, y: 0.0, z: 0.0), Point3D(x: 1.1, y: 0.1, z: 0.0)),
            (Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 0.1, y: 1.1, z: 0.0))
        ]

        for (reference, measured) in points {
            usecase.addCalibrationPoint(
                for: antennaId,
                referencePosition: reference,
                measuredPosition: measured
            )
        }

        await usecase.performCalibration(for: antennaId)

        // Act
        let testPoint = Point3D(x: 0.5, y: 0.5, z: 0.0)
        let calibratedPoint = usecase.applyCalibratedTransform(to: testPoint, for: antennaId)

        // Assert
        XCTAssertNotEqual(calibratedPoint.x, testPoint.x)
        XCTAssertNotEqual(calibratedPoint.y, testPoint.y)
    }

    func testApplyCalibratedTransform_キャリブレーション未実行() throws {
        // Arrange
        let antennaId = "test-antenna-1"
        let testPoint = Point3D(x: 1.0, y: 2.0, z: 3.0)

        // Act
        let result = usecase.applyCalibratedTransform(to: testPoint, for: antennaId)

        // Assert（キャリブレーション未実行の場合はそのまま返される）
        XCTAssertEqual(result.x, testPoint.x)
        XCTAssertEqual(result.y, testPoint.y)
        XCTAssertEqual(result.z, testPoint.z)
    }

    // MARK: - データクリア・管理テスト

    func testClearCalibrationData_特定アンテナ() throws {
        // Arrange
        let antennaId = "test-antenna-1"
        usecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: Point3D(x: 1.0, y: 1.0, z: 0.0),
            measuredPosition: Point3D(x: 1.1, y: 1.1, z: 0.1)
        )

        // Act
        usecase.clearCalibrationData(for: antennaId)

        // Assert
        let calibrationData = usecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(calibrationData.calibrationPoints.count, 0)
        XCTAssertFalse(usecase.isCalibrationValid(for: antennaId))
    }

    func testClearCalibrationData_全データ() throws {
        // Arrange
        usecase.addCalibrationPoint(
            for: "antenna-1",
            referencePosition: Point3D(x: 1.0, y: 1.0, z: 0.0),
            measuredPosition: Point3D(x: 1.1, y: 1.1, z: 0.1)
        )
        usecase.addCalibrationPoint(
            for: "antenna-2",
            referencePosition: Point3D(x: 2.0, y: 2.0, z: 0.0),
            measuredPosition: Point3D(x: 2.1, y: 2.1, z: 0.1)
        )

        // Act
        usecase.clearCalibrationData()

        // Assert
        XCTAssertEqual(usecase.currentCalibrationData.count, 0)
        XCTAssertEqual(usecase.calibrationStatus, .notStarted)
        XCTAssertNil(usecase.lastCalibrationResult)
    }

    func testRemoveCalibrationPoint() throws {
        // Arrange
        let antennaId = "test-antenna-1"
        usecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: Point3D(x: 1.0, y: 1.0, z: 0.0),
            measuredPosition: Point3D(x: 1.1, y: 1.1, z: 0.1)
        )
        usecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: Point3D(x: 2.0, y: 2.0, z: 0.0),
            measuredPosition: Point3D(x: 2.1, y: 2.1, z: 0.1)
        )

        let calibrationData = usecase.getCalibrationData(for: antennaId)
        let pointId = calibrationData.calibrationPoints.first?.id ?? ""

        // Act
        usecase.removeCalibrationPoint(for: antennaId, pointId: pointId)

        // Assert
        let updatedData = usecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(updatedData.calibrationPoints.count, 1)
        XCTAssertNil(updatedData.transform) // 変換行列がクリアされること
    }

    // MARK: - 統計情報テスト

    func testGetCalibrationStatistics() async throws {
        // Arrange
        let antennas = ["antenna-1", "antenna-2", "antenna-3"]
        let points = [
            (Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 0.1, y: 0.1, z: 0.0)),
            (Point3D(x: 1.0, y: 0.0, z: 0.0), Point3D(x: 1.1, y: 0.1, z: 0.0)),
            (Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 0.1, y: 1.1, z: 0.0))
        ]

        // 2つのアンテナでキャリブレーション実行
        for antenna in antennas.prefix(2) {
            for (reference, measured) in points {
                usecase.addCalibrationPoint(
                    for: antenna,
                    referencePosition: reference,
                    measuredPosition: measured
                )
            }
            await usecase.performCalibration(for: antenna)
        }

        // Act
        let statistics = usecase.getCalibrationStatistics()

        // Assert
        XCTAssertEqual(statistics.totalAntennas, 3)
        XCTAssertEqual(statistics.calibratedAntennas, 2)
        XCTAssertGreaterThan(statistics.averageAccuracy, 0)
    }

    // MARK: - パフォーマンステスト

    func testPerformance_大量キャリブレーションポイント() throws {
        let antennaId = "performance-test-antenna"

        measure {
            for i in 0..<1000 {
                usecase.addCalibrationPoint(
                    for: antennaId,
                    referencePosition: Point3D(x: Double(i), y: Double(i), z: 0.0),
                    measuredPosition: Point3D(x: Double(i) + 0.1, y: Double(i) + 0.1, z: 0.1)
                )
            }
        }
    }
}
