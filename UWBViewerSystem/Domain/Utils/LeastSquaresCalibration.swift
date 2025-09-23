import Accelerate
import Foundation

/// 最小二乗法を使用したアンテナキャリブレーション機能
public class LeastSquaresCalibration {

    // MARK: - エラータイプ

    /// キャリブレーション処理中に発生するエラー
    public enum CalibrationError: Error, LocalizedError {
        case insufficientPoints(required: Int, provided: Int)
        case singularMatrix
        case calculationFailed(String)
        case invalidInput(String)

        public var errorDescription: String? {
            switch self {
            case .insufficientPoints(let required, let provided):
                return "データ点が不足しています。必要: \(required)点、提供: \(provided)点"
            case .singularMatrix:
                return "行列が特異行列です。データ点の配置を確認してください"
            case .calculationFailed(let message):
                return "計算エラー: \(message)"
            case .invalidInput(let message):
                return "無効な入力: \(message)"
            }
        }
    }

    // MARK: - 公開メソッド

    /// キャリブレーション点から変換行列を計算
    /// - Parameter points: キャリブレーション点の配列（最小3点必要）
    /// - Returns: 計算された変換行列
    /// - Throws: キャリブレーションエラー
    public static func calculateTransform(from points: [CalibrationPoint]) throws -> CalibrationTransform {
        guard points.count >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: points.count)
        }

        // データ点の妥当性をチェック
        try validatePoints(points)

        // 測定座標と正解座標を分離
        let measuredPoints = points.map { $0.measuredPosition }
        let referencePoints = points.map { $0.referencePosition }

        // 重心を計算
        let measuredCentroid = calculateCentroid(measuredPoints)
        let referenceCentroid = calculateCentroid(referencePoints)

        // 重心を原点に移動
        let centeredMeasured = measuredPoints.map { $0 - measuredCentroid }
        let centeredReference = referencePoints.map { $0 - referenceCentroid }

        // 最適な回転とスケールを計算
        let (rotation, scale) = try calculateRotationAndScale(
            measured: centeredMeasured,
            reference: centeredReference
        )

        // 平行移動を計算（回転・スケール適用後の重心差）
        let rotatedScaledCentroid = applyRotationAndScale(
            point: measuredCentroid,
            rotation: rotation,
            scale: scale
        )
        let translation = referenceCentroid - rotatedScaledCentroid

        // 精度（RMSE）を計算
        let accuracy = calculateRMSE(
            measured: measuredPoints,
            reference: referencePoints,
            transform: CalibrationTransform(
                translation: translation,
                rotation: rotation,
                scale: scale,
                accuracy: 0.0  // 暫定値
            )
        )

        return CalibrationTransform(
            translation: translation,
            rotation: rotation,
            scale: scale,
            accuracy: accuracy
        )
    }

    /// 座標にキャリブレーション変換を適用
    /// - Parameters:
    ///   - point: 変換対象の座標
    ///   - transform: 変換行列
    /// - Returns: 変換後の座標
    public static func applyCalibration(to point: Point3D, using transform: CalibrationTransform) -> Point3D {
        // 1. スケール適用
        let scaled = Point3D(
            x: point.x * transform.scale.x,
            y: point.y * transform.scale.y,
            z: point.z * transform.scale.z
        )

        // 2. 回転適用（2D回転のみサポート）
        let rotated = applyRotation(point: scaled, rotation: transform.rotation)

        // 3. 平行移動適用
        return rotated + transform.translation
    }

    /// 複数の座標にキャリブレーション変換を適用
    /// - Parameters:
    ///   - points: 変換対象の座標配列
    ///   - transform: 変換行列
    /// - Returns: 変換後の座標配列
    public static func applyCalibration(to points: [Point3D], using transform: CalibrationTransform) -> [Point3D] {
        points.map { applyCalibration(to: $0, using: transform) }
    }

    // MARK: - プライベートメソッド

    /// データ点の妥当性をチェック
    private static func validatePoints(_ points: [CalibrationPoint]) throws {
        // 全ての点が同一線上にないかチェック
        guard points.count >= 3 else { return }

        let measured = points.map { $0.measuredPosition }
        let reference = points.map { $0.referencePosition }

        // 測定点が全て同じ位置でないかチェック
        let firstMeasured = measured[0]
        let allSameMeasured = measured.allSatisfy {
            $0.distance(to: firstMeasured) < 1e-10
        }

        if allSameMeasured {
            throw CalibrationError.invalidInput("全ての測定点が同じ位置にあります")
        }

        // 参照点が全て同じ位置でないかチェック
        let firstReference = reference[0]
        let allSameReference = reference.allSatisfy {
            $0.distance(to: firstReference) < 1e-10
        }

        if allSameReference {
            throw CalibrationError.invalidInput("全ての参照点が同じ位置にあります")
        }
    }

    /// 重心を計算
    private static func calculateCentroid(_ points: [Point3D]) -> Point3D {
        let count = Double(points.count)
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let sumZ = points.reduce(0.0) { $0 + $1.z }

        return Point3D(
            x: sumX / count,
            y: sumY / count,
            z: sumZ / count
        )
    }

    /// 最適な回転とスケールを計算（Procrustes解析）
    private static func calculateRotationAndScale(
        measured: [Point3D],
        reference: [Point3D]
    ) throws -> (rotation: Double, scale: Point3D) {

        // 2D変換のため、XY座標のみを使用
        let measuredXY = measured.map { ($0.x, $0.y) }
        let referenceXY = reference.map { ($0.x, $0.y) }

        // 共分散行列を計算
        var h11 = 0.0
        var h12 = 0.0
        var h21 = 0.0
        var h22 = 0.0

        for i in 0..<measuredXY.count {
            let (mx, my) = measuredXY[i]
            let (rx, ry) = referenceXY[i]

            h11 += mx * rx
            h12 += mx * ry
            h21 += my * rx
            h22 += my * ry
        }

        // SVD分解のためのマトリックス準備
        let H = [h11, h12, h21, h22]

        // 2x2行列のSVD分解（簡略化版）
        let rotation = try calculateOptimalRotation(H)

        // スケール計算（各軸独立、分散チェック付き）
        func calculateScaleWithFallback(measured: [Double], reference: [Double]) -> Double {
            let variance = measured.reduce(0.0) { $0 + $1 * $1 }
            if variance > 1e-12 {
                do {
                    return try calculateScale(measured: measured, reference: reference)
                } catch {
                    return 1.0  // エラーが発生した場合はスケール1.0を使用
                }
            } else {
                return 1.0  // 分散が不十分な場合はスケール1.0を使用
            }
        }

        let scaleX = calculateScaleWithFallback(measured: measured.map { $0.x }, reference: reference.map { $0.x })
        let scaleY = calculateScaleWithFallback(measured: measured.map { $0.y }, reference: reference.map { $0.y })
        let scaleZ = calculateScaleWithFallback(measured: measured.map { $0.z }, reference: reference.map { $0.z })

        return (
            rotation: rotation,
            scale: Point3D(x: scaleX, y: scaleY, z: scaleZ)
        )
    }

    /// 2x2行列から最適回転角を計算
    private static func calculateOptimalRotation(_ H: [Double]) throws -> Double {
        let h11 = H[0]
        let h12 = H[1]
        let h21 = H[2]
        let h22 = H[3]

        // 行列式がゼロに近い場合はエラー
        let determinant = h11 * h22 - h12 * h21
        if abs(determinant) < 1e-10 {
            throw CalibrationError.singularMatrix
        }

        // 最適回転角を計算
        let rotation = atan2(h21 - h12, h11 + h22)
        return rotation
    }

    /// 1次元でのスケール計算
    private static func calculateScale(measured: [Double], reference: [Double]) throws -> Double {
        guard measured.count == reference.count else {
            throw CalibrationError.invalidInput("測定点と参照点の数が一致しません")
        }

        let sumMeasuredSquared = measured.reduce(0.0) { $0 + $1 * $1 }
        let sumProduct = zip(measured, reference).reduce(0.0) { $0 + $1.0 * $1.1 }

        guard sumMeasuredSquared > 1e-12 else {
            throw CalibrationError.invalidInput("測定データの分散が不十分です")
        }

        return sumProduct / sumMeasuredSquared
    }

    /// 回転変換を適用
    private static func applyRotation(point: Point3D, rotation: Double) -> Point3D {
        let cos_r = cos(rotation)
        let sin_r = sin(rotation)

        return Point3D(
            x: point.x * cos_r - point.y * sin_r,
            y: point.x * sin_r + point.y * cos_r,
            z: point.z  // Z軸は回転しない
        )
    }

    /// 回転とスケールを適用
    private static func applyRotationAndScale(point: Point3D, rotation: Double, scale: Point3D) -> Point3D {
        // スケール適用
        let scaled = Point3D(
            x: point.x * scale.x,
            y: point.y * scale.y,
            z: point.z * scale.z
        )

        // 回転適用
        return applyRotation(point: scaled, rotation: rotation)
    }

    /// RMSE（Root Mean Square Error）を計算
    private static func calculateRMSE(
        measured: [Point3D],
        reference: [Point3D],
        transform: CalibrationTransform
    ) -> Double {
        guard measured.count == reference.count, !measured.isEmpty else {
            return 0.0
        }

        let transformedPoints = measured.map { applyCalibration(to: $0, using: transform) }

        let sumSquaredErrors = zip(transformedPoints, reference).reduce(0.0) { sum, pair in
            let (transformed, ref) = pair
            let error = transformed.distance(to: ref)
            return sum + error * error
        }

        return sqrt(sumSquaredErrors / Double(measured.count))
    }
}

// MARK: - CalibrationTransform 拡張

extension CalibrationTransform {

    /// 変換の逆行列を計算
    public var inverse: CalibrationTransform {
        // スケールの逆数
        let invScale = Point3D(
            x: scale.x != 0 ? 1.0 / scale.x : 1.0,
            y: scale.y != 0 ? 1.0 / scale.y : 1.0,
            z: scale.z != 0 ? 1.0 / scale.z : 1.0
        )

        // 回転の逆（負の角度）
        let invRotation = -rotation

        // 平行移動の逆（逆変換適用）
        let rotatedTranslation = Point3D(
            x: translation.x * cos(-rotation) - translation.y * sin(-rotation),
            y: translation.x * sin(-rotation) + translation.y * cos(-rotation),
            z: translation.z
        )

        let invTranslation = Point3D(
            x: -rotatedTranslation.x * invScale.x,
            y: -rotatedTranslation.y * invScale.y,
            z: -rotatedTranslation.z * invScale.z
        )

        return CalibrationTransform(
            translation: invTranslation,
            rotation: invRotation,
            scale: invScale,
            accuracy: accuracy
        )
    }

    /// 変換が有効かどうかを判定
    public var isValid: Bool {
        // スケールがゼロまたは負でないかチェック
        guard scale.x > 0, scale.y > 0, scale.z > 0 else {
            return false
        }

        // 回転角度が有効範囲内かチェック
        guard rotation.isFinite else {
            return false
        }

        // 平行移動が有効かチェック
        guard translation.x.isFinite, translation.y.isFinite, translation.z.isFinite else {
            return false
        }

        return true
    }
}
