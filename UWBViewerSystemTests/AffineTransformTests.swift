import Foundation
import Testing
@testable import UWBViewerSystem

/// アフィン変換機能のテスト
struct AffineTransformTests {

    private func setupSampleCalibrationPoints() -> [MapCalibrationPoint] {
        [
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 100, y: 100, z: 0),
                realWorldCoordinate: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1",
                pointIndex: 1
            ),
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 300, y: 100, z: 0),
                realWorldCoordinate: Point3D(x: 2, y: 0, z: 0),
                antennaId: "antenna1",
                pointIndex: 2
            ),
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 200, y: 300, z: 0),
                realWorldCoordinate: Point3D(x: 1, y: 2, z: 0),
                antennaId: "antenna1",
                pointIndex: 3
            )
        ]
    }

    // MARK: - アフィン変換テスト

    @Test("アフィン変換行列の計算")
    func testAffineTransformCalculation() throws {
        // Arrange
        let sampleMapCalibrationPoints = setupSampleCalibrationPoints()

        // Act
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)

        // Assert
        #expect(transform.isValid)
        #expect(abs(transform.determinant) > 1e-10)
        #expect(transform.accuracy < 1.0)

        print("📊 アフィン変換行列:")
        print(transform.matrixDescription)
    }

    @Test("マップ座標から実世界座標への変換")
    func testMapToRealWorldCoordinateConversion() throws {
        // Arrange
        let sampleMapCalibrationPoints = setupSampleCalibrationPoints()
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)
        let mapPoint = Point3D(x: 200, y: 200, z: 0)

        // Act
        let realWorldPoint = UWBViewerSystem.AffineTransform.mapToRealWorld(mapPoint: mapPoint, using: transform)

        // Assert
        #expect(realWorldPoint.x.isFinite)
        #expect(realWorldPoint.y.isFinite)
        #expect(realWorldPoint.z.isFinite)

        print("🗺️ 座標変換: マップ(\(mapPoint.x), \(mapPoint.y)) → 実世界(\(realWorldPoint.x), \(realWorldPoint.y))")
    }

    @Test("実世界座標からマップ座標への逆変換")
    func testRealWorldToMapCoordinateConversion() throws {
        // Arrange
        let sampleMapCalibrationPoints = setupSampleCalibrationPoints()
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)
        let realWorldPoint = Point3D(x: 1, y: 1, z: 0)

        // Act
        let mapPoint = try UWBViewerSystem.AffineTransform.realWorldToMap(realWorldPoint: realWorldPoint, using: transform)

        // Assert
        #expect(mapPoint.x.isFinite)
        #expect(mapPoint.y.isFinite)

        print("🔄 逆変換: 実世界(\(realWorldPoint.x), \(realWorldPoint.y)) → マップ(\(mapPoint.x), \(mapPoint.y))")
    }

    @Test("往復変換の精度")
    func testTransformationRoundTrip() throws {
        // Arrange
        let sampleMapCalibrationPoints = setupSampleCalibrationPoints()
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)
        let originalMapPoint = Point3D(x: 250, y: 150, z: 0)

        // Act
        let realWorldPoint = UWBViewerSystem.AffineTransform.mapToRealWorld(mapPoint: originalMapPoint, using: transform)
        let reconstructedMapPoint = try UWBViewerSystem.AffineTransform.realWorldToMap(realWorldPoint: realWorldPoint, using: transform)

        let errorX = abs(originalMapPoint.x - reconstructedMapPoint.x)
        let errorY = abs(originalMapPoint.y - reconstructedMapPoint.y)

        // Assert
        #expect(errorX < 1.0)
        #expect(errorY < 1.0)

        print("🔄 往復変換エラー: X=\(errorX), Y=\(errorY)")
    }

    // MARK: - エラーハンドリングテスト

    @Test("不十分なキャリブレーションポイントでのエラー")
    func testInsufficientCalibrationPoints() {
        // Arrange
        let sampleMapCalibrationPoints = setupSampleCalibrationPoints()
        let insufficientPoints = Array(sampleMapCalibrationPoints.prefix(2)) // 2点のみ

        // Act & Assert
        do {
            _ = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: insufficientPoints)
            #expect(Bool(false), "適切なエラータイプが発生する必要があります")
        } catch let error as UWBViewerSystem.AffineTransform.AffineTransformError {
            switch error {
            case .insufficientPoints(let required, let provided):
                #expect(required == 3)
                #expect(provided == 2)
            default:
                #expect(Bool(false), "期待されるエラータイプではありません")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("同一線上のキャリブレーションポイントでのエラー")
    func testCollinearCalibrationPoints() {
        // Arrange
        let collinearPoints = [
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 100, y: 100, z: 0),
                realWorldCoordinate: Point3D(x: 0, y: 0, z: 0),
                antennaId: "antenna1",
                pointIndex: 1
            ),
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 200, y: 200, z: 0),
                realWorldCoordinate: Point3D(x: 1, y: 1, z: 0),
                antennaId: "antenna1",
                pointIndex: 2
            ),
            MapCalibrationPoint(
                mapCoordinate: Point3D(x: 300, y: 300, z: 0),
                realWorldCoordinate: Point3D(x: 2, y: 2, z: 0),
                antennaId: "antenna1",
                pointIndex: 3
            )
        ]

        // Act & Assert
        do {
            _ = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: collinearPoints)
            #expect(Bool(false), "適切なエラータイプが発生する必要があります")
        } catch _ as UWBViewerSystem.AffineTransform.AffineTransformError {
            #expect(Bool(true)) // 期待される動作
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}