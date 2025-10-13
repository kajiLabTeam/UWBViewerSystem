import Foundation
import Testing

@testable import UWBViewerSystem

/// AntennaAffineCalibration機能のテスト
struct AntennaAffineCalibrationTests {

    // MARK: - Test Data Setup

    /// テスト用の測定データと真の座標を作成
    private func setupTestData() -> (
        measuredPointsByTag: [String: [Point3D]],
        truePositions: [String: Point3D]
    ) {
        // 真のタグ位置（既知の座標）
        let truePositions: [String: Point3D] = [
            "tag1": Point3D(x: 1.0, y: 0.0, z: 0.0),
            "tag2": Point3D(x: 0.0, y: 1.0, z: 0.0),
            "tag3": Point3D(x: 1.0, y: 1.0, z: 0.0),
        ]

        // アンテナが測定したローカル座標（若干のノイズを含む）
        // アンテナ位置 (2.0, 2.0)、回転 45度 を想定
        let measuredPointsByTag: [String: [Point3D]] = [
            "tag1": [
                Point3D(x: -0.7, y: 1.4, z: 0.0),
                Point3D(x: -0.72, y: 1.42, z: 0.0),
                Point3D(x: -0.68, y: 1.38, z: 0.0),
            ],
            "tag2": [
                Point3D(x: -1.4, y: 0.7, z: 0.0),
                Point3D(x: -1.42, y: 0.72, z: 0.0),
                Point3D(x: -1.38, y: 0.68, z: 0.0),
            ],
            "tag3": [
                Point3D(x: -0.7, y: 0.7, z: 0.0),
                Point3D(x: -0.72, y: 0.72, z: 0.0),
                Point3D(x: -0.68, y: 0.68, z: 0.0),
            ],
        ]

        return (measuredPointsByTag, truePositions)
    }

    /// 単純な変換用のテストデータ（回転なし、平行移動のみ）
    private func setupSimpleTestData() -> (
        measuredPointsByTag: [String: [Point3D]],
        truePositions: [String: Point3D]
    ) {
        let truePositions: [String: Point3D] = [
            "tag1": Point3D(x: 5.0, y: 5.0, z: 0.0),
            "tag2": Point3D(x: 7.0, y: 5.0, z: 0.0),
            "tag3": Point3D(x: 6.0, y: 7.0, z: 0.0),
        ]

        // アンテナ位置 (3.0, 3.0)、回転なし
        let measuredPointsByTag: [String: [Point3D]] = [
            "tag1": [
                Point3D(x: 2.0, y: 2.0, z: 0.0),
                Point3D(x: 2.01, y: 1.99, z: 0.0),
            ],
            "tag2": [
                Point3D(x: 4.0, y: 2.0, z: 0.0),
                Point3D(x: 3.99, y: 2.01, z: 0.0),
            ],
            "tag3": [
                Point3D(x: 3.0, y: 4.0, z: 0.0),
                Point3D(x: 3.01, y: 3.99, z: 0.0),
            ],
        ]

        return (measuredPointsByTag, truePositions)
    }

    // MARK: - アフィン変換推定テスト

    @Test("2Dアフィン変換の推定")
    func estimateAffineTransform() throws {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let sourcePoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let targetPoints = [
            Point3D(x: 2.0, y: 3.0, z: 0.0),
            Point3D(x: 3.0, y: 3.0, z: 0.0),
            Point3D(x: 2.0, y: 4.0, z: 0.0),
        ]

        // Act
        let transform = try calibration.estimateAffineTransform(
            sourcePoints: sourcePoints,
            targetPoints: targetPoints
        )

        // Assert
        #expect(abs(transform.A.determinant) > 1e-10)
        #expect(transform.t.x.isFinite)
        #expect(transform.t.y.isFinite)

        // 変換の検証: 平行移動 (2, 3)、スケール1、回転0度
        #expect(abs(transform.t.x - 2.0) < 0.01)
        #expect(abs(transform.t.y - 3.0) < 0.01)
        #expect(abs(transform.A.a11 - 1.0) < 0.01)
        #expect(abs(transform.A.a22 - 1.0) < 0.01)
    }

    @Test("回転角度の抽出")
    func extractRotationAngle() {
        // Arrange
        let calibration = AntennaAffineCalibration()

        // 45度回転の行列
        let cos45 = cos(Double.pi / 4)
        let sin45 = sin(Double.pi / 4)
        let rotationMatrix = AntennaAffineCalibration.Matrix2x2(
            a11: cos45,
            a12: -sin45,
            a21: sin45,
            a22: cos45
        )

        // Act
        let (angleDegrees, scaleFactors, R) = calibration.extractRotationAngle(from: rotationMatrix)

        // Assert
        #expect(abs(angleDegrees - 45.0) < 1.0)
        #expect(abs(scaleFactors.sx - 1.0) < 0.01)
        #expect(abs(scaleFactors.sy - 1.0) < 0.01)
        #expect(abs(R.determinant - 1.0) < 0.01)
    }

    @Test("アンテナ設定の推定（単純ケース）")
    func estimateAntennaConfigSimple() throws {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let (measuredData, truePositions) = self.setupSimpleTestData()

        // Act
        let config = try calibration.estimateAntennaConfig(
            measuredPointsByTag: measuredData,
            truePositions: truePositions
        )

        // Assert - アンテナ位置は約 (3.0, 3.0)
        #expect(abs(config.x - 3.0) < 0.5)
        #expect(abs(config.y - 3.0) < 0.5)

        // 回転は0度付近
        #expect(abs(config.angleDegrees) < 10.0)

        // RMSE は小さい
        #expect(config.rmse < 0.5)

        print(
            "推定アンテナ位置: (\(config.x), \(config.y)), 角度: \(config.angleDegrees)°, RMSE: \(config.rmse)"
        )
    }

    @Test("アンテナ設定の推定（回転あり）")
    func estimateAntennaConfigWithRotation() throws {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let (measuredData, truePositions) = self.setupTestData()

        // Act
        let config = try calibration.estimateAntennaConfig(
            measuredPointsByTag: measuredData,
            truePositions: truePositions
        )

        // Assert
        #expect(config.x.isFinite)
        #expect(config.y.isFinite)
        #expect(config.angleDegrees.isFinite)
        #expect(config.rmse >= 0.0)

        // アンテナ位置は約 (2.0, 2.0) 付近（想定）
        #expect(abs(config.x - 2.0) < 1.0)
        #expect(abs(config.y - 2.0) < 1.0)

        print(
            "推定アンテナ位置: (\(config.x), \(config.y)), 角度: \(config.angleDegrees)°, RMSE: \(config.rmse)"
        )
    }

    // MARK: - エラーハンドリングテスト

    @Test("不十分な対応点数でのエラー")
    func insufficientPoints() {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let sourcePoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
        ]
        let targetPoints = [
            Point3D(x: 2.0, y: 3.0, z: 0.0),
            Point3D(x: 3.0, y: 3.0, z: 0.0),
        ]

        // Act & Assert
        do {
            _ = try calibration.estimateAffineTransform(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints
            )
            #expect(Bool(false), "エラーが発生する必要があります")
        } catch let error as AntennaAffineCalibration.CalibrationError {
            switch error {
            case .insufficientPoints(let required, let provided):
                #expect(required == 3)
                #expect(provided == 2)
            default:
                #expect(Bool(false), "期待されるエラータイプではありません")
            }
        } catch {
            #expect(Bool(false), "予期しないエラー: \(error)")
        }
    }

    @Test("点数の不一致でのエラー")
    func mismatchedPointCounts() {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let sourcePoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let targetPoints = [
            Point3D(x: 2.0, y: 3.0, z: 0.0),
            Point3D(x: 3.0, y: 3.0, z: 0.0),
        ]

        // Act & Assert
        do {
            _ = try calibration.estimateAffineTransform(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints
            )
            #expect(Bool(false), "エラーが発生する必要があります")
        } catch let error as AntennaAffineCalibration.CalibrationError {
            switch error {
            case .invalidData:
                #expect(Bool(true))
            default:
                #expect(Bool(false), "期待されるエラータイプではありません")
            }
        } catch {
            #expect(Bool(false), "予期しないエラー: \(error)")
        }
    }

    @Test("共通タグなしでのエラー")
    func noCommonTags() {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let measuredData: [String: [Point3D]] = [
            "tag1": [Point3D(x: 1.0, y: 1.0, z: 0.0)],
            "tag2": [Point3D(x: 2.0, y: 2.0, z: 0.0)],
        ]
        let truePositions: [String: Point3D] = [
            "tag3": Point3D(x: 3.0, y: 3.0, z: 0.0),
            "tag4": Point3D(x: 4.0, y: 4.0, z: 0.0),
        ]

        // Act & Assert
        do {
            _ = try calibration.estimateAntennaConfig(
                measuredPointsByTag: measuredData,
                truePositions: truePositions
            )
            #expect(Bool(false), "エラーが発生する必要があります")
        } catch let error as AntennaAffineCalibration.CalibrationError {
            switch error {
            case .insufficientPoints:
                #expect(Bool(true))
            default:
                #expect(Bool(false), "期待されるエラータイプではありません: \(error)")
            }
        } catch {
            #expect(Bool(false), "予期しないエラー: \(error)")
        }
    }

    @Test("同一線上の点での特異行列エラー")
    func collinearPoints() {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let sourcePoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 2.0, y: 2.0, z: 0.0),
        ]
        let targetPoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 2.0, y: 2.0, z: 0.0),
        ]

        // Act & Assert
        do {
            _ = try calibration.estimateAffineTransform(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints
            )
            #expect(Bool(false), "特異行列エラーが発生する必要があります")
        } catch let error as AntennaAffineCalibration.CalibrationError {
            switch error {
            case .singularMatrix:
                #expect(Bool(true))
            default:
                #expect(Bool(false), "期待されるエラータイプではありません: \(error)")
            }
        } catch {
            #expect(Bool(false), "予期しないエラー: \(error)")
        }
    }

    // MARK: - 精度テスト

    @Test("変換の精度検証")
    func transformAccuracy() throws {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let (measuredData, truePositions) = self.setupSimpleTestData()

        // Act
        let config = try calibration.estimateAntennaConfig(
            measuredPointsByTag: measuredData,
            truePositions: truePositions
        )

        // Assert - RMSE が十分小さいこと
        #expect(config.rmse < 0.1)

        // スケール係数がほぼ1であること（単位変換なし）
        #expect(abs(config.scaleFactors.sx - 1.0) < 0.2)
        #expect(abs(config.scaleFactors.sy - 1.0) < 0.2)
    }

    @Test("複数回の測定値の平均化")
    func multipleMeasurementsAveraging() throws {
        // Arrange
        let calibration = AntennaAffineCalibration()
        let measuredData: [String: [Point3D]] = [
            "tag1": [
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 1.1, y: 0.9, z: 0.0),
                Point3D(x: 0.9, y: 1.1, z: 0.0),
                Point3D(x: 1.05, y: 0.95, z: 0.0),
            ],
            "tag2": [
                Point3D(x: 3.0, y: 1.0, z: 0.0),
                Point3D(x: 3.1, y: 0.9, z: 0.0),
                Point3D(x: 2.9, y: 1.1, z: 0.0),
            ],
            "tag3": [
                Point3D(x: 2.0, y: 3.0, z: 0.0),
                Point3D(x: 2.1, y: 2.9, z: 0.0),
                Point3D(x: 1.9, y: 3.1, z: 0.0),
            ],
        ]
        let truePositions: [String: Point3D] = [
            "tag1": Point3D(x: 2.0, y: 2.0, z: 0.0),
            "tag2": Point3D(x: 4.0, y: 2.0, z: 0.0),
            "tag3": Point3D(x: 3.0, y: 4.0, z: 0.0),
        ]

        // Act
        let config = try calibration.estimateAntennaConfig(
            measuredPointsByTag: measuredData,
            truePositions: truePositions
        )

        // Assert
        #expect(config.x.isFinite)
        #expect(config.y.isFinite)
        #expect(config.rmse >= 0.0)
        print("複数測定の平均化後の推定位置: (\(config.x), \(config.y)), RMSE: \(config.rmse)")
    }
}
