import Accelerate
import Foundation

/// アンテナごとの2Dアフィン変換を最小二乗法で推定し、アンテナ位置と角度を自動計算するユーティリティ
///
/// # 概要
/// 各アンテナが観測したタグ位置（測定座標）と、タグの正確な座標（既知）の対応点から、
/// 2Dアフィン変換 q = A * p + t を最小二乗法で推定します。
/// 推定したアフィン変換から平行移動（tx, ty）と回転成分（角度）を取り出し、
/// ANTENNA_CONFIG の (x, y, angle) を自動生成します。
///
/// # アフィン変換の推定
/// ```
/// q = A * p + t
/// ```
/// ここで：
/// - p: 測定座標（アンテナローカル座標系）
/// - q: 真の座標（実世界座標系）
/// - A: 2x2 線形変換行列（回転・スケール・せん断）
/// - t: 平行移動ベクトル（アンテナ位置）
///
/// # 使い方
/// ```swift
/// let calibration = AntennaAffineCalibration()
///
/// // 各アンテナごとに測定点と真の座標を用意
/// let measuredPoints: [String: [Point3D]] = [
///     "tag1": [Point3D(x: 1.0, y: 2.0, z: 0), ...],
///     "tag2": [Point3D(x: 3.0, y: 4.0, z: 0), ...]
/// ]
/// let truePositions: [String: Point3D] = [
///     "tag1": Point3D(x: 5.0, y: 6.0, z: 0),
///     "tag2": Point3D(x: 7.0, y: 8.0, z: 0)
/// ]
///
/// // アンテナ設定を推定
/// if let config = try? calibration.estimateAntennaConfig(
///     measuredPointsByTag: measuredPoints,
///     truePositions: truePositions
/// ) {
///     print("アンテナ位置: (\(config.x), \(config.y)), 角度: \(config.angleDegrees)°")
/// }
/// ```
struct AntennaAffineCalibration {

    // MARK: - Types

    /// 推定されたアンテナ設定
    struct AntennaConfig {
        let x: Double // アンテナのX座標 (m)
        let y: Double // アンテナのY座標 (m)
        let angleDegrees: Double // アンテナの角度 (度)
        let angleRadians: Double // アンテナの角度 (ラジアン)
        let scaleFactors: (sx: Double, sy: Double) // スケール係数
        let rmse: Double // 推定誤差 (RMSE)

        var position: Point3D {
            Point3D(x: self.x, y: self.y, z: 0)
        }
    }

    /// 品質情報付き測定点
    struct WeightedMeasurement {
        let position: Point3D
        let quality: SignalQuality

        /// 重みを計算（品質が高いほど重みが大きい）
        var weight: Double {
            let strengthWeight = self.quality.strength
            let confidenceWeight = self.quality.confidenceLevel
            let errorWeight = 1.0 / max(self.quality.errorEstimate, 0.01)
            // 正規化して0-1の範囲に
            let normalizedErrorWeight = min(errorWeight / 10.0, 1.0)
            return strengthWeight * confidenceWeight * normalizedErrorWeight
        }
    }

    /// 2x2行列
    struct Matrix2x2 {
        let a11: Double
        let a12: Double
        let a21: Double
        let a22: Double

        var determinant: Double {
            self.a11 * self.a22 - self.a12 * self.a21
        }

        func multiply(_ point: Point3D) -> Point3D {
            Point3D(
                x: self.a11 * point.x + self.a12 * point.y,
                y: self.a21 * point.x + self.a22 * point.y,
                z: 0
            )
        }
    }

    /// アフィン変換結果
    struct AffineTransform {
        let A: Matrix2x2 // 2x2線形変換行列
        let t: Point3D // 平行移動ベクトル
    }

    /// IRLS設定
    struct IRLSConfig {
        let maxIterations: Int
        let tolerance: Double
        let useCauchyLoss: Bool

        static let `default` = IRLSConfig(
            maxIterations: 10,
            tolerance: 1e-6,
            useCauchyLoss: true
        )
    }

    // MARK: - Properties

    /// IRLS設定
    private let irlsConfig: IRLSConfig

    // MARK: - Initialization

    init(irlsConfig: IRLSConfig = .default) {
        self.irlsConfig = irlsConfig
    }

    // MARK: - Errors

    enum CalibrationError: LocalizedError {
        case insufficientPoints(required: Int, provided: Int)
        case noCommonTags
        case singularMatrix
        case invalidData(String)

        var errorDescription: String? {
            switch self {
            case .insufficientPoints(let required, let provided):
                return "対応点が不足しています。最低\(required)点必要ですが、\(provided)点しかありません。"
            case .noCommonTags:
                return "測定データと真の座標に共通のタグが見つかりません。"
            case .singularMatrix:
                return "行列が特異です。点が一直線上にある可能性があります。"
            case .invalidData(let message):
                return "無効なデータ: \(message)"
            }
        }
    }

    // MARK: - Public Methods

    /// 対応点から2Dアフィン変換を最小二乗法で推定
    ///
    /// - Parameters:
    ///   - sourcePoints: 測定座標の配列（アンテナローカル座標系）
    ///   - targetPoints: 真の座標の配列（実世界座標系）
    /// - Returns: 推定されたアフィン変換 (A, t)
    /// - Throws: 点数が不足している場合や行列が特異の場合
    func estimateAffineTransform(
        sourcePoints: [Point3D],
        targetPoints: [Point3D]
    ) throws -> AffineTransform {
        guard sourcePoints.count == targetPoints.count else {
            throw CalibrationError.invalidData("測定点と真の座標の数が一致しません")
        }

        let n = sourcePoints.count
        guard n >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: n)
        }

        // デザイン行列を構築（列優先形式でLAPACKに渡す）
        // [ x y 0 0 1 0 ]   [ a11 ]   [ qx ]
        // [ 0 0 x y 0 1 ] * [ a12 ] = [ qy ]
        //                   [ a21 ]
        //                   [ a22 ]
        //                   [ tx  ]
        //                   [ ty  ]

        // LAPACKは列優先形式を期待するので、列ごとに構築
        let nrows = 2 * n
        let ncols = 6
        var X = [Double](repeating: 0.0, count: nrows * ncols)
        var Y = [Double](repeating: 0.0, count: nrows)

        for i in 0..<n {
            let p = sourcePoints[i]
            let q = targetPoints[i]

            // 行 2*i (qx の方程式): qx = a11*px + a12*py + tx
            // 列優先: X[col * nrows + row]
            X[0 * nrows + 2 * i] = p.x // a11の列、2*i行
            X[1 * nrows + 2 * i] = p.y // a12の列、2*i行
            X[2 * nrows + 2 * i] = 0.0 // a21の列、2*i行
            X[3 * nrows + 2 * i] = 0.0 // a22の列、2*i行
            X[4 * nrows + 2 * i] = 1.0 // txの列、2*i行
            X[5 * nrows + 2 * i] = 0.0 // tyの列、2*i行
            Y[2 * i] = q.x

            // 行 2*i+1 (qy の方程式): qy = a21*px + a22*py + ty
            X[0 * nrows + 2 * i + 1] = 0.0 // a11の列、2*i+1行
            X[1 * nrows + 2 * i + 1] = 0.0 // a12の列、2*i+1行
            X[2 * nrows + 2 * i + 1] = p.x // a21の列、2*i+1行
            X[3 * nrows + 2 * i + 1] = p.y // a22の列、2*i+1行
            X[4 * nrows + 2 * i + 1] = 0.0 // txの列、2*i+1行
            X[5 * nrows + 2 * i + 1] = 1.0 // tyの列、2*i+1行
            Y[2 * i + 1] = q.y
        }

        // 最小二乗法で解く: X * params = Y
        let params = try solveLeastSquares(X: X, Y: Y, m: nrows, n: ncols)

        let A = Matrix2x2(
            a11: params[0],
            a12: params[1],
            a21: params[2],
            a22: params[3]
        )
        let t = Point3D(x: params[4], y: params[5], z: 0)

        // 行列の妥当性チェック
        guard abs(A.determinant) > 1e-10 else {
            throw CalibrationError.singularMatrix
        }

        return AffineTransform(A: A, t: t)
    }

    /// 2x2行列から回転角度を抽出（SVD分解を使用）
    ///
    /// - Parameter A: 2x2線形変換行列
    /// - Returns: (角度(度), スケール係数, 回転行列)
    func extractRotationAngle(from A: Matrix2x2) -> (angleDegrees: Double, scaleFactors: (
        sx: Double, sy: Double
    ), R: Matrix2x2) {
        // SVD分解: A = U * S * V^T
        var matrixA = [A.a11, A.a21, A.a12, A.a22] // 列優先順序
        var U = [Double](repeating: 0.0, count: 4)
        var S = [Double](repeating: 0.0, count: 2)
        var Vt = [Double](repeating: 0.0, count: 4)

        var m: Int32 = 2
        var n: Int32 = 2
        var lda: Int32 = 2
        var ldu: Int32 = 2
        var ldvt: Int32 = 2
        var lwork: Int32 = -1
        var info: Int32 = 0

        // ワークスペースサイズを取得
        var workspaceQuery: Double = 0
        dgesvd_(
            UnsafeMutablePointer(mutating: ("A" as NSString).utf8String), // JOBU = 'A'
            UnsafeMutablePointer(mutating: ("A" as NSString).utf8String), // JOBVT = 'A'
            &m, &n,
            &matrixA, &lda,
            &S,
            &U, &ldu,
            &Vt, &ldvt,
            &workspaceQuery, &lwork,
            &info
        )

        // SVD実行
        lwork = Int32(workspaceQuery)
        var workspace = [Double](repeating: 0.0, count: Int(lwork))
        dgesvd_(
            UnsafeMutablePointer(mutating: ("A" as NSString).utf8String),
            UnsafeMutablePointer(mutating: ("A" as NSString).utf8String),
            &m, &n,
            &matrixA, &lda,
            &S,
            &U, &ldu,
            &Vt, &ldvt,
            &workspace, &lwork,
            &info
        )

        // 回転行列 R = U * V^T
        // U は列優先: [u11, u21, u12, u22]
        // Vt は列優先: [vt11, vt21, vt12, vt22]
        let u11 = U[0]
        let u21 = U[1]
        let u12 = U[2]
        let u22 = U[3]

        let vt11 = Vt[0]
        let vt21 = Vt[1]
        let vt12 = Vt[2]
        let vt22 = Vt[3]

        // R = U * V^T (行列の積)
        let r11 = u11 * vt11 + u12 * vt12
        let r12 = u11 * vt21 + u12 * vt22
        let r21 = u21 * vt11 + u22 * vt12
        let r22 = u21 * vt21 + u22 * vt22

        let R = Matrix2x2(a11: r11, a12: r12, a21: r21, a22: r22)

        // 反射を修正（det(R) < 0 の場合）
        var finalR = R
        var finalS = S
        if R.determinant < 0 {
            // Vの最後の列の符号を反転
            finalR = Matrix2x2(
                a11: u11 * vt11 - u12 * vt12,
                a12: u11 * vt21 - u12 * vt22,
                a21: u21 * vt11 - u22 * vt12,
                a22: u21 * vt21 - u22 * vt22
            )
            finalS[1] = -finalS[1]
        }

        // 回転角度を計算: θ = atan2(R21, R11)
        let angleRadians = atan2(finalR.a21, finalR.a11)
        let angleDegrees = angleRadians * 180.0 / .pi

        return (
            angleDegrees: angleDegrees,
            scaleFactors: (sx: finalS[0], sy: finalS[1]),
            R: finalR
        )
    }

    /// 各タグのアンテナ測定データと真の座標から、アンテナの設定を推定
    ///
    /// - Parameters:
    ///   - measuredPointsByTag: タグIDごとの測定座標リスト（アンテナが観測した座標）
    ///   - truePositions: タグIDごとの真の座標（既知の正確な位置）
    /// - Returns: 推定されたアンテナ設定 (x, y, angle)
    /// - Throws: データが不足している場合や推定に失敗した場合
    func estimateAntennaConfig(
        measuredPointsByTag: [String: [Point3D]],
        truePositions: [String: Point3D]
    ) throws -> AntennaConfig {
        // 共通のタグIDを取得
        let commonTags = Set(measuredPointsByTag.keys).intersection(Set(truePositions.keys))
        guard commonTags.count >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: commonTags.count)
        }

        // 各タグの測定点を平均して代表点を作成（外れ値処理）
        var sourcePoints: [Point3D] = []
        var targetPoints: [Point3D] = []

        for tagId in commonTags.sorted() {
            guard let measurements = measuredPointsByTag[tagId],
                  !measurements.isEmpty,
                  let truePos = truePositions[tagId]
            else {
                continue
            }

            // 測定点の平均を取る（外れ値除去のためにメディアンも検討可能）
            let avgX = measurements.map { $0.x }.reduce(0, +) / Double(measurements.count)
            let avgY = measurements.map { $0.y }.reduce(0, +) / Double(measurements.count)
            let avgMeasurement = Point3D(x: avgX, y: avgY, z: 0)

            sourcePoints.append(avgMeasurement)
            targetPoints.append(truePos)
        }

        guard sourcePoints.count >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: sourcePoints.count)
        }

        // デバッグ: 平均化された代表点を出力
        print("📊 平均化された測定点（ソース）:")
        for (index, point) in sourcePoints.enumerated() {
            print(
                "   Point\(index + 1): (\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y)))"
            )
        }
        print("📍 真の位置（ターゲット）:")
        for (index, point) in targetPoints.enumerated() {
            print(
                "   Point\(index + 1): (\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y)))"
            )
        }

        // 共線性チェック: 3点が一直線上にないか確認
        if sourcePoints.count == 3 {
            let p1 = sourcePoints[0]
            let p2 = sourcePoints[1]
            let p3 = sourcePoints[2]

            // 外積を計算して面積をチェック（面積が0に近いと共線）
            let v1x = p2.x - p1.x
            let v1y = p2.y - p1.y
            let v2x = p3.x - p1.x
            let v2y = p3.y - p1.y
            let crossProduct = abs(v1x * v2y - v1y * v2x)

            print("🔍 共線性チェック: 外積の絶対値 = \(String(format: "%.6f", crossProduct))")

            if crossProduct < 0.01 {
                throw CalibrationError.invalidData(
                    "測定点が一直線上に並んでいます（外積=\(String(format: "%.6f", crossProduct))）。"
                        + "タグを異なる位置に配置してください。"
                )
            }
        }

        // アフィン変換を推定（Cauchy Loss IRLS使用時）
        let transform: AffineTransform
        if self.irlsConfig.useCauchyLoss {
            transform = try self.estimateAffineTransformWithIRLS(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints
            )
        } else {
            transform = try self.estimateAffineTransform(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints
            )
        }

        // 回転角度とスケールを抽出
        let (angleDegrees, scaleFactors, _) = self.extractRotationAngle(from: transform.A)

        // RMSEを計算
        let rmse = self.calculateRMSE(
            sourcePoints: sourcePoints,
            targetPoints: targetPoints,
            transform: transform
        )

        // アンテナ設定を作成
        // t がアンテナの位置に対応
        let config = AntennaConfig(
            x: transform.t.x,
            y: transform.t.y,
            angleDegrees: angleDegrees,
            angleRadians: angleDegrees * .pi / 180.0,
            scaleFactors: scaleFactors,
            rmse: rmse
        )

        print("""
        📡 アンテナキャリブレーション結果:
           位置: (\(String(format: "%.3f", config.x)), \(String(format: "%.3f", config.y))) m
           角度: \(String(format: "%.2f", config.angleDegrees))°
           スケール: (sx: \(String(format: "%.3f", scaleFactors.sx)), sy: \(String(format: "%.3f", scaleFactors.sy)))
           RMSE: \(String(format: "%.4f", config.rmse)) m
           使用タグ数: \(sourcePoints.count)
        """)

        return config
    }

    /// 品質情報付き測定データからアンテナの設定を推定（重み付け平均使用）
    ///
    /// - Parameters:
    ///   - weightedMeasurementsByTag: タグIDごとの品質情報付き測定データリスト
    ///   - truePositions: タグIDごとの真の座標（既知の正確な位置）
    /// - Returns: 推定されたアンテナ設定 (x, y, angle)
    /// - Throws: データが不足している場合や推定に失敗した場合
    func estimateAntennaConfigWithQuality(
        weightedMeasurementsByTag: [String: [WeightedMeasurement]],
        truePositions: [String: Point3D]
    ) throws -> AntennaConfig {
        // 共通のタグIDを取得
        let commonTags = Set(weightedMeasurementsByTag.keys).intersection(Set(truePositions.keys))
        guard commonTags.count >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: commonTags.count)
        }

        // 各タグの測定点を重み付け平均して代表点を作成
        var sourcePoints: [Point3D] = []
        var targetPoints: [Point3D] = []
        var pointWeights: [Double] = []

        for tagId in commonTags.sorted() {
            guard let measurements = weightedMeasurementsByTag[tagId],
                  !measurements.isEmpty,
                  let truePos = truePositions[tagId]
            else {
                continue
            }

            // 重み付け平均を計算
            let (avgPoint, avgWeight) = self.calculateWeightedAverage(measurements: measurements)

            sourcePoints.append(avgPoint)
            targetPoints.append(truePos)
            pointWeights.append(avgWeight)
        }

        guard sourcePoints.count >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: sourcePoints.count)
        }

        // デバッグ: 重み付け平均された代表点を出力
        print("📊 重み付け平均された測定点（ソース）:")
        for (index, point) in sourcePoints.enumerated() {
            print(
                "   Point\(index + 1): (\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y))) weight: \(String(format: "%.3f", pointWeights[index]))"
            )
        }

        // 共線性チェック
        try self.checkCollinearity(points: sourcePoints)

        // 重み付きアフィン変換を推定（Cauchy Loss IRLS使用）
        let transform = try estimateWeightedAffineTransformWithIRLS(
            sourcePoints: sourcePoints,
            targetPoints: targetPoints,
            weights: pointWeights
        )

        // 回転角度とスケールを抽出
        let (angleDegrees, scaleFactors, _) = self.extractRotationAngle(from: transform.A)

        // RMSEを計算
        let rmse = self.calculateRMSE(
            sourcePoints: sourcePoints,
            targetPoints: targetPoints,
            transform: transform
        )

        let config = AntennaConfig(
            x: transform.t.x,
            y: transform.t.y,
            angleDegrees: angleDegrees,
            angleRadians: angleDegrees * .pi / 180.0,
            scaleFactors: scaleFactors,
            rmse: rmse
        )

        print("""
        📡 品質重み付けキャリブレーション結果:
           位置: (\(String(format: "%.3f", config.x)), \(String(format: "%.3f", config.y))) m
           角度: \(String(format: "%.2f", config.angleDegrees))°
           RMSE: \(String(format: "%.4f", config.rmse)) m
        """)

        return config
    }

    // MARK: - Weighted Average

    /// 品質情報付き測定点の重み付け平均を計算
    private func calculateWeightedAverage(
        measurements: [WeightedMeasurement]
    ) -> (point: Point3D, avgWeight: Double) {
        guard !measurements.isEmpty else {
            return (Point3D(x: 0, y: 0, z: 0), 0)
        }

        var totalWeight: Double = 0
        var weightedX: Double = 0
        var weightedY: Double = 0

        for m in measurements {
            let w = m.weight
            totalWeight += w
            weightedX += w * m.position.x
            weightedY += w * m.position.y
        }

        // 重みの合計が0の場合は単純平均にフォールバック
        if totalWeight < 1e-10 {
            let avgX = measurements.map { $0.position.x }.reduce(0, +) / Double(measurements.count)
            let avgY = measurements.map { $0.position.y }.reduce(0, +) / Double(measurements.count)
            return (Point3D(x: avgX, y: avgY, z: 0), 0.5)
        }

        let avgX = weightedX / totalWeight
        let avgY = weightedY / totalWeight
        let avgWeight = totalWeight / Double(measurements.count)

        return (Point3D(x: avgX, y: avgY, z: 0), avgWeight)
    }

    /// 共線性チェック
    private func checkCollinearity(points: [Point3D]) throws {
        guard points.count >= 3 else { return }

        let p1 = points[0]
        let p2 = points[1]
        let p3 = points[2]

        let v1x = p2.x - p1.x
        let v1y = p2.y - p1.y
        let v2x = p3.x - p1.x
        let v2y = p3.y - p1.y
        let crossProduct = abs(v1x * v2y - v1y * v2x)

        if crossProduct < 0.01 {
            throw CalibrationError.invalidData(
                "測定点が一直線上に並んでいます（外積=\(String(format: "%.6f", crossProduct))）。"
                    + "タグを異なる位置に配置してください。"
            )
        }
    }

    // MARK: - Private Methods

    /// 最小二乗法で線形方程式を解く（Accelerateフレームワークを使用）
    private func solveLeastSquares(X: [Double], Y: [Double], m: Int, n: Int) throws -> [Double] {
        var matrixX = X
        var vectorY = Y
        var mInt32 = Int32(m)
        var nInt32 = Int32(n)
        var nrhs: Int32 = 1
        var lda = mInt32
        var ldb = max(mInt32, nInt32)
        var info: Int32 = 0

        // 作業用配列を確保（vectorYは解で上書きされるため、サイズをldbに合わせる）
        var work = [Double](repeating: 0.0, count: Int(ldb))
        if vectorY.count < Int(ldb) {
            work[0..<vectorY.count] = vectorY[0...]
        } else {
            work = vectorY
        }

        var lwork: Int32 = -1
        var workspaceQuery: Double = 0

        // ワークスペースサイズを取得
        dgels_(
            UnsafeMutablePointer(mutating: ("N" as NSString).utf8String), // TRANS = 'N'
            &mInt32, &nInt32, &nrhs,
            &matrixX, &lda,
            &work, &ldb,
            &workspaceQuery, &lwork,
            &info
        )

        // 実際に解く
        lwork = Int32(workspaceQuery)
        var workspace = [Double](repeating: 0.0, count: Int(lwork))
        dgels_(
            UnsafeMutablePointer(mutating: ("N" as NSString).utf8String),
            &mInt32, &nInt32, &nrhs,
            &matrixX, &lda,
            &work, &ldb,
            &workspace, &lwork,
            &info
        )

        guard info == 0 else {
            throw CalibrationError.singularMatrix
        }

        return Array(work[0..<n])
    }

    /// RMSEを計算
    private func calculateRMSE(
        sourcePoints: [Point3D],
        targetPoints: [Point3D],
        transform: AffineTransform
    ) -> Double {
        var sumSquaredError: Double = 0.0

        for i in 0..<sourcePoints.count {
            let predicted = self.applyTransform(point: sourcePoints[i], transform: transform)
            let error = predicted.distance(to: targetPoints[i])
            sumSquaredError += error * error
        }

        return sqrt(sumSquaredError / Double(sourcePoints.count))
    }

    /// アフィン変換を適用
    private func applyTransform(point: Point3D, transform: AffineTransform) -> Point3D {
        let transformed = transform.A.multiply(point)
        return Point3D(
            x: transformed.x + transform.t.x,
            y: transformed.y + transform.t.y,
            z: 0
        )
    }

    // MARK: - IRLS (Iteratively Reweighted Least Squares) with Cauchy Loss

    /// Cauchy Loss IRLSを使用してアフィン変換を推定
    /// 外れ値に対してロバストな推定を行う
    private func estimateAffineTransformWithIRLS(
        sourcePoints: [Point3D],
        targetPoints: [Point3D]
    ) throws -> AffineTransform {
        let n = sourcePoints.count
        guard n >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: n)
        }

        // 初期重みは全て1.0
        var weights = [Double](repeating: 1.0, count: n)

        // 初期解を通常の最小二乗法で求める
        var currentParams = try solveWeightedLeastSquares(
            sourcePoints: sourcePoints,
            targetPoints: targetPoints,
            weights: weights
        )

        var previousLoss = Double.infinity

        // IRLS反復
        for iteration in 0..<self.irlsConfig.maxIterations {
            // 現在のパラメータでアフィン変換を構築
            let currentTransform = AffineTransform(
                A: Matrix2x2(
                    a11: currentParams[0],
                    a12: currentParams[1],
                    a21: currentParams[2],
                    a22: currentParams[3]
                ),
                t: Point3D(x: currentParams[4], y: currentParams[5], z: 0)
            )

            // 残差を計算し、Cauchy Lossに基づく重みを更新
            var totalLoss: Double = 0
            for i in 0..<n {
                let predicted = self.applyTransform(point: sourcePoints[i], transform: currentTransform)
                let residualX = predicted.x - targetPoints[i].x
                let residualY = predicted.y - targetPoints[i].y
                let residualSquared = residualX * residualX + residualY * residualY

                // Cauchy Loss: log(1 + 0.5 * residual^2)
                totalLoss += log(1.0 + 0.5 * residualSquared)

                // Cauchy Lossの重み: 1 / (1 + 0.5 * residual^2)
                weights[i] = 1.0 / (1.0 + 0.5 * residualSquared)
            }

            // 収束判定
            if abs(previousLoss - totalLoss) < self.irlsConfig.tolerance {
                print("🔄 IRLS収束: \(iteration + 1)回で収束 (loss変化: \(abs(previousLoss - totalLoss)))")
                break
            }
            previousLoss = totalLoss

            // 重み付き最小二乗法でパラメータを更新
            currentParams = try self.solveWeightedLeastSquares(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints,
                weights: weights
            )
        }

        let A = Matrix2x2(
            a11: currentParams[0],
            a12: currentParams[1],
            a21: currentParams[2],
            a22: currentParams[3]
        )
        let t = Point3D(x: currentParams[4], y: currentParams[5], z: 0)

        guard abs(A.determinant) > 1e-10 else {
            throw CalibrationError.singularMatrix
        }

        return AffineTransform(A: A, t: t)
    }

    /// 重み付きCauchy Loss IRLSを使用してアフィン変換を推定
    private func estimateWeightedAffineTransformWithIRLS(
        sourcePoints: [Point3D],
        targetPoints: [Point3D],
        weights: [Double]
    ) throws -> AffineTransform {
        let n = sourcePoints.count
        guard n >= 3 else {
            throw CalibrationError.insufficientPoints(required: 3, provided: n)
        }

        // 初期重みは品質重み
        var currentWeights = weights

        // 初期解を重み付き最小二乗法で求める
        var currentParams = try solveWeightedLeastSquares(
            sourcePoints: sourcePoints,
            targetPoints: targetPoints,
            weights: currentWeights
        )

        var previousLoss = Double.infinity

        // IRLS反復
        for iteration in 0..<self.irlsConfig.maxIterations {
            let currentTransform = AffineTransform(
                A: Matrix2x2(
                    a11: currentParams[0],
                    a12: currentParams[1],
                    a21: currentParams[2],
                    a22: currentParams[3]
                ),
                t: Point3D(x: currentParams[4], y: currentParams[5], z: 0)
            )

            var totalLoss: Double = 0
            for i in 0..<n {
                let predicted = self.applyTransform(point: sourcePoints[i], transform: currentTransform)
                let residualX = predicted.x - targetPoints[i].x
                let residualY = predicted.y - targetPoints[i].y
                let residualSquared = residualX * residualX + residualY * residualY

                totalLoss += log(1.0 + 0.5 * residualSquared)

                // Cauchy重みと品質重みを組み合わせる
                let cauchyWeight = 1.0 / (1.0 + 0.5 * residualSquared)
                currentWeights[i] = weights[i] * cauchyWeight
            }

            if abs(previousLoss - totalLoss) < self.irlsConfig.tolerance {
                print("🔄 重み付きIRLS収束: \(iteration + 1)回で収束")
                break
            }
            previousLoss = totalLoss

            currentParams = try self.solveWeightedLeastSquares(
                sourcePoints: sourcePoints,
                targetPoints: targetPoints,
                weights: currentWeights
            )
        }

        let A = Matrix2x2(
            a11: currentParams[0],
            a12: currentParams[1],
            a21: currentParams[2],
            a22: currentParams[3]
        )
        let t = Point3D(x: currentParams[4], y: currentParams[5], z: 0)

        guard abs(A.determinant) > 1e-10 else {
            throw CalibrationError.singularMatrix
        }

        return AffineTransform(A: A, t: t)
    }

    /// 重み付き最小二乗法でアフィン変換パラメータを解く
    /// 正規方程式 (X^T W X) params = X^T W Y を解く
    private func solveWeightedLeastSquares(
        sourcePoints: [Point3D],
        targetPoints: [Point3D],
        weights: [Double]
    ) throws -> [Double] {
        let n = sourcePoints.count

        // デザイン行列Xと目標ベクトルYを構築
        // 各点につき2つの方程式（x方向とy方向）
        let nrows = 2 * n
        let ncols = 6

        // X^T W X (6x6) と X^T W Y (6x1) を直接計算
        var XtWX = [[Double]](repeating: [Double](repeating: 0.0, count: ncols), count: ncols)
        var XtWY = [Double](repeating: 0.0, count: ncols)

        for i in 0..<n {
            let p = sourcePoints[i]
            let q = targetPoints[i]
            let w = weights[i]

            // 行 2*i: qx = a11*px + a12*py + tx
            // X_row1 = [px, py, 0, 0, 1, 0]
            let row1: [Double] = [p.x, p.y, 0, 0, 1, 0]

            // 行 2*i+1: qy = a21*px + a22*py + ty
            // X_row2 = [0, 0, px, py, 0, 1]
            let row2: [Double] = [0, 0, p.x, p.y, 0, 1]

            // X^T W X への寄与
            for j in 0..<ncols {
                for k in 0..<ncols {
                    XtWX[j][k] += w * row1[j] * row1[k]
                    XtWX[j][k] += w * row2[j] * row2[k]
                }
            }

            // X^T W Y への寄与
            for j in 0..<ncols {
                XtWY[j] += w * row1[j] * q.x
                XtWY[j] += w * row2[j] * q.y
            }
        }

        // 6x6の線形方程式系を解く（ガウス・ジョルダン法）
        let params = try solveLinearSystem(matrix: XtWX, vector: XtWY)

        return params
    }

    /// ガウス・ジョルダン法で線形方程式系を解く
    private func solveLinearSystem(matrix: [[Double]], vector: [Double]) throws -> [Double] {
        let n = vector.count
        var augmented = matrix.enumerated().map { (i, row) in
            row + [vector[i]]
        }

        // 前進消去
        for col in 0..<n {
            // ピボット選択（部分ピボット）
            var maxRow = col
            var maxVal = abs(augmented[col][col])
            for row in (col + 1)..<n {
                if abs(augmented[row][col]) > maxVal {
                    maxVal = abs(augmented[row][col])
                    maxRow = row
                }
            }

            // 行の入れ替え
            if maxRow != col {
                augmented.swapAt(col, maxRow)
            }

            // ピボットが0に近い場合はエラー
            guard abs(augmented[col][col]) > 1e-12 else {
                throw CalibrationError.singularMatrix
            }

            // ピボット行を正規化
            let pivot = augmented[col][col]
            for j in col...(n) {
                augmented[col][j] /= pivot
            }

            // 他の行から消去
            for row in 0..<n where row != col {
                let factor = augmented[row][col]
                for j in col...(n) {
                    augmented[row][j] -= factor * augmented[col][j]
                }
            }
        }

        // 解を抽出
        return augmented.map { $0[n] }
    }
}
