import Foundation

/// アフィン変換を使用したマップベースキャリブレーション機能
public class AffineTransform {

    // MARK: - エラータイプ

    /// アフィン変換処理中に発生するエラー
    public enum AffineTransformError: Error, LocalizedError {
        case insufficientPoints(required: Int, provided: Int)
        case singularMatrix
        case calculationFailed(String)
        case invalidInput(String)
        case invalidMapCoordinates
        case invalidRealWorldCoordinates

        public var errorDescription: String? {
            switch self {
            case .insufficientPoints(let required, let provided):
                return "データ点が不足しています。必要: \(required)点、提供: \(provided)点"
            case .singularMatrix:
                return "行列が特異行列です。基準座標の配置を確認してください"
            case .calculationFailed(let message):
                return "計算エラー: \(message)"
            case .invalidInput(let message):
                return "無効な入力: \(message)"
            case .invalidMapCoordinates:
                return "マップ座標が無効です"
            case .invalidRealWorldCoordinates:
                return "実世界座標が無効です"
            }
        }
    }

    // MARK: - 公開メソッド

    /// マップ基準座標からアフィン変換行列を計算
    /// - Parameter points: マップキャリブレーション点の配列（3点必要）
    /// - Returns: 計算されたアフィン変換行列
    /// - Throws: アフィン変換エラー
    public static func calculateAffineTransform(from points: [MapCalibrationPoint]) throws -> AffineTransformMatrix {
        guard points.count >= 3 else {
            throw AffineTransformError.insufficientPoints(required: 3, provided: points.count)
        }

        // データ点の妥当性をチェック
        try validateMapCalibrationPoints(points)

        // マップ座標と実世界座標を分離
        let mapCoordinates = points.map { $0.mapCoordinate }
        let realWorldCoordinates = points.map { $0.realWorldCoordinate }

        // アフィン変換行列を計算（最小二乗法）
        let (a, b, c, d, tx, ty) = try calculateAffineParameters(
            from: mapCoordinates,
            to: realWorldCoordinates
        )

        // Z軸変換（シンプルなスケール・平行移動）
        let (scaleZ, translateZ) = try calculateZTransform(
            from: mapCoordinates,
            to: realWorldCoordinates
        )

        // 精度（RMSE）を計算
        let transform = AffineTransformMatrix(
            a: a, b: b, c: c, d: d,
            tx: tx, ty: ty,
            scaleZ: scaleZ, translateZ: translateZ,
            accuracy: 0.0  // 暫定値
        )

        let accuracy = calculateRMSE(
            mapPoints: mapCoordinates,
            realWorldPoints: realWorldCoordinates,
            using: transform
        )

        return AffineTransformMatrix(
            a: a, b: b, c: c, d: d,
            tx: tx, ty: ty,
            scaleZ: scaleZ, translateZ: translateZ,
            accuracy: accuracy
        )
    }

    /// マップ座標を実世界座標に変換
    /// - Parameters:
    ///   - mapPoint: マップ座標
    ///   - transform: アフィン変換行列
    /// - Returns: 実世界座標
    public static func mapToRealWorld(mapPoint: Point3D, using transform: AffineTransformMatrix) -> Point3D {
        // 2D アフィン変換: [x', y'] = [a c tx; b d ty] * [x; y; 1]
        let transformedX = transform.a * mapPoint.x + transform.c * mapPoint.y + transform.tx
        let transformedY = transform.b * mapPoint.x + transform.d * mapPoint.y + transform.ty
        let transformedZ = mapPoint.z * transform.scaleZ + transform.translateZ

        return Point3D(x: transformedX, y: transformedY, z: transformedZ)
    }

    /// 実世界座標をマップ座標に変換
    /// - Parameters:
    ///   - realWorldPoint: 実世界座標
    ///   - transform: アフィン変換行列
    /// - Returns: マップ座標
    public static func realWorldToMap(realWorldPoint: Point3D, using transform: AffineTransformMatrix) throws -> Point3D
    {
        // 逆変換行列を計算
        let inverseTransform = try calculateInverseTransform(transform)
        return mapToRealWorld(mapPoint: realWorldPoint, using: inverseTransform)
    }

    /// 複数の座標を変換
    /// - Parameters:
    ///   - mapPoints: マップ座標の配列
    ///   - transform: アフィン変換行列
    /// - Returns: 実世界座標の配列
    public static func mapToRealWorld(mapPoints: [Point3D], using transform: AffineTransformMatrix) -> [Point3D] {
        mapPoints.map { mapToRealWorld(mapPoint: $0, using: transform) }
    }

    // MARK: - プライベートメソッド

    /// マップキャリブレーション点の妥当性をチェック
    private static func validateMapCalibrationPoints(_ points: [MapCalibrationPoint]) throws {
        guard points.count >= 3 else { return }

        // マップ座標が同一線上にないかチェック
        let mapCoords = points.map { $0.mapCoordinate }
        try validateCoordinatesNotCollinear(mapCoords, coordinateType: "マップ")

        // 実世界座標が同一線上にないかチェック
        let realWorldCoords = points.map { $0.realWorldCoordinate }
        try validateCoordinatesNotCollinear(realWorldCoords, coordinateType: "実世界")

        // 座標値が有効範囲内かチェック
        for point in points {
            guard
                point.mapCoordinate.x.isFinite && point.mapCoordinate.y.isFinite && point.realWorldCoordinate.x.isFinite
                && point.realWorldCoordinate.y.isFinite
            else {
                throw AffineTransformError.invalidInput("座標値が無効です")
            }
        }
    }

    /// 座標が同一線上にないかチェック
    private static func validateCoordinatesNotCollinear(_ coordinates: [Point3D], coordinateType: String) throws {
        guard coordinates.count >= 3 else { return }

        // 最初の3点を使って三角形の面積を計算
        let p1 = coordinates[0]
        let p2 = coordinates[1]
        let p3 = coordinates[2]

        // 外積を使って三角形の面積を計算
        let area = abs((p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y)) / 2.0

        if area < 1e-10 {
            throw AffineTransformError.invalidInput("\(coordinateType)座標が同一線上にあります")
        }
    }

    /// アフィン変換パラメータを最小二乗法で計算
    private static func calculateAffineParameters(
        from mapCoords: [Point3D],
        to realWorldCoords: [Point3D]
    ) throws -> (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {

        let n = mapCoords.count
        guard n >= 3 else {
            throw AffineTransformError.insufficientPoints(required: 3, provided: n)
        }

        // 連立方程式を構築: A * params = B
        // [u1 v1 1 0  0  0] [a ]   [x1]
        // [0  0  0 u1 v1 1] [c ]   [y1]
        // [u2 v2 1 0  0  0] [tx] = [x2]
        // [0  0  0 u2 v2 1] [b ]   [y2]
        // [u3 v3 1 0  0  0] [d ]   [x3]
        // [0  0  0 u3 v3 1] [ty]   [y3]

        var matrixA: [Double] = []
        var vectorB: [Double] = []

        for i in 0..<n {
            let u = mapCoords[i].x
            let v = mapCoords[i].y
            let x = realWorldCoords[i].x
            let y = realWorldCoords[i].y

            // X方程式: a*u + c*v + tx = x
            matrixA.append(contentsOf: [u, v, 1.0, 0.0, 0.0, 0.0])
            vectorB.append(x)

            // Y方程式: b*u + d*v + ty = y
            matrixA.append(contentsOf: [0.0, 0.0, 0.0, u, v, 1.0])
            vectorB.append(y)
        }

        // 最小二乗法でパラメータを計算
        let parameters = try solveLeastSquares(
            matrix: matrixA,
            vector: vectorB,
            rows: n * 2,
            cols: 6
        )

        guard parameters.count == 6 else {
            throw AffineTransformError.calculationFailed("パラメータ計算に失敗しました")
        }

        let a = parameters[0]
        let c = parameters[1]
        let tx = parameters[2]
        let b = parameters[3]
        let d = parameters[4]
        let ty = parameters[5]

        // 行列の特異性をチェック
        let determinant = a * d - b * c
        if abs(determinant) < 1e-10 {
            throw AffineTransformError.singularMatrix
        }

        return (a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    /// Z軸変換パラメータを計算
    private static func calculateZTransform(
        from mapCoords: [Point3D],
        to realWorldCoords: [Point3D]
    ) throws -> (scaleZ: Double, translateZ: Double) {

        // Z座標のマッピングは線形変換として扱う: z' = scale * z + translate
        let mapZ = mapCoords.map { $0.z }
        let realZ = realWorldCoords.map { $0.z }

        // 最小二乗法で線形回帰
        let n = Double(mapZ.count)
        let sumMapZ = mapZ.reduce(0, +)
        let sumRealZ = realZ.reduce(0, +)
        let sumMapZ2 = mapZ.map { $0 * $0 }.reduce(0, +)
        let sumMapZRealZ = zip(mapZ, realZ).map { $0.0 * $0.1 }.reduce(0, +)

        let denominator = n * sumMapZ2 - sumMapZ * sumMapZ
        guard abs(denominator) > 1e-10 else {
            // Z座標が定数の場合、スケール1、平行移動のみ
            return (scaleZ: 1.0, translateZ: realZ.first ?? 0.0)
        }

        let scaleZ = (n * sumMapZRealZ - sumMapZ * sumRealZ) / denominator
        let translateZ = (sumRealZ - scaleZ * sumMapZ) / n

        return (scaleZ: scaleZ, translateZ: translateZ)
    }

    /// 最小二乗法でAx = Bを解く（簡略化版）
    private static func solveLeastSquares(
        matrix: [Double],
        vector: [Double],
        rows: Int,
        cols: Int
    ) throws -> [Double] {

        // 簡略化された実装: 通常逆行列を使用
        // A^T * A * x = A^T * b

        guard rows >= cols else {
            throw AffineTransformError.calculationFailed("行列の次元が無効です")
        }

        // A^T * A を計算
        var AtA = Array(repeating: Array(repeating: 0.0, count: cols), count: cols)
        var Atb = Array(repeating: 0.0, count: cols)

        for i in 0..<cols {
            for j in 0..<cols {
                var sum = 0.0
                for k in 0..<rows {
                    sum += matrix[k * cols + i] * matrix[k * cols + j]
                }
                AtA[i][j] = sum
            }

            var sum = 0.0
            for k in 0..<rows {
                sum += matrix[k * cols + i] * vector[k]
            }
            Atb[i] = sum
        }

        // ガウス・ジョルダン法で連立方程式を解く
        return try solveLinearSystem(AtA, Atb)
    }

    /// ガウス・ジョルダン法で連立方程式を解く
    private static func solveLinearSystem(_ A: [[Double]], _ b: [Double]) throws -> [Double] {
        let n = A.count
        guard n == b.count && A.allSatisfy({ $0.count == n }) else {
            throw AffineTransformError.calculationFailed("行列の次元が一致しません")
        }

        var augmented = A.map { Array($0) }
        var result = b

        // 前進消去
        for i in 0..<n {
            // ピボット選択
            let maxRow = (i..<n).max { abs(augmented[$0][i]) < abs(augmented[$1][i]) } ?? i
            if maxRow != i {
                augmented.swapAt(i, maxRow)
                result.swapAt(i, maxRow)
            }

            let pivot = augmented[i][i]
            guard abs(pivot) > 1e-10 else {
                throw AffineTransformError.singularMatrix
            }

            // 行の正規化
            for j in 0..<n {
                augmented[i][j] /= pivot
            }
            result[i] /= pivot

            // 他の行を消去
            for k in 0..<n where k != i {
                let factor = augmented[k][i]
                for j in 0..<n {
                    augmented[k][j] -= factor * augmented[i][j]
                }
                result[k] -= factor * result[i]
            }
        }

        return result
    }

    /// 逆変換行列を計算
    public static func calculateInverseTransform(_ transform: AffineTransformMatrix) throws -> AffineTransformMatrix {
        let det = transform.determinant
        guard abs(det) > 1e-10 else {
            throw AffineTransformError.singularMatrix
        }

        let invDet = 1.0 / det
        let a = transform.d * invDet
        let b = -transform.b * invDet
        let c = -transform.c * invDet
        let d = transform.a * invDet
        let tx = (transform.c * transform.ty - transform.d * transform.tx) * invDet
        let ty = (transform.b * transform.tx - transform.a * transform.ty) * invDet

        let scaleZ = transform.scaleZ != 0 ? 1.0 / transform.scaleZ : 1.0
        let translateZ = -transform.translateZ * scaleZ

        return AffineTransformMatrix(
            a: a, b: b, c: c, d: d,
            tx: tx, ty: ty,
            scaleZ: scaleZ, translateZ: translateZ,
            accuracy: transform.accuracy
        )
    }

    /// RMSE（Root Mean Square Error）を計算
    private static func calculateRMSE(
        mapPoints: [Point3D],
        realWorldPoints: [Point3D],
        using transform: AffineTransformMatrix
    ) -> Double {
        guard mapPoints.count == realWorldPoints.count, !mapPoints.isEmpty else {
            return 0.0
        }

        let transformedPoints = mapPoints.map { mapToRealWorld(mapPoint: $0, using: transform) }

        let sumSquaredErrors = zip(transformedPoints, realWorldPoints).reduce(0.0) { sum, pair in
            let (transformed, reference) = pair
            let error = transformed.distance(to: reference)
            return sum + error * error
        }

        return sqrt(sumSquaredErrors / Double(mapPoints.count))
    }
}

// MARK: - AffineTransformMatrix 拡張

extension AffineTransformMatrix {

    /// 逆変換行列を取得
    public var inverse: AffineTransformMatrix {
        do {
            return try AffineTransform.calculateInverseTransform(self)
        } catch {
            // エラーが発生した場合は単位行列を返す
            return .identity
        }
    }

    /// 行列を文字列で表示（デバッグ用）
    public var matrixDescription: String {
        """
        [[ \(String(format: "%.3f", a))  \(String(format: "%.3f", c))  \(String(format: "%.3f", tx)) ]
         [ \(String(format: "%.3f", b))  \(String(format: "%.3f", d))  \(String(format: "%.3f", ty)) ]
         [ 0.000  0.000  1.000 ]]
        Z: scale=\(String(format: "%.3f", scaleZ)), translate=\(String(format: "%.3f", translateZ))
        Accuracy: \(String(format: "%.6f", accuracy))
        """
    }
}
