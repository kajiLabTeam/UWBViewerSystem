import Foundation
import Testing
@testable import UWBViewerSystem

/// キャリブレーション機能のテストケース
struct CalibrationTests {

    @MainActor
    private func createTestContext() -> (LeastSquaresCalibration.Type, MockCalibrationTestRepository, CalibrationUsecase) {
        let leastSquaresCalibration = LeastSquaresCalibration.self
        let mockRepository = MockCalibrationTestRepository()
        let calibrationUsecase = CalibrationUsecase(dataRepository: mockRepository)
        return (leastSquaresCalibration, mockRepository, calibrationUsecase)
    }

    private func createLeastSquaresCalibration() -> LeastSquaresCalibration.Type {
        LeastSquaresCalibration.self
    }

    // MARK: - 最小二乗法テスト

    @Test("完全に一致する3点でのキャリブレーション")
    func perfectCalibration() throws {
        // Arrange
        let leastSquaresCalibration = self.createLeastSquaresCalibration()

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

        // Act
        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // Assert
        // 完全に一致する場合、変換は恒等変換に近くなる
        #expect(abs(transform.translation.x - 0) < 0.001)
        #expect(abs(transform.translation.y - 0) < 0.001)
        #expect(abs(transform.rotation - 0) < 0.001)
        #expect(abs(transform.scale.x - 1) < 0.001)
        #expect(abs(transform.scale.y - 1) < 0.001)
        #expect(abs(transform.accuracy - 0) < 0.001)
    }

    @Test("平行移動のみのキャリブレーション")
    func translationOnlyCalibration() throws {
        // Arrange
        let leastSquaresCalibration = self.createLeastSquaresCalibration()

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

        // Act
        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // Assert
        // 平行移動量が正しく計算されることを確認
        #expect(abs(transform.translation.x - offset.x) < 0.01)
        #expect(abs(transform.translation.y - offset.y) < 0.01)
        #expect(abs(transform.rotation - 0) < 0.01)
        #expect(abs(transform.scale.x - 1) < 0.01)
        #expect(abs(transform.scale.y - 1) < 0.01)
        #expect(transform.accuracy < 0.01)
    }

    @Test("スケール変換のキャリブレーション")
    func scaleCalibration() throws {
        // Arrange
        let leastSquaresCalibration = self.createLeastSquaresCalibration()

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

        // Act
        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // Assert
        // スケール係数が正しく計算されることを確認
        #expect(abs(transform.scale.x - scaleFactor) < 0.01)
        #expect(abs(transform.scale.y - scaleFactor) < 0.01)
        #expect(transform.accuracy < 0.1)
    }

    @Test("不十分な点数でのエラー")
    func insufficientPointsError() {
        // Arrange
        let leastSquaresCalibration = self.createLeastSquaresCalibration()

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

        // Act & Assert
        do {
            _ = try leastSquaresCalibration.calculateTransform(from: points)
            #expect(Bool(false), "Expected insufficientPoints error")
        } catch let error as LeastSquaresCalibration.CalibrationError {
            switch error {
            case .insufficientPoints(let required, let provided):
                #expect(required == 3)
                #expect(provided == 2)
            default:
                #expect(Bool(false), "Expected insufficientPoints error")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("無効な入力データでのエラー")
    func invalidInputError() {
        // Arrange
        let leastSquaresCalibration = self.createLeastSquaresCalibration()

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

        // Act & Assert
        do {
            _ = try leastSquaresCalibration.calculateTransform(from: points)
            #expect(Bool(false), "Expected calibration error")
        } catch _ as LeastSquaresCalibration.CalibrationError {
            #expect(Bool(true)) // 期待される動作
        } catch {
            #expect(Bool(false), "Expected LeastSquaresCalibration.CalibrationError but got: \(error)")
        }
    }

    @Test("キャリブレーション適用")
    func calibrationApplication() throws {
        // Arrange
        let leastSquaresCalibration = self.createLeastSquaresCalibration()

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

        // Act
        let transform = try leastSquaresCalibration.calculateTransform(from: points)

        // 測定点にキャリブレーションを適用
        let testPoint = Point3D(x: -1.0, y: 1.0, z: 0)
        let calibratedPoint = leastSquaresCalibration.applyCalibration(to: testPoint, using: transform)

        // Assert
        // キャリブレーション後の点は正解座標に近くなるはず
        let expectedPoint = Point3D(x: 1.0, y: 2.5, z: 0)
        #expect(abs(calibratedPoint.x - expectedPoint.x) < 0.5)
        #expect(abs(calibratedPoint.y - expectedPoint.y) < 0.5)
    }

    // MARK: - UseCase テスト

    @Test("キャリブレーション点の追加と削除")
    @MainActor
    func addAndRemoveCalibrationPoint() async {
        // Arrange
        let (_, _, calibrationUsecase) = self.createTestContext()

        let antennaId = "test_antenna"
        let referencePosition = Point3D(x: 1, y: 1, z: 0)
        let measuredPosition = Point3D(x: 0.8, y: 1.2, z: 0)

        // Act
        // 点を追加
        calibrationUsecase.addCalibrationPoint(
            for: antennaId,
            referencePosition: referencePosition,
            measuredPosition: measuredPosition
        )

        let calibrationData = calibrationUsecase.getCalibrationData(for: antennaId)
        #expect(calibrationData.calibrationPoints.count == 1)

        guard let addedPoint = calibrationData.calibrationPoints.first else {
            #expect(Bool(false), "追加されたキャリブレーションポイントが見つかりません")
            return
        }
        #expect(addedPoint.referencePosition.x == referencePosition.x)
        #expect(addedPoint.measuredPosition.x == measuredPosition.x)

        // 点を削除
        calibrationUsecase.removeCalibrationPoint(for: antennaId, pointId: addedPoint.id)

        let updatedData = calibrationUsecase.getCalibrationData(for: antennaId)
        #expect(updatedData.calibrationPoints.isEmpty)
    }

    @Test("キャリブレーション実行")
    @MainActor
    func testPerformCalibration() async {
        // Arrange
        let (_, _, calibrationUsecase) = self.createTestContext()

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

        // Act
        // キャリブレーション実行
        await calibrationUsecase.performCalibration(for: antennaId)

        // Assert
        // 結果を確認
        #expect(calibrationUsecase.calibrationStatus == .completed)

        let calibrationData = calibrationUsecase.getCalibrationData(for: antennaId)
        #expect(calibrationData.isCalibrated)
        #expect(calibrationData.transform != nil)
        guard let accuracy = calibrationData.accuracy else {
            #expect(Bool(false), "キャリブレーション精度が取得できませんでした")
            return
        }
        #expect(accuracy < 0.5) // 精度が0.5m以下であることを確認
    }

    @Test("統計情報の計算")
    @MainActor
    func calibrationStatistics() async {
        // Arrange
        let (_, _, calibrationUsecase) = self.createTestContext()

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

        // Act
        let statistics = calibrationUsecase.getCalibrationStatistics()

        // Assert
        #expect(statistics.totalAntennas == 2)
        #expect(statistics.calibratedAntennas == 1)
        #expect(abs(statistics.completionPercentage - 50.0) < 0.1)
        #expect(statistics.averageAccuracy > 0)
    }

    // MARK: - Point3D 拡張テスト

    @Test("Point3Dの操作")
    func point3DOperations() {
        let point1 = Point3D(x: 1, y: 2, z: 3)
        let point2 = Point3D(x: 4, y: 5, z: 6)

        // 加算
        let sum = point1 + point2
        #expect(sum.x == 5)
        #expect(sum.y == 7)
        #expect(sum.z == 9)

        // 減算
        let diff = point2 - point1
        #expect(diff.x == 3)
        #expect(diff.y == 3)
        #expect(diff.z == 3)

        // スカラー倍
        let scaled = point1 * 2
        #expect(scaled.x == 2)
        #expect(scaled.y == 4)
        #expect(scaled.z == 6)

        // 距離計算
        let distance = point1.distance(to: point2)
        let expectedDistance = sqrt(9 + 9 + 9) // sqrt((4-1)^2 + (5-2)^2 + (6-3)^2)
        #expect(abs(distance - expectedDistance) < 0.001)

        // ベクトルの長さ
        let magnitude = point1.magnitude
        let expectedMagnitude = sqrt(1 + 4 + 9) // sqrt(1^2 + 2^2 + 3^2)
        #expect(abs(magnitude - expectedMagnitude) < 0.001)
    }

    // MARK: - CalibrationTransform 拡張テスト

    @Test("CalibrationTransformの検証")
    func calibrationTransformValidation() {
        // 有効な変換
        let validTransform = CalibrationTransform(
            translation: Point3D(x: 1, y: 1, z: 0),
            rotation: 0.1,
            scale: Point3D(x: 1.1, y: 1.1, z: 1.0),
            accuracy: 0.05
        )
        #expect(validTransform.isValid)

        // 無効な変換（スケールが負）
        let invalidTransform = CalibrationTransform(
            translation: Point3D(x: 1, y: 1, z: 0),
            rotation: 0.1,
            scale: Point3D(x: -1, y: 1.1, z: 1.0),
            accuracy: 0.05
        )
        #expect(!invalidTransform.isValid)

        // 無効な変換（NaN値）
        let nanTransform = CalibrationTransform(
            translation: Point3D(x: Double.nan, y: 1, z: 0),
            rotation: 0.1,
            scale: Point3D(x: 1.1, y: 1.1, z: 1.0),
            accuracy: 0.05
        )
        #expect(!nanTransform.isValid)
    }
}

// MARK: - Mock Data Repository

class MockCalibrationTestRepository: DataRepositoryProtocol {
    private var calibrationDataStorage: [String: Data] = [:]
    private let storageQueue = DispatchQueue(label: "MockCalibrationTestRepository.storage", attributes: .concurrent)

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
        // antennaIdが正常な文字列であることを確認
        guard !data.antennaId.isEmpty else {
            throw NSError(domain: "MockCalibrationTestRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "antennaId is empty"])
        }

        // JSONエンコードして安全に保存
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(data)

        // 同期的にスレッドセーフな保存
        self.storageQueue.sync(flags: .barrier) {
            self.calibrationDataStorage[data.antennaId] = encodedData
        }
    }

    func loadCalibrationData() async throws -> [CalibrationData] {
        self.storageQueue.sync {
            let decoder = JSONDecoder()
            return self.calibrationDataStorage.values.compactMap { data in
                try? decoder.decode(CalibrationData.self, from: data)
            }
        }
    }

    func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        self.storageQueue.sync {
            guard let data = calibrationDataStorage[antennaId] else { return nil }
            let decoder = JSONDecoder()
            return try? decoder.decode(CalibrationData.self, from: data)
        }
    }

    func deleteCalibrationData(for antennaId: String) async throws {
        self.storageQueue.sync(flags: .barrier) {
            self.calibrationDataStorage.removeValue(forKey: antennaId)
        }
    }

    func deleteAllCalibrationData() async throws {
        self.storageQueue.sync(flags: .barrier) {
            self.calibrationDataStorage.removeAll()
        }
    }

    func saveBoolSetting(key: String, value: Bool) {}
    func loadBoolSetting(key: String) -> Bool { false }
    func saveRecentSystemActivities(_ activities: [SystemActivity]) {}
    func loadRecentSystemActivities() -> [SystemActivity]? { nil }
    func saveData(_ data: some Codable, forKey key: String) throws {}
    func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? { nil }
}