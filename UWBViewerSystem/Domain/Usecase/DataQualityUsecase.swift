import Foundation

/// データ品質管理のビジネスロジック実装
///
/// このUseCaseは、UWB観測データの品質評価と監視を担当します。
/// 単一責任原則に基づき、データ品質に関する処理のみを行います。
///
/// ## 主要機能
/// - **品質評価**: 個別の観測データの品質を評価
/// - **NLoS検出**: 見通し線なし状態の検出
/// - **品質統計**: セッション全体の品質統計の取得
/// - **データフィルタリング**: 品質に基づいたデータフィルタリング
///
/// ## 使用例
/// ```swift
/// let usecase = DataQualityUsecase()
///
/// // データ品質評価
/// let evaluation = usecase.evaluateDataQuality(observation)
///
/// // NLoS検出
/// let nlosResult = usecase.detectNonLineOfSight(observations)
/// ```
public class DataQualityUsecase {

    // MARK: - Private Properties

    /// データ品質監視インスタンス
    private let qualityMonitor: DataQualityMonitor

    // MARK: - Initialization

    /// DataQualityUsecaseのイニシャライザ
    /// - Parameter qualityMonitor: データ品質監視インスタンス（依存性注入可能）
    public init(qualityMonitor: DataQualityMonitor = DataQualityMonitor()) {
        self.qualityMonitor = qualityMonitor
    }

    // MARK: - Data Quality Evaluation

    /// リアルタイム品質チェック
    /// - Parameter observation: 観測データ点
    /// - Returns: 品質評価結果
    public func evaluateDataQuality(_ observation: ObservationPoint) -> DataQualityEvaluation {
        self.qualityMonitor.evaluate(observation)
    }

    /// nLoS（見通し線なし）状態の検出
    /// - Parameter observations: 観測データ配列
    /// - Returns: nLoS検出結果
    public func detectNonLineOfSight(_ observations: [ObservationPoint]) -> NLoSDetectionResult {
        self.qualityMonitor.detectNLoS(observations)
    }

    // MARK: - Data Filtering

    /// 観測データを品質に基づいてフィルタリング
    /// - Parameters:
    ///   - observations: フィルタリング対象の観測データ配列
    ///   - qualityThreshold: 品質閾値（0.0-1.0）
    ///   - timeRange: 時間範囲（オプション）
    /// - Returns: フィルタリングされた観測データ
    public func filterObservations(
        _ observations: [ObservationPoint],
        qualityThreshold: Double = 0.5,
        timeRange: DateInterval? = nil
    ) -> [ObservationPoint] {
        observations.filter { observation in
            // 品質フィルタ
            if observation.quality.strength < qualityThreshold {
                return false
            }

            // 時間範囲フィルタ
            if let timeRange {
                return timeRange.contains(observation.timestamp)
            }

            return true
        }
    }

    // MARK: - Quality Statistics

    /// セッションの品質統計を計算
    /// - Parameter observations: 観測データ配列
    /// - Returns: 品質統計
    public func calculateQualityStatistics(_ observations: [ObservationPoint]) -> ObservationQualityStatistics {
        guard !observations.isEmpty else {
            return ObservationQualityStatistics(
                totalPoints: 0,
                validPoints: 0,
                averageQuality: 0.0,
                lineOfSightPercentage: 0.0,
                averageErrorEstimate: 0.0
            )
        }

        let totalPoints = observations.count
        let validPoints = observations.filter { observation in
            let evaluation = self.evaluateDataQuality(observation)
            return evaluation.isAcceptable
        }.count

        let averageQuality = observations.map { $0.quality.strength }.reduce(0, +) / Double(totalPoints)
        let averageErrorEstimate = observations.map { $0.quality.errorEstimate }.reduce(0, +) / Double(totalPoints)

        let losCount = observations.filter { $0.quality.isLineOfSight }.count
        let losPercentage = Double(losCount) / Double(totalPoints) * 100.0

        return ObservationQualityStatistics(
            totalPoints: totalPoints,
            validPoints: validPoints,
            averageQuality: averageQuality,
            lineOfSightPercentage: losPercentage,
            averageErrorEstimate: averageErrorEstimate
        )
    }

    // MARK: - Batch Evaluation

    /// 複数の観測データを一括で品質評価
    /// - Parameter observations: 観測データ配列
    /// - Returns: 各観測データの品質評価結果の配列
    public func evaluateBatch(_ observations: [ObservationPoint]) -> [(ObservationPoint, DataQualityEvaluation)] {
        observations.map { observation in
            (observation, self.evaluateDataQuality(observation))
        }
    }

    /// 低品質データのみを抽出
    /// - Parameter observations: 観測データ配列
    /// - Returns: 低品質と判定された観測データの配列
    public func extractLowQualityData(_ observations: [ObservationPoint]) -> [ObservationPoint] {
        observations.filter { observation in
            let evaluation = self.evaluateDataQuality(observation)
            return !evaluation.isAcceptable
        }
    }

    /// 高品質データのみを抽出
    /// - Parameter observations: 観測データ配列
    /// - Returns: 高品質と判定された観測データの配列
    public func extractHighQualityData(_ observations: [ObservationPoint]) -> [ObservationPoint] {
        observations.filter { observation in
            let evaluation = self.evaluateDataQuality(observation)
            return evaluation.isAcceptable
        }
    }
}
