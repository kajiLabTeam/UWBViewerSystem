import Foundation

/// キャリブレーション処理を管理するUseCase

// MARK: - Calibration Errors

/// キャリブレーション関連のエラー定義
public enum CalibrationError: LocalizedError {
    case noCalibrationData
    case invalidCalibrationData(String)
    case calculationFailed(String)
    case unexpectedError(String)

    public var errorDescription: String? {
        switch self {
        case .noCalibrationData:
            return "キャリブレーションデータがありません"
        case .invalidCalibrationData(let message):
            return "無効なキャリブレーションデータ: \(message)"
        case .calculationFailed(let message):
            return "キャリブレーション計算に失敗しました: \(message)"
        case .unexpectedError(let message):
            return "予期しないエラーが発生しました: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noCalibrationData:
            return "キャリブレーションポイントを追加してください。"
        case .invalidCalibrationData:
            return "キャリブレーションデータを確認し、有効な座標値を設定してください。"
        case .calculationFailed:
            return "キャリブレーションポイントを見直すか、操作を再試行してください。"
        case .unexpectedError:
            return "アプリケーションを再起動するか、サポートにお問い合わせください。"
        }
    }
}

@MainActor
public class CalibrationUsecase: ObservableObject {

    // MARK: - プロパティ

    private let dataRepository: DataRepositoryProtocol

    /// 現在のキャリブレーションデータ
    @Published public var currentCalibrationData: [String: CalibrationData] = [:]

    /// キャリブレーション状態
    @Published public var calibrationStatus: CalibrationStatus = .notStarted

    /// 進行中のキャリブレーション結果
    @Published public var lastCalibrationResult: CalibrationResult?

    /// エラーメッセージ
    @Published public var errorMessage: String?

    // MARK: - 初期化

    public init(dataRepository: DataRepositoryProtocol) {
        self.dataRepository = dataRepository
        loadCalibrationData()
    }

    // MARK: - 公開メソッド

    /// すべてのアンテナのキャリブレーションデータを読み込み
    public func loadCalibrationData() {
        Task {
            do {
                let calibrationData = try await dataRepository.loadCalibrationData()
                await MainActor.run {
                    self.currentCalibrationData = Dictionary(
                        uniqueKeysWithValues: calibrationData.map { ($0.antennaId, $0) }
                    )
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "キャリブレーションデータの読み込みに失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 特定のアンテナのキャリブレーションデータを取得
    /// - Parameter antennaId: アンテナID
    /// - Returns: キャリブレーションデータ（存在しない場合は新規作成）
    public func getCalibrationData(for antennaId: String) -> CalibrationData {
        currentCalibrationData[antennaId] ?? CalibrationData(antennaId: antennaId)
    }

    /// キャリブレーション点を追加
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - referencePosition: 正解座標
    ///   - measuredPosition: 測定座標
    public func addCalibrationPoint(
        for antennaId: String,
        referencePosition: Point3D,
        measuredPosition: Point3D
    ) {
        let point = CalibrationPoint(
            referencePosition: referencePosition,
            measuredPosition: measuredPosition,
            antennaId: antennaId
        )

        var calibrationData = getCalibrationData(for: antennaId)
        calibrationData.calibrationPoints.append(point)
        calibrationData.updatedAt = Date()

        currentCalibrationData[antennaId] = calibrationData
        calibrationStatus = .collecting

        // データを永続化
        saveCalibrationData(calibrationData)
    }

    /// キャリブレーション点を削除
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - pointId: 削除する点のID
    public func removeCalibrationPoint(for antennaId: String, pointId: String) {
        guard var calibrationData = currentCalibrationData[antennaId] else { return }

        calibrationData.calibrationPoints.removeAll { $0.id == pointId }
        calibrationData.updatedAt = Date()

        // 変換行列をクリア（点が削除されたため）
        calibrationData.transform = nil

        currentCalibrationData[antennaId] = calibrationData

        // データを永続化
        saveCalibrationData(calibrationData)
    }

    /// 特定のアンテナのキャリブレーションを実行
    /// - Parameter antennaId: アンテナID
    /// 特定のアンテナのキャリブレーションを実行
    /// - Parameter antennaId: アンテナID
    public func performCalibration(for antennaId: String) async {
        // バリデーション
        guard !antennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                self.lastCalibrationResult = CalibrationResult(
                    success: false,
                    errorMessage: "アンテナIDが無効です"
                )
                self.calibrationStatus = .failed
                self.errorMessage = "アンテナIDが無効です"
            }
            return
        }

        await MainActor.run {
            self.calibrationStatus = .calculating
            self.errorMessage = nil
        }

        do {
            guard let calibrationData = currentCalibrationData[antennaId] else {
                throw CalibrationError.noCalibrationData
            }

            // データの妥当性チェック
            guard !calibrationData.calibrationPoints.isEmpty else {
                throw CalibrationError.noCalibrationData
            }

            guard calibrationData.calibrationPoints.count >= 3 else {
                throw LeastSquaresCalibration.CalibrationError.insufficientPoints(
                    required: 3,
                    provided: calibrationData.calibrationPoints.count
                )
            }

            // キャリブレーションポイントの妥当性チェック
            for (index, point) in calibrationData.calibrationPoints.enumerated() {
                guard point.referencePosition.x.isFinite &&
                    point.referencePosition.y.isFinite &&
                    point.referencePosition.z.isFinite &&
                    point.measuredPosition.x.isFinite &&
                    point.measuredPosition.y.isFinite &&
                    point.measuredPosition.z.isFinite else {
                    throw CalibrationError.invalidCalibrationData("キャリブレーションポイント\(index + 1)に無効な座標値が含まれています")
                }
            }

            // 重複チェック
            let uniqueReferences = Set(calibrationData.calibrationPoints.map {
                "\($0.referencePosition.x),\($0.referencePosition.y),\($0.referencePosition.z)"
            })
            guard uniqueReferences.count == calibrationData.calibrationPoints.count else {
                throw CalibrationError.invalidCalibrationData("重複する基準座標が含まれています")
            }

            // 最小二乗法でキャリブレーション実行
            let transform = try LeastSquaresCalibration.calculateTransform(
                from: calibrationData.calibrationPoints
            )

            let result = CalibrationResult(
                success: true,
                transform: transform,
                processedPoints: calibrationData.calibrationPoints
            )

            await MainActor.run {
                // キャリブレーションデータを更新
                var updatedData = calibrationData
                updatedData.transform = transform
                updatedData.updatedAt = Date()

                self.currentCalibrationData[antennaId] = updatedData
                self.lastCalibrationResult = result
                self.calibrationStatus = .completed

                // データを永続化
                self.saveCalibrationData(updatedData)
            }

            print("✅ キャリブレーション成功: \(antennaId)")

        } catch let error as CalibrationError {
            await handleCalibrationError(error)
        } catch let error as LeastSquaresCalibration.CalibrationError {
            await handleCalibrationError(CalibrationError.calculationFailed(error.localizedDescription))
        } catch {
            await handleCalibrationError(CalibrationError.unexpectedError(error.localizedDescription))
        }
    }

    /// キャリブレーションエラーの処理
    private func handleCalibrationError(_ error: CalibrationError) async {
        let result = CalibrationResult(
            success: false,
            errorMessage: error.localizedDescription
        )

        await MainActor.run {
            self.lastCalibrationResult = result
            self.calibrationStatus = .failed
            self.errorMessage = error.localizedDescription
        }

        print("❌ キャリブレーションエラー: \(error.localizedDescription)")
    }

    /// すべてのアンテナのキャリブレーションを実行
    public func performAllCalibrations() async {
        for antennaId in currentCalibrationData.keys {
            await performCalibration(for: antennaId)

            // 失敗した場合は停止
            if calibrationStatus == .failed {
                break
            }
        }
    }

    /// 座標にキャリブレーションを適用
    /// - Parameters:
    ///   - point: 変換対象の座標
    ///   - antennaId: アンテナID
    /// - Returns: キャリブレーション済み座標
    public func applyCalibratedTransform(to point: Point3D, for antennaId: String) -> Point3D {
        guard let calibrationData = currentCalibrationData[antennaId],
              let transform = calibrationData.transform else {
            return point // キャリブレーションが未完了の場合はそのまま返す
        }

        return LeastSquaresCalibration.applyCalibration(to: point, using: transform)
    }

    /// 複数の座標にキャリブレーションを適用
    /// - Parameters:
    ///   - points: 変換対象の座標配列
    ///   - antennaId: アンテナID
    /// - Returns: キャリブレーション済み座標配列
    public func applyCalibratedTransform(to points: [Point3D], for antennaId: String) -> [Point3D] {
        points.map { applyCalibratedTransform(to: $0, for: antennaId) }
    }

    /// キャリブレーションデータをクリア
    /// - Parameter antennaId: アンテナID（nilの場合はすべてクリア）
    public func clearCalibrationData(for antennaId: String? = nil) {
        if let antennaId {
            // 特定のアンテナのデータをクリア
            currentCalibrationData[antennaId] = CalibrationData(antennaId: antennaId)
            Task {
                try? await dataRepository.deleteCalibrationData(for: antennaId)
            }
        } else {
            // すべてのデータをクリア
            currentCalibrationData.removeAll()
            calibrationStatus = .notStarted
            lastCalibrationResult = nil
            Task {
                try? await dataRepository.deleteAllCalibrationData()
            }
        }
    }

    /// キャリブレーション精度の評価
    /// - Parameter antennaId: アンテナID
    /// - Returns: 精度情報
    public func getCalibrationAccuracy(for antennaId: String) -> Double? {
        currentCalibrationData[antennaId]?.accuracy
    }

    /// キャリブレーションが有効かどうかを判定
    /// - Parameter antennaId: アンテナID
    /// - Returns: 有効性
    public func isCalibrationValid(for antennaId: String) -> Bool {
        guard let calibrationData = currentCalibrationData[antennaId],
              let transform = calibrationData.transform else {
            return false
        }

        return transform.isValid && calibrationData.calibrationPoints.count >= 3
    }

    /// キャリブレーション統計情報を取得
    /// - Returns: 統計情報
    public func getCalibrationStatistics() -> CalibrationStatistics {
        let totalAntennas = currentCalibrationData.count
        let calibratedAntennas = currentCalibrationData.values.filter { $0.isCalibrated }.count
        let averageAccuracy = currentCalibrationData.values.compactMap { $0.accuracy }.reduce(0, +) /
            Double(max(1, currentCalibrationData.values.filter { $0.isCalibrated }.count))

        return CalibrationStatistics(
            totalAntennas: totalAntennas,
            calibratedAntennas: calibratedAntennas,
            averageAccuracy: averageAccuracy.isFinite ? averageAccuracy : 0.0
        )
    }

    // MARK: - プライベートメソッド

    /// キャリブレーションデータを保存
    private func saveCalibrationData(_ data: CalibrationData) {
        Task { @MainActor in
            do {
                try await dataRepository.saveCalibrationData(data)
            } catch {
                self.errorMessage = "キャリブレーションデータの保存に失敗しました: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 統計情報

/// キャリブレーション統計情報
public struct CalibrationStatistics: Codable {
    public let totalAntennas: Int
    public let calibratedAntennas: Int
    public let averageAccuracy: Double

    public var completionPercentage: Double {
        guard totalAntennas > 0 else { return 0.0 }
        return Double(calibratedAntennas) / Double(totalAntennas) * 100.0
    }

    public init(totalAntennas: Int, calibratedAntennas: Int, averageAccuracy: Double) {
        self.totalAntennas = totalAntennas
        self.calibratedAntennas = calibratedAntennas
        self.averageAccuracy = averageAccuracy
    }
}