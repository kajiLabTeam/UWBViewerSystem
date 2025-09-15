import Foundation

/// キャリブレーション処理を管理するUseCase
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
    public func performCalibration(for antennaId: String) async {
        await MainActor.run {
            self.calibrationStatus = .calculating
            self.errorMessage = nil
        }

        do {
            guard let calibrationData = currentCalibrationData[antennaId] else {
                throw CalibrationError.noCalibrationData
            }

            guard calibrationData.calibrationPoints.count >= 3 else {
                throw LeastSquaresCalibration.CalibrationError.insufficientPoints(
                    required: 3,
                    provided: calibrationData.calibrationPoints.count
                )
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

        } catch {
            let result = CalibrationResult(
                success: false,
                errorMessage: error.localizedDescription
            )

            await MainActor.run {
                self.lastCalibrationResult = result
                self.calibrationStatus = .failed
                self.errorMessage = error.localizedDescription
            }
        }
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
        Task {
            do {
                try await dataRepository.saveCalibrationData(data)
            } catch {
                await MainActor.run {
                    self.errorMessage = "キャリブレーションデータの保存に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - エラータイプ

/// キャリブレーション関連のエラー
public enum CalibrationError: Error, LocalizedError {
    case noCalibrationData
    case invalidAntennaId(String)

    public var errorDescription: String? {
        switch self {
        case .noCalibrationData:
            return "キャリブレーションデータが見つかりません"
        case .invalidAntennaId(let id):
            return "無効なアンテナID: \(id)"
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