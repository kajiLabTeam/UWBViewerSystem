@testable import UWBViewerSystem
import XCTest

/// キャリブレーション機能のテストケース
final class CalibrationTests: XCTestCase {

    var leastSquaresCalibration: LeastSquaresCalibration.Type!
    var mockRepository: MockCalibrationTestRepository!
    var calibrationUsecase: CalibrationUsecase!

    override func setUpWithError() throws {
        super.setUp()
        leastSquaresCalibration = LeastSquaresCalibration.self
        mockRepository = MockCalibrationTestRepository()
    }

    @MainActor
    private func setupCalibrationUsecase() {
        calibrationUsecase = CalibrationUsecase(dataRepository: mockRepository)
    }

    override func tearDownWithError() throws {
        leastSquaresCalibration = nil
        mockRepository = nil
        calibrationUsecase = nil
        super.tearDown()
    }

    // MARK: - 最小二乗法テスト

    /// 完全に一致する3点でのキャリブレーションテスト
    func testPerfectCalibration() throws {
        // 正解座標と測定座標が完全に一致するケース（分散が十分なデータを使用）
        let points = [
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 0, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 5, y: 0, z: 0),
                measuredPosition: Point3D(x: 5, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 5, z: 0),
                measuredPosition: Point3D(x: 0, y: 5, z: 0),
                antennaId: "antenna1"
            )
        ]

        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // 完全に一致する場合、変換は恒等変換に近くなる
        XCTAssertEqual(transform.translation.x, 0, accuracy: 0.001)
        XCTAssertEqual(transform.translation.y, 0, accuracy: 0.001)
        XCTAssertEqual(transform.rotation, 0, accuracy: 0.001)
        XCTAssertEqual(transform.scale.x, 1, accuracy: 0.001)
        XCTAssertEqual(transform.scale.y, 1, accuracy: 0.001)
        XCTAssertEqual(transform.accuracy, 0, accuracy: 0.001)
    }

    /// 平行移動のみのキャリブレーションテスト
    func testTranslationOnlyCalibration() throws {
        // 測定座標が正解座標から一定量ずれているケース
        let offset = Point3D(x: 1.5, y: 1.0, z: 0)
        let points = [
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 0, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0) - offset,
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 5, y: 0, z: 0),
                measuredPosition: Point3D(x: 5, y: 0, z: 0) - offset,
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 5, z: 0),
                measuredPosition: Point3D(x: 0, y: 5, z: 0) - offset,
                antennaId: "antenna1"
            )
        ]

        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // 平行移動量が正しく計算されることを確認
        XCTAssertEqual(transform.translation.x, offset.x, accuracy: 0.01)
        XCTAssertEqual(transform.translation.y, offset.y, accuracy: 0.01)
        XCTAssertEqual(transform.rotation, 0, accuracy: 0.01)
        XCTAssertEqual(transform.scale.x, 1, accuracy: 0.01)
        XCTAssertEqual(transform.scale.y, 1, accuracy: 0.01)
        XCTAssertLessThan(transform.accuracy, 0.01)
    }

    /// スケール変換のキャリブレーションテスト
    func testScaleCalibration() throws {
        // 測定座標が正解座標の2倍になっているケース
        let scaleFactor = 0.5
        let points = [
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 0, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 3, y: 0, z: 0),
                measuredPosition: Point3D(x: 6, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 3, z: 0),
                measuredPosition: Point3D(x: 0, y: 6, z: 0),
                antennaId: "antenna1"
            )
        ]

        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // スケール係数が正しく計算されることを確認
        XCTAssertEqual(transform.scale.x, scaleFactor, accuracy: 0.01)
        XCTAssertEqual(transform.scale.y, scaleFactor, accuracy: 0.01)
        XCTAssertLessThan(transform.accuracy, 0.1)
    }

    /// 不十分な点数でのエラーテスト
    func testInsufficientPointsError() {
        let points = [
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 0, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 1, y: 0, z: 0),
                measuredPosition: Point3D(x: 1, y: 0, z: 0),
                antennaId: "antenna1"
            )
        ]

        XCTAssertThrowsError(try leastSquaresCalibration.calculateTransform(from: points)) { error in
            XCTAssertTrue(error is LeastSquaresCalibration.CalibrationError)
            if case let LeastSquaresCalibration.CalibrationError.insufficientPoints(required, provided) = error {
                XCTAssertEqual(required, 3)
                XCTAssertEqual(provided, 2)
            } else {
                XCTFail("Expected insufficientPoints error")
            }
        }
    }

    /// 無効な入力データでのエラーテスト
    func testInvalidInputError() {
        // 全ての測定点が同じ位置にあるケース
        let points = [
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 0, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 1, y: 0, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 1, z: 0),
                measuredPosition: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1"
            )
        ]

        XCTAssertThrowsError(try leastSquaresCalibration.calculateTransform(from: points)) { error in
            XCTAssertTrue(error is LeastSquaresCalibration.CalibrationError)
        }
    }

    /// キャリブレーション適用のテスト
    func testCalibrationApplication() throws {
        let points = [
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 0, z: 0),
                measuredPosition: Point3D(x: -2.0, y: -1.5, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 5, y: 0, z: 0),
                measuredPosition: Point3D(x: 3.0, y: -1.5, z: 0),
                antennaId: "antenna1"
            ),
            CalibrationPoint(
                referencePosition: Point3D(x: 0, y: 5, z: 0),
                measuredPosition: Point3D(x: -2.0, y: 3.5, z: 0),
                antennaId: "antenna1"
            )
        ]

        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // 測定点にキャリブレーションを適用
        let testPoint = Point3D(x: -1.0, y: 1.0, z: 0)
        let calibratedPoint = leastSquaresCalibration.applyCalibration(to: testPoint, using: transform)

        // キャリブレーション後の点は正解座標に近くなるはず
        let expectedPoint = Point3D(x: 1.0, y: 2.5, z: 0)
        XCTAssertEqual(calibratedPoint.x, expectedPoint.x, accuracy: 0.5)
        XCTAssertEqual(calibratedPoint.y, expectedPoint.y, accuracy: 0.5)
    }

    // MARK: - UseCase テスト

    /// キャリブレーション点の追加と削除のテスト
    @MainActor
    func testAddAndRemoveCalibrationPoint() async {
        setupCalibrationUsecase()

        let antennaId = "test_antenna"
        let referencePosition = Point3D(x: 1, y: 1, z: 0)
        let measuredPosition = Point3D(x: 0.8, y: 1.2, z: 0)

        // 点を追加
        calibrationUsecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: referencePosition,
            measuredPosition: measuredPosition
        )

        let calibrationData = calibrationUsecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(calibrationData.calibrationPoints.count, 1)

        guard let addedPoint = calibrationData.calibrationPoints.first else {
            XCTFail("追加されたキャリブレーションポイントが見つかりません")
            return
        }
        XCTAssertEqual(addedPoint.referencePosition.x, referencePosition.x)
        XCTAssertEqual(addedPoint.measuredPosition.x, measuredPosition.x)

        // 点を削除
        calibrationUsecase.removeCalibrationPoint(for: antennaId, pointId: addedPoint.id)

        let updatedData = calibrationUsecase.getCalibrationData(for: antennaId)
        XCTAssertEqual(updatedData.calibrationPoints.count, 0)
    }

    /// キャリブレーション実行のテスト
    @MainActor
    func testPerformCalibration() async {
        setupCalibrationUsecase()

        let antennaId = "test_antenna"

        // 3つの測定点を追加（分散が十分なデータを使用）
        let points = [
            (ref: Point3D(x: 0, y: 0, z: 0), meas: Point3D(x: 0.5, y: 0.5, z: 0)),
            (ref: Point3D(x: 5, y: 0, z: 0), meas: Point3D(x: 5.5, y: 0.5, z: 0)),
            (ref: Point3D(x: 0, y: 5, z: 0), meas: Point3D(x: 0.5, y: 5.5, z: 0))
        ]

        for point in points {
            calibrationUsecase.addCalibrationPoint(
                for: antennaId,
                referencePosition: point.ref,
                measuredPosition: point.meas
            )
        }

        // キャリブレーション実行
        await calibrationUsecase.performCalibration(for: antennaId)

        // 結果を確認
        XCTAssertEqual(calibrationUsecase.calibrationStatus, .completed)

        let calibrationData = calibrationUsecase.getCalibrationData(for: antennaId)
        XCTAssertTrue(calibrationData.isCalibrated)
        XCTAssertNotNil(calibrationData.transform)
        guard let accuracy = calibrationData.accuracy else {
            XCTFail("キャリブレーション精度が取得できませんでした")
            return
        }
        XCTAssertLessThan(accuracy, 0.5) // 精度が0.5m以下であることを確認
    }

    /// 統計情報の計算テスト
    @MainActor
    func testCalibrationStatistics() async {
        setupCalibrationUsecase()

        let antenna1 = "antenna1"
        let antenna2 = "antenna2"

        // antenna1のキャリブレーション完了（分散が十分なデータを使用）
        let referencePoints = [
            Point3D(x: 0, y: 0, z: 0),
            Point3D(x: 5, y: 0, z: 0),
            Point3D(x: 0, y: 5, z: 0)
        ]
        let measuredPoints = [
            Point3D(x: 0.5, y: 0.5, z: 0),
            Point3D(x: 5.5, y: 0.5, z: 0),
            Point3D(x: 0.5, y: 5.5, z: 0)
        ]

        for i in 0..<3 {
            calibrationUsecase.addCalibrationPoint(
                for: antenna1,
                referencePosition: referencePoints[i],
                measuredPosition: measuredPoints[i]
            )
        }
        await calibrationUsecase.performCalibration(for: antenna1)

        // antenna2は未完了（点が足りない）
        calibrationUsecase.addCalibrationPoint(
            for: antenna2,
            referencePosition: Point3D(x: 0, y: 0, z: 0),
            measuredPosition: Point3D(x: 0.2, y: 0.2, z: 0)
        )

        let statistics = calibrationUsecase.getCalibrationStatistics()
        XCTAssertEqual(statistics.totalAntennas, 2)
        XCTAssertEqual(statistics.calibratedAntennas, 1)
        XCTAssertEqual(statistics.completionPercentage, 50.0, accuracy: 0.1)
        XCTAssertGreaterThan(statistics.averageAccuracy, 0)
    }

    // MARK: - Point3D 拡張テスト

    func testPoint3DOperations() {
        let point1 = Point3D(x: 1, y: 2, z: 3)
        let point2 = Point3D(x: 4, y: 5, z: 6)

        // 加算
        let sum = point1 + point2
        XCTAssertEqual(sum.x, 5)
        XCTAssertEqual(sum.y, 7)
        XCTAssertEqual(sum.z, 9)

        // 減算
        let diff = point2 - point1
        XCTAssertEqual(diff.x, 3)
        XCTAssertEqual(diff.y, 3)
        XCTAssertEqual(diff.z, 3)

        // スカラー倍
        let scaled = point1 * 2
        XCTAssertEqual(scaled.x, 2)
        XCTAssertEqual(scaled.y, 4)
        XCTAssertEqual(scaled.z, 6)

        // 距離計算
        let distance = point1.distance(to: point2)
        let expectedDistance = sqrt(9 + 9 + 9) // sqrt((4-1)^2 + (5-2)^2 + (6-3)^2)
        XCTAssertEqual(distance, expectedDistance, accuracy: 0.001)

        // ベクトルの長さ
        let magnitude = point1.magnitude
        let expectedMagnitude = sqrt(1 + 4 + 9) // sqrt(1^2 + 2^2 + 3^2)
        XCTAssertEqual(magnitude, expectedMagnitude, accuracy: 0.001)
    }

    // MARK: - CalibrationTransform 拡張テスト

    func testCalibrationTransformValidation() {
        // 有効な変換
        let validTransform = CalibrationTransform(
            translation: Point3D(x: 1, y: 1, z: 0),
            rotation: 0.1,
            scale: Point3D(x: 1.1, y: 1.1, z: 1.0),
            accuracy: 0.05
        )
        XCTAssertTrue(validTransform.isValid)

        // 無効な変換（スケールが負）
        let invalidTransform = CalibrationTransform(
            translation: Point3D(x: 1, y: 1, z: 0),
            rotation: 0.1,
            scale: Point3D(x: -1, y: 1.1, z: 1.0),
            accuracy: 0.05
        )
        XCTAssertFalse(invalidTransform.isValid)

        // 無効な変換（NaN値）
        let nanTransform = CalibrationTransform(
            translation: Point3D(x: Double.nan, y: 1, z: 0),
            rotation: 0.1,
            scale: Point3D(x: 1.1, y: 1.1, z: 1.0),
            accuracy: 0.05
        )
        XCTAssertFalse(nanTransform.isValid)
    }
}

// MARK: - Mock Data Repository

class MockCalibrationTestRepository: DataRepositoryProtocol {
    private var calibrationDataStorage: [String: CalibrationData] = [:]

    func saveRecentSensingSessions(_ sessions: [SensingSession]) {}
    func loadRecentSensingSessions() -> [SensingSession] { [] }
    func saveAntennaPositions(_ positions: [AntennaPositionData]) {}
    func loadAntennaPositions() -> [AntennaPositionData]? { nil }
    func saveFieldAntennaConfiguration(_ antennas: [AntennaInfo]) {}
    func loadFieldAntennaConfiguration() -> [AntennaInfo]? { nil }
    func saveAntennaPairings(_ pairings: [AntennaPairing]) {}
    func loadAntennaPairings() -> [AntennaPairing]? { nil }
    func saveHasDeviceConnected(_ connected: Bool) {}
    func loadHasDeviceConnected() -> Bool { false }
    func saveCalibrationResults(_ results: Data) {}
    func loadCalibrationResults() -> Data? { nil }

    func saveCalibrationData(_ data: CalibrationData) async throws {
        calibrationDataStorage[data.antennaId] = data
    }

    func loadCalibrationData() async throws -> [CalibrationData] {
        Array(calibrationDataStorage.values)
    }

    func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        calibrationDataStorage[antennaId]
    }

    func deleteCalibrationData(for antennaId: String) async throws {
        calibrationDataStorage.removeValue(forKey: antennaId)
    }

    func deleteAllCalibrationData() async throws {
        calibrationDataStorage.removeAll()
    }

    func saveBoolSetting(key: String, value: Bool) {}
    func loadBoolSetting(key: String) -> Bool { false }
    func saveRecentSystemActivities(_ activities: [SystemActivity]) {}
    func loadRecentSystemActivities() -> [SystemActivity]? { nil }
    func saveData(_ data: some Codable, forKey key: String) throws {}
    func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? { nil }
}