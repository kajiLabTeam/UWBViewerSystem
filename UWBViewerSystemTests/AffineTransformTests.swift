import XCTest
@testable import UWBViewerSystem

/// アフィン変換機能のテスト
final class AffineTransformTests: XCTestCase {

    var sampleMapCalibrationPoints: [MapCalibrationPoint]!

    override func setUp() {
        setupSampleCalibrationPoints()
    }

    override func tearDown() {
        sampleMapCalibrationPoints = nil
    }

    // MARK: - セットアップメソッド

    private func setupSampleCalibrationPoints() {
        sampleMapCalibrationPoints = [
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

    func testAffineTransformCalculation() throws {
        // アフィン変換行列の計算テスト
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)

        XCTAssertTrue(transform.isValid, "計算された変換行列が有効である必要があります")
        XCTAssertGreaterThan(abs(transform.determinant), 1e-10, "変換行列の行列式が非特異である必要があります")
        XCTAssertLessThan(transform.accuracy, 1.0, "変換の精度が1.0m以下である必要があります")

        print("📊 アフィン変換行列:")
        print(transform.matrixDescription)
    }

    func testMapToRealWorldCoordinateConversion() throws {
        // マップ座標から実世界座標への変換テスト
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)

        let mapPoint = Point3D(x: 200, y: 200, z: 0)
        let realWorldPoint = UWBViewerSystem.AffineTransform.mapToRealWorld(mapPoint: mapPoint, using: transform)

        XCTAssertTrue(realWorldPoint.x.isFinite, "X座標が有限値である必要があります")
        XCTAssertTrue(realWorldPoint.y.isFinite, "Y座標が有限値である必要があります")
        XCTAssertTrue(realWorldPoint.z.isFinite, "Z座標が有限値である必要があります")

        print("🗺️ 座標変換: マップ(\(mapPoint.x), \(mapPoint.y)) → 実世界(\(realWorldPoint.x), \(realWorldPoint.y))")
    }

    func testRealWorldToMapCoordinateConversion() throws {
        // 実世界座標からマップ座標への逆変換テスト
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)

        let realWorldPoint = Point3D(x: 1, y: 1, z: 0)
        let mapPoint = try UWBViewerSystem.AffineTransform.realWorldToMap(realWorldPoint: realWorldPoint, using: transform)

        XCTAssertTrue(mapPoint.x.isFinite, "X座標が有限値である必要があります")
        XCTAssertTrue(mapPoint.y.isFinite, "Y座標が有限値である必要があります")

        print("🔄 逆変換: 実世界(\(realWorldPoint.x), \(realWorldPoint.y)) → マップ(\(mapPoint.x), \(mapPoint.y))")
    }

    func testTransformationRoundTrip() throws {
        // 往復変換の精度テスト
        let transform = try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: sampleMapCalibrationPoints)

        let originalMapPoint = Point3D(x: 250, y: 150, z: 0)
        let realWorldPoint = UWBViewerSystem.AffineTransform.mapToRealWorld(mapPoint: originalMapPoint, using: transform)
        let reconstructedMapPoint = try UWBViewerSystem.AffineTransform.realWorldToMap(realWorldPoint: realWorldPoint, using: transform)

        let errorX = abs(originalMapPoint.x - reconstructedMapPoint.x)
        let errorY = abs(originalMapPoint.y - reconstructedMapPoint.y)

        XCTAssertLessThan(errorX, 1.0, "X座標の往復変換エラーが1.0未満である必要があります")
        XCTAssertLessThan(errorY, 1.0, "Y座標の往復変換エラーが1.0未満である必要があります")

        print("🔄 往復変換エラー: X=\(errorX), Y=\(errorY)")
    }

    // MARK: - エラーハンドリングテスト

    func testInsufficientCalibrationPoints() {
        // 不十分な点数でのエラーテスト
        let insufficientPoints = Array(sampleMapCalibrationPoints.prefix(2)) // 2点のみ

        XCTAssertThrowsError(try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: insufficientPoints)) { error in
            XCTAssertTrue(error is UWBViewerSystem.AffineTransform.AffineTransformError, "適切なエラータイプが発生する必要があります")
            if case let UWBViewerSystem.AffineTransform.AffineTransformError.insufficientPoints(required, provided) = error {
                XCTAssertEqual(required, 3, "必要な点数が3である必要があります")
                XCTAssertEqual(provided, 2, "提供された点数が2である必要があります")
            } else {
                XCTFail("期待されるエラータイプではありません")
            }
        }
    }

    func testCollinearCalibrationPoints() {
        // 同一線上の点でのエラーテスト
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

        XCTAssertThrowsError(try UWBViewerSystem.AffineTransform.calculateAffineTransform(from: collinearPoints)) { error in
            XCTAssertTrue(error is UWBViewerSystem.AffineTransform.AffineTransformError, "適切なエラータイプが発生する必要があります")
        }
    }
}